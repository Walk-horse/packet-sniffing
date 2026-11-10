package com.packetsniffer.packet_sniffing

import android.content.Context
import android.util.Log
import java.io.BufferedWriter
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStreamWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 抓包日志（每次抓包落一个文件）。
 *
 * 落盘位置：`filesDir/capture_logs/capture-yyyyMMdd-HHmmss.log`，
 * Dart 侧「日志」页通过 getLogs / readLog 读取，进程重启后仍可查看。
 *
 * 之所以要落盘而不是只走 EventChannel：原生 `session started` 等事件在 Dart 订阅
 * 之前就发出，会被 EventSink 丢弃，早期日志会全部丢失。
 */
object FileLogger {
    private const val TAG = "FileLogger"
    private const val DIR_NAME = "capture_logs"
    private const val MAX_FILES = 30
    private const val MAX_BYTES = 4L * 1024 * 1024

    private val lineFmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    private val nameFmt = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)
    private val fullFmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US)

    private var writer: BufferedWriter? = null

    @Volatile
    private var fileName: String = ""

    @Volatile
    var running: Boolean = false
        private set

    private var written = 0L
    private var overflowed = false
    private var startedAt = 0L
    private var reqCount = 0
    private var ptCount = 0
    private var lastFlush = 0L

    /** 开始一份新日志；[header] 是启动参数摘要，逐行写入 */
    @Synchronized
    fun start(context: Context, header: String = "") {
        closeWriter()
        val dir = File(context.filesDir, DIR_NAME).apply { mkdirs() }
        val f = File(dir, "capture-${nameFmt.format(Date())}.log")
        fileName = f.name
        written = 0
        overflowed = false
        startedAt = System.currentTimeMillis()
        reqCount = 0
        ptCount = 0
        running = true
        try {
            writer = BufferedWriter(
                OutputStreamWriter(FileOutputStream(f, false), Charsets.UTF_8)
            )
        } catch (e: Exception) {
            Log.w(TAG, "open log failed: ${e.message}")
            writer = null
        }
        appendRaw("=== 抓包开始 ${fullFmt.format(Date())} ===")
        header.lineSequence().forEach { if (it.isNotBlank()) appendRaw("  $it") }
        flushNow()
        prune(dir)
    }

    /** 通用日志行，带时间戳 */
    @Synchronized
    fun log(msg: String) {
        Log.d(TAG, msg)
        appendRaw("[${lineFmt.format(Date())}] $msg")
    }

    /** 请求落定（成功/失败）时记一行摘要 */
    @Synchronized
    fun request(e: HttpExchange) {
        if (writer == null) return
        reqCount++
        val app = e.appLabel.ifEmpty { e.appPackage }
        val who = if (app.isEmpty()) "" else "  [$app]"
        val line = when {
            e.state == HttpExchange.State.FAILED ->
                "${e.method.ifEmpty { "?" }} ${e.url} !! ${e.error ?: "请求失败"}$who"
            else ->
                "${e.method.ifEmpty { "?" }} ${e.url} -> ${e.statusCode} " +
                    "(${e.durationMs.coerceAtLeast(0)}ms, ${human(e.responseBody.size)})$who"
        }
        appendRaw("[${lineFmt.format(Date())}] $line")
    }

    /** 透传连接（未解密）记录 */
    @Synchronized
    fun passthrough(p: PassthroughRec, finish: Boolean) {
        if (writer == null) return
        if (!finish) {
            ptCount++
            val app = p.appLabel.ifEmpty { p.appPackage }
            val who = if (app.isEmpty()) "" else "  [$app]"
            appendRaw(
                "[${lineFmt.format(Date())}] 透传 ${if (p.tls) "TLS " else ""}${p.host}:${p.port}" +
                    " (${p.reason})$who"
            )
        }
    }

    /** 停止抓包：写入汇总并关闭文件 */
    @Synchronized
    fun stop(upBytes: Long = 0, downBytes: Long = 0) {
        if (writer == null) {
            running = false
            return
        }
        val secs = ((System.currentTimeMillis() - startedAt) / 1000).coerceAtLeast(0)
        appendRaw(
            "=== 抓包结束，时长 ${secs}s，请求 $reqCount 条，透传 $ptCount 条，" +
                "上行 ${human(upBytes)} 下行 ${human(downBytes)} ==="
        )
        closeWriter()
        running = false
    }

    /** 日志文件列表（新→旧） */
    fun listFiles(context: Context): List<Map<String, Any?>> {
        flushNow()
        val dir = File(context.filesDir, DIR_NAME)
        if (!dir.exists()) return emptyList()
        return dir.listFiles { f -> f.isFile && f.name.endsWith(".log") }
            ?.sortedByDescending { it.lastModified() }
            ?.map {
                mapOf(
                    "name" to it.name,
                    "size" to it.length(),
                    "time" to it.lastModified()
                )
            }
            ?: emptyList()
    }

    fun readFile(context: Context, name: String): String {
        // 先把缓冲刷到磁盘，否则日志页会看到滞后内容
        flushNow()
        // 只允许读目录内的文件名，防止 ../ 越权
        val safe = File(name).name
        val f = File(File(context.filesDir, DIR_NAME), safe)
        return try {
            if (f.exists()) f.readText() else ""
        } catch (e: Exception) {
            "读取日志失败：${e.message}"
        }
    }

    @Synchronized
    fun deleteAll(context: Context) {
        // 正在抓包时删掉文件会让 writer 指向已删除的 inode，后续日志写进「黑洞」，
        // 因此清空后立刻新开一份，保证还在抓的这轮依然有日志。
        val wasRunning = running
        closeWriter()
        fileName = ""
        val dir = File(context.filesDir, DIR_NAME)
        dir.listFiles()?.forEach { runCatching { it.delete() } }
        running = false
        if (wasRunning) start(context, "（清空日志后继续抓包）")
    }

    @Synchronized
    fun flushNow() {
        runCatching { writer?.flush() }
        lastFlush = System.currentTimeMillis()
    }

    // ---- 内部 ----

    private fun appendRaw(line: String) {
        val w = writer ?: return
        if (overflowed) return
        val text = "$line\n"
        val size = text.toByteArray(Charsets.UTF_8).size
        if (written + size > MAX_BYTES) {
            overflowed = true
            runCatching {
                w.write("=== 日志已达 ${MAX_BYTES / 1024 / 1024}MB 上限，后续内容不再记录 ===\n")
                w.flush()
            }
            return
        }
        try {
            w.write(text)
            // 每行都刷到内核缓冲（不是 fsync，成本很低）：
            // 这样日志页轮询、或抓包中途停止，看到的都是完整内容
            w.flush()
            lastFlush = System.currentTimeMillis()
            written += size
        } catch (e: Exception) {
            Log.w(TAG, "write failed: ${e.message}")
        }
    }

    private fun closeWriter() {
        runCatching { writer?.flush() }
        runCatching { writer?.close() }
        writer = null
    }

    /** 只保留最近 [MAX_FILES] 份日志，避免长期使用后占满空间 */
    private fun prune(dir: File) {
        val files = dir.listFiles { f -> f.isFile && f.name.endsWith(".log") } ?: return
        if (files.size <= MAX_FILES) return
        files.sortedByDescending { it.lastModified() }
            .drop(MAX_FILES)
            .forEach { runCatching { it.delete() } }
    }

    private fun human(bytes: Int): String = human(bytes.toLong())

    private fun human(bytes: Long): String {
        if (bytes <= 0) return "0B"
        val units = arrayOf("B", "KB", "MB", "GB")
        var v = bytes.toDouble()
        var i = 0
        while (v >= 1024 && i < units.size - 1) {
            v /= 1024
            i++
        }
        return if (i == 0 || v >= 10) "${v.toInt()}${units[i]}" else String.format(Locale.US, "%.1f%s", v, units[i])
    }
}
