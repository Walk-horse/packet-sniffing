import Flutter
import UIKit
import NetworkExtension

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

    /// 与主 App / Network Extension 共享配置的 App Group。
    private let appGroupID = "group.com.packetsniffer.packetSniffing"
    /// iOS Network Extension（Transparent Proxy）的 bundle id，须与 pbxproj 中 NE target 一致。
    private let tunnelBundleID = "com.packetsniffer.packetSniffing.tunnel"
    /// NE 写入的抓包记录文件名（App Group 容器内 JSONL）。
    private let recordFileName = "capture_records.jsonl"

    private var capturing = false
    private var eventSink: FlutterEventSink?
    private var pollTimer: Timer?
    private var recordOffset: UInt64 = 0

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        // iOS 抓包通道：主 App 通过 App Group 把配置下发给 Network Extension，
        // 并由 NETunnelProviderManager 控制 NE 的启停。
        let channel = FlutterMethodChannel(
            name: "packetsniffing/capture",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handleCapture(call: call, result: result)
        }

        // 实时事件通道（请求/透传/会话/统计）。iOS 端记录经 App Group 文件回读（后续），
        // 这里先提供空流，避免 Dart 侧 listen 因「无 handler」而报错。
        let events = FlutterEventChannel(
            name: "packetsniffing/events",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        events.setStreamHandler(self)
    }

    // MARK: - MethodChannel 分发

    private func handleCapture(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            result(FlutterError(
                code: "APP_GROUP_UNAVAILABLE",
                message: "App Group (\(appGroupID)) 不可用",
                details: nil
            ))
            return
        }

        switch call.method {
        case "launchOptions":
            // iOS 端无 adb 直达参数，返回空。
            result([String: Any]())

        case "setFilter":
            if let m = call.arguments as? [String: Any] {
                if let bl = m["blacklist"] as? [String] { defaults.set(bl, forKey: "blacklist") }
                if let wl = m["whitelist"] as? [String] { defaults.set(wl, forKey: "whitelist") }
                if let be = m["blacklistEnabled"] as? Bool { defaults.set(be, forKey: "blacklistEnabled") }
                if let we = m["whitelistEnabled"] as? Bool { defaults.set(we, forKey: "whitelistEnabled") }
            }
            result(nil)

        case "setMocks":
            if let rules = call.arguments as? [[String: Any]] {
                defaults.set(rules, forKey: "mockRules")
            }
            result(nil)

        case "setMockEnabled":
            if let enabled = call.arguments as? Bool {
                defaults.set(enabled, forKey: "mockEnabled")
            }
            result(nil)

        case "setMockApps":
            // iOS 不做「按 App 分组」（免费账号 + NE 限制），接受参数但不按 App 过滤。
            if let apps = call.arguments as? [String] {
                defaults.set(apps, forKey: "mockApps")
            }
            result(nil)

        case "startCapture":
            startTunnel(arguments: call.arguments, defaults: defaults, result: result)

        case "stopCapture":
            stopTunnel(result: result)

        case "installCa":
            // iOS 安装 CA 需「设置 → 通用 → VPN与设备管理」导入描述文件，
            // 免费账号无法在 NE 内做 MITM，应用内无法直接调起安装。
            result([
                "ok": false,
                "message": "iOS 需手动在「设置 → 通用 → VPN与设备管理」安装 CA 描述文件（免费账号暂不支持应用内安装/NE 内 MITM）。"
            ])

        case "exportCa":
            result("iOS 端 CA 导出需配合描述文件，当前骨架未生成 CA 文件。")

        case "listApps":
            // iOS 隐私限制不暴露其它 App 列表，返回空。
            result([Any]())

        case "appLabel", "launchApp", "moveTaskToBack", "bringToFront",
             "relaxOverlay", "setWindowMode", "setHttpsProxy", "clearMitmCache", "clearLogs":
            // 这些 Android 专属入口在 iOS 上无直接对应，先安全返回。
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Network Extension 启停（iOS 抓包控制路径）

    private func startTunnel(
        arguments: Any?,
        defaults: UserDefaults,
        result: @escaping FlutterResult
    ) {
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let error = error {
                DispatchQueue.main.async {
                    result(["ok": false, "message": "读取 NE 配置失败：\(error.localizedDescription)"])
                }
                return
            }
            let manager: NETunnelProviderManager
            if let existing = managers?.first {
                manager = existing
            } else {
                manager = NETunnelProviderManager()
                let proto = NETunnelProviderProtocol()
                proto.providerBundleIdentifier = self.tunnelBundleID
                proto.serverAddress = "127.0.0.1"
                proto.includeAllNetworks = true
                manager.protocolConfiguration = proto
                manager.localizedDescription = "PacketSniffer"
            }
            manager.isEnabled = true

            manager.saveToPreferences { saveError in
                if let saveError = saveError {
                    DispatchQueue.main.async {
                        result(["ok": false, "message": "保存 NE 配置失败：\(saveError.localizedDescription)"])
                    }
                    return
                }
                // saveToPreferences 后需重新 load 才能拿到可用的 connection。
                manager.loadFromPreferences { loadError in
                    if let loadError = loadError {
                        DispatchQueue.main.async {
                            result(["ok": false, "message": "重载 NE 配置失败：\(loadError.localizedDescription)"])
                        }
                        return
                    }
                    do {
                        try manager.connection.startVPNTunnel(options: nil)
                        self.capturing = true
                        self.recordOffset = 0
                        DispatchQueue.main.async {
                            result(["ok": true])
                        }
                    } catch {
                        DispatchQueue.main.async {
                            result(["ok": false, "message": "启动 NE 失败：\(error.localizedDescription)"])
                        }
                    }
                }
            }
        }
    }

    private func stopTunnel(result: @escaping FlutterResult) {
        capturing = false
        pollTimer?.invalidate()
        pollTimer = nil
        if let sink = eventSink {
            sink(["type": "session", "state": "stopped"])
        }
        NETunnelProviderManager.loadAllFromPreferences { managers, error in
            if let manager = managers?.first, error == nil {
                manager.connection.stopVPNTunnel()
            }
            DispatchQueue.main.async {
                result(["ok": true])
            }
        }
    }

    // MARK: - 记录轮询（App Group -> Flutter 事件通道）

    private func startPollingIfNeeded() {
        guard capturing, pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollRecords()
        }
    }

    private func pollRecords() {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        let url = dir.appendingPathComponent(recordFileName)
        guard let fh = try? FileHandle(forReadingFrom: url) else { return }
        defer { fh.closeFile() }
        let size = (try? fh.seekToEnd()) ?? 0
        guard size > recordOffset else { return }
        fh.seek(toFileOffset: recordOffset)
        let chunk = fh.readDataToEndOfFile()
        recordOffset = size
        guard let text = String(data: chunk, encoding: .utf8), let sink = eventSink else { return }
        for line in text.split(separator: "\n") where !line.isEmpty {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
                  let dict = obj as? [String: Any],
                  let type = dict["recType"] as? String else { continue }
            let event = (type == "passthrough") ? "passthrough_add" : "request_add"
            sink(["type": event, "data": dict])
        }
    }
}

// MARK: - 事件通道（NE 记录 -> Flutter）

extension AppDelegate: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        // Dart 订阅时若已在抓包，补发 session 事件并启动轮询。
        if capturing {
            events(["type": "session", "state": "started",
                    "id": "ios_\(Int(Date().timeIntervalSince1970))"])
            startPollingIfNeeded()
        }
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
