import 'package:flutter/material.dart';

/// 全局导航器 key。
///
/// 悬浮窗（工作在另一个 isolate）要通过 shareData 通知主 isolate「长按退出」，
/// 主 isolate 收到后需要把界面切到抓包列表；此时没有 BuildContext 可用，
/// 只能走全局 key。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
