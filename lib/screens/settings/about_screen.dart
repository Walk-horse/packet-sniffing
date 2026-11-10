import 'package:flutter/material.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '关于',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: AppGradients.brandGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.radar_rounded,
                      size: 40, color: AppColors.brand),
                ),
                const SizedBox(height: 14),
                const Text('抓包精灵',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('手机端抓包工具 · v0.1.0',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('技术栈', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                SizedBox(height: 8),
                Text('Flutter 3.x + Dart · 原生 VPN 抓包（Android VpnService / iOS NetworkExtension）· 平台通道通信。',
                    style: TextStyle(color: AppColors.subtext, height: 1.6)),
                Text('工具箱完全基于 Dart 实现：URL/Base64/MD5/RSA/时间戳等，离线可用。',
                    style: TextStyle(color: AppColors.subtext, height: 1.6)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('免责声明', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
                SizedBox(height: 8),
                Text('本工具仅用于合法的网络调试、学习与自己拥有权限的流量分析。请勿用于任何未经授权的网络监听、破解或侵犯他人隐私的行为。因使用本工具产生的任何后果由使用者自行承担。',
                    style: TextStyle(color: AppColors.subtext, height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
