/// 调试直达参数：真机被禁用 adb 输入注入时，可用
/// `adb shell am start -n <pkg>/.MainActivity --es screen /history --ei tab 1`
/// 冷启动直接落到目标页面，方便验收与截图取证。
///
/// `--ez autostart true` 会在启动后自动点「开始抓包」，用于无人值守验证 VPN 链路。
/// `--ez overlay true` 会在启动后直接开窗口化悬浮窗，用于验证悬浮窗链路。
class LaunchOptions {
  final String? screen;
  final int? tab;

  /// `/request-detail` 无命名路由，用记录序号直接打开对应详情页
  final int? record;
  final bool autostart;

  /// 启动后直接开启窗口化悬浮窗（调试用）
  final bool overlay;

  /// 调试：冷启动直接跑一遍窗口化链路，值为目标应用包名（`all` 表示全部应用）
  final String? targetApp;

  /// 调试：悬浮窗建好后直接执行一条指令（expand / collapse / exit）
  final String? overlayAction;
  const LaunchOptions(
      {this.screen,
      this.tab,
      this.record,
      this.autostart = false,
      this.overlay = false,
      this.targetApp,
      this.overlayAction});

  bool get hasScreen => screen != null && screen!.isNotEmpty && screen != '/';
  bool get hasTab => tab != null && tab! >= 0 && tab! <= 2;
}
