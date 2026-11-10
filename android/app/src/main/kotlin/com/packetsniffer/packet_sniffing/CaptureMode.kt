package com.packetsniffer.packet_sniffing

/**
 * 抓包模式（基于 Dart 下发的黑白名单，见 [CaptureBridge]）：
 *  - 黑名单模式：名单内域名不解密（直接透传），其余正常抓包
 *  - 白名单模式：只解密名单内域名，其余透传
 *  两者都关闭 = 全局抓包
 */
object CaptureMode {

    /** 该 host 是否应当 MITM 解密（false = 透传不解析） */
    fun shouldMitm(host: String): Boolean {
        if (CaptureBridge.whitelistEnabled && CaptureBridge.whitelist.isNotEmpty())
            return matches(CaptureBridge.whitelist, host)
        if (CaptureBridge.blacklistEnabled && CaptureBridge.blacklist.isNotEmpty())
            return !matches(CaptureBridge.blacklist, host)
        return true
    }

    /**
     * 默认**不**拦截 QUIC(UDP 443)。
     *
     * 早期为了把 HTTP/3 流量逼回 HTTP/2 以便解密，会静默丢弃 UDP 443；
     * 但被丢的包不会回 ICMP，App 只能干等到超时，表现为「图片/卡片加载不出来」。
     * 现在改为正常转发：代价是 h3 流量在列表里看不到（透传列表有记录），
     * 换来页面资源能正常加载 —— 用户要的是「抓包时 App 还能用」。
     */
    fun quicBlockOn(): Boolean = quicBlockEnabled

    @Volatile
    var quicBlockEnabled: Boolean = false

    /** 「HTTPS 代理（系统代理）」开关：抓取 WebView/H5 等直连 + 抢 QUIC 的流量。可由 Dart 切换。 */
    @Volatile var httpsProxyEnabled: Boolean = true

    /** 是否启用系统 HTTPS 代理（参考 ProxyPin）。 */
    fun httpsProxyOn(): Boolean = httpsProxyEnabled

    /**
     * 用户是否在「抓包模式」白名单里显式点名了该 host。
     * 命中时即便它看起来是资源域名、或之前握手失败过，也要按用户意思做 MITM，
     * 否则用户配了白名单却发现抓不到，会很困惑。
     */
    fun explicitlyRequested(host: String): Boolean =
        CaptureBridge.whitelistEnabled && CaptureBridge.whitelist.isNotEmpty() &&
            matches(CaptureBridge.whitelist, host)

    /** 资源放行：图片/文件等命中后缀的请求直接透明转发，不解析、不进抓包列表。默认开启。 */
    @Volatile var skipResources: Boolean = true

    /** 是否放行资源型请求（图片/文件等）。 */
    fun skipResourcesOn(): Boolean = skipResources

    private fun matches(list: List<String>, host: String): Boolean {
        val h = host.lowercase()
        return list.any { d ->
            val dd = d.lowercase().trim()
            dd == h || (dd.startsWith("*.") && h.endsWith(dd.substring(1))) ||
                (dd.startsWith(".") && h.endsWith(dd))
        }
    }
}
