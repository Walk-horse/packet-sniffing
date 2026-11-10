import NetworkExtension
import Network
import Foundation

/// iOS 抓包引擎入口：Network Extension（Transparent Proxy）。
///
/// 与 Android 的差异（已在需求确认中同步给用户）：
/// - iOS 用独立的 NE 进程接管流量，主 App 经 App Group 下发配置、回读记录。
/// - 抓包粒度是「逐 TCP 流」（NEAppProxyTCPFlow 已重组好流，无需自己做 TCP 重组）。
/// - **不做按 App 分组**（免费账号 + NE 限制）；改为按域名过滤，与用户确认一致。
/// - **HTTPS 明文解密（MITM）不在免费账号能力内**：本引擎对 HTTPS 仅记录 SNI 域名
///   （PassthroughRecord，tls=true），不解密报文体；HTTP 明文可完整抓包并支持 Mock。
class PacketTunnelProvider: NETransparentProxyProvider {

    private let appGroupID = "group.com.packetsniffer.packetSniffing"

    // MARK: - 配置（来自主 App 经 App Group 写入）
    private var mockEnabled: Bool = false
    private var mockRules: [MockRule] = []
    private var blacklist: [String] = []
    private var whitelist: [String] = []
    private var whitelistEnabled: Bool = false
    private var blacklistEnabled: Bool = false

    private var sessionId: String = ""
    private var activeRelays = NSHashTable<FlowRelay>.weakObjects()

    // MARK: - 生命周期

    override func startProxy(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        loadConfig()
        sessionId = "ios_\(Int(Date().timeIntervalSince1970))"
        RecordStore.shared.reset()
        completionHandler(nil)
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        // 关闭所有进行中的流。
        for relay in activeRelays.allObjects {
            relay.finish()
        }
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard let tcpFlow = flow as? NEAppProxyTCPFlow else {
            // UDP 等交由系统直连（本引擎只代理 TCP）。
            return false
        }
        let host = (flow.remoteEndpoint as? NWHostEndpoint)?.hostname
            ?? flow.remoteHostname
            ?? ""
        let portStr = (flow.remoteEndpoint as? NWHostEndpoint)?.port ?? "443"
        let port = UInt16(portStr) ?? 443

        let relay = FlowRelay(provider: self, flow: tcpFlow, host: host, port: port)
        activeRelays.add(relay)

        tcpFlow.openWithLocalEndpoint(nil) { [weak relay] error in
            guard error == nil else {
                relay?.finish()
                return
            }
            relay?.begin()
        }
        return true
    }

    // MARK: - 配置加载（App Group 共享）

    func loadConfig() {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        mockEnabled = defaults.bool(forKey: "mockEnabled")
        if let rules = defaults.array(forKey: "mockRules") as? [[String: Any]] {
            mockRules = rules.map { MockRule.from($0) }
        }
        whitelistEnabled = defaults.bool(forKey: "whitelistEnabled")
        blacklistEnabled = defaults.bool(forKey: "blacklistEnabled")
        if let bl = defaults.array(forKey: "blacklist") as? [String] { blacklist = bl }
        if let wl = defaults.array(forKey: "whitelist") as? [String] { whitelist = wl }
    }

    // MARK: - 内部助手（供 FlowRelay 调用）

    func shouldRecord(host: String) -> Bool {
        return domainAllowed(
            host: host,
            blacklist: blacklist,
            whitelist: whitelist,
            blacklistEnabled: blacklistEnabled,
            whitelistEnabled: whitelistEnabled
        )
    }

    func matchingMock(for req: ParsedHttpRequest) -> MockRule? {
        guard mockEnabled else { return nil }
        return mockRules.first { matchMock($0, req: req) }
    }

    func currentSessionId() -> String { sessionId }
}

// MARK: - 单流代理

/// 一条 TCP 流的代理状态机：客户端<->服务端双向 relay，并在首包做 SNI/HTTP 解析、
/// Mock 注入、记录落盘。HTTPS 仅取 SNI（不解密）。
final class FlowRelay {
    weak var provider: PacketTunnelProvider?
    let flow: NEAppProxyTCPFlow
    let host: String
    let port: UInt16

    private let queue = DispatchQueue(label: "tunnel.relay")
    private var connection: NWConnection?
    private var finalized = false

    private var isTls: Bool = false
    private var isHttpRequest: Bool = false
    private var requestMeta: ParsedHttpRequest?
    private var responseStatusCode: Int = 0
    private var responseHeaders: [String: String] = [:]
    private var mocked: Bool = false

    private var requestData = Data()
    private var responseData = Data()
    private let bodyCap = 1_048_576 // 单流正文上限 1MB，防止内存膨胀
    private let startTime = Date()

    init(provider: PacketTunnelProvider, flow: NEAppProxyTCPFlow, host: String, port: UInt16) {
        self.provider = provider
        self.flow = flow
        self.host = host
        self.port = port
    }

    func begin() {
        isTls = (port == 443 || port == 8443)
        let scheme = isTls ? "https" : "http"
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .https,
            using: .tcp
        )
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.pumpClient()
                self?.pumpServer()
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    // 客户端 -> 服务端
    private func pumpClient() {
        flow.readDataWithCompletionHandler { [weak self] data, error in
            guard let self = self else { return }
            if let error = error {
                self.connection?.send(content: nil, completion: .final)
                self.finish()
                return
            }
            guard let data = data, !data.isEmpty else {
                self.connection?.send(content: nil, completion: .final)
                return
            }

            // 首包检查：TLS 取 SNI；HTTP 解析请求。
            if self.requestMeta == nil && !self.isHttpRequest {
                if self.isTls {
                    if let sni = parseSNI(data) {
                        self.requestMeta = ParsedHttpRequest(
                            method: "TCP", host: sni, path: "", headers: [:])
                    }
                } else if let req = parseHttpRequest(data) {
                    self.isHttpRequest = true
                    self.requestMeta = req
                    if let mock = self.provider?.matchingMock(for: req) {
                        self.injectMock(mock, for: req)
                        return
                    }
                }
            }

            if self.mocked { return } // Mock 已接管，不再转发

            if self.requestData.count < self.bodyCap {
                self.requestData.append(data)
            }

            self.connection?.send(content: data, completion: .contentProcessed { _ in
                self.pumpClient()
            })
        }
    }

    // 服务端 -> 客户端
    private func pumpServer() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, _, error in
            guard let self = self else { return }
            if let error = error {
                self.flow.closeReadWithError(nil)
                self.finish()
                return
            }
            guard let data = data, !data.isEmpty else {
                self.flow.closeReadWithError(nil)
                return
            }

            if self.isHttpRequest, self.responseStatusCode == 0 {
                self.parseResponse(data)
            }
            if self.responseData.count < self.bodyCap {
                self.responseData.append(data)
            }

            self.flow.writeData(data) { _ in
                self.pumpServer()
            }
        }
    }

    private func parseResponse(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let lines = text.components(separatedBy: "\r\n")
        if let status = lines.first {
            let parts = status.split(separator: " ")
            if parts.count >= 2, let code = Int(parts[1]) {
                responseStatusCode = code
            }
        }
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if let r = line.range(of: ":") {
                let k = line[..<r.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                let v = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                responseHeaders[k] = v
            }
        }
    }

    /// 命中 HTTP Mock：合成响应写回客户端，不转发到服务端，并落盘记录（mocked=true）。
    private func injectMock(_ mock: MockRule, for req: ParsedHttpRequest) {
        mocked = true
        let bodyData = Data(mock.body.utf8)
        var headerText = "HTTP/1.1 \(mock.statusCode) OK\r\n"
        headerText += "Content-Type: \(mock.contentType)\r\n"
        headerText += "Content-Length: \(bodyData.count)\r\n"
        for h in mock.headers {
            if h.count == 2 { headerText += "\(h[0]): \(h[1])\r\n" }
        }
        headerText += "\r\n"
        var resp = Data(headerText.utf8)
        resp.append(bodyData)

        // 先记录
        recordRequest(mocked: true, statusCode: mock.statusCode, headers: responseHeaders)

        flow.writeData(resp) { [weak self] _ in
            self?.flow.closeWriteWithError(nil)
            self?.connection?.cancel()
            self?.finish()
        }
    }

    func finish() {
        queue.async { [weak self] in
            guard let self = self, !self.finalized else { return }
            self.finalized = true

            if self.mocked {
                // 已在 injectMock 落盘
            } else if self.isTls {
                // HTTPS：仅 SNI 记录（无法解密），写入 PassthroughRecord。
                if let sni = self.requestMeta?.host, !sni.isEmpty {
                    self.recordPassthrough(host: sni)
                } else if !self.host.isEmpty {
                    self.recordPassthrough(host: self.host)
                }
            } else if self.isHttpRequest {
                self.recordRequest(
                    mocked: false,
                    statusCode: self.responseStatusCode,
                    headers: self.responseHeaders
                )
            }
            self.connection?.cancel()
        }
    }

    // MARK: - 记录落盘

    private func recordRequest(mocked: Bool, statusCode: Int, headers: [String: String]) {
        guard let provider = provider else { return }
        let host = requestMeta?.host ?? self.host
        guard provider.shouldRecord(host: host) else { return }

        let req = requestMeta
        let base64Body: String? = responseData.isEmpty ? nil : responseData.base64EncodedString()
        let ct = headers["content-type"] ?? ""
        let record: [String: Any] = [
            "recType": "request",
            "id": "\(provider.currentSessionId())_\(Int(startTime.timeIntervalSince1970 * 1000))_\(host)",
            "sessionId": provider.currentSessionId(),
            "method": req?.method ?? "GET",
            "scheme": isTls ? "https" : "http",
            "host": host,
            "path": req?.path ?? "/",
            "port": Int(port),
            "statusCode": statusCode,
            "requestTime": Int(startTime.timeIntervalSince1970 * 1000),
            "durationMs": Int(Date().timeIntervalSince(startTime) * 1000),
            "requestHeaders": req?.headers ?? [:],
            "responseHeaders": headers,
            "responseBody": base64Body ?? NSNull(),
            "requestSize": requestData.count,
            "responseSize": responseData.count,
            "isTls": isTls,
            "mocked": mocked,
            "contentType": ct,
            "uid": -1,
            "appPackage": "",
            "appLabel": ""
        ]
        RecordStore.shared.append(record)
    }

    private func recordPassthrough(host: String) {
        guard let provider = provider else { return }
        guard provider.shouldRecord(host: host) else { return }
        let record: [String: Any] = [
            "recType": "passthrough",
            "id": "\(provider.currentSessionId())_\(Int(startTime.timeIntervalSince1970 * 1000))_\(host)",
            "sessionId": provider.currentSessionId(),
            "host": host,
            "port": Int(port),
            "tls": true,
            "reason": "HTTPS(SNI)",
            "uid": -1,
            "appPackage": "",
            "appLabel": "",
            "startTime": Int(startTime.timeIntervalSince1970 * 1000),
            "upBytes": requestData.count,
            "downBytes": responseData.count
        ]
        RecordStore.shared.append(record)
    }
}
