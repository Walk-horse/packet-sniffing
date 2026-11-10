package com.packetsniffer.packet_sniffing

/**
 * 抓包记录的事件桥：把原生解析出的完整 [HttpExchange] / [PassthroughRec] / 会话状态，
 * 经由 [CaptureBridge.emit] 通过 EventChannel 流式发给 Dart 侧。
 * 与参考实现不同，这里不再使用 Kotlin StateFlow（Compose 专用），改为单向事件流，
 * Dart 侧自行维护列表与详情。
 */
object EventBridge {

    /** 当前进行中的 session id（每条请求/透传记录会带上它） */
    @Volatile var currentSessionId: String = ""

    fun add(e: HttpExchange) {
        if (currentSessionId.isNotEmpty()) e.sessionId = currentSessionId
        CaptureBridge.emit(mapOf("type" to "request_add", "data" to e.toJson()))
    }

    /** 请求已落定（响应到达 / 失败）：用于更新既有记录 */
    fun update(e: HttpExchange) {
        CaptureBridge.emit(mapOf("type" to "request_update", "data" to e.toJson()))
        // 抓包日志：只在这里记一行，add 阶段还没有状态码/耗时
        FileLogger.request(e)
    }

    fun addPassthrough(p: PassthroughRec) {
        if (currentSessionId.isNotEmpty()) p.sessionId = currentSessionId
        CaptureBridge.emit(mapOf("type" to "passthrough_add", "data" to p.toJson()))
        FileLogger.passthrough(p, finish = false)
    }

    fun finishPassthrough(p: PassthroughRec) {
        CaptureBridge.emit(mapOf("type" to "passthrough_update", "data" to p.toJson()))
    }

    fun startSession(id: String) {
        currentSessionId = id
        CaptureBridge.emit(mapOf("type" to "session", "data" to mapOf("state" to "started", "id" to id)))
    }

    fun endSession() {
        currentSessionId = ""
        CaptureBridge.emit(mapOf("type" to "session", "data" to mapOf("state" to "stopped")))
    }

    fun clearHistory() = CaptureBridge.emit(mapOf("type" to "clear_history"))
    fun clearCurrent() = CaptureBridge.emit(mapOf("type" to "clear_current"))
}
