import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/kit.dart';
import 'package:packet_sniffing/services/app_list_service.dart';

/// 一条接口模拟规则：匹配 method / host / path，命中后返回模拟响应（不转发真实服务器）。
class ApiMock {
  String id;
  String name;
  bool enabled;
  String method;
  String host;
  String path;
  int statusCode;
  String contentType;
  String body;
  int delayMs;
  List<List<String>> headers;

  ApiMock({
    required this.id,
    this.name = '',
    this.enabled = true,
    this.method = 'GET',
    this.host = '',
    this.path = '/',
    this.statusCode = 200,
    this.contentType = 'application/json',
    this.body = '{}',
    this.delayMs = 0,
    this.headers = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'method': method,
        'host': host,
        'path': path,
        'statusCode': statusCode,
        'contentType': contentType,
        'body': body,
        'delayMs': delayMs,
        'headers': headers,
      };

  factory ApiMock.fromJson(Map<String, dynamic> j) => ApiMock(
        id: j['id'],
        name: j['name'] ?? '',
        enabled: j['enabled'] ?? true,
        method: j['method'] ?? 'GET',
        host: j['host'] ?? '',
        path: j['path'] ?? '/',
        statusCode: j['statusCode'] ?? 200,
        contentType: j['contentType'] ?? 'application/json',
        body: j['body'] ?? '{}',
        delayMs: j['delayMs'] ?? 0,
        headers: (j['headers'] as List?)
                ?.map((e) => (e as List).map((v) => v.toString()).toList())
                .toList() ??
            const [],
      );
}

class ApiMockScreen extends StatefulWidget {
  const ApiMockScreen({super.key});

  @override
  State<ApiMockScreen> createState() => _ApiMockScreenState();
}

class _ApiMockScreenState extends State<ApiMockScreen> {
  List<ApiMock> _mocks = [];
  bool _enabled = false;
  List<String> _apps = [];
  static const _channel = MethodChannel('packetsniffing/capture');

  @override
  void initState() {
    _load();
    super.initState();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    _enabled = sp.getBool('mockEnabled') ?? false;
    _apps = sp.getStringList('mockApps') ?? [];
    final raw = sp.getString('apiMocks');
    if (raw != null) {
      _mocks = (jsonDecode(raw) as List).map((e) => ApiMock.fromJson(e)).toList();
    }
    if (mounted) setState(() {});
    _pushAll();
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('mockEnabled', _enabled);
    await sp.setStringList('mockApps', _apps);
    await sp.setString('apiMocks', jsonEncode(_mocks.map((m) => m.toJson()).toList()));
    _pushAll();
  }

  Future<void> _pushAll() async {
    try {
      await _channel.invokeMethod('setMockEnabled', _enabled);
      await _channel.invokeMethod('setMockApps', _apps);
      await _channel.invokeMethod(
          'setMocks', _mocks.map((m) => m.toJson()).toList());
    } catch (_) {}
  }

  void _edit(ApiMock? mock) async {
    final result = await showModalBottomSheet<ApiMock>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MockEditor(mock: mock),
    );
    if (result != null) {
      if (mock == null) {
        _mocks.add(result);
      } else {
        final i = _mocks.indexWhere((m) => m.id == result.id);
        if (i >= 0) _mocks[i] = result;
      }
      _save();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '接口模拟',
          leading: const BackLeading('返回'),
          actions: [
            IconButton(
                icon: const Icon(Icons.add_rounded),
                onPressed: () => _edit(null)),
          ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Expanded(
                    child: Text('接口模拟总开关',
                        style: TextStyle(fontWeight: FontWeight.w500))),
                CompactSwitch(
                  value: _enabled,
                  onChanged: (v) {
                    _enabled = v;
                    _save();
                    if (mounted) setState(() {});
                  },
                ),
              ]),
              const SizedBox(height: 6),
              const Text('开启后，命中规则的请求会返回模拟响应而不走真实服务器；并会强制解密被抓包模式排除的 host。',
                  style: TextStyle(fontSize: 13, color: AppColors.subtext, height: 1.5)),
            ],
          )),
          const SizedBox(height: 12),
          card(InkWell(
            onTap: () async {
              final picked = await Navigator.push<List<String>>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MockAppsScreen(selected: _apps)));
              if (picked != null) {
                _apps = picked;
                _save();
                if (mounted) setState(() {});
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              child: Row(children: [
                const Icon(Icons.apps_rounded, color: AppColors.brand),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        _apps.isEmpty ? '适用应用：未选择（不会生效）' : '适用应用：${_apps.length} 个',
                        style: const TextStyle(fontWeight: FontWeight.w500))),
                const Icon(Icons.chevron_right, color: AppColors.subtext),
              ]),
            ),
          )),
          const SizedBox(height: 16),
          Text('模拟规则',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          _mocks.isEmpty
              ? emptyState('暂无规则，点右上角添加', icon: Icons.science_rounded)
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _mocks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (c, i) {
                    final m = _mocks[i];
                    return card(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.methodColor(m.method)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(m.method,
                                style: TextStyle(
                                    color: AppColors.methodColor(m.method),
                                    fontWeight: FontWeight.w500, fontSize: 11)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(m.name.isEmpty ? m.host : m.name,
                                  style: const TextStyle(fontWeight: FontWeight.w500))),
                          CompactSwitch(
                            value: m.enabled,
                            onChanged: (v) {
                              m.enabled = v;
                              _save();
                              if (mounted) setState(() {});
                            },
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Text('${m.host}${m.path}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.subtext)),
                        const SizedBox(height: 6),
                        Row(children: [
                          IconButton(
                              icon: const Icon(Icons.edit_rounded,
                                  color: AppColors.subtext),
                              onPressed: () => _edit(m)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.danger),
                              onPressed: () {
                                _mocks.removeAt(i);
                                _save();
                                if (mounted) setState(() {});
                              }),
                          const Spacer(),
                          Text('${m.statusCode} · ${m.contentType}',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.subtext)),
                        ]),
                      ],
                    ));
                  },
                ),
        ],
      ),
    );
  }
}

/// 选择「适用应用」：只有被勾选的应用发起的请求才会被模拟。
class MockAppsScreen extends StatefulWidget {
  final List<String> selected;
  const MockAppsScreen({super.key, required this.selected});

  @override
  State<MockAppsScreen> createState() => _MockAppsScreenState();
}

class _MockAppsScreenState extends State<MockAppsScreen> {
  List<AppInfo> _apps = [];
  final Set<String> _picked = {};
  final _q = TextEditingController();

  @override
  void initState() {
    _picked.addAll(widget.selected);
    _load();
    super.initState();
  }

  Future<void> _load() async {
    _apps = await AppListService.load();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.toLowerCase();
    final list = _apps
        .where((a) =>
            q.isEmpty ||
            a.label.toLowerCase().contains(q) ||
            a.package.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      appBar: gradientAppBar(context, '选择适用应用',
          leading: const BackLeading('返回'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, _picked.toList()),
                child: const Text('完成', style: TextStyle(color: Colors.white)))
          ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _q,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '搜索应用',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? emptyState('无已安装应用', icon: Icons.apps_rounded)
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (c, i) {
                    final a = list[i];
                    final on = _picked.contains(a.package);
                    return ListTile(
                      leading: a.icon != null
                          ? Image.memory(a.icon!, width: 36, height: 36)
                          : const Icon(Icons.android_rounded),
                      title: Text(a.label),
                      subtitle: Text(a.package,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.subtext)),
                      trailing: Checkbox(
                        value: on,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _picked.add(a.package);
                          } else {
                            _picked.remove(a.package);
                          }
                        }),
                      ),
                      onTap: () => setState(() {
                        if (on) {
                          _picked.remove(a.package);
                        } else {
                          _picked.add(a.package);
                        }
                      }),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _MockEditor extends StatefulWidget {
  final ApiMock? mock;
  const _MockEditor({super.key, this.mock});

  @override
  State<_MockEditor> createState() => _MockEditorState();
}

class _MockEditorState extends State<_MockEditor> {
  late TextEditingController _name, _host, _path, _status, _body, _delay;
  String _method = 'GET';
  String _contentType = 'application/json';
  final _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];
  final _cts = [
    'application/json',
    'application/xml',
    'text/html',
    'text/plain',
    'text/xml'
  ];

  @override
  void initState() {
    final m = widget.mock;
    _name = TextEditingController(text: m?.name ?? '');
    _host = TextEditingController(text: m?.host ?? '');
    _path = TextEditingController(text: m?.path ?? '/');
    _status = TextEditingController(text: '${m?.statusCode ?? 200}');
    _body = TextEditingController(text: m?.body ?? '{}');
    _delay = TextEditingController(text: '${m?.delayMs ?? 0}');
    _method = m?.method ?? 'GET';
    _contentType = m?.contentType ?? 'application/json';
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('编辑接口模拟',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: '名称(可选)')),
            Row(children: [
              Expanded(
                  child: DropdownButton<String>(
                value: _method,
                isExpanded: true,
                items: _methods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v!),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: _status,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '状态码'))),
            ]),
            TextField(
                controller: _host,
                decoration: const InputDecoration(
                    labelText: 'Host(如 api.example.com，留空不限)')),
            TextField(
                controller: _path,
                decoration: const InputDecoration(
                    labelText: 'Path(支持 * 通配，留空不限)')),
            Row(children: [
              Expanded(
                  child: DropdownButton<String>(
                value: _contentType,
                isExpanded: true,
                items: _cts
                    .map((m) => DropdownMenuItem(
                        value: m, child: Text(m, style: const TextStyle(fontSize: 12))))
                    .toList(),
                onChanged: (v) => setState(() => _contentType = v!),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: TextField(
                      controller: _delay,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '延迟(ms)'))),
            ]),
            TextField(
                controller: _body,
                maxLines: 5,
                decoration: const InputDecoration(
                    labelText: '响应体(留空按类型自动生成示例)')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final m = widget.mock ??
                      ApiMock(id: 'm_${DateTime.now().millisecondsSinceEpoch}');
                  m.name = _name.text;
                  m.host = _host.text.trim();
                  m.path = _path.text.trim();
                  m.method = _method;
                  m.statusCode = int.tryParse(_status.text) ?? 200;
                  m.contentType = _contentType;
                  m.body = _body.text;
                  m.delayMs = int.tryParse(_delay.text) ?? 0;
                  Navigator.pop(context, m);
                },
                child: const Text('保存'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
