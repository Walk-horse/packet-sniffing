package com.packetsniffer.packet_sniffing

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

/**
 * 把「TUN 内 App 连接的四元组」映射为发起进程的 uid。
 *
 * 解析路径（按优先级）：
 * 1. Android 10+：[ConnectivityManager.getConnectionOwnerUid]（公开 API，API 29 起）。
 * 2. 回退：读 /proc/net/tcp（Android 10+ 普通应用不可读，仅 root / 旧系统有效）。
 */
object UidResolver {
    private const val TAG = "UidResolver"
    private const val SCAN_INTERVAL_MS = 300L

    @Volatile private var cm: ConnectivityManager? = null
    @Volatile private var appContext: Context? = null
    private val isolatedUidToAppUid = HashMap<Int, Int>()

    @Volatile private var procReadable = true
    @Volatile private var procWarned = false

    private val portToUid = HashMap<Int, Int>()
    private val connectionToUid = HashMap<String, Int>()
    @Volatile private var lastScan = 0L

    fun init(ctx: Context) {
        appContext = ctx.applicationContext
        if (cm == null) {
            cm = runCatching {
                ctx.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            }.getOrNull()
        }
    }

    fun uidOf(localIp: String, localPort: Int, remoteIp: String, remotePort: Int): Int {
        if (localPort <= 0) return -1
        var how = "cm"
        var uid = ownerUidViaConnectivity(localIp, localPort, remoteIp, remotePort)
        if (uid == null) {
            how = "proc"
            uid = uidOfConnection(localPort, remoteIp, remotePort).takeIf { it >= 0 }
        }
        val rawUid = uid ?: -1
        val resolved = canonicalAppUid(rawUid)
        if (resolved < 0 || logCount < 20) {
            val suffix = if (resolved != rawUid) " (isolated $rawUid -> app $resolved)" else ""
            Log.d(TAG, "uid($localIp:$localPort->$remoteIp:$remotePort)=$resolved via=$how$suffix")
        }
        logCount++
        return resolved
    }

    fun uidOfLocalProxyClient(socket: Socket): Int {
        val direct = uidOfSocket(socket)
        if (direct >= 0 && direct != Process.myUid()) return direct
        val fallback = foregroundAppUid()
        if (fallback >= 0) {
            Log.d(TAG, "proxy client uid fallback foreground=$fallback")
        }
        return fallback
    }

    /** 由 uid 反查主包名（多包时取第一个非系统的）。用于「按应用」分组展示。 */
    fun appPackageOf(uid: Int): String? {
        if (uid < 0) return null
        val context = appContext ?: return null
        val pkgs = runCatching { context.packageManager.getPackagesForUid(uid) }
            .getOrNull() ?: return null
        return pkgs.firstOrNull { it != "android" } ?: pkgs.firstOrNull()
    }

    /** 由 uid 反查应用显示名（label），用于「按应用」分组展示。 */
    fun appLabelOf(uid: Int): String? {
        val pkg = appPackageOf(uid) ?: return null
        val context = appContext ?: return null
        return runCatching {
            val info = context.packageManager.getApplicationInfo(pkg, 0)
            context.packageManager.getApplicationLabel(info).toString()
        }.getOrNull()
    }

    private fun uidOfSocket(socket: Socket): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1
        val local = socket.localSocketAddress as? InetSocketAddress ?: return -1
        val remote = socket.remoteSocketAddress as? InetSocketAddress ?: return -1
        val rawUid = ownerUidViaConnectivity(local, remote) ?: -1
        return canonicalAppUid(rawUid)
    }

    private fun foregroundAppUid(): Int {
        val context = appContext ?: return -1
        val selfUid = Process.myUid()
        val am = runCatching {
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        }.getOrNull() ?: return -1
        val processes = runCatching { am.runningAppProcesses.orEmpty() }.getOrNull().orEmpty()
        val ranked = processes
            .asSequence()
            .filter { it.uid >= 10000 && it.uid != selfUid }
            .filter {
                it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND ||
                    it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_VISIBLE
            }
            .sortedWith(
                compareBy<ActivityManager.RunningAppProcessInfo> {
                    if (it.uid in 99000..99999) 0 else 1
                }.thenBy {
                    if (it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND) 0 else 1
                }
            )
        for (process in ranked) {
            val packages = buildList {
                process.pkgList?.forEach { add(it) }
                process.processName?.substringBefore(':')?.takeIf { it.isNotBlank() }?.let { add(it) }
            }.distinct()
            for (pkg in packages) {
                val info = runCatching { context.packageManager.getApplicationInfo(pkg, 0) }.getOrNull()
                val isRenderer = process.uid in 99000..99999
                if (info != null && info.uid != selfUid &&
                    (info.uid == process.uid || (isRenderer && info.uid >= 10000))) {
                    if (isRenderer) {
                        isolatedUidToAppUid[process.uid] = info.uid
                        Log.i(TAG, "foreground renderer uid=${process.uid} package=$pkg appUid=${info.uid}")
                    }
                    return info.uid
                }
            }
        }
        return -1
    }

    private var logCount = 0

    private fun ownerUidViaConnectivity(
        localIp: String, localPort: Int, remoteIp: String, remotePort: Int
    ): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val c = cm ?: return null
        val localCandidates = LinkedHashSet<String>().apply {
            add(localIp)
            add("0.0.0.0")
            runCatching {
                c.allNetworks.forEach { network ->
                    c.getLinkProperties(network)?.linkAddresses?.forEach { link ->
                        link.address.hostAddress?.let { add(it) }
                    }
                }
            }
        }
        val remote = InetSocketAddress(remoteIp, remotePort)
        var lastError: Throwable? = null
        for (candidate in localCandidates) {
            try {
                val uid = c.getConnectionOwnerUid(
                    Packet.PROTO_TCP,
                    InetSocketAddress(candidate, localPort),
                    remote
                )
                if (uid >= 0) return uid
            } catch (t: Throwable) {
                lastError = t
            }
        }
        if (lastError != null && cmFailLog < 10) {
            cmFailLog++
            Log.w(TAG, "getConnectionOwnerUid failed: ${lastError.javaClass.simpleName}: ${lastError.message}")
        }
        return null
    }

    private fun ownerUidViaConnectivity(
        local: InetSocketAddress, remote: InetSocketAddress
    ): Int? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        val c = cm ?: return null
        val candidates = listOf(local to remote, remote to local)
        for ((candidateLocal, candidateRemote) in candidates) {
            try {
                val uid = c.getConnectionOwnerUid(Packet.PROTO_TCP, candidateLocal, candidateRemote)
                if (uid >= 0) return uid
            } catch (t: Throwable) {
                if (cmSocketFailLog < 10) {
                    cmSocketFailLog++
                    Log.w(TAG, "getConnectionOwnerUid(socket) failed: ${t.javaClass.simpleName}: ${t.message}")
                }
            }
        }
        return null
    }

    private var cmFailLog = 0
    private var cmSocketFailLog = 0

    @Synchronized
    private fun canonicalAppUid(rawUid: Int): Int {
        if (rawUid < 0) return rawUid
        isolatedUidToAppUid[rawUid]?.let { return it }
        val context = appContext ?: return rawUid
        val pm = context.packageManager
        val directPackages = runCatching { pm.getPackagesForUid(rawUid) }.getOrNull()
        if (!directPackages.isNullOrEmpty()) return rawUid

        val am = runCatching {
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        }.getOrNull() ?: return rawUid
        val process = runCatching {
            am.runningAppProcesses?.firstOrNull { it.uid == rawUid }
        }.getOrNull() ?: return rawUid
        val candidates = buildList {
            process.pkgList?.forEach { add(it) }
            process.processName?.substringBefore(':')?.takeIf { it.isNotBlank() }?.let { add(it) }
        }.distinct()
        for (pkg in candidates) {
            val appUid = runCatching { pm.getApplicationInfo(pkg, 0).uid }.getOrNull() ?: continue
            if (appUid >= 0 && appUid != rawUid) {
                isolatedUidToAppUid[rawUid] = appUid
                Log.i(TAG, "mapped isolated uid=$rawUid process=${process.processName} package=$pkg appUid=$appUid")
                return appUid
            }
        }
        return rawUid
    }

    @Synchronized
    fun uidOfPort(srcPort: Int): Int {
        refreshProcCache()
        return portToUid[srcPort] ?: -1
    }

    @Synchronized
    private fun uidOfConnection(localPort: Int, remoteIp: String, remotePort: Int): Int {
        refreshProcCache()
        val remoteHex = ipv4ProcHex(remoteIp)
        val exact = remoteHex?.let { connectionToUid[connectionKey(localPort, it, remotePort)] }
        return exact ?: portToUid[localPort] ?: -1
    }

    private fun refreshProcCache() {
        if (!procReadable) return
        val now = System.currentTimeMillis()
        if (portToUid.isNotEmpty() && now - lastScan <= SCAN_INTERVAL_MS) return
        portToUid.clear()
        connectionToUid.clear()
        scan("/proc/net/tcp")
        scan("/proc/net/tcp6")
        lastScan = now
    }

    private fun scan(path: String) {
        val lines = try {
            File(path).readLines()
        } catch (t: Throwable) {
            procReadable = false
            if (!procWarned) {
                procWarned = true
                Log.w(TAG, "$path unavailable (Android 10+ 已限制应用读取): ${t.message}")
            }
            return
        }
        for (line in lines) {
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 8) continue
            val local = parts[1]
            val remote = parts[2]
            val localIdx = local.lastIndexOf(':')
            val remoteIdx = remote.lastIndexOf(':')
            if (localIdx < 0 || remoteIdx < 0) continue
            val port = local.substring(localIdx + 1).toIntOrNull(16) ?: continue
            val remoteIp = remote.substring(0, remoteIdx).uppercase()
            val remotePort = remote.substring(remoteIdx + 1).toIntOrNull(16) ?: continue
            val uid = parts[7].toIntOrNull() ?: continue
            portToUid[port] = uid
            connectionToUid[connectionKey(port, remoteIp, remotePort)] = uid
        }
    }

    private fun connectionKey(localPort: Int, remoteIpHex: String, remotePort: Int): String =
        "$localPort|$remoteIpHex|$remotePort"

    private fun ipv4ProcHex(ip: String): String? {
        val octets = ip.split('.')
        if (octets.size != 4) return null
        val values = octets.map { it.toIntOrNull()?.takeIf { n -> n in 0..255 } ?: return null }
        return values.asReversed().joinToString("") { "%02X".format(it) }
    }
}
