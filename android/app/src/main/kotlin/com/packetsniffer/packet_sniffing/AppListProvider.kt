package com.packetsniffer.packet_sniffing

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.os.Build
import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import java.text.Collator
import java.util.Locale

/**
 * 手机已安装应用清单（窗口化「选择要抓取的应用」用）。
 *
 * 只返回**可启动**的应用：窗口化最后要把选中的应用拉到前台，没有启动入口的
 * 系统组件选了也没意义。图标统一缩到 64px 转 base64 PNG，避免把原始 drawable
 * 序列化过去（体积不可控），单个图标约 1~3KB，整份清单几百 KB 尚可接受。
 */
object AppListProvider {
    private const val TAG = "PacketSniffer"
    private const val ICON_PX = 64

    /** 图标缓存：包名 -> base64 PNG。二次进入选择页时省掉逐包解码。 */
    private val iconCache = HashMap<String, String>()

    fun list(ctx: Context): List<Map<String, Any?>> {
        val pm = ctx.packageManager
        // 用「桌面启动器 Activity」来拿应用列表，而不是 getInstalledApplications：
        // 1) 本来就只要可启动的应用；
        // 2) 国产 ROM（HyperOS / MIUI）对「读取应用列表」有独立的隐私拦截，
        //    getInstalledApplications 会弹系统授权框且拒绝后返回空列表，
        //    而 launcher 查询走的是常规 intent 解析，不会被拦。
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = try {
            pm.queryIntentActivities(intent, 0)
        } catch (e: Exception) {
            Log.e(TAG, "queryIntentActivities failed: ${e.message}")
            emptyList()
        }
        val seen = HashSet<String>(resolved.size)
        val out = ArrayList<Map<String, Any?>>(resolved.size)
        for (ri in resolved) {
            val ai = ri.activityInfo?.applicationInfo ?: continue
            val pkg = ai.packageName ?: continue
            if (pkg == ctx.packageName) continue
            if (!seen.add(pkg)) continue
            val label = try {
                ri.loadLabel(pm).toString()
            } catch (e: Exception) {
                pkg
            }
            val system = (ai.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            out.add(
                mapOf(
                    "package" to pkg,
                    "label" to label,
                    "system" to system,
                    "icon" to iconOf(pm, pkg)
                )
            )
        }
        // 用户应用在前，系统应用在后，组内按中文拼音排序
        val collator = Collator.getInstance(Locale.CHINA)
        out.sortWith(Comparator { a, b ->
            val sa = a["system"] as Boolean
            val sb = b["system"] as Boolean
            if (sa != sb) return@Comparator if (sa) 1 else -1
            collator.compare(a["label"] as String, b["label"] as String)
        })
        Log.d(TAG, "listApps -> ${out.size} launchable apps")
        return out
    }

    fun labelOf(ctx: Context, pkg: String): String = try {
        val pm = ctx.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (e: Exception) {
        pkg
    }

    private fun iconOf(pm: PackageManager, pkg: String): String {
        iconCache[pkg]?.let { return it }
        val drawable: Drawable = try {
            pm.getApplicationIcon(pkg)
        } catch (e: Exception) {
            return ""
        }
        val bmp = toBitmap(drawable)
        val bytes = try {
            ByteArrayOutputStream().use { bos ->
                bmp.compress(Bitmap.CompressFormat.PNG, 100, bos)
                bos.toByteArray()
            }
        } catch (e: Exception) {
            return ""
        }
        val encoded = Base64.encodeToString(bytes, Base64.NO_WRAP)
        iconCache[pkg] = encoded
        return encoded
    }

    private fun toBitmap(d: Drawable): Bitmap {
        if (d is BitmapDrawable) {
            d.bitmap?.let { src ->
                return Bitmap.createScaledBitmap(src, ICON_PX, ICON_PX, true)
            }
        }
        val bmp = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        d.setBounds(0, 0, ICON_PX, ICON_PX)
        d.draw(canvas)
        return bmp
    }

    @Suppress("unused")
    private fun apiLevel() = Build.VERSION.SDK_INT
}
