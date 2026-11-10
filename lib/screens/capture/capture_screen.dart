import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/kit.dart';
import 'package:packet_sniffing/widgets/request_item.dart';
import 'package:packet_sniffing/widgets/marquee_text.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/models/capture_models.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _query = '';
  bool _searching = false;
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    _tab = TabController(length: 4, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    // 只看本次 SESSION：旧批次记录保留在「抓包历史」里，不混进当前列表
    final records = capture.currentRecords.where((r) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return r.host.toLowerCase().contains(q) ||
          r.path.toLowerCase().contains(q) ||
          r.method.toLowerCase().contains(q);
    }).toList();
    final ptRecords = capture.currentPassthroughs.where((p) {
      if (_query.isEmpty) return true;
      return p.host.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: gradientAppBar(
        context,
        capture.capturing ? '正在抓包' : '抓包',
        leadingWidth: 96,
        leading: const BackLeading('总览'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: '清空本次记录',
            onPressed: () => _confirmClear(context, capture),
          ),
        ],
      ),
      body: MarqueeListScope(child: Column(
        children: [
          _ControlBar(capture: capture),
          SegTabBar(
            controller: _tab,
            labels: const ['全部请求', '按域名', '按应用', '透传'],
          ),
          _CounterRow(
            count: records.length,
            searching: _searching,
            controller: _searchCtl,
            onToggleSearch: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _searchCtl.clear();
                _query = '';
              }
            }),
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _RequestList(
                  records: records,
                  hasHistory: capture.sessions.isNotEmpty,
                ),
                _AppGroupList(records: records, passthroughs: ptRecords),
                _PassthroughList(records: ptRecords),
              ],
            ),
          ),
        ],
      )),
    );
  }

  void _confirmClear(BuildContext context, CaptureService capture) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空本次记录'),
        content: const Text('仅清空本次抓包列表，抓包历史会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () {
                capture.clearCurrentRecords();
                Navigator.pop(context);
              },
              child: const Text('清空')),
        ],
      ),
    );
  }
}

/// 顶部控制条：开始/停止 + ↑↓ 流量 + 计时
class _ControlBar extends StatelessWidget {
  final CaptureService capture;
  const _ControlBar({required this.capture});

  @override
  Widget build(BuildContext context) {
    final running = capture.capturing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppMetric.pagePadding, 7, AppMetric.pagePadding, 0),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppMetric.radius),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            PillButton(
              label: running ? '停止' : '开始',
              color: running ? AppColors.success : AppColors.action,
              onTap: () async {
                if (running) {
                  capture.stopCapture();
                  return;
                }
                if (!await confirmRealCapture(context)) return;
                capture.startCapture();
              },
            ),
            const SizedBox(width: 14),
            Text('↑ ${formatBytes(capture.uploadBytes)}',
                style: const TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
            const SizedBox(width: 10),
            Text('↓ ${formatBytes(capture.downloadBytes)}',
                style: const TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
            const Spacer(),
            const Icon(Icons.schedule, size: 17, color: AppColors.subtext),
            const SizedBox(width: 4),
            Text(running ? _fmt(capture.elapsed) : '—',
                style: const TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// 计数行 + 搜索
class _CounterRow extends StatelessWidget {
  final int count;
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onChanged;
  const _CounterRow({
    required this.count,
    required this.searching,
    required this.controller,
    required this.onToggleSearch,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppMetric.pagePadding, 0, AppMetric.pagePadding, 0),
      child: Column(
        children: [
          SizedBox(
            height: 34,
            child: Row(
              children: [
                Text('共 $count 个请求',
                    style: const TextStyle(
                        fontSize: AppFont.sub, color: AppColors.subtext)),
                const Spacer(),
                if (searching)
                  SizedBox(
                    width: 160,
                    height: 30,
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: onChanged,
                      style: const TextStyle(fontSize: AppFont.sub),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索域名 / 路径',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.search,
                        size: 20, color: AppColors.subtext),
                    onPressed: onToggleSearch,
                  ),
                if (searching)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close,
                        size: 18, color: AppColors.subtext),
                    onPressed: onToggleSearch,
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
        ],
      ),
    );
  }
}

class _RequestList extends StatelessWidget {
  final List records;
  final bool hasHistory;
  const _RequestList({required this.records, required this.hasHistory});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('暂无请求',
                style: TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
            if (hasHistory) ...[
              const SizedBox(height: 8),
              const Text('抓包历史已保留，本次新记录将显示在此',
                  style:
                      TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
            ],
          ],
        ),
      );
    }
    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (c, i) => RequestListItem(records[i], onTap: () {
        Navigator.of(context)
            .pushNamed(Routes.requestDetail, arguments: records[i]);
      }),
    );
  }
}

class _DomainGroup extends StatelessWidget {
  final List records;
  const _DomainGroup({required this.records});
  @override
  Widget build(BuildContext context) {
    final map = <String, List>{};
    for (final r in records) {
      map.putIfAbsent(r.host, () => []).add(r);
    }
    if (map.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Text('暂无请求',
            style: TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
      );
    }
    return ListView(
      children: map.entries.map((e) {
        return ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
          leading: const Icon(Icons.dns_rounded, color: AppColors.brand, size: 20),
          title: Text(e.key,
              style: const TextStyle(
                  fontSize: AppFont.title, fontWeight: FontWeight.w500)),
          subtitle: Text('${e.value.length} 个请求',
              style: const TextStyle(
                  fontSize: AppFont.small, color: AppColors.subtext)),
          children: e.value
              .map((r) => RequestListItem(r, onTap: () {
                    Navigator.of(context)
                        .pushNamed(Routes.requestDetail, arguments: r);
                  }))
              .toList(),
        );
      }).toList(),
    );
  }
}

/// 按应用（uid）分组：展开后显示该应用产生的请求记录。
class _AppGroupList extends StatelessWidget {
  final List<RequestRecord> records;
  final List<PassthroughRecord> passthroughs;
  const _AppGroupList({required this.records, required this.passthroughs});

  @override
  Widget build(BuildContext context) {
    final byUid = <int, AppGroup>{};
    for (final r in records) {
      final g = byUid.putIfAbsent(
          r.uid, () => AppGroup(uid: r.uid, package: r.appPackage, label: r.appLabel));
      g.requests.add(r);
    }
    for (final p in passthroughs) {
      final g = byUid.putIfAbsent(
          p.uid, () => AppGroup(uid: p.uid, package: p.appPackage, label: p.appLabel));
      g.passthroughs.add(p);
    }
    final groups = byUid.values.toList()
      ..sort((a, b) => b.totalCount.compareTo(a.totalCount));
    if (groups.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Text('暂无请求',
            style: TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
      );
    }
    return ListView(
      children: groups.map((g) {
        final parts = <String>[];
        if (g.requests.isNotEmpty) parts.add('${g.requests.length} 请求');
        if (g.passthroughs.isNotEmpty) parts.add('${g.passthroughs.length} 透传');
        final sub = parts.join(' · ');
        final detail = g.package.isNotEmpty ? '$sub\n$g.package' : sub;
        return ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
          leading: const Icon(Icons.android_rounded,
              color: AppColors.brand, size: 20),
          title: Text(g.displayName,
              style: const TextStyle(
                  fontSize: AppFont.title, fontWeight: FontWeight.w500)),
          subtitle: Text(detail,
              style: const TextStyle(
                  fontSize: AppFont.small, color: AppColors.subtext)),
          children: g.requests
              .map((r) => RequestListItem(r, onTap: () {
                    Navigator.of(context)
                        .pushNamed(Routes.requestDetail, arguments: r);
                  }))
              .toList(),
        );
      }).toList(),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final String msg;
  const _Placeholder(this.msg);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Text(msg,
            style: const TextStyle(
                fontSize: AppFont.sub, color: AppColors.subtext)),
      );
}

/// 透传记录列表：未解密的连接（黑/白名单排除、非 HTTP 流量等）
class _PassthroughList extends StatelessWidget {
  final List<PassthroughRecord> records;
  const _PassthroughList({required this.records});

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Text('暂无透传记录',
            style: TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
      );
    }
    return ListView.separated(
      itemCount: records.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.border),
      itemBuilder: (c, i) {
        final p = records[i];
        final scheme = p.tls ? 'HTTPS' : 'TCP';
        final mColor = p.tls ? AppColors.brand : AppColors.subtext;
        return Material(
          color: Colors.white,
          child: InkWell(
            // 透传行主行是目标域名，长按同样复制到剪贴板
            onLongPress: () =>
                copyEndpointName(context, p.host, toast: '已复制域名'),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(p.host),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('协议：$scheme'),
                    Text('端口：${p.port}'),
                    Text('耗时：${formatDuration(p.durationMs)}'),
                    Text('上行：${formatBytes(p.upBytes)}'),
                    Text('下行：${formatBytes(p.downBytes)}'),
                    const SizedBox(height: 8),
                    Text('原因：${p.reason}',
                        style: const TextStyle(color: AppColors.subtext)),
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭')),
                ],
              ),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 60),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppMetric.pagePadding, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 25,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: mColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(scheme,
                        maxLines: 1,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        MarqueeText(p.host,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                                height: 1.3)),
                        const SizedBox(height: 3),
                        Text(
                            '${p.reason} · ${formatBytes(p.upBytes)}↑ ${formatBytes(p.downBytes)}↓',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: AppFont.small,
                                color: AppColors.subtext)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
