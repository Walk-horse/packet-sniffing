import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/routes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _info;
  String? _installTime;

  @override
  void initState() {
    super.initState();
    _loadInstallTime();
  }

  Future<void> _loadInstallTime() async {
    final info = await PackageInfo.fromPlatform();
    final t = info.installTime;
    if (!mounted) return;
    setState(() {
      _info = info;
      _installTime = t == null
          ? null
          : DateFormat('yyyy-MM-dd HH:mm').format(t.toLocal());
    });
  }

  @override
  Widget build(BuildContext context) {
    final version = _info?.version ?? '0.1.0';
    final install = _installTime ?? '—';
    return Scaffold(
      appBar: gradientAppBar(context, '设置'),
      body: ListView(
        children: [
          sectionTitle('抓包配置'),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                listRow(
                  icon: Icons.lock_rounded,
                  title: 'HTTPS 抓包',
                  subtitle: '安装 CA 证书，解密 HTTPS 请求',
                  onTap: () => Navigator.pushNamed(context, Routes.https),
                ),
                listRow(
                  icon: Icons.tune_rounded,
                  title: '设置抓包模式',
                  subtitle: '过滤规则、黑白名单、端口范围',
                  onTap: () => Navigator.pushNamed(context, Routes.captureMode),
                ),
              ],
            ),
          ),
          sectionTitle('帮助'),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                listRow(
                  icon: Icons.menu_book_rounded,
                  title: '教程',
                  subtitle: '使用教程与常见问题',
                  onTap: () => Navigator.pushNamed(context, Routes.tutorial),
                ),
                listRow(
                  icon: Icons.info_rounded,
                  title: '关于',
                  subtitle: '版本信息与免责声明',
                  onTap: () => Navigator.pushNamed(context, Routes.about),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text('抓包精灵 v$version · Flutter',
                style: const TextStyle(color: AppColors.subtext, fontSize: 12)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('安装时间：$install',
                style: const TextStyle(color: AppColors.subtext, fontSize: 12)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
