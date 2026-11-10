import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// 悬浮窗 isolate 的启动体：由 main.dart 的 overlayMain 入口调用
/// （插件固定按名字 `overlayMain` 查找入口，入口函数必须写在 main.dart）。
void runOverlayEntry() {
  WidgetsFlutterBinding.ensureInitialized();
  // 悬浮窗是悬浮球/半屏卡片，用 WidgetsApp + 透明画布：
  // MaterialApp 会铺一层不透明底色，圆形图标外面就露出一块浅色方块。
  runApp(
    WidgetsApp(
      color: Colors.transparent,
      debugShowCheckedModeBanner: false,
      builder: (context, _) => const OverlayShell(),
    ),
  );
}

/// 一条请求的精简视图（主 isolate 推过来的）
class _Row {
  final String method;
  final String host;
  final String path;
  final int status;
  final DateTime time;

  const _Row(this.method, this.host, this.path, this.status, this.time);

  factory _Row.fromMap(Map m) => _Row(
        (m['m'] as String?) ?? 'GET',
        (m['h'] as String?) ?? '',
        (m['p'] as String?) ?? '',
        (m['s'] as num?)?.toInt() ?? 0,
        DateTime.fromMillisecondsSinceEpoch((m['t'] as num?)?.toInt() ?? 0),
      );
}

/// 窗口化悬浮窗：一个会自适应窗口大小的壳。
///
/// 展开 / 收起 / 退出都走原生直连通道 `packetsniffing/overlay`
/// （见 OverlayActions.kt）。不依赖插件 `shareData`：1.0.2 版本里悬浮窗发出的
/// 消息会被插件原样转回给悬浮窗自己，主 isolate 收不到，点击就等于没反应。
class OverlayShell extends StatefulWidget {
  const OverlayShell({super.key});

  @override
  State<OverlayShell> createState() => _OverlayShellState();
}

class _OverlayShellState extends State<OverlayShell>
    with SingleTickerProviderStateMixin {
  static const _native = MethodChannel('packetsniffing/overlay');

  String _mode = 'icon';
  bool _capturing = true;
  int _count = 0;
  String _app = '';
  List<_Row> _rows = const [];
  bool _busy = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    FlutterOverlayWindow.overlayListener.listen((msg) {
      if (msg is! Map || !mounted) return;
      if (msg['type'] != 'state') return;
      final raw = (msg['records'] as List?) ?? const [];
      setState(() {
        _capturing = (msg['capturing'] as bool?) ?? _capturing;
        _count = (msg['count'] as int?) ?? _count;
        _app = (msg['app'] as String?) ?? _app;
        _rows = raw
            .whereType<Map>()
            .map(_Row.fromMap)
            .toList(growable: false);
      });
      // 调试钩子：主 isolate 只能"推"，这里代替手指执行一次点击/长按
      final debug = msg['debugAction'] as String?;
      if (debug == 'expand') _expand();
      if (debug == 'collapse') _collapse();
      if (debug == 'exit') _exit();
    });
    // 起来后主动要一次最新状态
    FlutterOverlayWindow.shareData({'action': 'sync'});
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  // ---- 三个动作：都交给原生直接执行 ----

  Future<void> _expand() async {
    if (_busy || _mode == 'panel') return;
    _busy = true;
    HapticFeedback.selectionClick();
    var ok = false;
    try {
      ok = await _native.invokeMethod<bool>('expand') ?? false;
    } catch (e) {
      debugPrint('[overlay] expand failed: $e');
      ok = false;
    }
    debugPrint('[overlay] expand -> $ok');
    if (!mounted) return;
    // 只有窗口真的变成半屏才切内容，否则会在 56×56 的窗口里渲染一个被裁掉的卡片
    if (ok) {
      setState(() => _mode = 'panel');
    } else {
      // 兜底：老版本插件走主 isolate 那条（当前插件版本收不到，仅作兼容）
      FlutterOverlayWindow.shareData({'action': 'expand'});
    }
    _busy = false;
  }

  Future<void> _collapse() async {
    if (_busy || _mode == 'icon') return;
    _busy = true;
    HapticFeedback.selectionClick();
    var ok = false;
    try {
      ok = await _native.invokeMethod<bool>('collapse') ?? false;
      debugPrint('[overlay] collapse -> $ok');
    } catch (e) {
      debugPrint('[overlay] collapse failed: $e');
      FlutterOverlayWindow.shareData({'action': 'collapse'});
    }
    if (!mounted) return;
    // 窗口缩回 56×56 之后再切回图标，避免卡片内容被压进小窗口
    if (ok) setState(() => _mode = 'icon');
    _busy = false;
  }

  Future<void> _exit() async {
    HapticFeedback.mediumImpact();
    try {
      await _native.invokeMethod('exit');
    } catch (_) {
      FlutterOverlayWindow.shareData({'action': 'exit'});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: _mode == 'panel' ? _buildPanel() : _buildIcon(),
    );
  }

  // ---- 形态一：悬浮球 ----

  Widget _buildIcon() {
    final countText = _count > 99 ? '99+' : '$_count';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _expand,
      onLongPress: _exit,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _capturing ? _pulse.value : 0.0;
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _capturing
                    ? const [
                        Color(0xFF7C6BFF),
                        Color(0xFF4F46E5),
                        Color(0xFF312E81),
                      ]
                    : const [
                        Color(0xFFA7AFBD),
                        Color(0xFF6B7280),
                        Color(0xFF404653),
                      ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: _capturing ? 0.55 : 0.4),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_capturing ? const Color(0xFF4F46E5) : Colors.black)
                      .withValues(alpha: _capturing ? 0.24 + 0.1 * t : 0.18),
                  blurRadius: 7 + 5 * t,
                  spreadRadius: 0.5 + 1.5 * t,
                ),
              ],
            ),
            child: child,
          );
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 中心图标：podcast 的「信号发射」语义，比雷达更贴合抓包
            Icon(
              Icons.podcasts_rounded,
              color: Colors.white.withValues(alpha: _capturing ? 1 : 0.9),
              size: 25,
            ),
            // 抓包中：左下红点呼吸，表示正在录制
            if (_capturing)
              Positioned(
                left: 6,
                bottom: 7,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(const Color(0xFFF43F5E),
                          const Color(0x66F43F5E), _pulse.value)!,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.92), width: 1.3),
                    ),
                  ),
                ),
              ),
            if (_count > 0)
              Positioned(
                right: 2,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.92),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    countText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8.5,
                      height: 1.15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---- 形态二：半屏抓包列表 ----

  Widget _buildPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Color(0x2E000000), blurRadius: 20, offset: Offset(0, -4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _header(),
          const Divider(height: 1, color: Color(0xFFEDEFF3)),
          Expanded(
            child: _rows.isEmpty
                ? _empty()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 12,
                        endIndent: 12,
                        color: Color(0xFFEDEFF3)),
                    itemBuilder: (c, i) => _rowItem(_rows[i]),
                  ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(
          children: [
            // 抓包状态灯：抓包中红色呼吸，停止为灰
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _capturing
                      ? Color.lerp(
                          const Color(0xFFF43F5E),
                          const Color(0x59F43F5E),
                          _pulse.value,
                        )!
                      : const Color(0xFF9AA3B2),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _capturing ? '抓包中' : '已停止',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F3F7),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '$_count 条',
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w500),
              ),
            ),
            const SizedBox(width: 6),
            // 应用名占满剩余宽度并自动省略，避免长名字把这一行撑溢出
            Expanded(
              child: _app.isEmpty
                  ? const SizedBox.shrink()
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF0FF),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          _app,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4F46E5),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 24, color: Color(0xFF6B7280)),
              onPressed: _collapse,
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowItem(_Row r) {
    const methodColors = {
      'GET': Color(0xFF16A34A),
      'POST': Color(0xFF2563EB),
      'PUT': Color(0xFFD97706),
      'DELETE': Color(0xFFDC2626),
      'HEAD': Color(0xFF7C3AED),
      'OPTIONS': Color(0xFF0891B2),
      'TCP': Color(0xFF64748B),
      'UDP': Color(0xFF64748B),
    };
    final color = methodColors[r.method] ?? const Color(0xFF2563EB);
    final time =
        '${r.time.hour.toString().padLeft(2, '0')}:${r.time.minute.toString().padLeft(2, '0')}:${r.time.second.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              r.method,
              maxLines: 1,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                      height: 1.25),
                ),
                Text(
                  r.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8E8E93),
                      height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            r.status > 0 ? '${r.status}' : time,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: r.status >= 400
                  ? const Color(0xFFDC2626)
                  : (r.status > 0 ? const Color(0xFF16A34A) : const Color(0xFF8E8E93)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_tethering_rounded, size: 40, color: Color(0xFFC7CBD6)),
          SizedBox(height: 8),
          Text('等待请求…',
              style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDEFF3))),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '长按悬浮球：结束抓包并回到应用',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
            ),
          ),
          TextButton(
            onPressed: _exit,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF4F46E5),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              textStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            child: const Text('回到应用'),
          ),
        ],
      ),
    );
  }
}
