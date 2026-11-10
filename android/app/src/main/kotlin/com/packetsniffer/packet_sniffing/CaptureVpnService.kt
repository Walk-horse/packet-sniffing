package com.packetsniffer.packet_sniffing

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.util.Timer
import java.util.TimerTask
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 抓包 VPN 服务：建立本地 TUN，接管整机流量，
 * TCP 中继给 [LocalProxyServer] 解析，UDP（DNS）直接转发。
 * 解析出的 HTTP(S) 记录与透传记录经 [EventBridge] 流式上报 Dart 侧。
 */
class CaptureVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.packetsniffer.START"
        const val ACTION_STOP = "com.packetsniffer.STOP"
        private const val TAG = "CaptureVpnService"
        private const val NOTIF_ID = 1001
        private const val CHANNEL_ID = "capture"
        private const val CHANNEL_NAME = "抓包服务"
        private const val NOTIF_TEXT = "正在抓包，点击停止"
    }

    private var tun: ParcelFileDescriptor? = null
    @Volatile private var active = false
    private var readerThread: Thread? = null

    private val writeLock = Any()
    private var tunOutput: FileOutputStream? = null

    private val tcpSessions = ConcurrentHashMap<String, TcpSession>()
    private val udpSessions = ConcurrentHashMap<String, UdpSession>()

    private val proxyServer = LocalProxyServer()
    private val cleaner = Executors.newSingleThreadScheduledExecutor()
    @Volatile private var packetCount = 0L
    private var connectivityManager: ConnectivityManager? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var activeNetwork: Network? = null

    @Volatile private var upBytes: Long = 0
    @Volatile private var downBytes: Long = 0
    private var statsTimer: Timer? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopCapture()
            else -> startCapture()
        }
        return START_STICKY
    }

    private fun startCapture() {
        if (active) return
        startForegroundInternal()
        // 日志文件要在最开始就建好：后面的启动失败 / 早期请求才有地方落
        val targets = CaptureBridge.allowedPackages
        FileLogger.start(
            applicationContext,
            buildString {
                append("目标应用：")
                append(
                    if (targets.isEmpty()) "全部应用（排除本机）"
                    else CaptureBridge.allowedAppLabel.ifEmpty { targets.joinToString("、") }
                )
                append("\n抓包模式：")
                append(
                    when {
                        CaptureBridge.whitelistEnabled && CaptureBridge.whitelist.isNotEmpty() -> "白名单"
                        CaptureBridge.blacklistEnabled && CaptureBridge.blacklist.isNotEmpty() -> "黑名单"
                        else -> "全局"
                    }
                )
                append("\nHTTPS 代理：").append(if (CaptureMode.httpsProxyOn()) "开启" else "关闭")
                append("\n资源放行：").append(if (CaptureMode.skipResourcesOn()) "开启" else "关闭")
            }
        )
        try {
            proxyServer.start(applicationContext)
        } catch (e: Exception) {
            Log.e(TAG, "proxy start failed", e)
            FileLogger.log("❌ 本地代理启动失败：${e.message}")
            FileLogger.stop()
            stopSelf()
            return
        }
        FileLogger.log("本地代理端口：${proxyServer.port}")
        UidResolver.init(applicationContext)
        MitmExclusions.init(applicationContext)
        // 「不信任本机 CA」的应用名单会跨会话保留：先把它写进日志，便于解释为什么某些域名只有透传
        runCatching {
            val excluded = MitmExclusions.snapshot()
            if (excluded.isNotEmpty()) {
                FileLogger.log(
                    "已排除解密的域名（不信任本机 CA，直接透传）：${excluded.joinToString("、")}"
                )
            }
        }
        // 每次开始抓包清空 MITM 证书缓存，之前因 CA 未装好而失败的 host 有机会重试。
        LocalProxyServer.clearMitmCache()

        val fd: ParcelFileDescriptor? = Builder()
            .setSession("抓包精灵")
            .setMtu(1500)
            .addAddress("10.0.0.2", 24)
            .addRoute("0.0.0.0", 0)
            .addDnsServer("223.5.5.5")
            .setBlocking(true)
            .apply {
                // 目标应用：只抓取这些应用的流量，其余应用照常联网。
                // 注意：addAllowedApplication 与 addDisallowedApplication 互斥，二者不能同用。
                var added = 0
                if (targets.isNotEmpty()) {
                    for (target in targets) {
                        try {
                            addAllowedApplication(target)
                            added++
                        } catch (e: Exception) {
                            Log.w(TAG, "addAllowedApplication($target) failed: ${e.message}")
                            FileLogger.log("⚠️ 应用 $target 无法纳入抓包：${e.message}")
                        }
                    }
                    if (added == 0) {
                        // 一个都没加进去（应用被卸载等）：退化为抓全部
                        CaptureBridge.allowedPackages = emptySet()
                        CaptureBridge.allowedAppLabel = ""
                        FileLogger.log("⚠️ 目标应用全部无效，退化为抓取全部应用")
                    }
                }
                if (added == 0) {
                    // 无目标应用：抓取全部，但排除本 App 自身流量，避免代理出站被环回
                    try { addDisallowedApplication(packageName) } catch (_: Exception) {}
                }
                // 「HTTPS 代理」开关（参考 ProxyPin）：把整机 HTTP/HTTPS 系统代理指向本机代理端口，
                // 使 WebView/H5 等不走系统代理就会直连 + 抢 QUIC 的流量也能被 MITM。
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && CaptureMode.httpsProxyOn()) {
                    try {
                        setHttpProxy(ProxyInfo.buildDirectProxy("127.0.0.1", proxyServer.port))
                        Log.i(TAG, "system http proxy set -> 127.0.0.1:${proxyServer.port}")
                    } catch (e: Exception) {
                        Log.w(TAG, "setHttpProxy failed: ${e.message}")
                        FileLogger.log("⚠️ 系统 HTTPS 代理设置失败：${e.message}")
                    }
                }
            }
            .establish()

        if (fd == null) {
            Log.e(TAG, "establish failed")
            FileLogger.log("❌ TUN 建立失败（establish 返回 null），抓包未启动")
            FileLogger.stop()
            stopSelf()
            return
        }
        tun = fd
        tunOutput = FileOutputStream(fd.fileDescriptor)
        bindUnderlyingNetwork()
        VpnProtect.service = this
        active = true

        EventBridge.startSession("session-${UUID.randomUUID()}")
        readerThread = Thread({ readLoop(fd) }, "tun-reader").apply { isDaemon = true }
        readerThread?.start()

        cleaner.scheduleWithFixedDelay({ cleanIdleSessions() }, 30, 30, TimeUnit.SECONDS)
        statsTimer = Timer("vpn-stats", true).also { t ->
            t.scheduleAtFixedRate(object : TimerTask() {
                override fun run() {
                    if (!active) return
                    CaptureBridge.emit(
                        mapOf(
                            "type" to "stats",
                            "upload" to upBytes,
                            "download" to downBytes
                        )
                    )
                }
            }, 1000L, 1000L)
        }
        FileLogger.log("✅ VPN 已建立，TUN 网关 10.0.0.2，开始抓包")
        Log.i(TAG, "capture started")
    }

    private fun readLoop(fd: ParcelFileDescriptor) {
        val input = FileInputStream(fd.fileDescriptor)
        val buf = ByteArray(32767)
        while (active) {
            val n = try {
                input.read(buf)
            } catch (e: Exception) {
                if (active) {
                    Log.w(TAG, "tun read error: ${e.message}")
                    FileLogger.log("⚠️ TUN 读取异常，抓包线程退出：${e.message}")
                }
                break
            }
            if (n <= 0) continue
            try {
                dispatch(buf, n)
            } catch (e: Exception) {
                Log.w(TAG, "dispatch error: ${e.message}")
            }
        }
    }

    private fun dispatch(buf: ByteArray, n: Int) {
        packetCount++
        val ip = Packet.parseIp(buf, n) ?: return
        when (ip.protocol) {
            Packet.PROTO_TCP -> {
                val tcp = Packet.parseTcp(buf, ip) ?: return
                if (!isTunAddress(ip.src)) return
                val key = "${Packet.ipKey(ip.src)}:${tcp.srcPort}->${Packet.ipKey(ip.dst)}:${tcp.dstPort}"
                val session = tcpSessions.getOrPut(key) {
                    TcpSession(
                        key = key,
                        appIp = ip.src, appPort = tcp.srcPort,
                        remoteIp = ip.dst, remotePort = tcp.dstPort,
                        proxyPort = proxyServer.port,
                        uid = resolveUid(
                            localIp = Packet.ipKey(ip.src), localPort = tcp.srcPort,
                            remoteIp = Packet.ipKey(ip.dst), remotePort = tcp.dstPort
                        ),
                        resolveUid = {
                            resolveUid(
                                localIp = Packet.ipKey(ip.src), localPort = tcp.srcPort,
                                remoteIp = Packet.ipKey(ip.dst), remotePort = tcp.dstPort
                            )
                        },
                        writeToTun = { writeToTun(it) },
                        onClose = { tcpSessions.remove(it) }
                    )
                }
                session.onAppSegment(ip, tcp, buf)
            }
            Packet.PROTO_UDP -> {
                val udp = Packet.parseUdp(buf, ip) ?: return
                if (!isTunAddress(ip.src)) return
                if (udp.dstPort == 443 && CaptureMode.quicBlockOn()) {
                    // QUIC 回退：丢弃到 443 的 UDP，App 会回退到 HTTPS(HTTP/2) 供 MITM 解密
                    return
                }
                val key = "udp:${Packet.ipKey(ip.src)}:${udp.srcPort}->${Packet.ipKey(ip.dst)}:${udp.dstPort}"
                val session = udpSessions.getOrPut(key) {
                    UdpSession(
                        key = key,
                        appIp = ip.src, appPort = udp.srcPort,
                        remoteIp = ip.dst, remotePort = udp.dstPort,
                        writeToTun = { writeToTun(it) },
                        onClose = { udpSessions.remove(it) }
                    )
                }
                session.onAppDatagram(buf, udp)
            }
        }
        // 流量统计：源地址是本机 TUN 地址算上行，否则下行
        if (isTunAddress(ip.src)) upBytes += ip.totalLen.toLong() else downBytes += ip.totalLen.toLong()
    }

    private fun resolveUid(localIp: String, localPort: Int, remoteIp: String, remotePort: Int): Int {
        val detected = UidResolver.uidOf(localIp, localPort, remoteIp, remotePort)
        return detected.takeIf { it >= 0 } ?: -1
    }

    private fun isTunAddress(ip: ByteArray): Boolean =
        ip.size == 4 && ip[0].toInt() == 10 && ip[1].toInt() == 0 && ip[2].toInt() == 0

    private fun writeToTun(packet: ByteArray) {
        synchronized(writeLock) {
            try {
                tunOutput?.write(packet)
                tunOutput?.flush()
            } catch (e: Exception) {
                Log.w(TAG, "tun write: ${e.message}")
            }
        }
    }

    private fun cleanIdleSessions() {
        val now = System.currentTimeMillis()
        tcpSessions.values.filter { now - it.lastActive > 180_000 }.forEach { it.close() }
        udpSessions.values.filter { now - it.lastActive > 90_000 }.forEach { it.close() }
    }

    private fun stopCapture() {
        if (!active) return
        active = false
        VpnProtect.service = null
        tcpSessions.values.forEach { it.close() }
        udpSessions.values.forEach { it.close() }
        tcpSessions.clear(); udpSessions.clear()
        proxyServer.stop()
        unregisterNetworkCallback()
        try { tun?.close() } catch (_: Exception) {}
        tun = null
        tunOutput = null
        cleaner.shutdownNow()
        statsTimer?.cancel()
        statsTimer = null
        EventBridge.endSession()
        FileLogger.log("VPN 服务停止")
        FileLogger.stop(upBytes, downBytes)
        stopForeground(true)
        stopSelf()
        Log.i(TAG, "capture stopped")
    }

    private fun bindUnderlyingNetwork() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val cm = getSystemService(CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        connectivityManager = cm
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                activeNetwork = network
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    runCatching { setUnderlyingNetworks(arrayOf(network)) }
                        .onFailure { Log.w(TAG, "setUnderlyingNetworks failed: ${it.message}") }
                }
            }
        }
        networkCallback = callback
        try {
            cm.registerDefaultNetworkCallback(callback)
        } catch (e: Exception) {
            Log.w(TAG, "register default network callback failed: ${e.message}")
            networkCallback = null
        }
    }

    private fun unregisterNetworkCallback() {
        val cm = connectivityManager
        val callback = networkCallback
        if (cm != null && callback != null) {
            runCatching { cm.unregisterNetworkCallback(callback) }
        }
        networkCallback = null
        connectivityManager = null
        activeNetwork = null
    }

    private fun startForegroundInternal() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_LOW)
            )
        }
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.let {
            PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL_ID)
        else Notification.Builder(this)
        val notif = builder
            .setContentTitle(CHANNEL_NAME)
            .setContentText(NOTIF_TEXT)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(launch)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIF_ID, notif, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, notif)
        }
    }

    override fun onDestroy() {
        stopCapture()
        super.onDestroy()
    }

    override fun onRevoke() {
        stopCapture()
        super.onRevoke()
    }
}
