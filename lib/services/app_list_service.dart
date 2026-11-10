import 'dart:convert';

import 'package:flutter/services.dart';

const _channel = MethodChannel('packetsniffing/capture');

/// 手机里一个可启动的应用
class AppInfo {
  final String package;
  final String label;
  final bool system;

  /// 64×64 PNG 图标，可能为空（取不到图标时用占位）
  final Uint8List? icon;

  const AppInfo({
    required this.package,
    required this.label,
    this.system = false,
    this.icon,
  });

  factory AppInfo.fromMap(Map<dynamic, dynamic> m) {
    Uint8List? bytes;
    final raw = m['icon'];
    if (raw is String && raw.isNotEmpty) {
      try {
        bytes = base64Decode(raw);
      } catch (_) {
        bytes = null;
      }
    }
    return AppInfo(
      package: (m['package'] as String?) ?? '',
      label: (m['label'] as String?) ?? '',
      system: (m['system'] as bool?) ?? false,
      icon: bytes,
    );
  }
}

/// 应用清单 / 拉起 / 前后台切换，全部走原生。
class AppListService {
  AppListService._();

  static List<AppInfo>? _cache;

  /// 已安装应用（仅可启动的）。第二次直接走缓存。
  static Future<List<AppInfo>> load({bool refresh = false}) async {
    if (!refresh && _cache != null) return _cache!;
    try {
      final list =
          await _channel.invokeListMethod<dynamic>('listApps') ?? const [];
      final apps = list
          .whereType<Map<dynamic, dynamic>>()
          .map(AppInfo.fromMap)
          .where((a) => a.package.isNotEmpty)
          .toList();
      _cache = apps;
      return apps;
    } catch (_) {
      return _cache ?? const [];
    }
  }

  /// 打开目标应用（本身会把自己压到后台）
  static Future<bool> launch(String package) async {
    try {
      return await _channel.invokeMethod<bool>('launchApp', package) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 不指定目标应用时：自己退到后台，让用户去用别的 App
  static Future<void> moveTaskToBack() async {
    try {
      await _channel.invokeMethod('moveTaskToBack');
    } catch (_) {}
  }

  /// 从悬浮窗把本应用拉回前台
  static Future<bool> bringToFront() async {
    try {
      return await _channel.invokeMethod<bool>('bringToFront') ?? false;
    } catch (_) {
      return false;
    }
  }
}
