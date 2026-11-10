import Foundation
import Network

/// iOS 抓包引擎的纯逻辑层：SNI / HTTP 解析、Mock 匹配、域名过滤、记录落盘。
/// 与 PacketTunnelProvider 解耦，便于单测与阅读。

// MARK: - Mock 规则（对齐 Android MockRule）

struct MockRule {
    let id: String
    let enabled: Bool
    let name: String
    let method: String      // "*" 表示任意方法
    let host: String
    let path: String
    let statusCode: Int
    let contentType: String
    let body: String
    let delayMs: Int
    let headers: [[String]] // [key, value]
}

extension MockRule {
    static func from(_ dict: [String: Any]) -> MockRule {
        return MockRule(
            id: (dict["id"] as? String) ?? "",
            enabled: (dict["enabled"] as? Bool) ?? true,
            name: (dict["name"] as? String) ?? "",
            method: (dict["method"] as? String) ?? "*",
            host: (dict["host"] as? String) ?? "",
            path: (dict["path"] as? String) ?? "",
            statusCode: (dict["statusCode"] as? Int) ?? 200,
            contentType: (dict["contentType"] as? String) ?? "application/json",
            body: (dict["body"] as? String) ?? "",
            delayMs: (dict["delayMs"] as? Int) ?? 0,
            headers: (dict["headers"] as? [[String]]) ?? []
        )
    }
}

// MARK: - SNI 解析（TLS ClientHello）

/// 从 TLS ClientHello 提取 SNI 主机名；非握手包或解析失败返回 nil。
func parseSNI(_ data: Data) -> String? {
    let bytes = [UInt8](data)
    guard bytes.count > 5, bytes[0] == 0x16 else { return nil } // 0x16 = handshake
    guard bytes.count > 43 else { return nil }
    guard bytes[5] == 0x01 else { return nil }                   // 0x01 = ClientHello

    var idx = 43
    // session_id
    guard bytes.count > idx else { return nil }
    let sidLen = Int(bytes[idx]); idx += 1 + sidLen
    guard bytes.count > idx + 1 else { return nil }
    // cipher_suites
    let csLen = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1]); idx += 2 + csLen
    guard bytes.count > idx else { return nil }
    // compression_methods
    let compLen = Int(bytes[idx]); idx += 1 + compLen
    guard bytes.count > idx + 1 else { return nil }
    // extensions
    let extTotal = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1]); idx += 2
    let extEnd = idx + extTotal
    guard extEnd <= bytes.count else { return nil }

    while idx + 4 <= extEnd {
        let extType = (Int(bytes[idx]) << 8) | Int(bytes[idx + 1])
        let extLen = (Int(bytes[idx + 2]) << 8) | Int(bytes[idx + 3])
        idx += 4
        guard idx + extLen <= extEnd else { break }
        if extType == 0x0000 { // server_name
            var p = idx
            _ = (Int(bytes[p]) << 8) | Int(bytes[p + 1]); p += 2 // server_name_list length
            guard p + 3 <= bytes.count else { break }
            let nameType = bytes[p]; p += 1
            if nameType == 0x00 { // host_name
                let nameLen = (Int(bytes[p]) << 8) | Int(bytes[p + 1]); p += 2
                if p + nameLen <= bytes.count {
                    let nameData = Data(bytes[p..<(p + nameLen)])
                    return String(data: nameData, encoding: .utf8)
                }
            }
        }
        idx += extLen
    }
    return nil
}

// MARK: - HTTP 明文请求解析

struct ParsedHttpRequest {
    let method: String
    let host: String
    let path: String
    let headers: [String: String]
}

/// 解析 HTTP/1.x 请求首部（请求行 + 头部），非 HTTP 返回 nil。
func parseHttpRequest(_ data: Data) -> ParsedHttpRequest? {
    guard let text = String(data: data, encoding: .utf8) else { return nil }
    let lines = text.components(separatedBy: "\r\n")
    guard let first = lines.first else { return nil }
    let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }
    let method = parts[0]
    let rawTarget = parts.count >= 3 ? parts[1] : "/"

    var host = ""
    var headers: [String: String] = [:]
    for i in 1..<lines.count {
        let line = lines[i]
        if line.isEmpty { break }
        if let r = line.range(of: ":") {
            let k = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
            let v = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            headers[k] = v
            if k == "host" { host = v }
        }
    }

    var path = rawTarget
    // 代理风格绝对路径 "http://host/path"
    if let u = URL(string: rawTarget), let h = u.host, !h.isEmpty {
        host = h
        path = u.path + (u.query.map { "?\($0)" } ?? "")
    }
    if path.isEmpty { path = "/" }
    return ParsedHttpRequest(method: method, host: host, path: path, headers: headers)
}

// MARK: - Mock 匹配

func matchMock(_ rule: MockRule, req: ParsedHttpRequest) -> Bool {
    guard rule.enabled else { return false }
    if rule.method != "*", rule.method.lowercased() != req.method.lowercased() { return false }
    if !rule.host.isEmpty, !hostMatches(rule.host, req.host) { return false }
    if !rule.path.isEmpty, !pathMatches(rule.path, req.path) { return false }
    return true
}

private func hostMatches(_ pattern: String, _ host: String) -> Bool {
    let p = pattern.lowercased()
    let h = host.lowercased()
    if p == h { return true }
    if p.hasPrefix("*.") {
        let suffix = String(p.dropFirst(2))
        return h == suffix || h.hasSuffix(".\(suffix)")
    }
    return false
}

private func pathMatches(_ pattern: String, _ path: String) -> Bool {
    let p = pattern
    let t = path
    if p == t { return true }
    if p.hasSuffix("*") {
        let prefix = String(p.dropLast())
        return t.hasPrefix(prefix)
    }
    return false
}

// MARK: - 域名过滤（展示/记录过滤，对齐 Android CaptureFilter）

func domainAllowed(
    host: String,
    blacklist: [String],
    whitelist: [String],
    blacklistEnabled: Bool,
    whitelistEnabled: Bool
) -> Bool {
    if whitelistEnabled, !whitelist.isEmpty {
        guard whitelist.contains(where: { hostMatches($0, host) }) else { return false }
    }
    if blacklistEnabled, !blacklist.isEmpty {
        if blacklist.contains(where: { hostMatches($0, host) }) { return false }
    }
    return true
}

// MARK: - 记录落盘（App Group 共享，主 App 轮询回读）

/// 把抓包记录以 JSONL 追加写入 App Group 容器，供主 App 读回并转发给 Flutter。
final class RecordStore {
    static let shared = RecordStore()

    private let appGroupID = "group.com.packetsniffer.packetSniffing"
    private let fileName = "capture_records.jsonl"
    private let lock = NSLock()
    private var fileHandle: FileHandle?
    private var fileURL: URL?

    private init() {}

    /// 新一轮抓包开始时清空历史，避免回读上一轮记录。
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        fileHandle?.closeFile()
        fileHandle = nil
        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ensureFile() -> URL? {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let url = dir.appendingPathComponent(fileName)
        fileURL = url
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return url
    }

    func append(_ record: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = ensureFile() else { return }
        if fileHandle == nil {
            fileHandle = try? FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
        }
        guard let fh = fileHandle else { return }
        guard let line = try? JSONSerialization.data(withJSONObject: record),
              let nl = "\n".data(using: .utf8) else { return }
        fh.write(line)
        fh.write(nl)
    }

    /// 从指定偏移读取新增 JSONL 行，返回解析后的记录与新的偏移。
    func drain(from offset: UInt64) -> ([Any], UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = ensureFile() else { return ([], offset) }
        guard let fh = try? FileHandle(forReadingFrom: url) else { return ([], offset) }
        defer { fh.closeFile() }
        let size = (try? fh.seekToEnd()) ?? 0
        guard size > offset else { return ([], offset) }
        fh.seek(toFileOffset: offset)
        let newData = fh.readDataToEndOfFile()
        guard let text = String(data: newData, encoding: .utf8) else {
            return ([], size)
        }
        var records: [Any] = []
        for line in text.split(separator: "\n") where !line.isEmpty {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
               let dict = obj as? [String: Any] {
                records.append(dict)
            }
        }
        return (records, size)
    }
}
