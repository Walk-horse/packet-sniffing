import 'package:flutter/material.dart';
import 'package:packet_sniffing/services/app_list_service.dart';
import 'package:packet_sniffing/services/capture_apps_store.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';

/// 抓包应用：勾选要抓包的应用，未勾选时抓取全部应用。
class CaptureAppsScreen extends StatefulWidget {
  const CaptureAppsScreen({super.key});

  @override
  State<CaptureAppsScreen> createState() => _CaptureAppsScreenState();
}

class _CaptureAppsScreenState extends State<CaptureAppsScreen> {
  final TextEditingController _search = TextEditingController();

  /// 与窗口化页一致：不用 PageStorage 记忆滚动位置
  final ScrollController _scroll = ScrollController(keepScrollOffset: false);

  List<AppInfo> _apps = const [];
  Set<String> _selected = {};
  bool _loading = true;
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

  Future<void> _load() async {
    final apps = await AppListService.load();
    final selected = await CaptureAppsStore.load();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _selected = selected.toSet();
      _loading = false;
    });
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

  Future<void> _toggle(String package, bool checked) async {
    setState(() {
      if (checked) {
        _selected.add(package);
      } else {
        _selected.remove(package);
      }
    });
    await CaptureAppsStore.toggle(package, checked);
  }

  Future<void> _clearAll() async {
    setState(() => _selected = {});
    await CaptureAppsStore.clear();
    if (mounted) showToast(context, '已清空，将抓取全部应用');
  }

  Future<void> _selectVisible() async {
    final next = _selected.toSet()
      ..addAll(_filtered.map((a) => a.package));
    setState(() => _selected = next);
    await CaptureAppsStore.save(next);
    if (mounted) showToast(context, '已勾选当前列表 ${_filtered.length} 个应用');
  }

  @override
  Widget build(BuildContext context) {
    final apps = _filtered;

    return Scaffold(
      appBar: gradientAppBar(
        context,
        '抓包应用',
        actions: [
          TextButton(
            onPressed: _loading
                ? null
                : (_selected.isEmpty ? _selectVisible : _clearAll),
            child: Text(
              _selected.isEmpty ? '全选' : '清空',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _searchBar(),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                    itemCount: apps.length + (_query.isEmpty ? 3 : 2),
                    itemBuilder: (c, i) {
                      if (_query.isEmpty) {
                        if (i == 0) return _allAppsRow();
                        if (i == 1) return _summaryTitle(apps.length);
                        if (i == apps.length + 2) return _footnote();
                        return _appRow(apps[i - 2]);
                      }
                      if (i == 0) return _summaryTitle(apps.length);
                      if (i == apps.length + 1) return _footnote();
                      return _appRow(apps[i - 1]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryTitle(int visible) {
    final n = _selected.length;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 14, bottom: 6),
      child: Text(
        n == 0 ? '已安装应用 ($visible) · 当前抓取全部' : '已勾选 $n 个 · 列表 $visible 个',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.subtext,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _footnote() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        '勾选的应用会被纳入 VPN 抓包；不勾选任何应用时抓取全部应用'
        '（排除本应用自身流量）。',
        style:
            TextStyle(color: AppColors.subtext, fontSize: 12, height: 1.5),
      ),
    );
  }

  Widget _allAppsRow() {
    final on = _selected.isEmpty;
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: on ? null : _clearAll,
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
                    Text('不筛选，记录全部连接',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.subtext)),
                  ],
                ),
              ),
              _check(on, (v) {
                if (!v) _clearAll();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appRow(AppInfo app) {
    final on = _selected.contains(app.package);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _toggle(app.package, !on),
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
                  margin: const EdgeInsets.only(right: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.chipTrack,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text('系统',
                      style:
                          TextStyle(fontSize: 10, color: AppColors.subtext)),
                ),
              _check(on, (v) => _toggle(app.package, v)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _check(bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Checkbox(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        activeColor: AppColors.brand,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
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
            prefixIcon: const Icon(Icons.search_rounded,
                size: 18, color: AppColors.subtext),
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
