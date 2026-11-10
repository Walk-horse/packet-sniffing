import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/kit.dart';

class Md5Tool extends StatefulWidget {
  const Md5Tool({super.key});

  @override
  State<Md5Tool> createState() => _Md5ToolState();
}

class _Md5ToolState extends State<Md5Tool> {
  final _input = TextEditingController();
  String _md5 = '';
  bool _upper = false;

  void _run() {
    final bytes = utf8.encode(_input.text);
    var h = md5.convert(bytes).toString();
    if (_upper) h = h.toUpperCase();
    setState(() => _md5 = h);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, 'MD5',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _input,
            maxLines: 4,
            decoration: const InputDecoration(labelText: '待计算文本'),
            onChanged: (_) => _run(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('大写输出'),
              const SizedBox(width: 8),
              CompactSwitch(
                  value: _upper,
                  onChanged: (v) {
                    _upper = v;
                    _run();
                  }),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _md5));
                  showToast(context, '已复制 MD5');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_md5.isEmpty ? '—' : _md5,
                style: const TextStyle(
                    fontSize: 18,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: AppColors.brand)),
          ),
        ],
      ),
    );
  }
}
