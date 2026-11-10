import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:packet_sniffing/widgets/common.dart';

class Base64Tool extends StatefulWidget {
  const Base64Tool({super.key});

  @override
  State<Base64Tool> createState() => _Base64ToolState();
}

class _Base64ToolState extends State<Base64Tool> {
  final _input = TextEditingController();
  final _output = TextEditingController();
  bool _encrypt = true;

  void _run() {
    final t = _input.text;
    if (t.isEmpty) return;
    try {
      _output.text = _encrypt
          ? base64Encode(utf8.encode(t))
          : utf8.decode(base64Decode(t.trim()));
    } catch (e) {
      _output.text = '错误：$e';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, 'Base64 加解密',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('加密')),
              ButtonSegment(value: false, label: Text('解密')),
            ],
            selected: {_encrypt},
            onSelectionChanged: (s) => setState(() => _encrypt = s.first),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            maxLines: 4,
            decoration: InputDecoration(
                labelText: _encrypt ? '明文' : 'Base64 密文'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('执行'),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _output,
            maxLines: 4,
            readOnly: true,
            decoration: const InputDecoration(labelText: '结果'),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _output.text));
                showToast(context, '已复制结果');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制结果'),
            ),
          ),
        ],
      ),
    );
  }
}
