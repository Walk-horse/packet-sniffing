import 'package:flutter/material.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/widgets/common.dart';

class TutorialScreen extends StatelessWidget {
  const TutorialScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(context, '教程',
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('快速上手',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                SizedBox(height: 8),
                Text('1. 首页点击「开始抓包」，系统会请求 VPN 权限（本机 VPN 接管流量）。',
                    style: TextStyle(height: 1.6)),
                Text('2. 打开任意 App 上网，回到本 App → 抓包/抓包历史 查看请求。',
                    style: TextStyle(height: 1.6)),
                Text('3. 点击任意请求进入详情，可看 请求/响应/时间，支持 JSON 美化、搜索、复制 cURL、导出 HAR。',
                    style: TextStyle(height: 1.6)),
                Text('4. 详情页点 ⭐ 收藏，回到首页「收藏请求」可快速定位。',
                    style: TextStyle(height: 1.6)),
              ],
            ),
          ),
          sectionTitle('HTTPS 解密'),
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· 解密 HTTPS 需安装本 App 的 CA 证书（设置 → HTTPS 抓包 → 安装）。',
                    style: TextStyle(height: 1.6)),
                Text('· Android 7+ 的第三方 App 默认不信任用户证书，仅「信任用户 CA」的 App 可解密；其余会在 TLS 握手失败后自动透传，不影响上网。',
                    style: TextStyle(height: 1.6, color: AppColors.danger)),
                Text('· 系统安装失败可导出 .crt 到下载目录，再到 设置→安全→加密与凭据→安装证书 手动安装。',
                    style: TextStyle(height: 1.6)),
              ],
            ),
          ),
          sectionTitle('常见问题'),
          const _Faq('抓不到某些 App 的 HTTPS？',
              '多为证书信任或证书锁定(SSL Pinning)导致，参考上方 HTTPS 说明；命中锁定的域名会自动透传。'),
          const _Faq('能抓局域网/其他进程吗？',
              '本机 VPN 仅接管本机流量，无法跨设备；「按应用」分组因系统限制未实现。'),
          const _Faq('窗口化是什么？',
              '开启后抓包状态以悬浮窗形式常驻屏幕，便于边操作边观察（依赖系统 Overlay 权限）。'),
        ],
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  final String q, a;
  const _Faq(this.q, this.a);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: const Border.fromBorderSide(BorderSide(color: AppColors.border)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.help_outline_rounded,
                    color: AppColors.brand, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(q,
                        style: const TextStyle(fontWeight: FontWeight.w500))),
              ],
            ),
            const SizedBox(height: 6),
            Text(a, style: const TextStyle(color: AppColors.subtext, height: 1.5)),
          ],
        ),
      );
}
