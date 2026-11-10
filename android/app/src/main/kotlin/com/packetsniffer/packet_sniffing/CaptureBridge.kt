package com.packetsniffer.packet_sniffing

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel

/**
 * 跨线程/跨组件的事件桥：
 * - [eventSink] 由 Flutter 的 EventChannel 持有，捕获线程解析到数据包后通过它把事件流回 Dart。
 * - [filterHosts] / [acceptAll] 等状态由 MethodChannel 下发，供捕获线程做黑白名单过滤。
 *
 * 注意：EventSink 的方法带 @UiThread 约束，必须投递到主线程调用，
 * 否则会抛 "Methods marked with @UiThread must be executed on the main thread"，
 * 表现为「VPN 已建立但列表一直是 0 条」。
 */
object CaptureBridge {
    private const val TAG = "PacketSniffer"

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    var eventSink: EventChannel.EventSink? = null

    // 黑名单/白名单（域名或 IP 子串）
    var blacklist: List<String> = emptyList()
    var whitelist: List<String> = emptyList()
    var blacklistEnabled = false
    var whitelistEnabled = false

    /**
     * 要抓包的应用包名集合。非空时 VpnService 用 addAllowedApplication 把这些应用
     * 逐个纳入 VPN，其余应用不受影响（见 CaptureVpnService.startCapture）。
     * 空集合表示抓全部应用。
     */
    @Volatile
    var allowedPackages: Set<String> = emptySet()

    /** 目标应用名，仅用于日志/悬浮窗展示 */
    @Volatile
    var allowedAppLabel: String = ""

    // 接口模拟（mock）配置：总开关、按应用包名集合、规则列表（内存态，由 Dart 下发）
    @Volatile
    var mockEnabled: Boolean = false
    @Volatile
    var mockApps: Set<String> = emptySet()
    @Volatile
    var mockRules: List<MockRule> = emptyList()

    private var emitCount = 0L

    fun matchFilter(host: String): Boolean {
        if (whitelistEnabled && whitelist.isNotEmpty()) {
            return whitelist.any { host.contains(it, ignoreCase = true) }
        }
        if (blacklistEnabled && blacklist.isNotEmpty()) {
            return !blacklist.any { host.contains(it, ignoreCase = true) }
        }
        return true
    }

    fun emit(map: Map<String, Any?>) {
        val sink = eventSink ?: run {
            Log.w(TAG, "emit dropped (sink==null): ${map["type"]}")
            return
        }
        mainHandler.post {
            try {
                sink.success(map)
                emitCount++
                if (emitCount <= 5 || emitCount % 200L == 0L) {
                    Log.d(TAG, "emit #$emitCount type=${map["type"]}")
                }
            } catch (e: Exception) {
                Log.e(TAG, "emit failed: ${e.message}")
            }
        }
    }

    fun emitLog(name: String, content: String) {
        Log.d(TAG, "log[$name] $content")
        // 追加语义：Dart 侧按 name 拼接，避免后一条覆盖前一条
        emit(mapOf("type" to "log_append", "name" to name, "content" to content))
    }
}
