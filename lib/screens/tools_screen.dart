import 'package:flutter/material.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';

/// 工具页：与设置页保持一致的列表式排版。
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '工具'),
      body: ListView(
        children: [
          sectionTitle('编解码'),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                listRow(
                  icon: Icons.link_rounded,
                  title: 'URL 编码解码',
                  subtitle: 'URL encode / decode，支持组件与整串',
                  onTap: () => Navigator.pushNamed(context, Routes.urlTool),
                ),
                listRow(
                  icon: Icons.code_rounded,
                  title: 'Base64 加解密',
                  subtitle: '文本与 Base64 互转，支持 UTF-8',
                  iconColor: AppColors.accent,
                  onTap: () => Navigator.pushNamed(context, Routes.base64Tool),
                ),
              ],
            ),
          ),
          sectionTitle('加密与转换'),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                listRow(
                  icon: Icons.tag_rounded,
                  title: 'MD5',
                  subtitle: '计算 32 位摘要，可选大写输出',
                  iconColor: AppColors.action,
                  onTap: () => Navigator.pushNamed(context, Routes.md5Tool),
                ),
                listRow(
                  icon: Icons.vpn_key_rounded,
                  title: 'RSA 加解密',
                  subtitle: '生成密钥对，公钥加密 / 私钥解密',
                  iconColor: AppColors.accent,
                  onTap: () => Navigator.pushNamed(context, Routes.rsaTool),
                ),
                listRow(
                  icon: Icons.schedule_rounded,
                  title: '时间戳转化',
                  subtitle: 'Unix 时间戳与日期互转',
                  onTap: () => Navigator.pushNamed(context, Routes.timestampTool),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text('所有工具均在本地计算，不联网',
                style: TextStyle(color: AppColors.subtext, fontSize: 12)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
