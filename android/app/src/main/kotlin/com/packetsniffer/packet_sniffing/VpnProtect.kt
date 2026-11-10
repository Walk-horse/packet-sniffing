package com.packetsniffer.packet_sniffing

import android.util.Log
import java.net.DatagramSocket
import java.net.Socket

/**
 * VPN 出站保活桥。
 *
 * 在 VPN 接管整机路由（addRoute 0.0.0.0/0）的环境下，本 App 自己创建、需要真正
 * 出网的 socket 必须先调用 VpnService.protect()，否则发出的包会被 VPN 自身再次接管
 * 路由，形成环路（黑洞）——典型表现就是三方 App 全部"无网络"，尤其 DNS(UDP/53) 被
 * 环路后任何域名都解析不了。
 *
 * 仅连接本机回环 127.0.0.1（本地代理 LocalProxyServer）的 socket 不需要 protect。
 */
object VpnProtect {
    private const val TAG = "VpnProtect"

    /** 由 CaptureVpnService 在 startCapture 时登记、stopCapture 时清空。 */
    @Volatile var service: CaptureVpnService? = null

    fun protect(socket: Socket): Boolean {
        val svc = service ?: run {
            Log.w(TAG, "protect(Socket): service 未就绪，跳过")
            return false
        }
        return runCatching { svc.protect(socket) }
            .onFailure { Log.w(TAG, "protect(Socket) failed: ${it.message}") }
            .getOrDefault(false)
    }

    fun protect(socket: DatagramSocket): Boolean {
        val svc = service ?: run {
            Log.w(TAG, "protect(DatagramSocket): service 未就绪，跳过")
            return false
        }
        return runCatching { svc.protect(socket) }
            .onFailure { Log.w(TAG, "protect(DatagramSocket) failed: ${it.message}") }
            .getOrDefault(false)
    }
}
