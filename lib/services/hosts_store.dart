import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条本地 hosts 映射：命中 [domain] 的连接改指向 [target]。
class HostMapping {
  final String domain;
  final String target;
  const HostMapping({required this.domain, required this.target});

  Map<String, dynamic> toJson() => {'domain': domain, 'target': target};

  factory HostMapping.fromJson(Map<String, dynamic> j) =>
      HostMapping(domain: j['domain'] ?? '', target: j['target'] ?? '');
}

/// 本地 HOSTS 映射存储（SharedPreferences）。
///
/// 抓包开启时由代理层将命中域名的连接改指向映射目标。
class HostsStore {
  static const _key = 'hosts_mappings';

  static Future<List<HostMapping>> list() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => HostMapping.fromJson(e as Map<String, dynamic>))
          .where((m) => m.domain.isNotEmpty && m.target.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> add(String domain, String target) async {
    final items = await list();
    items.removeWhere((m) => m.domain == domain);
    items.add(HostMapping(domain: domain, target: target));
    await _save(items);
  }

  static Future<void> remove(String domain) async {
    final items = await list();
    items.removeWhere((m) => m.domain == domain);
    await _save(items);
  }

  static Future<String> exportText() async {
    final items = await list();
    if (items.isEmpty) return '';
    final buf = StringBuffer('# 抓包精灵 Hosts\n');
    for (final m in items) {
      buf.writeln('${m.target} ${m.domain}');
    }
    return buf.toString();
  }

  static Future<void> _save(List<HostMapping> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(items.map((m) => m.toJson()).toList()));
  }
}
