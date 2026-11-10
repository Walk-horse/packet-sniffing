import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/kit.dart';
import 'package:packet_sniffing/utils/curl_parser.dart';
import 'package:packet_sniffing/utils/export_utils.dart';

class BuildRequestScreen extends StatefulWidget {
  final Map<String, dynamic>? args;
  const BuildRequestScreen({super.key, this.args});

  @override
  State<BuildRequestScreen> createState() => _BuildRequestScreenState();
}

class _BuildRequestScreenState extends State<BuildRequestScreen>
    with SingleTickerProviderStateMixin {
  final _urlCtl = TextEditingController();
  final _bodyCtl = TextEditingController();
  final _curlCtl = TextEditingController();
  final List<_HeaderRow> _headers = [];
  String _method = 'GET';
  late TabController _tab;
  bool _sending = false;
  String _respText = '';
  int _status = 0;
  final Map<String, String> _respHeaders = {};

  final _methods = ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'HEAD', 'OPTIONS'];

  @override
  void initState() {
    _tab = TabController(length: 2, vsync: this);
    if (widget.args != null) {
      _method = widget.args!['method'] ?? 'GET';
      _urlCtl.text = widget.args!['url'] ?? '';
      final h = widget.args!['headers'];
      if (h is Map) {
        h.forEach((k, v) =>
            _headers.add(_HeaderRow(k.toString(), v.toString())));
      }
      _bodyCtl.text = widget.args!['body'] ?? '';
    }
    super.initState();
  }

  @override
  void dispose() {
    _urlCtl.dispose();
    _bodyCtl.dispose();
    _curlCtl.dispose();
    _tab.dispose();
    super.dispose();
  }

  void _parseCurl() {
    final p = parseCurl(_curlCtl.text);
    setState(() {
      _method = p.method;
      _urlCtl.text = p.url;
      _bodyCtl.text = p.body ?? '';
      _headers.clear();
      p.headers.forEach((k, v) => _headers.add(_HeaderRow(k, v)));
    });
    showToast(context, '已解析 cURL');
  }

  Future<void> _send() async {
    final url = _urlCtl.text.trim();
    if (url.isEmpty) {
      showToast(context, '请输入链接');
      return;
    }
    setState(() {
      _sending = true;
      _respText = '';
      _respHeaders.clear();
      _status = 0;
      _tab.index = 1;
    });
    try {
      final req = http.Request(_method, Uri.parse(url));
      for (final h in _headers) {
        if (h.key.isNotEmpty) req.headers[h.key] = h.value;
      }
      if (_method != 'GET' && _method != 'HEAD' && _bodyCtl.text.isNotEmpty) {
        req.body = _bodyCtl.text;
      }
      final streamed = await req.send().timeout(const Duration(seconds: 15));
      final resp = await http.Response.fromStream(streamed);
      setState(() {
        _status = resp.statusCode;
        _respHeaders.addAll(resp.headers);
        _respText = prettyJson(resp.body);
      });
    } catch (e) {
      setState(() => _respText = '请求失败：$e');
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(
        context,
        '构建请求',
        leadingWidth: 88,
        leading: const BackLeading('总览'),
        actions: [
          TextButton(
            onPressed: _showCurlDialog,
            child: const Text('curl',
                style: TextStyle(color: Colors.white, fontSize: AppFont.sub)),
          ),
          IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 20),
              onPressed: _sending ? null : _send),
        ],
      ),
      body: Column(
        children: [
          SegTabBar(controller: _tab, labels: const ['请求', '响应']),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildRequestTab(),
                _buildResponseTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTab() {
    return ListView(
      children: [
        const SectionBar('请求行'),
        // 方法
        Container(
          height: AppMetric.rowHeight,
          padding:
              const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              const Text('方法',
                  style:
                      TextStyle(fontSize: AppFont.body, color: AppColors.text)),
              const Spacer(),
              DropdownButton<String>(
                value: _method,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down,
                    color: AppColors.subtext, size: 20),
                style: const TextStyle(
                    fontSize: AppFont.body, color: AppColors.text),
                items: _methods
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _method = v!),
              ),
            ],
          ),
        ),
        // 链接
        Container(
          constraints: const BoxConstraints(minHeight: AppMetric.rowHeight),
          padding:
              const EdgeInsets.symmetric(horizontal: AppMetric.pagePadding),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Row(
            children: [
              const Text('链接',
                  style:
                      TextStyle(fontSize: AppFont.body, color: AppColors.text)),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _urlCtl,
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.url,
                  style: const TextStyle(fontSize: AppFont.body),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '请输入链接',
                    hintStyle: TextStyle(
                        fontSize: AppFont.body, color: AppColors.subtext),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        SectionBar('请求头部',
            trailing: TextAction('+ 添加',
                () => setState(() => _headers.add(_HeaderRow('', ''))))),

        ..._headers.asMap().entries.map((e) {
          final row = e.value;
          return Container(
            height: AppMetric.rowHeight,
            padding:
                const EdgeInsets.only(left: AppMetric.pagePadding, right: 4),
            decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppColors.border))),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: row.keyCtl,
                    style: const TextStyle(fontSize: AppFont.sub),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Header',
                      hintStyle: TextStyle(
                          fontSize: AppFont.sub, color: AppColors.subtext),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: row.valCtl,
                    style: const TextStyle(fontSize: AppFont.sub),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Value',
                      hintStyle: TextStyle(
                          fontSize: AppFont.sub, color: AppColors.subtext),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: AppColors.danger, size: 20),
                    onPressed: () => setState(() => _headers.removeAt(e.key))),
              ],
            ),
          );
        }),

        const SectionBar('请求体'),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(
              AppMetric.pagePadding, 10, AppMetric.pagePadding, 10),
          child: TextField(
            controller: _bodyCtl,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(
                fontSize: AppFont.small, fontFamily: 'monospace', height: 1.5),
            decoration: const InputDecoration(
              hintText: '请求体（JSON / 表单等）',
              hintStyle: TextStyle(fontSize: AppFont.small),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildResponseTab() {
    if (_sending) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_respText.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(
            AppMetric.pagePadding, 16, AppMetric.pagePadding, 0),
        child: Text('发送请求后在此查看响应',
            style: TextStyle(fontSize: AppFont.sub, color: AppColors.subtext)),
      );
    }
    return ListView(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(
              AppMetric.pagePadding, 12, AppMetric.pagePadding, 12),
          child: Text('HTTP/1.1 $_status',
              style: const TextStyle(
                  fontSize: AppFont.sub,
                  fontWeight: FontWeight.w500,
                  height: 1.5)),
        ),
        const Divider(height: 1, color: AppColors.border),
        if (_respHeaders.isNotEmpty) ...[
          SectionBar('响应头', trailing: Text('${_respHeaders.length}')),
          ..._respHeaders.entries.map((e) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppMetric.pagePadding, vertical: 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppColors.border))),
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
                              fontSize: AppFont.small, color: AppColors.text)),
                    ),
                  ],
                ),
              )),
        ],
        const SectionBar('Body'),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(AppMetric.pagePadding),
          child: SelectableText(_respText,
              style: const TextStyle(
                  fontSize: AppFont.small,
                  fontFamily: 'monospace',
                  height: 1.5)),
        ),
      ],
    );
  }

  void _showCurlDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('粘贴 cURL 命令'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: _curlCtl,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'curl -X POST ...'),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          TextButton(
              onPressed: () {
                _parseCurl();
                Navigator.pop(context);
              },
              child: const Text('解析')),
        ],
      ),
    );
  }
}

class _HeaderRow {
  final keyCtl = TextEditingController();
  final valCtl = TextEditingController();
  _HeaderRow(String k, String v) {
    keyCtl.text = k;
    valCtl.text = v;
  }
  String get key => keyCtl.text;
  String get value => valCtl.text;
}
