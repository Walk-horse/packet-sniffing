import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/widgets/kit.dart';

class CaptureModeScreen extends StatefulWidget {
  const CaptureModeScreen({super.key});

  @override
  State<CaptureModeScreen> createState() => _CaptureModeScreenState();
}

class _CaptureModeScreenState extends State<CaptureModeScreen> {
  late CaptureFilter _filter;

  @override
  void initState() {
    _load();
    super.initState();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString('captureFilter');
    _filter = raw != null
        ? CaptureFilter.fromJson(jsonDecode(raw))
        : CaptureFilter();
    setState(() {});
    _push();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('captureFilter', jsonEncode(_filter.toJson()));
    _push();
  }

  void _push() {
    context.read<CaptureService>().setFilter(_filter);
  }

  void _editList(bool black) async {
    final list = List<String>.from(black ? _filter.blacklist : _filter.whitelist);
    final ctrl = TextEditingController();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(black ? '黑名单设置' : '白名单设置'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(hintText: '输入域名，如 api.example.com'),
                ),
                const SizedBox(height: 10),
                ...list.map((d) => ListTile(
                      title: Text(d),
                      trailing: IconButton(
                          icon: const Icon(Icons.close, color: AppColors.danger),
                          onPressed: () => setSt(() => list.remove(d))),
                    )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, list),
                child: const Text('完成')),
            TextButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) {
                    list.add(ctrl.text.trim());
                    setSt(() {});
                    ctrl.clear();
                  }
                },
                child: const Text('添加')),
          ],
        ),
      ),
    );
    if (result != null) {
      if (black) {
        _filter.blacklist = result;
      } else {
        _filter.whitelist = result;
      }
      _save();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '设置抓包模式',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ModeCard(
            title: '黑名单模式',
            desc:
                '默认只抓取除黑名单以外域名的请求，适用于全局抓包及处理 SSL Pinning 场景。',
            enabled: _filter.blacklistEnabled,
            onChanged: (v) {
              _filter.blacklistEnabled = v;
              _save();
              setState(() {});
            },
            onEdit: () => _editList(true),
            count: _filter.blacklist.length,
            editLabel: '黑名单设置',
          ),
          _ModeCard(
            title: '白名单模式',
            desc:
                '默认只抓取白名单内域名的请求，适用于只调试固定几个域名的场景。（白名单优先于黑名单）',
            enabled: _filter.whitelistEnabled,
            onChanged: (v) {
              _filter.whitelistEnabled = v;
              _save();
              setState(() {});
            },
            onEdit: () => _editList(false),
            count: _filter.whitelist.length,
            editLabel: '白名单设置',
          ),
          _ModeCard(
            title: 'HTTP/3（QUIC）回退',
            desc:
                '启用后拦截 UDP 443 流量，迫使使用 HTTP/3 的 App 回退到 HTTPS（HTTP/2），从而可被解密记录。',
            note: '注意：少数仅支持 HTTP/3 的服务可能因此无法连接，遇到时请关闭此项。',
            enabled: _filter.quicFallback,
            onChanged: (v) {
              _filter.quicFallback = v;
              _save();
              setState(() {});
            },
          ),
          sectionTitle('同步数据到电脑（已关闭）'),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
              border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
            ),
            child: const ListTile(
              title: Text('同步数据到电脑',
                  style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.subtext)),
              subtitle: Text('开启后手机提供 HTTP 同步服务（本版本未启用）',
                  style: TextStyle(fontSize: 12, color: AppColors.subtext)),
              trailing: Icon(Icons.block_rounded, color: AppColors.subtext),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('本版本专注于手机端抓包，不提供电脑端同步。',
                style: TextStyle(color: AppColors.subtext, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title, desc;
  final String? note;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onEdit;
  final int? count;
  final String? editLabel;
  const _ModeCard({
    required this.title,
    required this.desc,
    this.note,
    required this.enabled,
    required this.onChanged,
    this.onEdit,
    this.count,
    this.editLabel,
  });

  @override
  Widget build(BuildContext context) => card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500))),
                CompactSwitch(value: enabled, onChanged: onChanged),
              ],
            ),
            const SizedBox(height: 6),
            Text(desc, style: const TextStyle(fontSize: 13, color: AppColors.subtext, height: 1.5)),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(note!,
                    style: const TextStyle(fontSize: 12, color: AppColors.danger, height: 1.5)),
              ),
            if (onEdit != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onEdit,
                  child: Text('$editLabel${count != null ? "（$count）" : ""}'),
                ),
              ),
          ],
        ),
      );
}
