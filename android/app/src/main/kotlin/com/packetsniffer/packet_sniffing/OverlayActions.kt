package com.packetsniffer.packet_sniffing

import android.util.Log
import flutter.overlay.window.flutter_overlay_window.OverlayService
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * 悬浮窗（第二个 FlutterEngine，入口 `overlayMain`）与原生之间的直连通道。
 *
 * 为什么不走插件的 `shareData`：`flutter_overlay_window` 1.0.2 的
 * `OverlayService` 收到悬浮窗发出的消息后执行的是
 * `windowSetup.getMessenger().send(message)`，而那个 messenger 绑在**主引擎**上、
 * 处理器又是插件自己的 `onMessage`，它会再把消息转给悬浮窗引擎——等于原样
 * 回弹给自己，主 isolate 永远收不到「expand / exit」。
 * 结果就是：点图标只改了悬浮窗内部 UI，窗口尺寸没人改（56×56 里塞半屏卡片），
 * 看起来就是「点了没反应」；长按也传不出去。
 *
 * 这里在悬浮窗引擎上自建一条 MethodChannel，展开/收起/退出都由原生直接执行，
 * 不再依赖主 isolate 中转。
 */
object OverlayActions {

    private const val TAG = "PacketSniffer"
    private const val CHANNEL = "packetsniffing/overlay"

    /** 插件里 `OverlayConstants.CACHED_TAG` 是包内可见常量，值固定，这里照抄 */
    private const val CACHED_TAG = "myCachedEngine"

    private const val ICON_DP = 56
    private const val PANEL_MARGIN = 8
    private const val PANEL_MIN_H = 280.0
    private const val PANEL_MAX_H = 480.0

    /** 悬浮窗需要原生执行的动作（由 Activity 提供） */
    interface Callbacks {
        /** 长按悬浮球：结束抓包并回到本应用 */
        fun onExitRequested()
    }

    private var installedFor: Any? = null
    private var iconX = Int.MIN_VALUE
    private var iconY = Int.MIN_VALUE

    /** 悬浮窗引擎是 `showOverlay` 时才创建的，所以这里允许反复调用，装好即返回 */
    fun ensureInstalled(callbacks: Callbacks): Boolean {
        val engine = FlutterEngineCache.getInstance().get(CACHED_TAG) ?: return false
        val messenger = engine.dartExecutor.binaryMessenger
        if (installedFor === messenger) return true
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "expand" -> {
                    val ok = expand()
                    Log.d(TAG, "overlay expand -> $ok")
                    result.success(ok)
                }
                "collapse" -> {
                    val ok = collapse()
                    Log.d(TAG, "overlay collapse -> $ok")
                    result.success(ok)
                }
                "exit" -> {
                    result.success(true)
                    Log.d(TAG, "overlay exit requested")
                    callbacks.onExitRequested()
                }
                else -> result.notImplemented()
            }
        }
        installedFor = messenger
        Log.d(TAG, "overlay native channel installed")
        return true
    }

    /** 图标 → 半屏卡片。插件内部会 dp→px，这里传 dp */
    fun expand(): Boolean {
        val size = OverlayService.getScreenSize() ?: return false
        val sw = size["width"] ?: return false
        val sh = size["height"] ?: return false
        // 记住图标当前所在位置（用户可能拖过），收起时还原
        OverlayService.getCurrentPosition()?.let {
            it["x"]?.toInt()?.let { v -> iconX = v }
            it["y"]?.toInt()?.let { v -> iconY = v }
        }
        val w = (sw - PANEL_MARGIN * 2).toInt().coerceAtLeast(200)
        val h = (sh * 0.52).coerceIn(PANEL_MIN_H, PANEL_MAX_H).toInt()
        return OverlayService.updateOverlay(0, PANEL_MARGIN, w, h, false)
    }

    /** 半屏卡片 → 图标 */
    fun collapse(): Boolean {
        val size = OverlayService.getScreenSize() ?: return false
        val sw = size["width"] ?: return false
        val sh = size["height"] ?: return false
        val x = if (iconX != Int.MIN_VALUE) iconX else ((sw - ICON_DP) / 2).toInt()
        val y = if (iconY != Int.MIN_VALUE) iconY else (sh * 0.55).toInt()
        return OverlayService.updateOverlay(x, y, ICON_DP, ICON_DP, true)
    }
}
