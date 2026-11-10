import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/services/app_list_service.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/services/settings_service.dart';
import 'package:packet_sniffing/services/window_service.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';

/// 窗口化：选择要抓取的应用。
///
/// 选中后：开抓包（只把该应用纳入 VPN）→ 亮出悬浮图标 → 自己退到后台并打开
/// 选中的应用，用户就能一边用目标应用一边点悬浮图标看请求列表了。
class WindowScreen extends StatefulWidget {
  const WindowScreen({super.key});

  @override
  State<WindowScreen> createState() => _WindowScreenState();
}

class _WindowScreenState extends State<WindowScreen> {
  final TextEditingController _search = TextEditingController();

  /// 不用 PageStorage 记忆滚动位置：否则从别的页面回来会莫名停在半中间
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);
  List<AppInfo> _apps = const [];
  bool _loading = true;
  bool _busy = false;
  String _busyText = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    final apps = await AppListService.load(refresh: refresh);
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<AppInfo> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _apps;
    return _apps
        .where((a) =>
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
        .toList();
  }

  /// 开始前把「会发生什么」讲清楚：断网风险 + 悬浮图标的两种手势
  Future<bool> _confirm(AppInfo? app) async {
    final name = app?.label ?? '全部应用';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('窗口化抓取「$name」'),
        content: Text(
          '· 只把「$name」的流量纳入本机 VPN，其他应用不受影响\n'
          '· 本应用会退到后台，屏幕上出现悬浮图标\n'
          '· 单击图标：半屏查看抓包列表\n'
          '· 长按图标：结束抓包并回到本应用\n\n'
          '当前版本 VPN 只解析数据包、尚未实现转发，抓包期间该应用可能无法联网。',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('开始抓包')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// 整个窗口化启动链路收敛在 OverlayBridge.startForApp 里，这里只管 loading 与提示
  Future<void> _start(AppInfo? app) async {
    if (_busy) return;
    if (!await _confirm(app)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _busyText = app == null ? '正在启动抓包…' : '正在启动 ${app.label}…';
    });

    final err = await OverlayBridge.startForApp(
      context,
      package: app?.package,
      label: app?.label,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) showToast(context, err);
  }

  Future<void> _stopWindow() async {
    final capture = context.read<CaptureService>();
    await capture.stopCapture();
    await OverlayBridge.hide();
    if (!mounted) return;
    showToast(context, '已退出窗口化');
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final apps = _filtered;

    return Scaffold(
      appBar: gradientAppBar(context, '窗口化',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: Stack(
        children: [
          Column(
            children: [
              if (settings.windowMode) _activeBanner(),
              _searchBar(),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                        itemCount: apps.length + (_query.isEmpty ? 2 : 1),
                        itemBuilder: (c, i) {
                          if (_query.isEmpty) {
                            if (i == 0) return _allAppsRow();
                            if (i == 1) return sectionTitle('已安装应用 (${apps.length})');
                            return _appRow(apps[i - 2]);
                          }
                          if (i == 0) return sectionTitle('搜索结果 (${apps.length})');
                          return _appRow(apps[i - 1]);
                        },
                      ),
              ),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.28),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 12),
                        Text(_busyText,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _activeBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.picture_in_picture_alt_rounded,
              size: 18, color: AppColors.brand),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('窗口化已开启，悬浮图标在屏幕上',
                style: TextStyle(fontSize: 13, color: AppColors.brand)),
          ),
          TextButton(
            onPressed: _stopWindow,
            child: const Text('关闭', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: SizedBox(
        height: 38,
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: '搜索应用名或包名',
            hintStyle:
                const TextStyle(fontSize: 13, color: AppColors.subtext),
            prefixIcon:
                const Icon(Icons.search_rounded, size: 18, color: AppColors.subtext),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 9),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.brand),
            ),
          ),
        ),
      ),
    );
  }

  Widget _allAppsRow() {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _start(null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.actionSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.apps_rounded,
                    size: 20, color: AppColors.action),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('全部应用',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    Text('不限定应用，记录全部连接',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.subtext)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.subtext),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appRow(AppInfo app) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _start(app),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _AppIcon(app: app),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w500)),
                    Text(app.package,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.subtext)),
                  ],
                ),
              ),
              if (app.system)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.chipTrack,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('系统',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.subtext)),
                ),
              const Icon(Icons.chevron_right,
                  color: AppColors.subtext, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  final AppInfo app;
  const _AppIcon({required this.app});

  @override
  Widget build(BuildContext context) {
    final icon = app.icon;
    if (icon == null || icon.isEmpty) {
      return Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          app.label.isEmpty ? '?' : app.label.substring(0, 1),
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.brand),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(icon, width: 36, height: 36, gaplessPlayback: true),
    );
  }
}
