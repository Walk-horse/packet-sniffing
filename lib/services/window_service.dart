import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/nav.dart';
import 'package:packet_sniffing/routes.dart';
import 'package:packet_sniffing/services/app_list_service.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/services/settings_service.dart';

/// 窗口化 / 悬浮窗的结果，区分「没权限」和「真失败」，便于给不同提示
enum OverlayResult { shown, hidden, denied, failed }

/// 悬浮窗与主 App 的桥，负责三件事：
///
/// 1. **形态切换**：屏幕上是 56dp 的圆形图标，点一下变成半屏抓包列表（同一个
///    Overlay 窗口改尺寸+位置，而不是开第二个窗口，避免两层遮挡与触摸冲突）。
///    `updateOverlay` 收的是 **dp**，`showOverlay` 收的是 **px**，两者不能混。
/// 2. **数据下发**：悬浮窗跑在插件内部第二个 FlutterEngine 里，**没有注册任何
///    插件**，读不到 shared_preferences / MethodChannel，所以抓包状态与列表必须由
///    主 isolate 用 `shareData` 推过去。
/// 3. **指令回收**：悬浮窗上的「展开 / 收起 / 长按退出」都用 shareData 回传，
///    由主 isolate 执行（那个 isolate 里调 closeOverlay 会 MissingPluginException）。
class OverlayBridge {
  OverlayBridge._();

  static const MethodChannel _native = MethodChannel('packetsniffing/capture');

  /// 图标尺寸（dp），圆形悬浮球
  static const double iconSize = 56;

  static bool _bound = false;
  static bool _active = false;
  static String _mode = 'icon'; // icon | panel
  static String _appLabel = '';

  static double _screenW = 360;
  static double _screenH = 720;
  static double _iconX = 0;
  static double _iconY = 0;

  static CaptureService? _capture;
  static SettingsService? _settings;
  static Timer? _throttle;

  static bool get active => _active;
  static String get mode => _mode;
  static String get appLabel => _appLabel;

  static void bind({
    required CaptureService capture,
    required SettingsService settings,
  }) {
    if (_bound) return;
    _bound = true;
    _capture = capture;
    _settings = settings;
    capture.addListener(_push);
    FlutterOverlayWindow.overlayListener.listen(_onOverlayMessage);
  }

  /// 冷启动对账：进程被杀后悬浮窗也没了，别让设置里一直显示「已开启」
  static Future<void> syncOnStart() async {
    bool running = false;
    try {
      running = await FlutterOverlayWindow.isActive();
    } catch (_) {
      running = false;
    }
    _active = running;
    if (running) {
      _mode = 'icon';
      await _push(immediate: true);
    } else if (_settings?.windowMode == true) {
      await _settings?.setWindowMode(false);
    }
  }

  // ---- 开关 ----

  static Future<OverlayResult> show(
    BuildContext context, {
    String appLabel = '',
  }) async {
    // MediaQuery 必须在第一个 await 之前取，避免跨 await 用 context
    final dpr = MediaQuery.of(context).devicePixelRatio;

    var granted = await isPermissionGranted();
    if (!granted) {
      if (!context.mounted) return OverlayResult.denied;
      granted = await _requestPermission(context);
    }
    if (!granted) return OverlayResult.denied;

    _appLabel = appLabel;
    _mode = 'icon';
    try {
      // showOverlay 的宽高是像素（原生直接塞进 LayoutParams）
      await FlutterOverlayWindow.showOverlay(
        width: (iconSize * dpr).round(),
        height: (iconSize * dpr).round(),
        alignment: OverlayAlignment.bottomCenter,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        overlayTitle: '抓包精灵',
        overlayContent:
            appLabel.isEmpty ? '正在抓取全部应用' : '正在抓取 $appLabel',
      );
    } catch (_) {
      return OverlayResult.failed;
    }
    _active = true;
    // 插件只会二选一：不抢焦点但吞掉窗外触摸，或可透传但抢焦点。
    // 这里补上「两者都要」，否则图标一出现后面的 App 就点不动了。
    await _relaxTouchModal();
    await _loadGeometry();
    await _applyIcon();
    await _settings?.setWindowMode(true);
    await _push(immediate: true);
    return OverlayResult.shown;
  }

  static Future<OverlayResult> hide() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {
      // 已经关掉的情况忽略
    }
    _active = false;
    _mode = 'icon';
    _appLabel = '';
    _throttle?.cancel();
    await _settings?.setWindowMode(false);
    return OverlayResult.hidden;
  }

  /// 供选择页使用的权限前置检查
  static Future<bool> isPermissionGranted() async {
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> ensurePermission(BuildContext context) async {
    if (await isPermissionGranted()) return true;
    if (!context.mounted) return false;
    return _requestPermission(context);
  }

  /// 窗口化完整启动链路：悬浮窗权限 → 开抓包（只纳入 [package]）→ 亮出悬浮图标
  /// → 自己退到后台并打开目标应用。
  ///
  /// 成功返回 null，失败返回给用户看的错误文案。
  static Future<String?> startForApp(
    BuildContext context, {
    String? package,
    String? label,
  }) async {
    final capture = context.read<CaptureService>();

    // 只给包名时补一个可读的应用名，悬浮窗上的标签才不会显示成一长串包名
    var name = label ?? '';
    final pkg0 = package ?? '';
    if (name.isEmpty && pkg0.isNotEmpty) {
      try {
        name = await _native.invokeMethod<String>('appLabel', pkg0) ?? '';
      } catch (_) {}
    }

    if (!context.mounted) return '页面已关闭';
    if (!await ensurePermission(context)) {
      return '未授予悬浮窗权限，无法窗口化';
    }
    if (!context.mounted) return '页面已关闭';

    final started = await capture.startCapture(package: package, label: name);
    if (!started) return '抓包启动失败，请确认已授予 VPN 权限';

    // 本应用还在前台时把悬浮窗拉起来（前台服务更稳）
    if (!context.mounted) return '页面已关闭';
    final r = await show(context, appLabel: name);
    if (r != OverlayResult.shown) {
      await capture.stopCapture();
      return r == OverlayResult.denied
          ? '未授予悬浮窗权限，无法窗口化'
          : '悬浮窗启动失败，请检查系统权限';
    }

    // 自己切到后台，再把选中的应用拉到前台
    final pkg = pkg0;
    if (pkg.isEmpty || !await AppListService.launch(pkg)) {
      await AppListService.moveTaskToBack();
    }
    return null;
  }

  /// 调试入口：等价于悬浮窗回传的指令（adb input 被禁时用来验收整条链路）
  ///
  /// 先把指令随状态推给悬浮窗，由悬浮窗自己走「原生直连」执行——和手指点击
  /// 完全同一条路径，这样才能真正验证点击/长按是否可用。
  static Future<void> debugAction(String action) async {
    _pendingDebug = action;
    await _push(immediate: true);
    _pendingDebug = null;
  }

  static String? _pendingDebug;

  // ---- 形态切换 ----

  /// 悬浮窗是异步建出来的，这里重试几次直到把窗口标志改成「可透传 + 不抢焦点」
  static Future<void> _relaxTouchModal() async {
    for (var i = 0; i < 10; i++) {
      try {
        final ok = await _native.invokeMethod<bool>('relaxOverlay') ?? false;
        if (ok) return;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 120));
    }
  }

  static Future<void> _loadGeometry() async {
    try {
      final s = await FlutterOverlayWindow.getScreenSize();
      if (s.x > 0 && s.y > 0) {
        _screenW = s.x;
        _screenH = s.y;
      }
    } catch (_) {}
    // 默认贴右边、屏幕 45% 高度处，避开底部导航
    _iconX = (_screenW - iconSize) / 2 - 8;
    _iconY = _screenH * 0.45;
  }

  static Future<void> _applyIcon() async {
    try {
      await FlutterOverlayWindow.updateOverlay(
        x: _iconX.round(),
        y: _iconY.round(),
        width: iconSize.round(),
        height: iconSize.round(),
        enableDrag: true,
      );
    } catch (_) {}
  }

  /// 图标 → 半屏列表
  static Future<void> _expand() async {
    if (!_active) return;
    // 记住图标当前位置（用户可能拖过），收起时还原
    try {
      final p = await FlutterOverlayWindow.getOverlayPosition();
      if (p.x != 0 || p.y != 0) {
        _iconX = p.x;
        _iconY = p.y;
      }
    } catch (_) {}
    _mode = 'panel';
    final h = (_screenH * 0.52).clamp(280.0, 480.0);
    try {
      // 左右各留 8dp、底部留 8dp，做成浮起来的卡片，不被导航条压住
      await FlutterOverlayWindow.updateOverlay(
        x: 8,
        y: 8,
        width: (_screenW - 16).round(),
        height: h.round(),
        enableDrag: false,
      );
    } catch (_) {}
    await _push(immediate: true);
  }

  /// 半屏列表 → 图标
  static Future<void> _collapse() async {
    if (!_active) return;
    _mode = 'icon';
    await _applyIcon();
    await _push(immediate: true);
  }

  /// 长按悬浮球 / 面板「回到应用」：结束抓包 → 回到前台 → 关悬浮窗 → 打开抓包列表
  ///
  /// 真正的动作交给原生 `exitOverlay` 执行（先拉起 Activity、再收悬浮窗，
  /// 顺序反了会被 MIUI 以「后台启动 Activity」静默拦下）。
  static Future<void> _exitToApp() async {
    await _capture?.stopCapture();
    var ok = false;
    try {
      ok = await _native.invokeMethod<bool>('exitOverlay') ?? false;
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    // 原生通道不可用时退回 Dart 侧（旧版本/插件缺失）
    final brought = await AppListService.bringToFront();
    if (!brought) {
      await hide();
      return;
    }
    _active = false;
    await _settings?.setWindowMode(false);
    await Future.delayed(const Duration(milliseconds: 300));
    try {
      appNavigatorKey.currentState?.pushNamed(Routes.capture);
    } catch (_) {}
  }

  /// 原生收掉悬浮窗后的复位：设置里的「窗口化」不能一直显示已开启
  static void onNativeExit() {
    _active = false;
    _mode = 'icon';
    _appLabel = '';
    _throttle?.cancel();
    _settings?.setWindowMode(false);
  }

  // ---- 数据下发 ----

  static Future<void> _push({bool immediate = false}) async {
    if (!_active) return;
    _throttle?.cancel();
    if (!immediate) {
      _throttle = Timer(const Duration(milliseconds: 220), () => _sendState());
      return;
    }
    await _sendState();
  }

  static Future<void> _sendState() async {
    final c = _capture;
    if (c == null || !_active) return;
    try {
      await FlutterOverlayWindow.shareData({
        'type': 'state',
        'mode': _mode,
        'capturing': c.capturing,
        'count': c.requestCount,
        'upload': c.uploadBytes,
        'download': c.downloadBytes,
        'app': _appLabel,
        'records': _recentRecords(c),
        if (_pendingDebug != null) 'debugAction': _pendingDebug,
      });
    } catch (_) {
      // 窗口被系统回收时会抛，忽略即可
    }
  }

  /// 只推最近的 40 条，控制消息体大小（悬浮窗半屏列表够用）
  static List<Map<String, Object>> _recentRecords(CaptureService c) {
    final out = <Map<String, Object>>[];
    for (final RequestRecord r in c.currentRecords.take(40)) {
      out.add({
        'm': r.method,
        'h': r.host,
        'p': r.isTunnel && r.path.startsWith(':')
            ? '端口 ${r.path.substring(1)}'
            : r.displayPath,
        's': r.statusCode,
        't': r.requestTime.millisecondsSinceEpoch,
      });
    }
    return out;
  }

  static Future<void> _onOverlayMessage(dynamic msg) async {
    if (msg is! Map) return;
    switch (msg['action']) {
      case 'expand':
        await _expand();
      case 'collapse':
        await _collapse();
      case 'exit':
        await _exitToApp();
      case 'sync':
        await _push(immediate: true);
    }
  }

  /// 没权限时给出说明再跳系统授权页；ROM 侧「后台弹出界面」也一并提示
  static Future<bool> _requestPermission(BuildContext context) async {
    if (!context.mounted) return false;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要悬浮窗权限'),
        content: const Text(
          '窗口化会用一个悬浮图标显示抓包状态、点开还能半屏看请求列表，'
          '需要在「其他应用上层显示」，请先授予悬浮窗权限。\n\n'
          '部分手机（如小米）授权后还要在权限页允许「后台弹出界面」，'
          '否则悬浮窗不显示、长按也回不到本应用。',
          style: TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去授权')),
        ],
      ),
    );
    if (go != true) return false;
    try {
      await FlutterOverlayWindow.requestPermission();
    } catch (_) {
      return false;
    }
    return isPermissionGranted();
  }
}
