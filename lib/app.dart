import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/theme.dart';
import 'package:packet_sniffing/screens/home_screen.dart';
import 'package:packet_sniffing/screens/tools_screen.dart';
import 'package:packet_sniffing/screens/settings_screen.dart';
import 'package:packet_sniffing/screens/capture/capture_screen.dart';
import 'package:packet_sniffing/screens/capture/request_detail_screen.dart';
import 'package:packet_sniffing/screens/capture/history_screen.dart';
import 'package:packet_sniffing/screens/capture/build_request_screen.dart';
import 'package:packet_sniffing/screens/capture/favorites_screen.dart';
import 'package:packet_sniffing/screens/capture/api_mock_screen.dart';
import 'package:packet_sniffing/screens/capture/window_screen.dart';
import 'package:packet_sniffing/screens/capture/https_screen.dart';
import 'package:packet_sniffing/screens/capture/capture_mode_screen.dart';
import 'package:packet_sniffing/screens/capture/capture_apps_screen.dart';
import 'package:packet_sniffing/screens/capture/logs_screen.dart';
import 'package:packet_sniffing/screens/capture/hosts_screen.dart';
import 'package:packet_sniffing/screens/settings/tutorial_screen.dart';
import 'package:packet_sniffing/screens/settings/about_screen.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/services/settings_service.dart';
import 'package:packet_sniffing/services/window_service.dart';
import 'package:packet_sniffing/launch_options.dart';
import 'package:packet_sniffing/nav.dart';
import 'package:packet_sniffing/routes.dart';
export 'package:packet_sniffing/routes.dart';
import 'package:packet_sniffing/screens/tools/url_tool.dart';
import 'package:packet_sniffing/screens/tools/base64_tool.dart';
import 'package:packet_sniffing/screens/tools/md5_tool.dart';
import 'package:packet_sniffing/screens/tools/timestamp_tool.dart';
import 'package:packet_sniffing/screens/tools/rsa_tool.dart';
import 'package:packet_sniffing/models/capture_models.dart';

/// 与原生共用的一条通道：除了调用，也接收原生主动下发的界面指令
const MethodChannel _nativeChannel = MethodChannel('packetsniffing/capture');

class App extends StatelessWidget {
  final LaunchOptions launch;
  const App({super.key, this.launch = const LaunchOptions()});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '抓包精灵',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      navigatorKey: appNavigatorKey,
      initialRoute: '/',
      home: RootScaffold(launch: launch),
      routes: {
        Routes.capture: (c) => const CaptureScreen(),
        Routes.history: (c) => const HistoryScreen(),
        Routes.buildRequest: (c) => const BuildRequestScreen(),
        Routes.favorites: (c) => const FavoritesScreen(),
        Routes.apiMock: (c) => const ApiMockScreen(),
        Routes.window: (c) => const WindowScreen(),
        Routes.https: (c) => const HttpsScreen(),
        Routes.captureMode: (c) => const CaptureModeScreen(),
        Routes.captureApps: (c) => const CaptureAppsScreen(),
        Routes.logs: (c) => const LogsScreen(),
        Routes.hosts: (c) => const HostsScreen(),
        Routes.tools: (c) => const ToolsScreen(),
        Routes.settings: (c) => const SettingsScreen(),
        Routes.tutorial: (c) => const TutorialScreen(),
        Routes.about: (c) => const AboutScreen(),
        Routes.urlTool: (c) => const UrlTool(),
        Routes.base64Tool: (c) => const Base64Tool(),
        Routes.md5Tool: (c) => const Md5Tool(),
        Routes.timestampTool: (c) => const TimestampTool(),
        Routes.rsaTool: (c) => const RsaTool(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == Routes.requestDetail) {
          final record = settings.arguments as RequestRecord;
          return MaterialPageRoute(
              builder: (_) => RequestDetailScreen(record: record));
        }
        return null;
      },
    );
  }
}

class RootScaffold extends StatefulWidget {
  final LaunchOptions launch;
  const RootScaffold({super.key, this.launch = const LaunchOptions()});

  @override
  State<RootScaffold> createState() => _RootScaffoldState();
}

class _RootScaffoldState extends State<RootScaffold> {
  @override
  void initState() {
    super.initState();
    // 原生回传的界面指令：悬浮窗「回到应用」后切到抓包列表、复位窗口化状态
    _nativeChannel.setMethodCallHandler((call) async {
      if (!mounted) return null;
      switch (call.method) {
        case 'navigate':
          final route = call.arguments as String?;
          if (route != null && route.isNotEmpty) {
            appNavigatorKey.currentState?.pushNamed(route);
          }
          break;
        case 'overlayExited':
          OverlayBridge.onNativeExit();
          break;
      }
      return null;
    });
    if (widget.launch.hasScreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final idx = widget.launch.record;
        final capture = context.read<CaptureService>();
        if (widget.launch.screen == Routes.requestDetail &&
            idx != null &&
            idx < capture.allRecords.length) {
          // 详情页需要具体记录，调试时按序号直达
          Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  RequestDetailScreen(record: capture.allRecords[idx])));
          return;
        }
        Navigator.of(context).pushNamed(widget.launch.screen!);
      });
    }
    if (widget.launch.autostart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<CaptureService>().startCapture();
      });
    }
    // 窗口化：绑定「抓包状态 → 悬浮窗」的同步通道，并做一次冷启动对账
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      OverlayBridge.bind(
        capture: context.read<CaptureService>(),
        settings: context.read<SettingsService>(),
      );
      await OverlayBridge.syncOnStart();
      if (!mounted) return;
      if (widget.launch.overlay && !OverlayBridge.active) {
        await OverlayBridge.show(context);
      }
      if (!mounted) return;
      // 调试直达：adb input 被禁时用启动参数把整条窗口化链路跑一遍
      final target = widget.launch.targetApp;
      if (target != null && target.isNotEmpty) {
        final pkg = target == 'all' ? null : target;
        await OverlayBridge.startForApp(context, package: pkg);
      }
      final action = widget.launch.overlayAction;
      if (action != null && action.isNotEmpty) {
        // 抓包/悬浮窗/目标应用都是异步起来的，等它们落定再执行调试指令
        await Future.delayed(const Duration(milliseconds: 2500));
        // 支持逗号分隔的连续指令（如 "expand,collapse"），方便一次跑完整条链路
        for (final a in action.split(',').map((e) => e.trim())) {
          if (a.isEmpty) continue;
          await OverlayBridge.debugAction(a);
          await Future.delayed(const Duration(milliseconds: 1800));
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 底部 tab 已移除：首页即单一入口，工具/设置改为二级页面
    return const HomeScreen();
  }

  @override
  void dispose() {
    _nativeChannel.setMethodCallHandler(null);
    super.dispose();
  }
}
