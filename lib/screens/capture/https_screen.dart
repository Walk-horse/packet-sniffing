import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/widgets/kit.dart';

class HttpsScreen extends StatefulWidget {
  const HttpsScreen({super.key});

  @override
  State<HttpsScreen> createState() => _HttpsScreenState();
}

class _HttpsScreenState extends State<HttpsScreen> {
  bool _httpsProxy = true;

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    return Scaffold(
      appBar: gradientAppBar(context, 'HTTPS 抓包',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 顶部说明卡片
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('如果您要抓取 HTTPS 的请求，需要先启动抓包，然后安装 CA 证书。',
                    style: TextStyle(fontSize: 13, height: 1.5)),
                SizedBox(height: 6),
                Text(
                    '注意：Android 7+ 应用默认不信任用户证书，仅「信任用户 CA」的 App 可解密；其余 App 会在 TLS 握手失败时记录原因并断开连接（不影响上网）。',
                    style: TextStyle(fontSize: 12, color: AppColors.danger, height: 1.5)),
              ],
            ),
          ),
          sectionTitle('步骤一：安装 CA 证书'),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    '系统安装失败时，可导出 .crt 到下载目录，再到 设置→安全→加密与凭据→安装证书 手动选择。',
                    style: TextStyle(fontSize: 13, color: AppColors.subtext, height: 1.5)),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => capture.installCa(),
                    icon: const Icon(Icons.security_rounded, size: 18),
                    label: const Text('安装 CA 证书'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Divider(),
                InkWell(
                  onTap: () => _exportCa(context, capture),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.download_rounded, size: 18, color: AppColors.brand),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('导出 CA 证书到下载目录',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.subtext),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          sectionTitle('HTTPS 代理（系统代理）'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('启用 HTTPS 代理',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w500)),
                        SizedBox(height: 2),
                        Text('开启后可抓取 WebView/H5 等走系统代理的流量',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.subtext)),
                      ],
                    ),
                  ),
                  CompactSwitch(
                    value: _httpsProxy,
                    onChanged: (v) {
                      setState(() => _httpsProxy = v);
                      _setHttpsProxy(v);
                    },
                  ),
                ],
              ),
            ),
          ),
          sectionTitle('清除 MITM 缓存'),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
            ),
            child: InkWell(
              onTap: () => _clearCache(context, capture),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.cleaning_services_rounded, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('清除 MITM 缓存',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _exportCa(BuildContext context, CaptureService capture) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await capture.exportCa();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(result ?? '导出失败，请检查存储权限后重试'),
      duration: const Duration(seconds: 3),
    ));
  }

  Future<void> _clearCache(BuildContext context, CaptureService capture) async {
    final messenger = ScaffoldMessenger.of(context);
    await capture.clearMitmCache();
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(
      content: Text('MITM 缓存已清空'),
      duration: Duration(seconds: 2),
    ));
  }

  void _setHttpsProxy(bool on) {
    try {
      const channel = MethodChannel('packetsniffing/capture');
      channel.invokeMethod('setHttpsProxy', on);
    } catch (_) {}
  }
}
