package com.packetsniffer.packet_sniffing

import android.graphics.Color
import android.util.Log
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager

/**
 * 悬浮窗窗口标志修正。
 *
 * `flutter_overlay_window` 的 `WindowSetup.setFlag` 只支持「单标志」：
 * - `defaultFlag`      → FLAG_NOT_FOCUSABLE（窗口**触摸模态**，会吞掉窗口以外的所有触摸，
 *                        也就是说悬浮图标一出现，后面的 App 就点不动了）
 * - `focusPointer`     → FLAG_NOT_TOUCH_MODAL（可透传，但窗口变成可获得焦点，会抢输入焦点）
 *
 * 我们需要的是两者叠加：既透传窗口外的触摸，又不抢焦点。插件没有这个枚举，
 * 而标志只在建窗时写入，事后拿不到 View。这里用反射拿到服务内的 FlutterView，
 * 直接把两个标志或进去并重新布局——插件版本在 pubspec.lock 里锁死，字段名稳定。
 */
object OverlayWindowTuner {
    private const val TAG = "PacketSniffer"
    private const val SERVICE_CLASS =
        "flutter.overlay.window.flutter_overlay_window.OverlayService"

    /** 成功返回 true；悬浮窗还没建好时返回 false，调用方重试即可 */
    fun relaxTouchModal(): Boolean {
        return try {
            val cls = Class.forName(SERVICE_CLASS)
            val instanceField = cls.getDeclaredField("instance").apply { isAccessible = true }
            val service = instanceField.get(null) ?: return false

            val viewField = cls.getDeclaredField("flutterView").apply { isAccessible = true }
            val view = viewField.get(service) as? View ?: return false

            val wmField = cls.getDeclaredField("windowManager").apply { isAccessible = true }
            val wm = wmField.get(service) as? WindowManager ?: return false

            val lp = view.layoutParams as? WindowManager.LayoutParams ?: return false
            // 窗口内容由 FlutterTextureView 绘制，它默认 setOpaque(true)：
            // 圆形图标外面那圈"透明"像素会被当成不透明画出来（露出一块浅色方块）。
            // 这里把整棵子树背景清空 + 关掉 TextureView 的 opaque，才有干净边缘。
            makeTransparent(view)
            val wanted = lp.flags or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            if (lp.flags == wanted) {
                wm.updateViewLayout(view, lp)
                return true
            }
            lp.flags = wanted
            wm.updateViewLayout(view, lp)
            Log.d(TAG, "overlay flags relaxed -> ${Integer.toHexString(wanted)}")
            true
        } catch (e: Throwable) {
            Log.w(TAG, "relaxTouchModal failed: ${e.javaClass.simpleName} ${e.message}")
            false
        }
    }

    /** 把窗口内所有 View 的背景清空，并让 TextureView 参与 alpha 合成 */
    private fun makeTransparent(v: View) {
        try {
            v.setBackgroundColor(Color.TRANSPARENT)
        } catch (_: Throwable) {
        }
        if (v is TextureView) {
            try {
                v.isOpaque = false
            } catch (_: Throwable) {
            }
        }
        if (v is ViewGroup) {
            for (i in 0 until v.childCount) makeTransparent(v.getChildAt(i))
        }
    }
}
