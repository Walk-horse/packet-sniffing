package com.packetsniffer.packet_sniffing

import android.content.Context
import android.util.Log
import com.packetsniffer.packet_sniffing.CaptureMode
import com.packetsniffer.packet_sniffing.CertAuthority
import com.packetsniffer.packet_sniffing.EventBridge
import com.packetsniffer.packet_sniffing.FileLogger
import com.packetsniffer.packet_sniffing.HttpCodec
import com.packetsniffer.packet_sniffing.HttpExchange
import com.packetsniffer.packet_sniffing.PassthroughRec
import com.packetsniffer.packet_sniffing.ReplaySocket
import com.packetsniffer.packet_sniffing.SniParser
import com.packetsniffer.packet_sniffing.UidResolver
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.io.SequenceInputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket

/**
 * 本机回环代理（127.0.0.1:8888）。
 * TUN 中继把每条 TCP 连接交给它，首行为 "DEST <ip> <port> [uid]" 告知原始目标。
 * 按流量特征分流：
 *  - TLS ClientHello → 解析 SNI → 动态签证书做 MITM → 按 HTTP 解析
 *  - 明文 HTTP → 解析并记录
 *  - 其他 → 盲转发（透传），记录连接元数据
 * 每条 App 连接只处理一个请求（对 App 回 Connection: close），简化实现。
 */
class LocalProxyServer {
    companion object {
        private const val TAG = "LocalProxyServer"
        private val HTTP_METHODS = listOf(
            "GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "PATCH", "CONNECT", "TRACE"
        )

        /** 资源类型后缀（图片/音视频/压缩包/文档/安装包/字体）。命中则放行、不解析不记录。 */
        private val RESOURCE_EXT = setOf(
            "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "ico", "tiff", "tif", "avif", "heic", "heif",
            "mp4", "mov", "avi", "flv", "mkv", "webm", "m3u8", "ts",
            "mp3", "wav", "ogg", "aac", "m4a", "flac", "wma",
            "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz",
            "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf", "txt", "csv",
            "apk", "ipa", "exe", "dmg", "deb", "rpm",
            "ttf", "otf", "woff", "woff2", "eot", "fon"
        )

        /** 清除动态站点证书缓存（CA 装好后可重新生成）。注意：不动 MitmExclusions 排除名单。 */
        fun clearMitmCache() {
            CertAuthority.clearCache()
            mitmOkHosts.clear()
        }

        /** 本会话 MITM 成功抓到过请求的域名（混合 TLS 栈的 App 保护名单）。 */
        private val mitmOkHosts = java.util.concurrent.ConcurrentHashMap.newKeySet<String>()

        fun noteMitmSuccess(host: String) {
            if (host.isNotEmpty()) mitmOkHosts.add(host)
        }

        /**
         * 已知「不信任本机 CA」的域名（尝试过 MITM 被拒）：直接盲转发。
         * 名单持久化在 [MitmExclusions]，下次抓包一开始就生效，不用再等失败一次。
         */
        fun isMitmBlocked(host: String): Boolean = MitmExclusions.contains(host)

        /**
         * 记录一次 MITM 失败。
         * 「证书被 App 拒绝」的表现不止 certificate_unknown/unknown_ca：
         * SSL Pinning / 双向认证更常见的是握手阶段直接断开（EOFException）、
         * handshake_failure、或握手完成后客户端不发请求。这些都计入名单。
         * 例外：域名本会话抓到过请求（混合 TLS 栈 App）则不排除，避免误伤能抓的接口。
         *
         * @return true 表示本次新加入了域名名单（调用方据此打一条日志）
         */
        fun noteMitmFailure(host: String, uid: Int, certRejected: Boolean): Boolean {
            if (!certRejected) return false
            if (mitmOkHosts.contains(host)) return false
            return MitmExclusions.add(host)
        }

        /**
         * 域名看着就是图片/静态资源 CDN（img./static./cdn./alicdn/oss…）。
         * 这类域名不做 MITM：① 资源不需要明文；② 很多 CDN SDK 自带证书库，
         * 一做 MITM 就被拒，页面图片全部加载不出来。
         */
        private val RESOURCE_HOST_TOKENS = setOf(
            "img", "image", "images", "pic", "photo", "static", "cdn", "oss",
            "alicdn", "gtimg", "qpic", "bcebos", "myqcloud", "cloudfront",
            "gstatic", "media", "assets", "res"
        )

        fun looksLikeResourceHost(host: String): Boolean {
            if (host.isEmpty()) return false
            // IP 直连无法判断，交给 MITM 流程
            if (host.first().isDigit()) return false
            for (label in host.lowercase().split('.')) {
                for (token in RESOURCE_HOST_TOKENS) {
                    // 前缀/后缀/全等都要认：cdn50、statics02 是「token+序号」，
                    // ismcdn 是「前缀+token」，只做 == 或 "token-" 前缀会全部漏判
                    //（真实案例：海尔智家图片 CDN ismcdn.haier.net / cdn50.ehaier.com 被 MITM 掐断）。
                    if (label == token || label.startsWith(token) || label.endsWith(token)) return true
                }
            }
            return false
        }
    }

    val port = 8888
    @Volatile private var running = false
    private var serverSocket: ServerSocket? = null
    private val pool = Executors.newCachedThreadPool()
    private lateinit var appContext: Context

    fun start(context: Context) {
        if (running) return
        appContext = context.applicationContext
        val ss = ServerSocket()
        ss.reuseAddress = true
        ss.bind(InetSocketAddress("127.0.0.1", port), 128)
        serverSocket = ss
        running = true
        pool.execute {
            while (running) {
                try {
                    val client = ss.accept()
                    pool.execute {
                        runCatching { handle(client) }.onFailure {
                            Log.w(TAG, "conn error: ${it.message}")
                            // 单条连接失败不影响其他连接，但要在日志页留痕，便于定位
                            FileLogger.log(
                                "代理连接异常：${it.javaClass.simpleName}: ${it.message ?: "无错误信息"}"
                            )
                            runCatching { client.close() }
                        }
                    }
                } catch (e: Exception) {
                    if (running) Log.w(TAG, "accept: ${e.message}")
                }
            }
        }
        Log.i(TAG, "proxy listening on 127.0.0.1:$port")
    }

    fun stop() {
        running = false
        runCatching { serverSocket?.close() }
        pool.shutdownNow()
    }

    private fun handle(app: Socket) {
        app.soTimeout = 30_000
        app.tcpNoDelay = true
        val rawIn = app.getInputStream()
        val appOut = BufferedOutputStream(app.getOutputStream(), 64 * 1024)

        val firstLine = readLineRaw(rawIn) ?: return
        if (firstLine.startsWith("DEST ")) {
            val parts = firstLine.split(" ")
            val destIp = parts.getOrNull(1) ?: return
            val destPort = parts.getOrNull(2)?.toIntOrNull() ?: return
            val uid = parts.getOrNull(3)?.toIntOrNull() ?: -1
            dispatchTun(app, rawIn, appOut, destIp, destPort, uid)
        } else {
            handleForwardProxy(app, rawIn, appOut, firstLine)
        }
    }

    /** TUN 中继来的连接：根据首字节分流 TLS / 明文 HTTP / 其他 */
    private fun dispatchTun(
        app: Socket, rawIn: InputStream, appOut: BufferedOutputStream,
        destIp: String, destPort: Int, uid: Int
    ) {
        val first = rawIn.read()
        if (first < 0) { app.close(); return }

        if (first == 0x16) {
            val headerRest = ByteArray(4)
            readFully(rawIn, headerRest)
            val recordLen = ((headerRest[2].toInt() and 0xFF) shl 8) or (headerRest[3].toInt() and 0xFF)
            if (recordLen <= 0 || recordLen > 18432) { app.close(); return }
            val body = ByteArray(recordLen)
            readFully(rawIn, body)
            val record = byteArrayOf(first.toByte()) + headerRest + body
            val sni = SniParser.extract(record)
            handleTls(app, record, appOut, destIp, destPort, sni, uid)
        } else {
            val lineBytes = ByteArrayOutputStream()
            lineBytes.write(first)
            var b: Int
            while (rawIn.read().also { b = it } >= 0) {
                lineBytes.write(b)
                if (b == '\n'.code || lineBytes.size() > 8192) break
            }
            val prefix = lineBytes.toByteArray()
            val line = String(prefix, Charsets.ISO_8859_1).trim()
            val method = line.substringBefore(' ').uppercase()
            val stream = BufferedInputStream(SequenceInputStream(ByteArrayInputStream(prefix), rawIn), 64 * 1024)
            if (method in HTTP_METHODS) {
                handlePlainHttp(app, stream, appOut, destIp, destPort, uid)
            } else {
                blindRelay(app, stream, appOut, destIp, destPort, uid = uid)
            }
        }
    }

    /**
     * 系统代理转发来的正向代理连接（开启「HTTPS 代理」后，WebView/H5 等走此路径）。
     */
    private fun handleForwardProxy(
        app: Socket, rawIn: InputStream, appOut: BufferedOutputStream, firstLine: String
    ) {
        val clientUid = UidResolver.uidOfLocalProxyClient(app)
        val line = firstLine.trim()
        val requestParts = line.split(Regex("\\s+"), limit = 3)
        val method = requestParts.getOrNull(0)?.uppercase() ?: return
        val target = requestParts.getOrNull(1) ?: return

        if (method == "CONNECT") {
            val authority = parseAuthority(target, 443) ?: return
            val host = authority.first
            val port = authority.second
            readHeadBlock(rawIn)
            appOut.write("HTTP/1.1 200 Connection Established\r\n\r\n".toByteArray())
            appOut.flush()
            FileLogger.log("PROXY CONNECT $host:$port")
            val first = try {
                rawIn.read()
            } catch (e: Exception) {
                FileLogger.log("CONNECT $host:$port 客户端未继续 TLS（${e.javaClass.simpleName}）")
                runCatching { app.close() }
                return
            }
            if (first < 0) {
                FileLogger.log("CONNECT $host:$port 客户端已断开（未发送 ClientHello）")
                runCatching { app.close() }
                return
            }
            if (first != 0x16) {
                val stream = BufferedInputStream(
                    SequenceInputStream(ByteArrayInputStream(byteArrayOf(first.toByte())), rawIn), 64 * 1024)
                blindRelay(app, stream, appOut, host, port,
                    tls = false, hostLabel = host, reason = "CONNECT 隧道非 TLS 流量", uid = clientUid)
                return
            }
            val headerRest = ByteArray(4)
            readFully(rawIn, headerRest)
            val recordLen = ((headerRest[2].toInt() and 0xFF) shl 8) or (headerRest[3].toInt() and 0xFF)
            if (recordLen <= 0 || recordLen > 18432) { runCatching { app.close() }; return }
            val body = ByteArray(recordLen)
            readFully(rawIn, body)
            val record = byteArrayOf(first.toByte()) + headerRest + body
            val sni = SniParser.extract(record)
            handleTls(app, record, appOut, host, port, sni, clientUid)
            return
        }

        if (target.startsWith("http://", ignoreCase = true)) {
            val uri = runCatching { java.net.URI(target) }.getOrNull()
            if (uri?.host != null) {
                val host = uri.host
                val port = if (uri.port > 0) uri.port else 80
                val path = (uri.path ?: "") + if (uri.query != null) "?${uri.query}" else ""
                val originLine = "$method ${if (path.isEmpty()) "/" else path} HTTP/1.1"
                val headBlock = readHeadBlock(rawIn)
                val cut = String(headBlock, Charsets.ISO_8859_1).indexOf("\r\n")
                val rest = if (cut >= 0) headBlock.copyOfRange(cut + 2, headBlock.size) else headBlock
                val rebuilt = "$originLine\r\n".toByteArray() + rest
                val stream = BufferedInputStream(
                    SequenceInputStream(ByteArrayInputStream(rebuilt), rawIn), 64 * 1024)
                handlePlainHttp(app, stream, appOut, host, port, clientUid)
                return
            }
        }

        val hp = parseHostPortFromTarget(target)
        if (hp != null) {
            FileLogger.log("PROXY tunnel $method -> ${hp.first}:${hp.second}")
            val stream = BufferedInputStream(
                SequenceInputStream(ByteArrayInputStream("$firstLine\r\n".toByteArray()), rawIn), 64 * 1024)
            blindRelay(app, stream, appOut, hp.first, hp.second, reason = "正向代理隧道透传: $method", uid = clientUid)
        } else {
            runCatching { app.close() }
        }
    }

    private fun parseHostPortFromTarget(target: String): Pair<String, Int>? {
        val m = Regex("""^[a-zA-Z]+://([^/:?#]+)(?::(\d+))?""").find(target) ?: return null
        val host = m.groupValues[1]
        val port = m.groupValues[2].toIntOrNull() ?: if (target.startsWith("https", true)) 443 else 80
        return host to port
    }

    private fun parseAuthority(target: String, defaultPort: Int): Pair<String, Int>? {
        val value = target.trim()
        if (value.startsWith("[")) {
            val end = value.indexOf(']')
            if (end <= 1) return null
            val host = value.substring(1, end)
            val port = value.substring(end + 1).removePrefix(":").toIntOrNull() ?: defaultPort
            return host to port
        }
        val colon = value.lastIndexOf(':')
        if (colon <= 0) return value to defaultPort
        return value.substring(0, colon) to (value.substring(colon + 1).toIntOrNull() ?: defaultPort)
    }

    private fun readHeadBlock(input: InputStream): ByteArray {
        val out = ByteArrayOutputStream()
        val tail = ByteArray(4)
        var n = 0
        while (true) {
            val c = input.read()
            if (c < 0) break
            out.write(c)
            if (n < 4) tail[n] = c.toByte()
            else { tail[0] = tail[1]; tail[1] = tail[2]; tail[2] = tail[3]; tail[3] = c.toByte() }
            n++
            if (n >= 4 && tail[0] == '\r'.code.toByte() && tail[1] == '\n'.code.toByte()
                && tail[2] == '\r'.code.toByte() && tail[3] == '\n'.code.toByte()) break
        }
        return out.toByteArray()
    }

    // ---------- 明文 HTTP ----------

    private fun handlePlainHttp(app: Socket, appIn: BufferedInputStream, appOut: BufferedOutputStream, destIp: String, destPort: Int, uid: Int) {
        val head = HttpCodec.readHead(appIn) ?: return
        val startParts = head.startLine.split(" ")
        if (startParts.size < 2) return
        val method = startParts[0].uppercase()
        val hostHeader = head.value("Host")
        val host = hostHeader?.substringBefore(':') ?: destIp
        FileLogger.log("HTTP $method $host${startParts.getOrElse(1) { "" }} -> $destIp:$destPort")

        val reqPath = normalizePath(startParts[1])
        // 接口模拟：命中规则则直接返回模拟响应，不转发真实服务器
        val mockRule = MockEngine.match(uid, method, host, reqPath)
        if (mockRule != null) {
            serveMock(app, appOut, mockRule, "http", host, destPort, false, uid, reqPath, method, head.headers.toList())
            return
        }
        if (CaptureMode.skipResources && isResourcePath(reqPath)) {
            // 图片/文件等资源：透明转发，不解析、不进抓包列表
            tunnelResource(appIn, appOut, app, destIp, destPort, host, head, false, uid,
                "资源放行（图片/文件等，不解析）")
            return
        }
        val exchange = HttpExchange(scheme = "http", host = host, port = destPort, isTls = false)
        exchange.remoteIp = destIp
        exchange.uid = uid
        exchange.appPackage = UidResolver.appPackageOf(uid) ?: ""
        exchange.appLabel = UidResolver.appLabelOf(uid) ?: ""
        exchange.method = method
        exchange.path = reqPath
        exchange.requestHeaders = head.headers.toList()
        EventBridge.add(exchange)

        try {
            if (head.value("Expect")?.contains("100-continue", true) == true) {
                appOut.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray())
                appOut.flush()
            }
            val reqRaw = HttpCodec.readBody(appIn, head, isResponse = false, method = method, decode = false)
            exchange.requestBody = cap(HttpCodec.decodeBody(reqRaw, head))

            Socket().use { up ->
                VpnProtect.protect(up)
                up.soTimeout = 30_000
                up.connect(InetSocketAddress(InetAddress.getByName(destIp), destPort), 10_000)
                val upIn = BufferedInputStream(up.getInputStream(), 64 * 1024)
                val upOut = BufferedOutputStream(up.getOutputStream(), 64 * 1024)
                HttpCodec.writeHeadAndBody(upOut, head.startLine, head.headers, reqRaw)

                val respHead = HttpCodec.readHead(upIn)
                if (respHead == null) { fail(exchange, "empty response"); return }
                fillResponse(exchange, respHead)
                val respRaw = HttpCodec.readBody(upIn, respHead, isResponse = true, method = method, decode = false)
                exchange.responseBody = cap(HttpCodec.decodeBody(respRaw, respHead))
                complete(exchange)
                HttpCodec.writeHeadAndBody(appOut, respHead.startLine, respHead.headers, respRaw)
            }
        } catch (e: Exception) {
            fail(exchange, e.message ?: e.javaClass.simpleName)
        } finally {
            runCatching { app.close() }
        }
    }

    // ---------- HTTPS MITM ----------

    private fun handleTls(
        app: Socket, clientHello: ByteArray, appOut: BufferedOutputStream,
        destIp: String, destPort: Int, sni: String?, uid: Int
    ) {
        val host = sni ?: destIp
        if (!CaptureMode.shouldMitm(host) && !MockEngine.shouldForceMitm(host)) {
            FileLogger.log("TLS $host bypassed by capture mode")
            val stream = BufferedInputStream(SequenceInputStream(ByteArrayInputStream(clientHello), app.getInputStream()), 64 * 1024)
            blindRelay(app, stream, appOut, destIp, destPort,
                tls = true, hostLabel = sni, reason = "抓包模式（黑/白名单）排除", uid = uid)
            return
        }
        // 资源域名（图片/静态文件 CDN）：不做 MITM，直接透传。
        // 否则 CDN SDK 的证书校验会把图片请求全部掐断（页面图片不显示）。
        // 用户在白名单里点名要抓的域名除外。
        if (CaptureMode.skipResourcesOn() && !MockEngine.shouldForceMitm(host) &&
            !CaptureMode.explicitlyRequested(host) && looksLikeResourceHost(host)
        ) {
            val stream = BufferedInputStream(SequenceInputStream(ByteArrayInputStream(clientHello), app.getInputStream()), 64 * 1024)
            blindRelay(app, stream, appOut, destIp, destPort,
                tls = true, hostLabel = sni, reason = "资源域名放行（图片/静态文件，不解析）", uid = uid)
            return
        }
        // 该域名此前做过 MITM 被 App 拒绝（SSL Pinning / 自带证书库）：
        // 再尝试只会让它的图片、统计、推送继续失败，直接透传保住功能。
        if (!MockEngine.shouldForceMitm(host) && !CaptureMode.explicitlyRequested(host) && isMitmBlocked(host)) {
            val stream = BufferedInputStream(SequenceInputStream(ByteArrayInputStream(clientHello), app.getInputStream()), 64 * 1024)
            blindRelay(app, stream, appOut, destIp, destPort,
                tls = true, hostLabel = sni, reason = "不信任本机 CA（已排除解密）", uid = uid)
            return
        }
        val serverCtx = try {
            CertAuthority.serverContext(appContext, host)
        } catch (e: Exception) {
            Log.w(TAG, "no MITM certificate for host=$host sni=$sni", e)
            FileLogger.log("TLS $host 站点证书生成失败，连接已关闭: ${e.javaClass.simpleName}: ${e.message ?: "无错误信息"}")
            null
        }
        if (serverCtx == null) {
            runCatching { app.close() }
            return
        }

        val appTls = try {
            val replay = ReplaySocket(app, clientHello)
            val s = serverCtx.socketFactory.createSocket(replay, host, destPort, true) as SSLSocket
            s.useClientMode = false
            s.sslParameters = s.sslParameters.apply {
                applicationProtocols = arrayOf("http/1.1")
            }
            s.wantClientAuth = false
            s.needClientAuth = false
            s.soTimeout = 30_000
            s.startHandshake()
            s
        } catch (e: Exception) {
            val detail = buildString {
                append(e.javaClass.simpleName)
                append(": ")
                append(e.message ?: "无错误信息")
                var cause = e.cause
                var depth = 0
                while (cause != null && depth++ < 3) {
                    append("; cause=")
                    append(cause.javaClass.simpleName)
                    append(": ")
                    append(cause.message ?: "")
                    cause = cause.cause
                }
            }
            Log.w(TAG, "TLS MITM handshake failed host=$host sni=$sni: $detail", e)
            // 日志页只留可读的一句话：先给结论，再附一小段原始信息便于排查
            val brief = detail.replace(Regex("\\s+"), " ").take(100)
            val lower = detail.lowercase()
            // 「证书被拒」的完整表现集：显式证书告警 + Pinning 常见的握手即断 / handshake_failure。
            // 只认 certificate_unknown 的话，cdn50 这类「读到证书就关连接」的域名永远学不会。
            val certRejected = lower.contains("certificate_unknown") || lower.contains("unknown_ca") ||
                lower.contains("connection closed") || lower.contains("eofexception") ||
                lower.contains("handshake_failure") || lower.contains("failure in ssl library")
            val added = noteMitmFailure(host, uid, certRejected)
            FileLogger.log(
                buildString {
                    append("TLS ").append(host).append(" 解密失败：").append(mitmFailHint(detail))
                    if (added) append(" → 已加入「不解密」名单，之后该域名直接透传")
                    append("（").append(brief).append("）")
                }
            )
            runCatching { app.close() }
            return
        }

        try {
            val tlsIn = BufferedInputStream(appTls.inputStream, 64 * 1024)
            val tlsOut = BufferedOutputStream(appTls.outputStream, 64 * 1024)

            val head = HttpCodec.readHead(tlsIn)
            if (head == null) {
                // 客户端（应用）接受证书后会立刻发请求；读到 EOF 通常是它校验证书失败主动断开
                FileLogger.log("TLS $host MITM 已握手但客户端未发请求（应用可能不信任本机 CA）")
                noteMitmFailure(host, uid, certRejected = true)
                return
            }
            noteMitmSuccess(host)
            val startParts = head.startLine.split(" ")
            if (startParts.size < 2) return
            val method = startParts[0].uppercase()
            val hostHeader = head.value("Host")?.substringBefore(':')

            val reqPath = normalizePath(startParts[1])
            val mockRuleHttps = MockEngine.match(uid, method, hostHeader ?: host, reqPath)
            if (mockRuleHttps != null) {
                serveMock(app, tlsOut, mockRuleHttps, "https", hostHeader ?: host, destPort, true, uid, reqPath, method, head.headers.toList())
                return
            }
            if (CaptureMode.skipResources && isResourcePath(reqPath)) {
                // 图片/文件等资源：MITM 握手后改为透明隧道转发，不解析、不进抓包列表
                tunnelResource(tlsIn, tlsOut, app, destIp, destPort, hostHeader ?: host, head, true, uid,
                    "资源放行（图片/文件等，不解析）")
                return
            }
            val exchange = HttpExchange(scheme = "https", host = hostHeader ?: host, port = destPort, isTls = true)
            exchange.remoteIp = destIp
            exchange.uid = uid
            exchange.appPackage = UidResolver.appPackageOf(uid) ?: ""
            exchange.appLabel = UidResolver.appLabelOf(uid) ?: ""
            exchange.method = method
            exchange.path = reqPath
            exchange.requestHeaders = head.headers.toList()
            EventBridge.add(exchange)

            try {
                if (head.value("Expect")?.contains("100-continue", true) == true) {
                    tlsOut.write("HTTP/1.1 100 Continue\r\n\r\n".toByteArray())
                    tlsOut.flush()
                }
                // 请求体：原始字节原样转发（头部 Content-Encoding 才与内容一致），
                // 列表里展示解压后的内容。
                val reqRaw = HttpCodec.readBody(tlsIn, head, isResponse = false, method = method, decode = false)
                exchange.requestBody = cap(HttpCodec.decodeBody(reqRaw, head))

                createUpstreamTls(destIp, destPort, hostHeader ?: host).use { up ->
                    val upIn = BufferedInputStream(up.inputStream, 64 * 1024)
                    val upOut = BufferedOutputStream(up.outputStream, 64 * 1024)
                    HttpCodec.writeHeadAndBody(upOut, head.startLine, head.headers, reqRaw)

                    val respHead = HttpCodec.readHead(upIn)
                    if (respHead == null) { fail(exchange, "empty response"); return }
                    fillResponse(exchange, respHead)
                    val respRaw = HttpCodec.readBody(upIn, respHead, isResponse = true, method = method, decode = false)
                    exchange.responseBody = cap(HttpCodec.decodeBody(respRaw, respHead))
                    complete(exchange)
                    HttpCodec.writeHeadAndBody(tlsOut, respHead.startLine, respHead.headers, respRaw)
                }
            } catch (e: Exception) {
                fail(exchange, e.message ?: e.javaClass.simpleName)
            }
        } finally {
            runCatching { appTls.close() }
        }
    }

    /**
     * 把 MITM 握手的异常翻译成一句人话：
     * 90% 的情况是「应用不信任用户安装的 CA」，日志页直接给出结论，省得看 OpenSSL 细节。
     */
    private fun mitmFailHint(detail: String): String {
        val d = detail.lowercase()
        return when {
            d.contains("certificate_unknown") || d.contains("unknown_ca") ->
                "应用不信任本机 CA（需把 CA 装到系统证书或该应用信任列表）"
            d.contains("connection closed") || d.contains("eofexception") ->
                "客户端握手时断开（应用可能做了证书校验/双向认证）"
            d.contains("handshake_failure") -> "握手失败（应用可能启用了 SSL Pinning）"
            d.contains("protocol version") || d.contains("unsupported") -> "TLS 协议版本不匹配"
            d.contains("timeout") || d.contains("timed out") -> "握手超时"
            else -> "握手失败"
        }
    }

    private fun createUpstreamTls(destIp: String, destPort: Int, sniHost: String): SSLSocket {
        val ctx = SSLContext.getDefault()
        val raw = Socket()
        VpnProtect.protect(raw)
        raw.soTimeout = 30_000
        raw.connect(InetSocketAddress(InetAddress.getByName(destIp), destPort), 10_000)
        val tls = ctx.socketFactory.createSocket(raw, sniHost, destPort, true) as SSLSocket
        tls.useClientMode = true
        val params = tls.sslParameters
        params.applicationProtocols = arrayOf("http/1.1")
        tls.sslParameters = params
        tls.soTimeout = 30_000
        tls.startHandshake()
        return tls
    }

    // ---------- 盲转发 ----------

    private fun blindRelay(
        app: Socket, appIn: InputStream, appOut: BufferedOutputStream,
        destIp: String, destPort: Int,
        tls: Boolean = false, hostLabel: String? = null, reason: String = "非 HTTP 流量",
        uid: Int = -1
    ) {
        Log.d(TAG, "blind relay to $destIp:$destPort ($reason)")
        val rec = PassthroughRec(
            host = hostLabel ?: destIp,
            port = destPort,
            tls = tls,
            reason = reason,
            uid = uid,
            appPackage = UidResolver.appPackageOf(uid) ?: "",
            appLabel = UidResolver.appLabelOf(uid) ?: ""
        )
        EventBridge.addPassthrough(rec)
        val upstream = Socket()
        VpnProtect.protect(upstream)
        upstream.soTimeout = 60_000
        upstream.connect(InetSocketAddress(InetAddress.getByName(destIp), destPort), 10_000)
        try {
            val writer = Thread {
                try {
                    val buf = ByteArray(16384)
                    while (true) {
                        val n = upstream.getInputStream().read(buf)
                        if (n < 0) break
                        rec.downBytes.addAndGet(n.toLong())
                        appOut.write(buf, 0, n)
                        appOut.flush()
                    }
                } catch (_: Exception) {}
                runCatching { appOut.flush() }
                runCatching { app.close() }
            }
            writer.isDaemon = true
            writer.start()
            try {
                val buf = ByteArray(16384)
                while (true) {
                    val n = appIn.read(buf)
                    if (n < 0) break
                    rec.upBytes.addAndGet(n.toLong())
                    upstream.getOutputStream().write(buf, 0, n)
                    upstream.getOutputStream().flush()
                }
            } catch (_: Exception) {}
        } finally {
            runCatching { upstream.close() }
            runCatching { app.close() }
            EventBridge.finishPassthrough(rec)
        }
    }

    // ---------- 资源放行（透明隧道） ----------

    private fun isResourcePath(path: String): Boolean {
        val p = path.substringBefore('?').substringBefore('#')
        val dot = p.lastIndexOf('.')
        if (dot <= 0 || dot >= p.length - 1) return false
        return RESOURCE_EXT.contains(p.substring(dot + 1).lowercase())
    }

    /** 原样写出请求头（保留 Content-Length / Transfer-Encoding，因为 body 要透传），仅剔除非端到端头。 */
    private fun writeHeadPreserving(out: OutputStream, head: HttpCodec.Head) {
        val sb = StringBuilder()
        sb.append(head.startLine).append("\r\n")
        for ((k, v) in head.headers) {
            if (k.equals("Connection", true) || k.equals("Proxy-Connection", true) ||
                k.equals("Keep-Alive", true) || k.equals("Expect", true)
            ) continue
            sb.append(k).append(": ").append(v).append("\r\n")
        }
        sb.append("Connection: close\r\n\r\n")
        out.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
        out.flush()
    }

    /**
     * 资源放行：对命中资源后缀的请求做透明隧道转发（App <-> 真实服务器），
     * 不解析 body、不进请求列表，仅记一条透传以说明放行。保证图片/文件等照常加载。
     */
    private fun tunnelResource(
        appIn: InputStream, appOut: OutputStream, appSocket: Socket,
        destIp: String, destPort: Int, sniHost: String,
        head: HttpCodec.Head, tlsUpstream: Boolean, uid: Int, reason: String
    ) {
        val rec = PassthroughRec(
            host = sniHost, port = destPort, tls = tlsUpstream, reason = reason, uid = uid,
            appPackage = UidResolver.appPackageOf(uid) ?: "",
            appLabel = UidResolver.appLabelOf(uid) ?: ""
        )
        EventBridge.addPassthrough(rec)
        Log.d(TAG, "resource passthrough $sniHost ${head.startLine.split(' ').getOrNull(1) ?: ""}")
        try {
            val up: Socket
            val upIn: BufferedInputStream
            val upOut: BufferedOutputStream
            if (tlsUpstream) {
                val tls = createUpstreamTls(destIp, destPort, sniHost)
                up = tls
                upIn = BufferedInputStream(tls.inputStream, 64 * 1024)
                upOut = BufferedOutputStream(tls.outputStream, 64 * 1024)
            } else {
                val raw = Socket()
                VpnProtect.protect(raw)
                raw.soTimeout = 60_000
                raw.connect(InetSocketAddress(InetAddress.getByName(destIp), destPort), 10_000)
                up = raw
                upIn = BufferedInputStream(raw.getInputStream(), 64 * 1024)
                upOut = BufferedOutputStream(raw.getOutputStream(), 64 * 1024)
            }
            writeHeadPreserving(upOut, head)
            // App -> 真实服务器（请求 body 透传）
            val a2u = Thread {
                val buf = ByteArray(16384)
                try {
                    while (true) {
                        val n = appIn.read(buf)
                        if (n < 0) break
                        rec.upBytes.addAndGet(n.toLong())
                        upOut.write(buf, 0, n)
                        upOut.flush()
                    }
                } catch (_: Exception) {
                }
                runCatching { upOut.close() }
            }
            a2u.isDaemon = true
            a2u.start()
            // 真实服务器 -> App（响应透传）
            val buf = ByteArray(16384)
            try {
                while (true) {
                    val n = upIn.read(buf)
                    if (n < 0) break
                    rec.downBytes.addAndGet(n.toLong())
                    appOut.write(buf, 0, n)
                    appOut.flush()
                }
            } catch (_: Exception) {
            }
        } catch (e: Exception) {
            Log.w(TAG, "tunnelResource failed host=$sniHost: ${e.message}")
        } finally {
            runCatching { appOut.flush() }
            runCatching { appSocket.close() }
            EventBridge.finishPassthrough(rec)
        }
    }

    // ---------- 工具 ----------

    private fun readLineRaw(input: InputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val c = input.read()
            if (c < 0) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) break
            if (c != '\r'.code) sb.append(c.toChar())
            if (sb.length > 4096) return null
        }
        return sb.toString()
    }

    private fun readFully(input: InputStream, buf: ByteArray) {
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) throw EOFException()
            off += n
        }
    }

    private fun fillResponse(e: HttpExchange, head: HttpCodec.Head) {
        val parts = head.startLine.split(" ", limit = 3)
        e.statusCode = parts.getOrNull(1)?.toIntOrNull() ?: 0
        e.statusText = parts.getOrNull(2) ?: ""
        e.responseHeaders = head.headers.toList()
    }

    private fun complete(e: HttpExchange) {
        e.state = HttpExchange.State.COMPLETE
        e.endTime = System.currentTimeMillis()
        EventBridge.update(e)
    }

    private fun fail(e: HttpExchange, msg: String) {
        e.state = HttpExchange.State.FAILED
        e.error = msg
        e.endTime = System.currentTimeMillis()
        FileLogger.log("FAIL ${e.method} ${e.host}${e.path}: $msg")
        EventBridge.update(e)
    }

    private fun cap(body: ByteArray): ByteArray =
        if (body.size > HttpExchange.MAX_BODY) body.copyOf(HttpExchange.MAX_BODY) else body

    private fun normalizePath(raw: String): String =
        if (raw.startsWith("http://") || raw.startsWith("https://")) {
            raw.substringAfter("://").substringAfter("/", "/")
        } else raw

    /**
     * 命中接口模拟规则：直接返回模拟响应，不转发真实服务器，并记录一条 mocked 记录。
     * 用于「接口模拟」功能（参考 packet-capture，已移除桌面端同步）。
     */
    private fun serveMock(
        app: Socket, appOut: BufferedOutputStream,
        rule: MockRule, scheme: String, host: String, port: Int, isTls: Boolean,
        uid: Int, path: String, method: String, requestHeaders: List<Pair<String, String>>
    ) {
        val resp = MockEngine.respond(rule)
        val exchange = HttpExchange(scheme = scheme, host = host, port = port, isTls = isTls)
        exchange.remoteIp = host
        exchange.uid = uid
        exchange.appPackage = UidResolver.appPackageOf(uid) ?: ""
        exchange.appLabel = UidResolver.appLabelOf(uid) ?: ""
        exchange.method = method
        exchange.path = path
        exchange.requestHeaders = requestHeaders
        exchange.mocked = true
        exchange.mockAuto = resp.autoGenerated
        exchange.statusCode = resp.statusCode
        exchange.statusText = resp.statusText
        exchange.responseHeaders = resp.headers
        exchange.responseBody = resp.body
        EventBridge.add(exchange)
        complete(exchange)
        try {
            val sb = StringBuilder()
            sb.append("HTTP/1.1 ${resp.statusCode} ${resp.statusText}\r\n")
            sb.append("Content-Length: ${resp.body.size}\r\n")
            for ((k, v) in resp.headers) sb.append("$k: $v\r\n")
            sb.append("Connection: close\r\n\r\n")
            appOut.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
            appOut.write(resp.body)
            appOut.flush()
        } catch (e: Exception) {
            fail(exchange, e.message ?: e.javaClass.simpleName)
        } finally {
            runCatching { app.close() }
        }
    }
}
