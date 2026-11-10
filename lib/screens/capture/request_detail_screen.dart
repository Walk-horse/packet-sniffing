import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/kit.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/utils/export_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RequestDetailScreen extends StatefulWidget {
  final RequestRecord record;
  const RequestDetailScreen({super.key, required this.record});

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    _tab = TabController(length: 4, vsync: this);
    super.initState();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final capture = context.watch<CaptureService>();
    return Scaffold(
      appBar: gradientAppBar(
        context,
        '抓包详情',
        leadingWidth: 92,
        leading: const BackLeading('返回'),
        actions: [
          IconButton(
            icon: Icon(
                r.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: r.isFavorite ? AppColors.action : Colors.white),
            onPressed: () {
              capture.toggleFavorite(r.id);
              setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: r.url));
              showToast(context, '已复制请求链接');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          SegTabBar(
            controller: _tab,
            labels: const ['总览', '请求', '响应', '时间'],
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _Overview(r),
                _MessageTab(
                  key: const PageStorageKey('req'),
                  record: r,
                  isRequest: true,
                ),
                _MessageTab(
                  key: const PageStorageKey('res'),
                  record: r,
                  isRequest: false,
                ),
                _Timeline(r),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- 总览

class _Overview extends StatelessWidget {
  final RequestRecord r;
  const _Overview(this.r);

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SectionBar('基本信息'),
        KvRow(label: '方法', value: r.method),
        KvRow(label: '链接', value: r.url),
        KvRow(label: '域名', value: r.host),
        KvRow(
            label: '流量',
            value:
                '↑ ${formatBytes(r.requestSize)}  ↓ ${formatBytes(r.responseSize)}'),
        KvRow(label: '地址', value: '${r.localAddress} → ${r.remoteAddress}'),
        KvRow(
            label: '状态',
            value: r.isError
                ? '失败：${r.errorReason ?? ''}'
                : '已完成 (${r.statusCode})'),
        KvRow(label: '请求时间', value: formatTime(r.requestTime)),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
          child: Row(
            children: [
              TextAction('复制 cURL', () {
                Clipboard.setData(ClipboardData(text: buildCurl(r)));
                showToast(context, '已复制 cURL');
              }),
              const SizedBox(width: 12),
              TextAction('导出 HAR', () {
                Clipboard.setData(ClipboardData(text: buildHar([r])));
                showToast(context, '已复制 HAR');
              }),
              const SizedBox(width: 12),
              TextAction('重新请求', () {
                Navigator.of(context).pushNamed(Routes.buildRequest, arguments: {
                  'method': r.method,
                  'url': r.url,
                  'headers': r.requestHeaders,
                  'body': r.requestBody ?? '',
                });
              }),
            ],
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------- 请求 / 响应

enum _BodyMode { text, json, utf16, hex }

class _MessageTab extends StatefulWidget {
  final RequestRecord record;
  final bool isRequest;
  const _MessageTab({
    super.key,
    required this.record,
    required this.isRequest,
  });

  @override
  State<_MessageTab> createState() => _MessageTabState();
}

class _MessageTabState extends State<_MessageTab> {
  bool _headersExpanded = true;
  _BodyMode _mode = _BodyMode.json;
  final bool _searching = false;
  String _query = '';
  final _searchCtl = TextEditingController();
  final Set<String> _collapsed = {};

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  String get _body {
    final b = widget.isRequest
        ? widget.record.requestBody
        : widget.record.responseBody;
    return b ?? '';
  }

  Map<String, String> get _headers => widget.isRequest
      ? widget.record.requestHeaders
      : widget.record.responseHeaders;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final line = widget.isRequest
        ? '${r.method} ${r.displayPath} HTTP/1.1'
        : 'HTTP/1.1 ${r.statusCode} ${_reason(r.statusCode)}';
    final hasBody = _body.isNotEmpty;

    return ListView(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(
              AppMetric.pagePadding, 12, AppMetric.pagePadding, 12),
          child: Text(line,
              style: const TextStyle(
                  fontSize: AppFont.sub,
                  fontWeight: FontWeight.w500,
                  height: 1.5)),
        ),
        const Divider(height: 1, color: AppColors.border),

        // 头部
        Container(
          color: Colors.white,
          child: Column(
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _headersExpanded = !_headersExpanded),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppMetric.pagePadding),
                    child: Row(
                      children: [
                        Text(widget.isRequest ? '请求头' : '响应头',
                            style: const TextStyle(
                                fontSize: AppFont.sub,
                                color: AppColors.subtext)),
                        const Spacer(),
                        Text('${_headers.length}',
                            style: const TextStyle(
                                fontSize: AppFont.sub,
                                color: AppColors.subtext)),
                        const SizedBox(width: 4),
                        Icon(
                            _headersExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 18,
                            color: AppColors.subtext),
                      ],
                    ),
                  ),
                ),
              ),
              if (_headersExpanded)
                ..._headers.entries.map((e) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppMetric.pagePadding, vertical: 6),
                      decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.border))),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 120,
                            child: Text(e.key,
                                style: const TextStyle(
                                    fontSize: AppFont.small,
                                    color: AppColors.subtext)),
                          ),
                          Expanded(
                            child: SelectableText(e.value,
                                style: const TextStyle(
                                    fontSize: AppFont.small,
                                    color: AppColors.text)),
                          ),
                        ],
                      ),
                    )),
            ],
          ),
        ),

        // Body 标题行 + 动作
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(
              AppMetric.pagePadding, 12, AppMetric.pagePadding, 6),
          child: Row(
            children: [
              const Text('Body',
                  style: TextStyle(fontSize: AppFont.sub, color: AppColors.text)),
              const Spacer(),
              if (widget.isRequest && hasBody) ...[
                TextAction('cURL', () {
                  Clipboard.setData(ClipboardData(text: buildCurl(r)));
                  showToast(context, '已复制 cURL');
                }),
                const SizedBox(width: 10),
                TextAction('设为模拟', () async {
                  final sp = await SharedPreferences.getInstance();
                  final raw = sp.getString('apiMocks');
                  final list = raw != null
                      ? (jsonDecode(raw) as List).toList()
                      : <dynamic>[];
                  list.add({
                    'id': 'm_${DateTime.now().millisecondsSinceEpoch}',
                    'enabled': true,
                    'name': r.host,
                    'method': r.method,
                    'host': r.host,
                    'path': r.path,
                    'statusCode': r.statusCode,
                    'contentType':
                        r.contentType.isEmpty ? 'application/json' : r.contentType,
                    'body': r.responseBody ?? '',
                    'delayMs': 0,
                  });
                  await sp.setString('apiMocks', jsonEncode(list));
                  try {
                    await const MethodChannel('packetsniffing/capture')
                        .invokeMethod('setMocks', list);
                  } catch (_) {}
                  showToast(context, '已保存为接口模拟规则');
                }),
                const SizedBox(width: 10),
              ],
              if (hasBody)
                TextAction('复制', () {
                  Clipboard.setData(ClipboardData(text: _body));
                  showToast(context, '已复制 Body');
                }),
            ],
          ),
        ),

        // 格式 chips
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(
              AppMetric.pagePadding, 0, AppMetric.pagePadding, 8),
          child: Row(
            children: [
              _chip('文本', _BodyMode.text),
              const SizedBox(width: 8),
              _chip('JSON', _BodyMode.json),
              const SizedBox(width: 8),
              _chip('UTF-16', _BodyMode.utf16),
              const SizedBox(width: 8),
              _chip('HEX', _BodyMode.hex),
            ],
          ),
        ),

        // 搜索 + 展开/折叠
        if (hasBody && _mode == _BodyMode.json)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
                AppMetric.pagePadding, 0, AppMetric.pagePadding, 8),
            child: Column(
              children: [
                if (_searching)
                  SizedBox(
                    height: 34,
                    child: TextField(
                      controller: _searchCtl,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      style: const TextStyle(fontSize: AppFont.sub),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '搜索 Body 内容',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppMetric.smallRadius),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  )
                else
                  Row(
                    children: [
                      const Spacer(),
                      TextAction('展开全部',
                          () => setState(() => _collapsed.clear())),
                      const SizedBox(width: 14),
                      TextAction('折叠全部', () {
                        final data = _tryJson(_body);
                        if (data == null) return;
                        setState(() {
                          _collapsed
                            ..clear()
                            ..addAll(_allPaths(data));
                        });
                      }),
                    ],
                  ),
              ],
            ),
          ),

        if (!hasBody)
          const Padding(
            padding: EdgeInsets.all(AppMetric.pagePadding),
            child: Text('(无 Body)',
                style: TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
          )
        else
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(
                AppMetric.pagePadding, 0, AppMetric.pagePadding, 16),
            child: _buildBody(),
          ),
      ],
    );
  }

  Widget _chip(String label, _BodyMode mode) {
    final active = _mode == mode;
    return InkWell(
      onTap: () => setState(() => _mode = mode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.brandLight : AppColors.bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: AppFont.small,
                color: active ? AppColors.brand : AppColors.subtext,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400)),
      ),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _BodyMode.text:
        return SelectableText(_body,
            style: const TextStyle(
                fontSize: AppFont.small,
                fontFamily: 'monospace',
                height: 1.5));
      case _BodyMode.hex:
        return SelectableText(_hexDump(_body),
            style: const TextStyle(
                fontSize: AppFont.small,
                fontFamily: 'monospace',
                height: 1.5));
      case _BodyMode.utf16:
        return SelectableText(_utf16View(_body),
            style: const TextStyle(
                fontSize: AppFont.small,
                fontFamily: 'monospace',
                height: 1.5));
      case _BodyMode.json:
        final data = _tryJson(_body);
        if (data == null) {
          return SelectableText(_body,
              style: const TextStyle(
                  fontSize: AppFont.small,
                  fontFamily: 'monospace',
                  height: 1.5));
        }
        return JsonTree(
          data: data,
          collapsed: _collapsed,
          query: _query,
          onToggle: (path) => setState(() {
            if (!_collapsed.remove(path)) _collapsed.add(path);
          }),
        );
    }
  }

  String _reason(int code) {
    switch (code) {
      case 200:
        return 'OK';
      case 201:
        return 'Created';
      case 204:
        return 'No Content';
      case 301:
        return 'Moved Permanently';
      case 304:
        return 'Not Modified';
      case 400:
        return 'Bad Request';
      case 401:
        return 'Unauthorized';
      case 403:
        return 'Forbidden';
      case 404:
        return 'Not Found';
      case 500:
        return 'Internal Server Error';
      case 502:
        return 'Bad Gateway';
      case 503:
        return 'Service Unavailable';
      default:
        return '';
    }
  }
}

dynamic _tryJson(String s) {
  final t = s.trim();
  if (!(t.startsWith('{') || t.startsWith('['))) return null;
  try {
    return jsonDecode(t);
  } catch (_) {
    return null;
  }
}

Set<String> _allPaths(dynamic data) {
  final out = <String>{};
  void walk(dynamic v, String path) {
    if (v is Map) {
      if (v.isNotEmpty) out.add(path);
      v.forEach((k, val) => walk(val, '$path/$k'));
    } else if (v is List) {
      if (v.isNotEmpty) out.add(path);
      for (var i = 0; i < v.length; i++) {
        walk(v[i], '$path/$i');
      }
    }
  }

  walk(data, 'root');
  return out;
}

String _hexDump(String s) {
  final bytes = utf8.encode(s);
  final buf = StringBuffer();
  for (var i = 0; i < bytes.length; i += 16) {
    final chunk = bytes.sublist(
        i, i + 16 > bytes.length ? bytes.length : i + 16);
    final hex =
        chunk.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    buf.writeln(hex);
  }
  return buf.toString();
}

String _utf16View(String s) {
  final units = s.codeUnits;
  final buf = StringBuffer();
  for (final u in units) {
    buf.write(u.toRadixString(16).padLeft(4, '0'));
    buf.write(' ');
  }
  return buf.toString();
}

// ------------------------------------------------------------ JSON 树

/// 可折叠 JSON 视图，对应视频里 Body 的「展开全部 / 折叠全部」交互。
class JsonTree extends StatelessWidget {
  final dynamic data;
  final Set<String> collapsed;
  final String query;
  final ValueChanged<String> onToggle;

  const JsonTree({
    super.key,
    required this.data,
    required this.collapsed,
    required this.onToggle,
    this.query = '',
  });

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    _walk(data, 'root', 0, rows, null);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  void _walk(dynamic v, String path, int depth, List<Widget> out,
      String? keyLabel) {
    final indent = 14.0 + depth * 14.0;
    final isMap = v is Map;
    final isList = v is List;
    final children = isMap ? v.keys.length : (isList ? v.length : 0);

    if ((isMap || isList) && children > 0) {
      final open = isMap ? '{' : '[';
      final close = isMap ? '}' : ']';
      final isCollapsed = collapsed.contains(path);
      out.add(_line(
        indent: indent,
        onTap: () => onToggle(path),
        children: [
          if (keyLabel != null) _key(keyLabel),
          TextSpan(
              text: isCollapsed ? '$open … $close  ($children)' : open,
              style: const TextStyle(color: AppColors.subtext)),
        ],
      ));
      if (!isCollapsed) {
        if (isMap) {
          v.forEach((k, val) {
            _walk(val, '$path/$k', depth + 1, out, k.toString());
          });
        } else {
          for (var i = 0; i < v.length; i++) {
            _walk(v[i], '$path/$i', depth + 1, out, null);
          }
        }
        out.add(_line(
          indent: indent,
          children: [
            TextSpan(
                text: close, style: const TextStyle(color: AppColors.subtext)),
          ],
        ));
      }
      return;
    }

    // 叶子
    out.add(_line(
      indent: indent,
      children: [
        if (keyLabel != null) _key(keyLabel),
        _valueSpan(v),
      ],
    ));
  }

  TextSpan _key(String k) => TextSpan(
        text: '"$k"',
        style: const TextStyle(color: AppColors.brand, fontSize: AppFont.small),
      );

  TextSpan _valueSpan(dynamic v) {
    if (v is String) {
      return TextSpan(
          text: '"$v"',
          style: const TextStyle(color: AppColors.success, fontSize: AppFont.small));
    }
    if (v is num) {
      return TextSpan(
          text: '$v',
          style: const TextStyle(color: AppColors.action, fontSize: AppFont.small));
    }
    if (v is bool) {
      return TextSpan(
          text: '$v',
          style: const TextStyle(color: AppColors.methodHead, fontSize: AppFont.small));
    }
    return const TextSpan(
        text: 'null',
        style: TextStyle(color: AppColors.subtext, fontSize: AppFont.small));
  }

  Widget _line({
    required double indent,
    required List<TextSpan> children,
    VoidCallback? onTap,
  }) {
    final line = Padding(
      padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
      child: Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                const TextSpan(
                    text: ': ',
                    style: TextStyle(
                        color: AppColors.subtext, fontSize: AppFont.small)),
            ],
          ],
        ),
        style: const TextStyle(
            fontFamily: 'monospace', fontSize: AppFont.small, height: 1.45),
      ),
    );
    if (onTap == null) return line;
    return InkWell(onTap: onTap, child: line);
  }
}

// ---------------------------------------------------------------- 时间

class _Timeline extends StatelessWidget {
  final RequestRecord r;
  const _Timeline(this.r);

  @override
  Widget build(BuildContext context) {
    final start = r.requestTime;
    final end = start.add(Duration(milliseconds: r.durationMs));
    return ListView(
      children: [
        const SectionBar('时间线'),
        _TimeRow('请求发送', formatTime(start)),
        _TimeRow('响应接收', formatTime(end)),
        _TimeRow('总耗时', formatDuration(r.durationMs)),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  final String label, value;
  const _TimeRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
        height: AppMetric.rowHeight,
        padding:
            const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border))),
        child: Row(
          children: [
            Text(label,
                style:
                    const TextStyle(fontSize: AppFont.body, color: AppColors.text)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: AppFont.sub, color: AppColors.subtext)),
          ],
        ),
      );
}
