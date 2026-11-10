import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:packet_sniffing/theme.dart';

/// 通用小组件集合，统一重设计后的视觉语言。

/// 顶部渐变标题栏
AppBar gradientAppBar(BuildContext context, String title,
    {List<Widget>? actions, Widget? leading, double? leadingWidth}) {
  return AppBar(
    leading: leading,
    leadingWidth: leadingWidth,
    title: Text(title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
    centerTitle: true,
    flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppGradients.brandGradient)),
    actions: actions,
  );
}

/// 真实抓包前的确认。
///
/// 当前原生实现是网络层解析，尚未实现 TCP/UDP 转发，全量路由会导致设备断网，
/// 因此在开始抓包前必须让用户明确知情。
Future<bool> confirmRealCapture(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('开始抓包'),
      content: const Text(
        '即将申请 VPN 权限并在系统网络层接管流量。\n\n'
        '当前版本只解析数据包元数据，尚未实现 TCP/UDP 转发，'
        '因此在抓包期间设备可能无法上网。\n\n'
        '如需恢复上网，点「停止抓包」即可。',
        style: TextStyle(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('仍然开启')),
      ],
    ),
  );
  return ok ?? false;
}

/// 区块标题
Widget sectionTitle(String text) => Padding(
      padding: const EdgeInsets.only(left: 4, top: 14, bottom: 6),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.subtext,
              letterSpacing: 0.5)),
    );

/// 设置风格列表行（左图标+标题+副标题，右侧 chevron 或自定义）
Widget listRow({
  required IconData icon,
  required String title,
  String? subtitle,
  Widget? trailing,
  VoidCallback? onTap,
  Color iconColor = AppColors.brand,
}) {
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: const BoxDecoration(
            border:
                Border(bottom: BorderSide(color: AppColors.border, width: 1))),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.brandLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w500)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.subtext)),
                    ),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right, color: AppColors.subtext),
          ],
        ),
      ),
    ),
  );
}

/// 卡片容器
Widget card(Widget child, {EdgeInsets? padding}) => Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );

/// 主操作大按钮（琥珀渐变）
Widget primaryButton(String label, VoidCallback? onPressed,
    {bool loading = false}) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.action,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 38),
        padding: const EdgeInsets.symmetric(vertical: 8),
        textStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
      child: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Text(label),
    ),
  );
}

/// 空状态
Widget emptyState(String text, {IconData icon = Icons.inbox_rounded}) =>
    Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.subtext.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(color: AppColors.subtext, fontSize: 14)),
        ],
      ),
    );

/// 复制 / Toast 辅助
void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// 长按列表行时复制主行文字（接口名 / 目标域名），并给出 Toast 反馈。
/// 请求行、透传行共用，保证各列表的长按行为一致。
void copyEndpointName(BuildContext context, String text,
    {String toast = '已复制接口名'}) {
  Clipboard.setData(ClipboardData(text: text));
  showToast(context, toast);
}
