import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/services/hosts_store.dart';

/// Hosts 设置：本地域名映射，抓包开启时生效。
class HostsScreen extends StatefulWidget {
  const HostsScreen({super.key});

  @override
  State<HostsScreen> createState() => _HostsScreenState();
}

class _HostsScreenState extends State<HostsScreen> {
  List<HostMapping> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await HostsStore.list();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _addDialog() async {
    final domainCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加 Hosts 映射'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: domainCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '被映射的域名',
                hintText: 'mock.example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: targetCtrl,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '映射到的 IP 或域名',
                hintText: '127.0.0.1',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final d = domainCtrl.text.trim();
      final t = targetCtrl.text.trim();
      if (d.isNotEmpty && t.isNotEmpty) {
        await HostsStore.add(d, t);
        await _reload();
      } else if (mounted) {
        showToast(context, '域名和目标不能为空');
      }
    }
    domainCtrl.dispose();
    targetCtrl.dispose();
  }

  Future<void> _remove(String domain) async {
    await HostsStore.remove(domain);
    await _reload();
    if (mounted) showToast(context, '已删除 $domain');
  }

  Future<void> _copyAll() async {
    final text = await HostsStore.exportText();
    if (text.isEmpty) {
      if (mounted) showToast(context, '暂无映射可导出');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) showToast(context, 'Hosts 已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(
        context,
        'Hosts 设置',
        actions: [
          TextButton(
            onPressed: _addDialog,
            child: const Text('添加', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                sectionTitle('本地映射'),
                Container(
                  color: Colors.white,
                  child: _items.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              '暂无映射，点右上角「添加」',
                              style: TextStyle(
                                  color: AppColors.subtext, fontSize: 13),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            for (final m in _items)
                              listRow(
                                icon: Icons.dns_rounded,
                                iconColor: AppColors.accent,
                                title: m.domain,
                                subtitle: '→ ${m.target}',
                                trailing: IconButton(
                                  icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: AppColors.danger),
                                  onPressed: () => _remove(m.domain),
                                ),
                              ),
                          ],
                        ),
                ),
                sectionTitle('导出'),
                Container(
                  color: Colors.white,
                  child: listRow(
                    icon: Icons.copy_rounded,
                    title: '复制 Hosts 文本',
                    subtitle: '导出全部映射，便于分享或备份',
                    onTap: _copyAll,
                  ),
                ),
                const SizedBox(height: 16),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '本地 HOSTS 映射在抓包开启时生效：代理层会把命中域名的连接改指向映射目标。',
                    style: TextStyle(
                        color: AppColors.subtext, fontSize: 12, height: 1.5),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
