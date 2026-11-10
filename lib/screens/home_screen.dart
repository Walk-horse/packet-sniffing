import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/routes.dart';
import 'package:packet_sniffing/services/capture_service.dart';

/// 总览页：渐变头部 + 悬浮操作卡片 + 分类入口宫格。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capture = context.watch<CaptureService>();
    final top = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _Header(capture: capture, topPadding: top),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(15, 28, 15, 24),
              children: [
                _Section(
                  title: '工具',
                  items: [
                    _Tile(
                      icon: Icons.history_rounded,
                      label: '抓包历史',
                      color: AppColors.brand,
                      onTap: () => Navigator.pushNamed(context, Routes.history),
                    ),
                    _Tile(
                      icon: Icons.picture_in_picture_alt_rounded,
                      label: '窗口化',
                      color: AppColors.action,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.window),
                    ),
                    _Tile(
                      icon: Icons.edit_rounded,
                      label: '构建请求',
                      color: AppColors.brand,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.buildRequest),
                    ),
                    _Tile(
                      icon: Icons.dns_rounded,
                      label: 'Hosts 设置',
                      color: AppColors.accent,
                      onTap: () => Navigator.pushNamed(context, Routes.hosts),
                    ),
                    _Tile(
                      icon: Icons.star_rounded,
                      label: '收藏请求',
                      color: AppColors.brand,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.favorites),
                    ),
                    _Tile(
                      icon: Icons.build_rounded,
                      label: '常用工具',
                      color: AppColors.action,
                      onTap: () => Navigator.pushNamed(context, Routes.tools),
                    ),
                  ],
                ),
                _Section(
                  title: '设置',
                  items: [
                    _Tile(
                      icon: Icons.lock_rounded,
                      label: 'HTTPS 抓包',
                      color: AppColors.accent,
                      onTap: () => Navigator.pushNamed(context, Routes.https),
                    ),
                    _Tile(
                      icon: Icons.tune_rounded,
                      label: '设置抓包模式',
                      color: AppColors.brand,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.captureMode),
                    ),
                    _Tile(
                      icon: Icons.apps_rounded,
                      label: '抓包应用',
                      color: AppColors.action,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.captureApps),
                    ),
                    _Tile(
                      icon: Icons.format_list_bulleted_rounded,
                      label: '日志',
                      color: AppColors.accent,
                      onTap: () => Navigator.pushNamed(context, Routes.logs),
                    ),
                    _Tile(
                      icon: Icons.menu_book_rounded,
                      label: '教程',
                      color: AppColors.brand,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.tutorial),
                    ),
                    _Tile(
                      icon: Icons.info_rounded,
                      label: '关于',
                      color: AppColors.accent,
                      onTap: () => Navigator.pushNamed(context, Routes.about),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Tile> items;
  const _Section({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, top: 6, bottom: 10),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.subtext,
            ),
          ),
        ),
        _TileGrid(items: items),
        const SizedBox(height: 10),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final CaptureService capture;
  final double topPadding;
  const _Header({required this.capture, required this.topPadding});

  @override
  Widget build(BuildContext context) {
    final running = capture.capturing;
    // 与参考视频一致：标题区 64、卡片高 78、头部底色延伸到卡片 2/3 处
    const cardTop = 64.0;
    const cardHeight = 78.0;

    return SizedBox(
      height: topPadding + cardTop + cardHeight,
      child: Stack(
        children: [
          Container(
            height: topPadding + cardTop + cardHeight * 0.65,
            decoration:
                const BoxDecoration(gradient: AppGradients.brandGradient),
          ),
          Positioned(
            top: topPadding,
            left: 0,
            right: 0,
            child: const SizedBox(
              height: cardTop,
              child: Center(
                child: Text(
                  '总览',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: topPadding + cardTop,
            left: 15,
            right: 15,
            child: Container(
              height: cardHeight,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: running ? '查看抓包' : '开始抓包',
                      color: running ? AppColors.brand : AppColors.action,
                      onTap: () {
                        // 点击「开始抓包」直接打开二级抓包页；
                        // 实际开始抓包（含确认弹窗）在抓包页自身的「开始」按钮上
                        if (context.mounted) {
                          Navigator.pushNamed(context, Routes.capture);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: '接口模拟',
                      color: AppColors.brand,
                      onTap: () =>
                          Navigator.pushNamed(context, Routes.apiMock),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Tile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _TileGrid extends StatelessWidget {
  final List<_Tile> items;
  const _TileGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 14,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final it = items[i];
        return InkWell(
          onTap: it.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: it.color,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(it.icon, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 7),
              Text(
                it.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.text,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
