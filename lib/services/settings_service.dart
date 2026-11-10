import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置：窗口化、通知等。
class SettingsService extends ChangeNotifier {
  late SharedPreferences _sp;
  bool windowMode = false;
  bool notification = true;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    windowMode = _sp.getBool('windowMode') ?? false;
    notification = _sp.getBool('notification') ?? true;
    notifyListeners();
  }

  Future<void> setWindowMode(bool v) async {
    windowMode = v;
    await _sp.setBool('windowMode', v);
    notifyListeners();
  }

  Future<void> setNotification(bool v) async {
    notification = v;
    await _sp.setBool('notification', v);
    notifyListeners();
  }
}
