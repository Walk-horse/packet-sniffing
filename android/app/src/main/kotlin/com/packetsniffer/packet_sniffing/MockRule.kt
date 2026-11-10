package com.packetsniffer.packet_sniffing

/**
 * 一条接口模拟规则。匹配维度：应用（按包名）→ 规则开关 → method / host / path。
 * body 为空时表示「未配置示例」，由 MockEngine 按响应类型自动生成占位示例。
 *
 * 注：参考仓库的 yapiId / 桌面端同步字段均已移除（本实现只做移动端本地模拟）。
 */
data class MockRule(
    val id: String,
    val enabled: Boolean = true,
    val name: String = "",
    val method: String = "*",
    val host: String = "",
    val path: String = "",
    val statusCode: Int = 200,
    val contentType: String = "application/json",
    val body: String = "",
    val delayMs: Long = 0,
    val headers: List<Pair<String, String>> = emptyList()
) {
    /** 是否自定义了响应示例（否则按响应类型自动生成） */
    val hasCustomBody: Boolean get() = body.isNotBlank()
}
