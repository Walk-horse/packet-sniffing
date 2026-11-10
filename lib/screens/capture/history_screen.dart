import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/request_item.dart';
import 'package:packet_sniffing/widgets/marquee_text.dart';
import 'package:packet_sniffing/services/capture_service.dart';

/// 抓包历史：iOS 分组列表样式（分组头/脚注 + 白色通栏行）。
/// 颜色全部取自当前主题，页面背景沿用主题 scaffoldBackgroundColor，不单独覆盖。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    final sessions = capture.sessions;
    return Scaffold(
      appBar: gradientAppBar(
        context,
        '抓包历史',
        leadingWidth: 84,
        leading: _OverviewBack(onTap: () => Navigator.maybePop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('抓包 SESSION 历史记录'),
          _Group(
            children: sessions.isEmpty
                ? const [_HistoryRow(title: '暂无抓包记录', muted: true)]
                : [
                    for (final s in sessions)
                      _HistoryRow(
                        title: _fmt(s.startTime),
                        subtitle: s.endTime == null
                            ? '进行中'
                            : '${s.durationSec} 秒',
                        onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => _SessionRequests(
                                      sessionId: s.id)),
                            ),
                      ),
                  ],
          ),
          const _SectionFooter('清空全部记录，无法撤销'),
          _Group(
            children: [
              _HistoryRow(
                title: '清空抓包历史',
                danger: true,
                onTap: () => _confirmClear(context, capture),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, CaptureService capture) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空抓包历史'),
        content: const Text('清空全部记录，无法撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () {
                capture.clearHistory();
                Navigator.pop(ctx);
              },
              child: const Text('清空',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
  }

  String _fmt(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
}

/// 顶栏左侧「‹ 总览」，与参考图一致；背景仍是主题渐变。
class _OverviewBack extends StatelessWidget {
  final VoidCallback onTap;
  const _OverviewBack({required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.only(left: 8, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, size: 24, color: Colors.white),
              SizedBox(width: 2),
              Text('总览',
                  style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 10),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
      );
}

class _SectionFooter extends StatelessWidget {
  final String text;
  const _SectionFooter(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 9),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.subtext)),
      );
}

/// 白色通栏分组：上下各一条细线，多行时行间加左缩进分隔线。
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
            bottom: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Padding(
                  padding: EdgeInsets.only(left: 20),
                  child: SizedBox(
                      height: 1, width: double.infinity, child: ColoredBox(color: AppColors.border)),
                ),
              children[i],
            ],
          ],
        ),
      );
}

/// 分组内的一行：主标题 + 可选副标题 + 右侧 chevron。
class _HistoryRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool danger;
  final bool muted;
  final VoidCallback? onTap;
  const _HistoryRow({
    required this.title,
    this.subtitle,
    this.danger = false,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? AppColors.danger
        : (muted ? AppColors.subtext : AppColors.text);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: subtitle == null ? 46 : 58),
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          color: color)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.subtext)),
                    ),
                ],
              ),
            ),
            if (onTap != null && !danger && !muted)
              Icon(Icons.chevron_right,
                  size: 20,
                  color: AppColors.subtext.withValues(alpha: 0.7)),
          ],
        ),
      ),
    );
  }
}

class _SessionRequests extends StatelessWidget {
  final String sessionId;
  const _SessionRequests({required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    final records = capture.recordsOfSession(sessionId);
    return Scaffold(
      appBar: gradientAppBar(context, 'SESSION 请求'),
      body: MarqueeListScope(child: records.isEmpty
          ? emptyState('该批次无请求')
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: records.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.border),
              itemBuilder: (c, i) => RequestListItem(records[i], onTap: () {
                Navigator.of(context)
                    .pushNamed(Routes.requestDetail, arguments: records[i]);
              }),
            )),
    );
  }
}
