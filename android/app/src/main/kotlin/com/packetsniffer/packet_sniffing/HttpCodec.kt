package com.packetsniffer.packet_sniffing

import java.io.BufferedInputStream
import java.io.EOFException
import java.io.IOException
import java.io.OutputStream
import java.util.zip.GZIPInputStream
import java.util.zip.InflaterInputStream

/** HTTP/1.1 报文读写（简化实现：不处理 keep-alive 复用，单请求单连接） */
object HttpCodec {

    class Head(val startLine: String, val headers: MutableList<Pair<String, String>>) {
        fun value(name: String): String? = headers.firstOrNull { it.first.equals(name, true) }?.second
    }

    private const val MAX_HEAD = 64 * 1024

    /**
     * 单条报文 body 的缓存上限。
     *
     * 旧值 8MB 会误伤 RN dev bundle（10MB+）与大 JSON 接口，导致整条连接失败、
     * 应用侧表现为「网络错误」；这里放宽到 32MB。
     */
    private const val MAX_BODY_READ = 32 * 1024 * 1024

    @Throws(IOException::class)
    fun readHead(input: BufferedInputStream): Head? {
        val first = readLine(input) ?: return null
        if (first.isEmpty()) return null
        val headers = mutableListOf<Pair<String, String>>()
        var total = first.length
        while (true) {
            val line = readLine(input) ?: throw EOFException("head truncated")
            total += line.length
            if (total > MAX_HEAD) throw IOException("head too large")
            if (line.isEmpty()) break
            val idx = line.indexOf(':')
            if (idx > 0) headers.add(line.substring(0, idx).trim() to line.substring(idx + 1).trim())
        }
        return Head(first, headers)
    }

    /**
     * 按 Content-Length / chunked / EOF 读取完整 body。
     *
     * [decode] = true 时按 Content-Encoding 解压（供 UI 展示）；
     * [decode] = false 时返回原始字节（原样转发给对端，头部里的 Content-Encoding 才与内容一致）。
     */
    @Throws(IOException::class)
    fun readBody(
        input: BufferedInputStream,
        head: Head,
        isResponse: Boolean,
        method: String? = null,
        decode: Boolean = true
    ): ByteArray {
        if (isResponse) {
            val status = head.startLine.split(" ").getOrNull(1)?.toIntOrNull() ?: 0
            if (method == "HEAD" || status in listOf(204, 304) || status in 100..199) return ByteArray(0)
        }
        val te = head.value("Transfer-Encoding")
        val cl = head.value("Content-Length")?.toLongOrNull()
        val raw = when {
            te != null && te.contains("chunked", true) -> readChunked(input)
            cl != null -> readFixed(input, cl)
            isResponse -> readToEof(input)
            else -> ByteArray(0)
        }
        return if (decode) decodeBody(raw, head) else raw
    }

    /** 根据 Content-Encoding 解压（gzip / deflate）；其他编码原样返回 */
    fun decodeBody(raw: ByteArray, head: Head): ByteArray {
        val enc = head.value("Content-Encoding")?.lowercase() ?: return raw
        if (raw.isEmpty()) return raw
        return try {
            when {
                enc.contains("gzip") -> GZIPInputStream(raw.inputStream()).use { it.readBytes() }
                enc.contains("deflate") -> InflaterInputStream(raw.inputStream()).use { it.readBytes() }
                else -> raw
            }
        } catch (_: Exception) {
            raw
        }
    }

    private fun readFixed(input: BufferedInputStream, len: Long): ByteArray {
        require(len <= MAX_BODY_READ) { "body too large" }
        val buf = ByteArray(len.toInt())
        var off = 0
        while (off < buf.size) {
            val n = input.read(buf, off, buf.size - off)
            if (n < 0) throw EOFException("body truncated")
            off += n
        }
        return buf
    }

    private fun readChunked(input: BufferedInputStream): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        while (true) {
            val sizeLine = readLine(input) ?: throw EOFException("chunk size missing")
            val size = sizeLine.substringBefore(';').trim().toIntOrNull(16)
                ?: throw IOException("bad chunk size: $sizeLine")
            if (size == 0) {
                // trailer
                while (true) {
                    val l = readLine(input) ?: throw EOFException()
                    if (l.isEmpty()) break
                }
                break
            }
            if (out.size() + size > MAX_BODY_READ) throw IOException("body too large")
            val buf = ByteArray(size)
            var off = 0
            while (off < size) {
                val n = input.read(buf, off, size - off)
                if (n < 0) throw EOFException("chunk truncated")
                off += n
            }
            out.write(buf)
            readLine(input) // chunk 末尾 CRLF
        }
        return out.toByteArray()
    }

    private fun readToEof(input: BufferedInputStream): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(8192)
        while (true) {
            val n = input.read(buf)
            if (n < 0) break
            if (out.size() + n > MAX_BODY_READ) throw IOException("body too large")
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    @Throws(IOException::class)
    fun readLine(input: BufferedInputStream): String? {
        val sb = StringBuilder()
        while (true) {
            val c = input.read()
            if (c < 0) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) break
            if (c != '\r'.code) sb.append(c.toChar())
            if (sb.length > MAX_HEAD) throw IOException("line too long")
        }
        return sb.toString()
    }

    /**
     * 过滤 hop-by-hop 头，重写 Content-Length / Connection: close 后写出。
     *
     * [body] 必须是**未解压的原始字节**（readBody(decode = false) 的返回），
     * 这样保留的 Content-Encoding 才与 body 一致；否则客户端会把明文当 gzip 解压而报错。
     */
    fun writeHeadAndBody(out: OutputStream, startLine: String, headers: List<Pair<String, String>>, body: ByteArray) {
        val sb = StringBuilder()
        sb.append(startLine).append("\r\n")
        for ((k, v) in headers) {
            if (k.equals("Connection", true) || k.equals("Proxy-Connection", true) ||
                k.equals("Keep-Alive", true) || k.equals("Transfer-Encoding", true) ||
                k.equals("Content-Length", true) || k.equals("Expect", true)
            ) continue
            sb.append(k).append(": ").append(v).append("\r\n")
        }
        sb.append("Content-Length: ").append(body.size).append("\r\n")
        sb.append("Connection: close\r\n\r\n")
        out.write(sb.toString().toByteArray(Charsets.ISO_8859_1))
        out.write(body)
        out.flush()
    }
}
