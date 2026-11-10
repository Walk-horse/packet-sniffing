import 'package:shared_preferences/shared_preferences.dart';

/// 「抓包应用」白名单存储（SharedPreferences）。
///
/// 空集合表示不筛选：抓取全部应用。非空时只把这些包名纳入 VPN。
class CaptureAppsStore {
  static const _key = 'capture_app_packages';

  static Set<String> _cache = {};
  static bool _loaded = false;

  /// 已勾选的包名（同步读缓存，页面首帧就能用）
  static Set<String> get selected => _cache;

  static Future<Set<String>> load() async {
    if (_loaded) return _cache;
    final sp = await SharedPreferences.getInstance();
    _cache = (sp.getStringList(_key) ?? const []).toSet();
    _loaded = true;
    return _cache;
  }

  static Future<void> save(Set<String> packages) async {
    _cache = packages.toSet();
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_key, _cache.toList());
  }

  static Future<void> toggle(String package, bool checked) async {
    final next = _cache.toSet();
    if (checked) {
      next.add(package);
    } else {
      next.remove(package);
    }
    await save(next);
  }

  static Future<void> clear() async {
    _cache = {};
    _loaded = true;
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
