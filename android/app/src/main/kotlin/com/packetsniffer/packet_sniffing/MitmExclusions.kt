package com.packetsniffer.packet_sniffing

import android.content.Context
import android.util.Log

/**
 * 「不要对它做 MITM」的域名名单（持久化到 SharedPreferences）。
 *
 * 来源：MITM 握手被 App 拒绝（内置证书库 / SSL Pinning / 不信任用户 CA）。
 * 这类域名再尝试解密只会失败，表现就是图片、统计、部分内容加载不出来。
 * 记住之后直接透传 —— App 与真实服务器正常 TLS，页面能正常渲染。
 *
 * 只在域名粒度排除，不做「整个应用透传」：
 * 用户的核心诉求是「抓得到接口」，能成功解密的域名必须继续抓。
 *
 * 每个域名10 分钟后自动过期再试一次 MITM：
 *  - 真 Pinning 的域名：每隔约 10 分钟死一条连接，随后又回到透传，代价可忽略；
 *  - 被误伤的域名（偶发握手失败）：下次重试成功即恢复解密。
 * 也可以在「HTTPS 抓包 → 清空 MITM 缓存」手动清空。
 */
object MitmExclusions {
    private const val TAG = "MitmExclusions"
    private const val PREFS = "mitm_exclusions"
    private const val KEY_HOSTS = "hosts"
    private const val HOST_TTL = 10 * 60 * 1000L

    private var appContext: Context? = null
    /** host -> 加入时间戳 */
    private val hosts = java.util.concurrent.ConcurrentHashMap<String, Long>()

    fun init(context: Context) {
        appContext = context.applicationContext
        if (hosts.isNotEmpty()) return
        runCatching {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            prefs.getStringSet(KEY_HOSTS, emptySet())?.forEach { entry ->
                // 格式 "host@timestamp"
                val sep = entry.lastIndexOf('@')
                if (sep <= 0) return@forEach
                val host = entry.substring(0, sep)
                val at = entry.substring(sep + 1).toLongOrNull() ?: 0L
                if (host.isNotEmpty() && now - at <= HOST_TTL) hosts[host] = at
            }
        }.onFailure { Log.w(TAG, "load failed: ${it.message}") }
    }

    fun contains(host: String): Boolean {
        if (host.isEmpty()) return false
        val at = hosts[host] ?: return false
        if (System.currentTimeMillis() - at > HOST_TTL) {
            hosts.remove(host)
            return false
        }
        return true
    }

    /** @return true 表示这是新加入（或过期后重新加入）的域名（调用方据此打日志） */
    fun add(host: String): Boolean {
        if (host.isEmpty()) return false
        val now = System.currentTimeMillis()
        val prev = hosts[host]
        if (prev != null && now - prev <= HOST_TTL) {
            hosts[host] = now // 持续失败就持续顺延
            return false
        }
        hosts[host] = now
        persist()
        return true
    }

    fun clear() {
        hosts.clear()
        runCatching {
            appContext?.getSharedPreferences(PREFS, Context.MODE_PRIVATE)?.edit()?.clear()?.apply()
        }
    }

    fun snapshot(): Set<String> {
        val now = System.currentTimeMillis()
        hosts.entries.removeAll { now - it.value > HOST_TTL }
        return hosts.keys.toSet()
    }

    private fun persist() {
        val ctx = appContext ?: return
        val snapshot = hosts.entries.joinToString("\n") { "${it.key}@${it.value}" }
        Thread {
            runCatching {
                ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putStringSet(KEY_HOSTS, snapshot.split("\n").toSet())
                    .apply()
            }
        }.apply { isDaemon = true }.start()
    }
}
