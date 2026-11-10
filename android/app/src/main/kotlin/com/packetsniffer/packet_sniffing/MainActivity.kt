package com.packetsniffer.packet_sniffing

import android.app.Activity
import android.app.ActivityManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.security.KeyChain
import android.util.Log
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "packetsniffing/capture"
    private val EVENTS = "packetsniffing/events"
    private val VPN_REQUEST_CODE = 1001

    /** VPN 授权是异步的：等 onActivityResult 回来再回复 Dart，避免「以为开了其实没开」 */
    private var pendingStartResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // 调试直达：adb am start --es screen /history --ei tab 1
                    // 详情页无命名路由，用 --ei record <序号> 直接打开对应记录
                    "launchOptions" -> {
                        val screen = intent?.getStringExtra("screen")
                        val tab = intent?.getIntExtra("tab", -1) ?: -1
                        val record = intent?.getIntExtra("record", -1) ?: -1
                        val autostart = intent?.getBooleanExtra("autostart", false) ?: false
                        // 调试：冷启动直接开悬浮窗（MIUI 禁用 adb input 时用来验收窗口化）
                        val overlay = intent?.getBooleanExtra("overlay", false) ?: false
                        val targetApp = intent?.getStringExtra("targetApp")
                        val overlayAction = intent?.getStringExtra("overlayAction")
                        result.success(
                            mapOf(
                                "screen" to screen,
                                "tab" to if (tab >= 0) tab else null,
                                "record" to if (record >= 0) record else null,
                                "autostart" to autostart,
                                "overlay" to overlay,
                                "targetApp" to targetApp,
                                "overlayAction" to overlayAction
                            )
                        )
                    }
                    "startCapture" -> {
                        // 参数：{package: String?, packages: List<String>?}
                        // package 为窗口化单应用；packages 为「抓包应用」勾选的白名单；都为空 = 抓全部。
                        val args = call.arguments as? Map<*, *>
                        val pkg = (args?.get("package") as? String)?.trim().orEmpty()
                        val pkgs = (args?.get("packages") as? List<*>)
                            ?.mapNotNull { (it as? String)?.trim() }
                            ?.filter { it.isNotEmpty() }
                            ?.toSet()
                            ?: emptySet()
                        val targets = if (pkg.isNotEmpty()) setOf(pkg) else pkgs
                        CaptureBridge.allowedPackages = targets
                        CaptureBridge.allowedAppLabel =
                            if (targets.isEmpty()) "" else targets.joinToString("、") {
                                AppListProvider.labelOf(this, it)
                            }
                        ensureVpnPermissionThenStart(result)
                    }
                    "listApps" -> {
                        // 扫描安装列表 + 解码图标比较慢，丢到后台线程，回主线程回复
                        Thread {
                            val list = try {
                                AppListProvider.list(this)
                            } catch (e: Exception) {
                                Log.e("PacketSniffer", "listApps failed: ${e.message}")
                                emptyList<Map<String, Any?>>()
                            }
                            mainHandler.post { result.success(list) }
                        }.start()
                    }
                    "appLabel" -> {
                        val pkg = call.arguments as? String
                        result.success(
                            if (pkg.isNullOrEmpty()) "" else AppListProvider.labelOf(this, pkg)
                        )
                    }
                    "launchApp" -> {
                        val pkg = call.arguments as? String
                        result.success(pkg != null && launchTargetApp(pkg))
                    }
                    "moveTaskToBack" -> {
                        result.success(moveTaskToBack(true))
                    }
                    "bringToFront" -> {
                        result.success(bringSelfToFront())
                    }
                    "exitOverlay" -> {
                        // 悬浮窗长按 / 调试指令的统一出口：结束抓包 → 回前台 → 收悬浮窗
                        exitOverlayToApp()
                        result.success(true)
                    }
                    "relaxOverlay" -> {
                        // 悬浮窗建好后把「不抢焦点 + 透传窗外触摸」补上，见 OverlayWindowTuner
                        val relaxed = OverlayWindowTuner.relaxTouchModal()
                        // 引擎此时才存在：顺手把悬浮窗的原生直连通道装好
                        OverlayActions.ensureInstalled(overlayCallbacks)
                        result.success(relaxed)
                    }
                    "stopCapture" -> {
                        val intent = Intent(this, CaptureVpnService::class.java).apply {
                            action = CaptureVpnService.ACTION_STOP
                        }
                        startService(intent)
                        result.success(null)
                    }
                    "setFilter" -> {
                        val m = call.arguments as? Map<*, *>
                        CaptureBridge.blacklist =
                            (m?.get("blacklist") as? List<*>)?.mapNotNull { it as? String }
                                ?: CaptureBridge.blacklist
                        CaptureBridge.whitelist =
                            (m?.get("whitelist") as? List<*>)?.mapNotNull { it as? String }
                                ?: CaptureBridge.whitelist
                        CaptureBridge.blacklistEnabled =
                            (m?.get("blacklistEnabled") as? Boolean) ?: CaptureBridge.blacklistEnabled
                        CaptureBridge.whitelistEnabled =
                            (m?.get("whitelistEnabled") as? Boolean) ?: CaptureBridge.whitelistEnabled
                        result.success(null)
                    }
                    "setMocks" -> {
                        val raw = call.arguments as? List<Any?>
                        val rules = (raw ?: emptyList()).mapNotNull { item ->
                            val m = item as? Map<*, *> ?: return@mapNotNull null
                            MockRule(
                                id = (m["id"] as? String) ?: "",
                                enabled = (m["enabled"] as? Boolean) ?: true,
                                name = (m["name"] as? String) ?: "",
                                method = (m["method"] as? String) ?: "*",
                                host = (m["host"] as? String) ?: "",
                                path = (m["path"] as? String) ?: "",
                                statusCode = (m["statusCode"] as? Number)?.toInt() ?: 200,
                                contentType = (m["contentType"] as? String) ?: "application/json",
                                body = (m["body"] as? String) ?: "",
                                delayMs = (m["delayMs"] as? Number)?.toLong() ?: 0,
                                headers = (m["headers"] as? List<*>)?.mapNotNull { h ->
                                    val p = h as? List<*>
                                    val k = p?.getOrNull(0) as? String
                                    val v = p?.getOrNull(1) as? String
                                    if (k != null) k to (v ?: "") else null
                                } ?: emptyList()
                            )
                        }
                        CaptureBridge.mockRules = rules
                        result.success(null)
                    }
                    "setMockEnabled" -> {
                        CaptureBridge.mockEnabled = (call.arguments as? Boolean) ?: false
                        result.success(null)
                    }
                    "setMockApps" -> {
                        val raw = call.arguments as? List<Any?>
                        CaptureBridge.mockApps = (raw ?: emptyList())
                            .mapNotNull { it as? String }.toSet()
                        result.success(null)
                    }
                    "installCa" -> {
                        val ok = CertAuthority.ensureCa(this)
                        if (ok) {
                            val der = CertAuthority.caDerBytes(this)
                            if (der != null) {
                                try {
                                    val intent = KeyChain.createInstallIntent()
                                    intent.putExtra(KeyChain.EXTRA_CERTIFICATE, der)
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    Log.e("PacketSniffer", "installCa startActivity failed: ${e.message}")
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "exportCa" -> {
                        val ok = CertAuthority.ensureCa(this)
                        if (ok) {
                            val pem = CertAuthority.caPemBytes(this)?.toString(Charsets.UTF_8) ?: ""
                            result.success(saveCaToDownloads(this, pem))
                        } else {
                            result.success("导出失败：CA 初始化失败")
                        }
                    }
                    "clearMitmCache" -> {
                        // 用户手动重置：证书缓存 + 排除名单一起清，所有域名重新尝试解密
                        LocalProxyServer.clearMitmCache()
                        CertAuthority.clearCache()
                        MitmExclusions.clear()
                        result.success(null)
                    }
                    "clearLogs" -> {
                        FileLogger.deleteAll(this)
                        result.success(null)
                    }
                    "getLogs" -> {
                        // 日志文件在 filesDir/capture_logs，读列表比较轻，直接主线程回
                        result.success(FileLogger.listFiles(this))
                    }
                    "readLog" -> {
                        val name = call.arguments as? String ?: ""
                        result.success(FileLogger.readFile(this, name))
                    }
                    "setWindowMode" -> {
                        result.success(null)
                    }
                    "setHttpsProxy" -> {
                        val enabled = (call.arguments as? Boolean) ?: true
                        CaptureMode.httpsProxyEnabled = enabled
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    CaptureBridge.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    CaptureBridge.eventSink = null
                }
            })
    }

    private fun ensureVpnPermissionThenStart(result: MethodChannel.Result) {
        // 上一次没回复完的结果先丢掉，避免 Dart 侧永远等
        pendingStartResult?.success(false)
        pendingStartResult = result
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivityForResult(prepare, VPN_REQUEST_CODE)
        } else {
            startVpnService()
            finishStart(true)
        }
    }

    private fun finishStart(ok: Boolean) {
        pendingStartResult?.success(ok)
        pendingStartResult = null
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                startVpnService()
                finishStart(true)
            } else {
                CaptureBridge.allowedPackages = emptySet()
                CaptureBridge.allowedAppLabel = ""
                CaptureBridge.emitLog(
                    "vpn_permission.log",
                    "用户未授予 VPN 权限，抓包未能启动。"
                )
                finishStart(false)
            }
        }
    }

    /** 打开选中的应用，本身会把自己的任务压到后台 */
    private fun launchTargetApp(pkg: String): Boolean {
        val intent = packageManager.getLaunchIntentForPackage(pkg) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
        return try {
            startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e("PacketSniffer", "launchApp($pkg) failed: ${e.message}")
            false
        }
    }

    /**
     * 从悬浮窗把本 App 拉回前台。
     *
     * 后台启动 Activity 默认被系统拦截，但持有 SYSTEM_ALERT_WINDOW 的应用属于豁免场景，
     * 窗口化必须先拿到悬浮窗权限，这里才走得通。
     */
    /**
     * 从悬浮窗回到本应用。
     *
     * 踩坑记录（都在真机上验证过）：
     * - `SINGLE_TOP` / `singleTask` / `CLEAR_TOP+SINGLE_TOP` 命中已有实例时，系统只回
     *   `START_DELIVERED_TO_TOP`：intent 投递到了，但任务栈**不会**提到前台，界面没反应；
     * - `moveTaskToFront` 虽然有 `REORDER_TASKS` 权限、也不抛异常，但在 MIUI 上被静默忽略。
     *
     * 所以改成 `NEW_TASK + CLEAR_TOP`（不带 SINGLE_TOP）：清掉旧实例、在同一任务栈里
     * 重建，系统才会给 `START_TASK_TO_FRONT`，界面真的切过来。新实例通过
     * `screen=/capture` 直达抓包列表。
     */
    private fun bringSelfToFront(): Boolean {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("screen", "/capture")
        }
        var ok = try {
            startActivity(intent)
            Log.d("PacketSniffer", "bringToFront via NEW_TASK|CLEAR_TOP")
            true
        } catch (e: Exception) {
            Log.e("PacketSniffer", "bringToFront failed: ${e.message}")
            false
        }
        if (!ok) {
            ok = try {
                val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                am.moveTaskToFront(taskId, 0)
                true
            } catch (e2: Exception) {
                Log.e("PacketSniffer", "moveTaskToFront failed: ${e2.message}")
                false
            }
        }
        // 系统只回 START_DELIVERED_TO_TOP、Activity 没有被重建时，Dart 侧还活着，
        // 由它自己切到抓包列表，补上「回到应用但停在首页」的情况。
        postNavigate("/capture")
        // 等界面真正可见后再收悬浮窗：先收会被 MIUI 拦成「点了没反应」
        mainHandler.postDelayed({ closeOverlayQuietly() }, 900)
        return ok
    }

    /** 悬浮窗长按的统一出口：停抓包 → 拉起本应用 → 收悬浮窗 */
    private fun exitOverlayToApp() {
        try {
            startService(Intent(this, CaptureVpnService::class.java).apply {
                action = CaptureVpnService.ACTION_STOP
            })
        } catch (e: Exception) {
            Log.w("PacketSniffer", "stop capture from overlay failed: ${e.message}")
        }
        if (!bringSelfToFront()) {
            Log.w("PacketSniffer", "bringSelfToFront failed, closing overlay only")
            mainHandler.postDelayed({ closeOverlayQuietly() }, 200)
        }
    }

    /** 走主引擎通道让 Dart 推出对应页面（Activity 未被重建时用） */
    private fun postNavigate(route: String) {
        mainHandler.postDelayed({
            try {
                val engine = flutterEngine ?: return@postDelayed
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigate", route)
            } catch (e: Exception) {
                Log.w("PacketSniffer", "navigate($route) dropped: ${e.message}")
            }
        }, 320)
    }

    /** 收掉悬浮窗，并让 Dart 复位「窗口化已开启」的状态 */
    private fun closeOverlayQuietly() {
        try {
            val engine = flutterEngine
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("overlayExited", null)
            }
        } catch (_: Exception) {
        }
        try {
            stopService(Intent(this, OverlayService::class.java))
            Log.d("PacketSniffer", "overlay closed")
        } catch (e: Exception) {
            Log.w("PacketSniffer", "close overlay failed: ${e.message}")
        }
    }

    private val overlayCallbacks = object : OverlayActions.Callbacks {
        override fun onExitRequested() = exitOverlayToApp()
    }

    override fun onResume() {
        super.onResume()
        // showOverlay 之后引擎才会出现在缓存里；这里再兜一次，避免漏装通道
        OverlayActions.ensureInstalled(overlayCallbacks)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val screen = intent.getStringExtra("screen")
        setIntent(intent)
        if (!screen.isNullOrEmpty()) postNavigate(screen)
    }

    private fun startVpnService() {
        val intent = Intent(this, CaptureVpnService::class.java).apply {
            action = CaptureVpnService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    /**
     * 把 CA 证书（PEM）写入系统「下载」目录，返回给用户可读的路径或错误信息。
     * - Android 10+ 走 MediaStore.Downloads，无需存储权限；
     * - 旧版本回退到 Environment 公开下载目录（需 WRITE_EXTERNAL_STORAGE）。
     */
    private fun saveCaToDownloads(activity: Activity, pem: String): String {
        val filename = "PacketSniffer-CA.crt"
        return try {
            if (pem.isEmpty()) {
                "导出失败：证书内容为空"
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = activity.contentResolver
                val collection =
                    MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, filename)
                    put(MediaStore.Downloads.MIME_TYPE, "application/x-x509-ca-cert")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val itemUri: Uri = resolver.insert(collection, values)
                    ?: return "导出失败：无法在下载目录创建文件"
                resolver.openOutputStream(itemUri)?.use { os ->
                    os.write(pem.toByteArray(Charsets.UTF_8))
                } ?: return "导出失败：无法写入文件"
                "${Environment.DIRECTORY_DOWNLOADS}/$filename"
            } else {
                val dir =
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, filename)
                file.writeText(pem, Charsets.UTF_8)
                file.absolutePath
            }
        } catch (e: Exception) {
            "导出失败：${e.message}"
        }
    }
}
