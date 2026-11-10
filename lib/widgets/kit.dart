import 'package:flutter/material.dart';
import 'package:packet_sniffing/theme.dart';

/// 尺寸/字号令牌：按参考视频（540×1200 录屏）反推的 dp 值，全应用统一。
class AppMetric {
  static const double pagePadding = 12;
  static const double rowHeight = 56;
  static const double sectionBarHeight = 36;
  static const double buttonHeight = 38;
  static const double smallButtonHeight = 30;
  static const double segTabHeight = 30;
  static const double radius = 8;
  static const double smallRadius = 6;
}

class AppFont {
  static const double appBarTitle = 17;
  static const double title = 15;
  static const double body = 15;
  static const double sub = 14;
  static const double small = 13;
  static const double tiny = 12;
}

/// 灰色分段控件（灰槽 + 白色选中药丸），对应视频里「全部请求/按域名/按应用/透传」。
class SegTabBar extends StatelessWidget {
  final TabController controller;
  final List<String> labels;
  const SegTabBar({super.key, required this.controller, required this.labels});

  @override
  Widget build(BuildContext context) {
    // 参考视频：灰底胶囊直接贴在页面底色上，高 30，无白色外框
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppMetric.pagePadding, 12, AppMetric.pagePadding, 0),
      child: Container(
        height: AppMetric.segTabHeight,
        decoration: BoxDecoration(
          color: AppColors.chipTrack,
          borderRadius: BorderRadius.circular(AppMetric.smallRadius),
        ),
        child: TabBar(
          controller: controller,
          indicator: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppMetric.smallRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelColor: AppColors.text,
          unselectedLabelColor: AppColors.subtext,
          labelStyle: const TextStyle(
              fontSize: AppFont.small, fontWeight: FontWeight.w500),
          unselectedLabelStyle: const TextStyle(fontSize: AppFont.small),
          labelPadding: EdgeInsets.zero,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          tabs: labels
              .map((t) => Tab(height: AppMetric.segTabHeight, text: t))
              .toList(),
        ),
      ),
    );
  }
}

/// 灰色分区标题条，对应视频里的「请求行 / 请求头部 / 状态 / 维护」。
class SectionBar extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionBar(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppMetric.sectionBarHeight,
      color: const Color(0xFFF7F7FA),
      padding: const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 「标签 —— 值」一行，行高 52，底部细分割线。
class KvRow extends StatelessWidget {
  final String label;
  final String? value;
  final String? hint;
  final Widget? trailing;
  final VoidCallback? onTap;
  const KvRow({
    super.key,
    required this.label,
    this.value,
    this.hint,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      constraints: const BoxConstraints(minHeight: AppMetric.rowHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(fontSize: AppFont.body, color: AppColors.text)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value ?? hint ?? '',
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppFont.body,
                color: value == null ? AppColors.subtext : AppColors.text,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// 小型实心按钮（开始 / 停止），32 高、6 圆角。
class PillButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double width;
  const PillButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.width = 58,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppMetric.smallRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetric.smallRadius),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: AppMetric.smallButtonHeight,
          child: Center(
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppFont.small,
                    fontWeight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

/// 带文字返回按钮的 AppBar leading，对应视频里的「← 总览 / ← 日志」。
class BackLeading extends StatelessWidget {
  final String label;
  const BackLeading(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.maybePop(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.arrow_back, size: 20, color: Colors.white),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: AppFont.sub)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 文内小号文字动作（cURL / 设为模拟 / 复制 / 展开全部）
class TextAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const TextAction(this.label, this.onTap,
      {super.key, this.color = AppColors.brand});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(label,
            style: TextStyle(fontSize: AppFont.small, color: color)),
      ),
    );
  }
}

/// 紧凑开关：Material 3 的 Switch 固定 52×32，FittedBox 等比压到 42×26，
/// 与其配套的行高一起让「设置类」页面更紧凑。
class CompactSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  const CompactSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 26,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
