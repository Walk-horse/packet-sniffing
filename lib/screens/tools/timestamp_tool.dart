import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';

class TimestampTool extends StatefulWidget {
  const TimestampTool({super.key});

  @override
  State<TimestampTool> createState() => _TimestampToolState();
}

class _TimestampToolState extends State<TimestampTool> {
  bool _toDate = true; // true: 时间戳->时间
  final _tsCtl = TextEditingController();
  bool _seconds = true;
  String _result = '';
  DateTime _picked = DateTime.now();

  void _convert() {
    if (_toDate) {
      final raw = int.tryParse(_tsCtl.text.trim());
      if (raw == null) {
        setState(() => _result = '请输入有效数字');
        return;
      }
      final ms = _seconds ? raw * 1000 : raw;
      final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: false);
      final utc = dt.toUtc();
      setState(() => _result =
          '本地：${DateFormat('yyyy-MM-dd HH:mm:ss').format(dt)}\nUTC ：${DateFormat('yyyy-MM-dd HH:mm:ss').format(utc)}');
    } else {
      final ms = _picked.millisecondsSinceEpoch;
      setState(() => _result =
          '秒：${(ms / 1000).toInt()}\n毫秒：$ms');
    }
  }

  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _picked,
        firstDate: DateTime(1970),
        lastDate: DateTime(2100));
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_picked));
    if (t == null || !mounted) return;
    setState(() => _picked = DateTime(d.year, d.month, d.day, t.hour, t.minute));
    _convert();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '时间戳转化',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('时间戳→时间')),
              ButtonSegment(value: false, label: Text('时间→时间戳')),
            ],
            selected: {_toDate},
            onSelectionChanged: (s) {
              setState(() => _toDate = s.first);
              _convert();
            },
          ),
          const SizedBox(height: 16),
          if (_toDate) ...[
            TextField(
              controller: _tsCtl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '时间戳'),
              onChanged: (_) => _convert(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('单位：'),
                const SizedBox(width: 8),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('秒'),
                  selected: _seconds,
                  onSelected: (_) {
                    _seconds = true;
                    _convert();
                    setState(() {});
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: const Text('毫秒'),
                  selected: !_seconds,
                  onSelected: (_) {
                    _seconds = false;
                    _convert();
                    setState(() {});
                  },
                ),
                const Spacer(),
                TextButton(
                    onPressed: () {
                      _tsCtl.text =
                          '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
                      _seconds = true;
                      _convert();
                      setState(() {});
                    },
                    child: const Text('当前时间')),
              ],
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('选择时间'),
              subtitle: Text(DateFormat('yyyy-MM-dd HH:mm').format(_picked)),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pick,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _convert,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('转换'),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(_result.isEmpty ? '—' : _result,
                style: const TextStyle(
                    fontSize: 15, fontFamily: 'monospace', color: AppColors.brand)),
          ),
        ],
      ),
    );
  }
}
