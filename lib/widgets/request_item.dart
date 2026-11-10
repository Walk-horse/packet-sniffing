import 'package:flutter/material.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/widgets/kit.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/marquee_text.dart';

/// 请求列表项：方法彩标 + 路径（主）+ 域名（次）+ 状态/大小/耗时
/// 版式对齐参考视频：主行是 path，次行是 host，右侧状态码在上、体积·耗时在下。
class RequestListItem extends StatelessWidget {
  final RequestRecord r;
  final VoidCallback? onTap;
  const RequestListItem(this.r, {this.onTap, super.key});

  @override
  Widget build(BuildContext context) {
    final mColor = AppColors.methodColor(r.method);
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        // 长按复制主行接口名（displayPath：去掉 query 的 path；隧道记录为 host）
        onLongPress: () => copyEndpointName(context, r.displayPath),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(
              horizontal: AppMetric.pagePadding, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: mColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(r.method,
                    maxLines: 1,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 单行跑马灯：仅屏幕内行、且外层未竖向滚动时才运行
                    MarqueeText(r.displayPath,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                            height: 1.3)),
                    const SizedBox(height: 3),
                    Text(
                        r.isTunnel
                            ? (r.scheme == 'https' ? 'HTTPS 连接' : '${r.method} 连接')
                            : r.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: AppFont.small,
                            color: AppColors.subtext)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (r.isTunnel)
                    const SizedBox.shrink()
                  else if (r.isError)
                    const Text('失败',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: AppFont.sub,
                            fontWeight: FontWeight.w500))
                  else if (r.statusCode == 0)
                    const Icon(Icons.sync_rounded,
                        size: 15, color: AppColors.subtext)
                  else
                    Text('${r.statusCode}',
                        style: TextStyle(
                            color: r.statusCode >= 400
                                ? AppColors.danger
                                : AppColors.success,
                            fontSize: 15,
                            fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                      '${formatBytes(r.responseSize)} · ${formatDuration(r.durationMs)}',
                      style: const TextStyle(
                          fontSize: AppFont.tiny, color: AppColors.subtext)),
                ],
              ),
              const SizedBox(width: 2),
              const Icon(Icons.more_horiz, size: 16, color: AppColors.subtext),
            ],
          ),
        ),
      ),
    );
  }
}
