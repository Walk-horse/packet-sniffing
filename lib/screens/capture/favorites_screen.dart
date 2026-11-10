import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/widgets/common.dart';
import 'package:packet_sniffing/widgets/request_item.dart';
import 'package:packet_sniffing/widgets/marquee_text.dart';
import 'package:packet_sniffing/services/capture_service.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    final favs = capture.favorites;
    return Scaffold(
      appBar: gradientAppBar(context, '收藏请求'),
      body: MarqueeListScope(child: Column(
        children: [
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text('共 ${favs.length} 个收藏',
                style: const TextStyle(color: AppColors.subtext)),
          ),
          Expanded(
            child: favs.isEmpty
                ? emptyState('暂无收藏，可在请求详情页点 ⭐ 收藏',
                    icon: Icons.star_outline_rounded)
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: favs.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (c, i) => RequestListItem(favs[i], onTap: () {
                      Navigator.of(context)
                          .pushNamed(Routes.requestDetail, arguments: favs[i]);
                    }),
                  ),
          ),
        ],
      )),
    );
  }
}
