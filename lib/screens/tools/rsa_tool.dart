import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/utils/rsa.dart';

class RsaTool extends StatefulWidget {
  const RsaTool({super.key});

  @override
  State<RsaTool> createState() => _RsaToolState();
}

class _RsaToolState extends State<RsaTool> {
  final _pub = TextEditingController();
  final _priv = TextEditingController();
  final _plain = TextEditingController();
  final _cipher = TextEditingController();
  String _msg = '';

  void _gen() {
    final pair = generateRSAKeyPair();
    _pub.text = encodePublicKey(pair.publicKey);
    _priv.text = encodePrivateKey(pair.privateKey);
    setState(() => _msg = '已生成 RSA-2048 密钥对');
  }

  void _encrypt() {
    try {
      final pub = decodePublicKey(_pub.text.trim());
      _cipher.text = rsaEncrypt(pub, _plain.text);
      setState(() => _msg = '加密完成');
    } catch (e) {
      setState(() => _msg = '加密失败（公钥无效）：$e');
    }
  }

  void _decrypt() {
    try {
      final priv = decodePrivateKey(_priv.text.trim());
      _plain.text = rsaDecrypt(priv, _cipher.text.trim());
      setState(() => _msg = '解密完成');
    } catch (e) {
      setState(() => _msg = '解密失败（私钥无效或密文错误）：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, 'RSA 加解密',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _gen,
              icon: const Icon(Icons.key_rounded),
              label: const Text('生成 RSA-2048 密钥对'),
            ),
          ),
          const SizedBox(height: 12),
          _KeyField('公钥（可编辑/粘贴）', _pub, AppColors.brand),
          const SizedBox(height: 8),
          _KeyField('私钥（可编辑/粘贴）', _priv, AppColors.danger),
          const SizedBox(height: 12),
          const Divider(),
          TextField(
            controller: _plain,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '明文'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _encrypt,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('用公钥加密'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cipher,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '密文（Base64）'),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _decrypt,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('用私钥解密'),
            ),
          ),
          const SizedBox(height: 12),
          if (_msg.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_msg, style: const TextStyle(color: AppColors.accent)),
            ),
        ],
      ),
    );
  }
}

class _KeyField extends StatelessWidget {
  final String label;
  final TextEditingController ctl;
  final Color color;
  const _KeyField(this.label, this.ctl, this.color);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: ctl.text));
                  showToast(context, '已复制');
                },
                icon: const Icon(Icons.copy_rounded, size: 14),
                label: const Text('复制', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          TextField(
            controller: ctl,
            maxLines: 3,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              fillColor: color.withValues(alpha: 0.05),
            ),
          ),
        ],
      );
}
