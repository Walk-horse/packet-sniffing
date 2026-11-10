import 'dart:async';

import 'package:flutter/material.dart';

/// 列表的竖向滚动状态。由 [MarqueeListScope] 下发，所有行共用同一个实例。
/// 只在「开始 / 结束」两个时刻通知，滚动过程中不逐帧通知，避免每帧遍历列表行。
class MarqueeScrollSignal extends ChangeNotifier {
  bool _scrolling = false;
  bool get scrolling => _scrolling;

  void start() {
    if (_scrolling) return;
    _scrolling = true;
    notifyListeners();
  }

  void end() {
    if (!_scrolling) return;
    _scrolling = false;
    notifyListeners();
  }
}

/// 放在列表外层：捕获所有子列表的滚动通知，并把状态通过 [MarqueeScrollScope] 下发。
/// 一个页面只需一个实例（TabBarView 下多个 tab 共用）。
class MarqueeListScope extends StatefulWidget {
  final Widget child;
  const MarqueeListScope({super.key, required this.child});

  @override
  State<MarqueeListScope> createState() => _MarqueeListScopeState();
}

class _MarqueeListScopeState extends State<MarqueeListScope> {
  final _signal = MarqueeScrollSignal();
  Timer? _watchdog;
  DateTime? _lastArm;

  @override
  void dispose() {
    _watchdog?.cancel();
    _signal.dispose();
    super.dispose();
  }

  /// 兜底：某些情况下 ScrollEndNotification 不会到达（手势被中断、页面被回收等），
  /// 否则所有行会永久停在「竖向滚动中」状态、再也不恢复横向动画。
  /// 500ms 内没有任何滚动更新就认为滚动已结束。
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(milliseconds: 500), _signal.end);
  }

  bool _onNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _signal.start();
      _lastArm = DateTime.now();
      _armWatchdog();
    } else if (n is ScrollUpdateNotification) {
      if (_signal.scrolling) {
        final now = DateTime.now();
        // 惯性滚动每帧都有 update，最多每 200ms 重置一次计时器，避免每帧建 Timer
        if (_lastArm == null ||
            now.difference(_lastArm!) > const Duration(milliseconds: 200)) {
          _lastArm = now;
          _armWatchdog();
        }
      }
    } else if (n is ScrollEndNotification) {
      _watchdog?.cancel();
      _signal.end();
    }
    return false; // 不拦截，继续冒泡
  }

  @override
  Widget build(BuildContext context) => MarqueeScrollScope(
        signal: _signal,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onNotification,
          child: widget.child,
        ),
      );
}

/// 信号是命令式下发的（行用 addListener 直接启停动画），不建立 Inherited 依赖，
/// 所以滚动状态变化不会 rebuild 任何列表行。
class MarqueeScrollScope extends InheritedWidget {
  final MarqueeScrollSignal signal;
  // ignore: use_super_parameters
  const MarqueeScrollScope(
      {super.key, required this.signal, required Widget child})
      : super(child: child);

  static MarqueeScrollSignal? maybeOf(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<MarqueeScrollScope>()
              ?.widget as MarqueeScrollScope?)
          ?.signal;

  @override
  bool updateShouldNotify(covariant MarqueeScrollScope oldWidget) => false;
}

const double _overflowSlack = 6; // 溢出判定安全余量，抵消行宽浮动与字形墨迹溢出

/// 单行**单向匀速循环**跑马灯：文本超宽时以恒定速度一直向左滚，滚完一整圈
/// 由第二份文本无缝接回开头；短文本静态显示。
///
/// 全程匀速：位移 `dx = -step * controller.value`，控制器默认线性推进，
/// 没有任何加减速曲线、分段变速或开头/尾部停留。周期时长由
/// `step / speed` 决定，所以所有文本的单位时间位移都相同。
///
/// 文字用 [TextPainter] 在 paint 阶段绘制两份完整文本（不受父级宽度约束），
/// canvas 裁出可见区。位移始终递减（0 → -[step]），-step 与 0 画面等价，
/// 因此是无缝循环而非来回滚动。
///
/// 性能约束：
/// - 只有几何上处在屏幕内的行才会启动 ticker，屏幕外（含 ListView 缓存区）行 stop；
/// - 外部竖向滚动期间全部暂停，滚动结束后再按可见性恢复；
/// - 每帧只画两个 paragraph，不构建 widget、不触发 layout；
/// - 用 RepaintBoundary 把重绘限制在文本区域。
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final double speed; // 全程恒定速度，单位 px / 秒（逻辑像素）
  final double gap; // 两份文本之间的间隔
  const MarqueeText(
    this.text, {
    super.key,
    required this.style,
    this.speed = 60,
    this.gap = 16,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  TextPainter? _tp;
  MarqueeScrollSignal? _signal;
  Size? _screen;
  TextScaler? _scaler;
  double _textWidth = 0;
  double _boxWidth = -1;
  String? _measuredText;
  TextStyle? _measuredStyle;
  bool _overflow = false;
  bool _visible = true;
  bool _syncScheduled = false;
  double _step = 0; // 一个完整循环的位移 = 文本宽度 + gap
  int _totalMs = 4000;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mq = MediaQuery.maybeOf(context);
    _screen = mq?.size;
    final scaler = mq?.textScaler;
    if (scaler != _scaler) {
      _scaler = scaler;
      _measuredText = null; // 系统字体缩放变化需要重新测量
    }
    final s = MarqueeScrollScope.maybeOf(context);
    if (!identical(s, _signal)) {
      _signal?.removeListener(_onSignal);
      _signal = s;
      _signal?.addListener(_onSignal);
    }
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 列表行被复用时文本会变，重新测量并在帧末同步可见性/动画
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.speed != widget.speed ||
        oldWidget.gap != widget.gap) {
      _measuredText = null;
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    _signal?.removeListener(_onSignal);
    _tp?.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _onSignal() {
    if (!mounted) return;
    if (_signal?.scrolling == true) {
      // 竖向滚动中：立刻停掉，且不做逐帧可见性计算
      if (_ctrl.isAnimating) _ctrl.stop();
      return;
    }
    _refreshVisibility();
    _sync();
  }

  bool _computeVisible() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || _screen == null) return true;
    final p = box.localToGlobal(Offset.zero);
    // 同时判断水平方向：TabBarView 里被翻到屏幕外的页面不应滚动
    return p.dy < _screen!.height &&
        p.dy + box.size.height > 0 &&
        p.dx < _screen!.width &&
        p.dx + box.size.width > 0;
  }

  void _refreshVisibility() => _visible = _computeVisible();

  /// build 阶段不能启停 AnimationController（会触发子级 setState during build），
  /// 统一推到帧末执行。
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!mounted) return;
      _refreshVisibility();
      _sync();
    });
  }

  void _sync() {
    final shouldRun = _overflow &&
        _visible &&
        (_signal?.scrolling != true) &&
        widget.text.isNotEmpty;
    if (!shouldRun) {
      if (_ctrl.isAnimating) _ctrl.stop();
      return;
    }
    if (_ctrl.duration?.inMilliseconds != _totalMs) {
      final wasAnimating = _ctrl.isAnimating;
      _ctrl.duration = Duration(milliseconds: _totalMs);
      if (wasAnimating) _ctrl.repeat();
    }
    if (!_ctrl.isAnimating) _ctrl.repeat();
  }

  void _measure(double maxWidth) {
    if (!maxWidth.isFinite) return;
    if (identical(_measuredText, widget.text) &&
        _measuredStyle == widget.style &&
        _boxWidth == maxWidth) {
      return;
    }
    final tp = _tp ??= TextPainter(maxLines: 1);
    // 与 Text widget 使用同一个 textScaler，否则系统字体缩放下测量会偏小，
    // 文字实际渲染超宽却被判成「不溢出」，最终被硬切且不滚动。
    tp.textScaler = MediaQuery.textScalerOf(context);
    tp.textDirection = Directionality.of(context);
    tp.text = TextSpan(text: widget.text, style: widget.style);
    // 不传 maxWidth：按文本固有宽度排版，保证尾部字符也被绘制出来
    tp.layout();
    _textWidth = tp.width;
    _measuredText = widget.text;
    _measuredStyle = widget.style;
    _boxWidth = maxWidth;
    // 留 6px 余量：右侧状态列宽度会随内容浮动，且字形墨迹可能略超 advance width
    _overflow = _textWidth > maxWidth - _overflowSlack;
    _step = _textWidth + widget.gap;
    // 匀速的唯一来源：整圈距离 / 恒定速度。不做分段、不做 clamp 提速，
    // 控制器线性推进，所以每毫秒的位移都一致。
    _totalMs = (_step / widget.speed * 1000).round().clamp(200, 120000);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _measure(constraints.maxWidth);
      final lineHeight =
          (widget.style.fontSize ?? 15) * (widget.style.height ?? 1.3);
      if (!_overflow || _tp == null) {
        _scheduleSync();
        return Text(widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: widget.style);
      }
      _scheduleSync();
      final h = _tp!.height > lineHeight ? _tp!.height : lineHeight;
      return RepaintBoundary(
        child: SizedBox(
          width: constraints.maxWidth,
          height: h,
          child: CustomPaint(
            painter: _MarqueePainter(
              label: _tp!,
              step: _step,
              ctrl: _ctrl,
            ),
          ),
        ),
      );
    });
  }
}

/// 每帧只画两次 paragraph；[CustomPainter.repaint] 直接挂在 controller 上，
/// tick 时仅触发 paint，不经过 widget 树。
///
/// 位移 dx 从 0 线性递减到 -step，第二份文本位于 dx + step，
/// 所以 dx = -step 与 dx = 0 画面完全等价 —— 单向、匀速、无缝、循环。
class _MarqueePainter extends CustomPainter {
  final TextPainter label;
  final double step;
  final AnimationController ctrl;
  _MarqueePainter({
    required this.label,
    required this.step,
    required this.ctrl,
  }) : super(repaint: ctrl);

  @override
  void paint(Canvas canvas, Size size) {
    final dx = -step * ctrl.value;
    final dy = (size.height - label.height) / 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    label.paint(canvas, Offset(dx, dy));
    label.paint(canvas, Offset(dx + step, dy));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter old) =>
      old.step != step || !identical(old.label, label);
}
