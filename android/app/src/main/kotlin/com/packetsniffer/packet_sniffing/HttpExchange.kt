package com.packetsniffer.packet_sniffing

import android.util.Base64
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong

/** 一条被抓取到的 HTTP(S) 请求/响应记录 */
class HttpExchange(
    val id: String = UUID.randomUUID().toString(),
    val scheme: String,          // http / https
    val host: String,
    val port: Int,
    val isTls: Boolean
) {
    enum class State { PENDING, COMPLETE, FAILED }

    var method: String = ""
    var path: String = ""
    var requestHeaders: List<Pair<String, String>> = emptyList()
    var requestBody: ByteArray = ByteArray(0)

    var statusCode: Int = 0
    var statusText: String = ""
    var responseHeaders: List<Pair<String, String>> = emptyList()
    var responseBody: ByteArray = ByteArray(0)

    var state: State = State.PENDING
    var error: String? = null

    /** 所属抓包 session id */
    var sessionId: String = ""

    /** 是否收藏 */
    var favorite: Boolean = false

    /** 该响应由「接口模拟」返回（未走真实服务器） */
    var mocked: Boolean = false

    /** 模拟响应体是「按响应数据类型自动生成」的示例（规则未配置示例） */
    var mockAuto: Boolean = false

    /** 实际连接的远端 IP */
    var remoteIp: String? = null

    /** 发起请求的应用进程 uid（-1 表示未能解析） */
    var uid: Int = -1

    /** 发起请求的应用包名（由 uid 反查，未能解析则为空） */
    var appPackage: String = ""

    /** 发起请求的应用显示名（由 uid 反查，未能解析则为空） */
    var appLabel: String = ""

    val startTime: Long = System.currentTimeMillis()
    var endTime: Long = 0

    val url: String get() = "$scheme://$host${if ((scheme == "http" && port == 80) || (scheme == "https" && port == 443)) "" else ":$port"}$path"
    val durationMs: Long get() = if (endTime > 0) endTime - startTime else -1

    fun headerValue(headers: List<Pair<String, String>>, name: String): String? =
        headers.firstOrNull { it.first.equals(name, true) }?.second

    val responseContentType: String? get() = headerValue(responseHeaders, "Content-Type")
    val requestContentType: String? get() = headerValue(requestHeaders, "Content-Type")

    /** 序列化为 Dart 侧 RequestRecord 兼容的 Map（body 用 base64 字符串） */
    fun toJson(): Map<String, Any?> {
        return mapOf(
            "id" to id,
            "sessionId" to sessionId,
            "method" to method,
            "scheme" to scheme,
            "host" to host,
            "path" to path,
            "port" to port,
            "statusCode" to statusCode,
            "statusText" to statusText,
            "requestTime" to startTime,
            "durationMs" to durationMs,
            "requestHeaders" to requestHeaders.associate { it.first to it.second },
            "responseHeaders" to responseHeaders.associate { it.first to it.second },
            "requestBody" to if (requestBody.isEmpty()) null
            else Base64.encodeToString(requestBody, Base64.NO_WRAP),
            "responseBody" to if (responseBody.isEmpty()) null
            else Base64.encodeToString(responseBody, Base64.NO_WRAP),
            "requestSize" to requestBody.size,
            "responseSize" to responseBody.size,
            "remoteAddress" to (remoteIp ?: ""),
            "uid" to uid,
            "appPackage" to appPackage,
            "appLabel" to appLabel,
            "isError" to (state == State.FAILED),
            "errorReason" to error,
            "isFavorite" to favorite,
            "contentType" to (responseContentType ?: ""),
            "isTls" to isTls,
            "mocked" to mocked,
            "mockAuto" to mockAuto,
            "state" to state.name
        )
    }

    companion object {
        val counter = AtomicLong(0)
        const val MAX_BODY = 4 * 1024 * 1024 // body 存储上限 4MB（超出截断，尽量留全）
    }
}
