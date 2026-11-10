import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:packet_sniffing/app.dart';
import 'package:packet_sniffing/launch_options.dart';
import 'package:packet_sniffing/overlay_entry.dart';
import 'package:packet_sniffing/services/capture_service.dart';
import 'package:packet_sniffing/services/settings_service.dart';

/// 窗口化悬浮窗的 Dart 入口。
///
/// flutter_overlay_window 原生侧固定按名字 `overlayMain` 建 DartEntrypoint，
/// 所以这个函数必须留在 main.dart（入口库），不能挪到别的文件里。
@pragma('vm:entry-point')
void overlayMain() => runOverlayEntry();

Future<LaunchOptions> _readLaunchOptions() async {
  try {
    const channel = MethodChannel('packetsniffing/capture');
    final m = await channel.invokeMapMethod<String, dynamic>('launchOptions');
    if (m == null) return const LaunchOptions();
    return LaunchOptions(
      screen: (m['screen'] as String?)?.trim(),
      tab: m['tab'] as int?,
      record: m['record'] as int?,
      autostart: (m['autostart'] as bool?) ?? false,
      overlay: (m['overlay'] as bool?) ?? false,
      targetApp: (m['targetApp'] as String?)?.trim(),
      overlayAction: (m['overlayAction'] as String?)?.trim(),
    );
  } catch (_) {
    return const LaunchOptions();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final capture = CaptureService();
  final settings = SettingsService();
  await settings.init();
  final launch = await _readLaunchOptions();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: capture),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: App(launch: launch),
    ),
  );
}
