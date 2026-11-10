import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/services/capture_service.dart';

/// 抓包日志：原生每轮抓包落一个文件（capture-yyyyMMdd-HHmmss.log），
/// 这里列出文件、点开看内容，抓包中每 2 秒刷新大小。
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  Timer? _poll;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final capture = context.read<CaptureService>();
    capture.refreshLogs().then((_) {
      if (mounted) setState(() => _loading = false);
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      // 抓包中日志还在增长，定时把文件大小刷出来
      if (context.read<CaptureService>().capturing) {
        context.read<CaptureService>().refreshLogs();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    final logs = capture.logFiles;
    return Scaffold(
      appBar: gradientAppBar(context, '抓包日志',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context)),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => capture.refreshLogs()),
          ]),
      body: _buildBody(context, capture, logs),
    );
  }

  Widget _buildBody(
      BuildContext context, CaptureService capture, List<LogFile> logs) {
    if (_loading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (logs.isEmpty) {
      return Column(
        children: [
          _hint(),
          Expanded(
              child: emptyState('暂无日志，开始抓包后自动生成',
                  icon: Icons.article_outlined)),
        ],
      );
    }
    return RefreshIndicator(
      onRefresh: capture.refreshLogs,
      child: ListView(
        children: [
          _hint(),
          ...logs.map((l) => ListTile(
                leading: const Icon(Icons.description_rounded,
                    color: AppColors.brand),
                title: Text(l.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(
                    '${_fmt(l.createdAt)} · ${formatBytes(l.size)}'),
                trailing: const Icon(Icons.chevron_right,
                    color: AppColors.subtext),
                onTap: () => _openLog(capture, l.name),
              )),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () => _confirmClear(context, capture),
              icon: const Icon(Icons.cleaning_services_rounded,
                  color: AppColors.danger),
              label: const Text('清空日志',
                  style: TextStyle(color: AppColors.danger)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _hint() => Container(
        color: Colors.white,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: const Text('每次抓包生成一个日志文件，包含启动参数、每个请求的结果与异常',
            style: TextStyle(color: AppColors.subtext)),
      );

  Future<void> _openLog(CaptureService capture, String name) async {
    // 先弹一个加载态，避免大文件读取时点击没反应
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final content = await capture.readLog(name);
    if (!mounted) return;
    Navigator.pop(context); // 关掉加载圈
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(name, style: const TextStyle(fontSize: 14)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              content.isEmpty ? '（空文件）' : content,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, CaptureService capture) {
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('清空日志'),
              content: const Text('清空全部日志文件，无法撤销。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () {
                      capture.clearLogs();
                      Navigator.pop(context);
                    },
                    child: const Text('清空',
                        style: TextStyle(color: AppColors.danger))),
              ],
            ));
  }

  String _fmt(DateTime t) =>
      '${t.month}-${t.day} ${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
}
