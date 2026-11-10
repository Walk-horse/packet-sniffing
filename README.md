# 抓包精灵 (PacketSniffer)

基于 Flutter 的手机端抓包工具。

## 功能

- **底部导航**：首页 / 工具 / 设置
- **首页（总览）**：渐变头部 + 悬浮操作卡（开始/停止抓包、抓包历史）+ 6 项入口宫格
  （窗口化、构建请求、Hosts 设置、收藏请求、接口模拟、日志）；工具入口只保留底部 tab，首页不再重复
- **工具**：列表式排版，分「编解码」（URL、Base64）与「加密与转换」（MD5、RSA、时间戳）两组，
  均本地真实计算、不联网
- **设置**：抓包配置（HTTPS 抓包、抓包模式、Hosts）+ 帮助（教程、关于）
- **窗口化**：选一个应用 → 本应用退到后台、目标应用打开、屏幕上留一个悬浮图标；
  单击图标半屏看抓包列表，长按结束抓包并回到抓包列表

## 架构

```
lib/                         Flutter UI + 状态管理 (provider)
 ├─ app.dart                路由 + 底部导航
 ├─ theme.dart              重新设计的主题（青绿/琥珀渐变）
 ├─ routes.dart             路由名
 ├─ models/                 抓包记录、会话、Hosts、过滤规则等模型
 ├─ services/               CaptureService（平台通道 + 记录/会话管理）
 ├─ screens/                首页 / 工具 / 设置 及抓包相关页面
 ├─ utils/                  RSA、curl 解析、导出（cURL/HAR）
 └─ widgets/                通用组件

android/app/src/main/kotlin/  原生抓包桥
 ├─ MainActivity.kt         MethodChannel / EventChannel 接线
 ├─ CaptureVpnService.kt    VpnService 建立 TUN，解析 IPv4/TCP/UDP 并回传事件
 └─ CaptureBridge.kt        跨线程事件桥 + 黑白名单过滤
```

### 抓包链路

首页点「开始抓包」→ 申请 VPN 权限 → 启动 `CaptureVpnService`，在**网络层**捕获 TCP/UDP 连接（目的 IP/端口/协议/负载长度）并实时回传。

> **关于 HTTPS 解密**：当前原生实现是网络层抓包（连接级元数据）。要进一步解析 HTTP/HTTPS 的请求头与响应体（含 TLS 解密），需要在本地起一个 MITM 代理、用自签名 CA 做证书注入（参考源仓库的 BouncyCastle CA + 本地代理方案），并在 `CaptureVpnService` 中把流量重定向到该代理。这是下一步扩展点，已在 `MainActivity` 的 `installCa / exportCa / clearMitmCache` 预留了通道。

## 运行

```bash
flutter pub get
flutter run            # 需要真机，启动抓包时会申请 VPN 权限
```

#### 真机抓包

1. 首页点击「开始抓包」，确认提示后授予 VPN 权限
2. 在「日志 / 抓包历史」中查看捕获到的连接

> ⚠️ **已知限制（重要）**：当前 `CaptureVpnService` 只做「读包 + 解析元数据」，
> **尚未实现 TCP/UDP 转发**（userspace 协议栈或 tun2socks）。开启全量路由后
> 设备会短暂失去上网能力（流量进 TUN 后没有出口）。点「停止抓包」即恢复。
> 抓包前的确认弹窗已明确提示这一点。
> 下一步要做的是：在 `parsePacket` 之后把连接通过 `protect()` 保护的
> SocketChannel/DatagramChannel 转发出去，这条链路补上后才是可日常使用的抓包。

## 真机调试通道（无人值守验收）

真机若被禁用 `adb shell input`（如 MIUI 报 `INJECT_EVENTS` 权限缺失），
无法用点击脚本走查页面，可用启动参数直接落到目标页面：

```bash
adb shell am start -n com.packetsniffer.packet_sniffing/.MainActivity \
  --es screen /capture --ei tab 0 --ez autostart true
```

| 参数                                      | 说明                                                                                        |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- |
| `--es screen <route>`                     | 冷启动后直接 push 到该路由（`/history`、`/api-mock`、`/tool/rsa`…）                         |
| `--ei tab 0/1/2`                          | 首页 / 工具 / 设置                                                                          |
| `--ez autostart true`                     | 启动后自动开始抓包（用于验证 VPN 链路）                                                     |
| `--ei record <n>`                         | 配合 `--es screen /request-detail` 直接打开第 n 条记录的详情页                              |
| `--ez overlay true`                       | 启动后直接开窗口化悬浮窗（验证悬浮窗链路）                                                  |
| `--es targetApp <包名>`                   | 冷启动直接跑完整窗口化链路（自动开抓包、亮悬浮图标、打开该应用）；值写 `all` 表示不限定应用 |
| `--es overlayAction expand/collapse/exit` | 悬浮窗起来后执行一条指令（等价于「单击 / 收起 / 长按」）                                    |

例：以海尔智家为目标验收整条链路

```bash
adb shell am force-stop com.packetsniffer.packet_sniffing
adb shell am start -n com.packetsniffer.packet_sniffing/.MainActivity \
  --es targetApp com.haier.uhome.uplus --es overlayAction expand
```

> 参数只在**冷启动**生效：先 `am force-stop`，再 `am start`。

## UI 尺寸基线

页面字体、按钮、行距按参考录屏（540×1200，对应 360dp 宽）反推，统一放在
`lib/widgets/kit.dart` 的 `AppMetric` / `AppFont` 里：

| 令牌                        | 值                | 用途                       |
| --------------------------- | ----------------- | -------------------------- |
| `pagePadding`               | 12                | 页面左右留白               |
| `rowHeight`                 | 56                | 键值行最小高度             |
| `segTabHeight`              | 30                | 灰底分段控件高度           |
| `buttonHeight`              | 38                | 主按钮（执行/转换/加密等） |
| `smallButtonHeight`         | 30                | 行内小按钮（开始/停止）    |
| `body / sub / small / tiny` | 15 / 14 / 13 / 12 | 正文 / 次要 / 小字 / 极小  |

### 紧凑型控件

按钮与切换类组件统一走「紧凑」规格，落点在 `theme.dart` 的主题级配置 + `kit.dart` 的组件：

| 控件                         | 紧凑规格                                                       | 落点               |
| ---------------------------- | -------------------------------------------------------------- | ------------------ |
| Elevated / Filled / Outlined | 高 38（次级 34）、字号 14、圆角 8、内边距 14×8                 | `theme.dart`       |
| TextButton                   | 高 30、字号 13、内边距 8×5                                     | `theme.dart`       |
| SegmentedButton              | 高 30、字号 13、圆角 7                                         | `theme.dart`       |
| ChoiceChip                   | 字号 12.5、内边距 10×2（颜色必须显式给，否则未选中文字会变白） | `theme.dart`       |
| 开关                         | `CompactSwitch` 42×26（FittedBox 等比压缩原生 Switch）         | `kit.dart`         |
| 全局密度                     | `visualDensity: compact` + `materialTapTargetSize: shrinkWrap` | `theme.dart`       |
| 首页操作按钮                 | 高 40、字号 15                                                 | `home_screen.dart` |

首页宫格单独对齐录屏实测值：图标块 68×68、圆角 8、图标 32、文字 15、行列间距 15。

## 窗口化（悬浮窗）实现说明

流程：首页「窗口化」→ **选择要抓取的应用** → 开抓包（只把该应用纳入 VPN）→ 亮出悬浮图标
→ 本应用退到后台并打开目标应用。

```
                    ┌──────────────┐   单击    ┌────────────────┐
   悬浮图标 56dp  ──┤ 半屏抓包列表 ├── 收起 ──►│  图标回到原位置 │
                    └──────────────┘           └────────────────┘
                          长按 ──► 结束抓包 → 回到本应用 → 抓包列表
```

| 事项                                                                                              | 落点                                                |
| ------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `SYSTEM_ALERT_WINDOW` / `FOREGROUND_SERVICE_SPECIAL_USE` / `QUERY_ALL_PACKAGES` / `REORDER_TASKS` | `AndroidManifest.xml`                               |
| `OverlayService` 声明（`foregroundServiceType="specialUse"` + `<property>` 子类型）               | `AndroidManifest.xml`                               |
| Dart 入口 `overlayMain`（插件按名字查找，必须写在 `main.dart`）                                   | `main.dart` → `runOverlayEntry()`                   |
| 悬浮窗 UI：圆形图标（状态点 + 条数）/ 半屏列表（方法标签、主机、端口、时间）                      | `overlay_entry.dart`                                |
| 启动链路、形态切换、状态推送、指令回传                                                            | `services/window_service.dart` 的 `OverlayBridge`   |
| 应用清单（图标 64px base64、用户应用在前、可启动才有）                                            | `AppListProvider.kt`                                |
| 按应用过滤抓包                                                                                    | `CaptureVpnService` 的 `addAllowedApplication(pkg)` |
| 窗口标志修正（不抢焦点 + 透传窗外触摸）                                                           | `OverlayWindowTuner.kt`                             |

### 五个坑（都在真机上报过障）

1. **插件清单里没有服务声明**：`flutter_overlay_window` 只声明了权限，`OverlayService` 必须由
   App 声明，否则 `startService` 失败、`showOverlay` 静默无效，异常还被 `catch` 吃掉，
   表现成「点了没反应」。
2. **窗口标志只能二选一**：`defaultFlag` = `FLAG_NOT_FOCUSABLE`（**触摸模态**，窗口以外全被吞掉，
   悬浮图标一出现后面的 App 就点不动）；`focusPointer` = `FLAG_NOT_TOUCH_MODAL`（可透传但抢焦点）。
   两者叠加才行，插件没有这个枚举，所以用反射改 `OverlayService` 里的 `LayoutParams`
   （`OverlayWindowTuner`），按「不抢焦点 + 可透传」写入。
3. **尺寸单位不一致**：`showOverlay` 的 `width/height` 是**像素**；`updateOverlay` / `moveOverlay`
   走 **dp**。图标按 `dp × devicePixelRatio` 传，之后改尺寸一律用 dp。
4. **悬浮窗引擎没有插件**：它跑在 `createAndRunEngine` 起的第二个引擎里，未注册任何插件，
   所以调 `closeOverlay()` 会 `MissingPluginException`；「展开 / 收起 / 退出」统一用 `shareData`
   回传主 isolate 执行，主 isolate 反向推状态前要先确认 `OverlayBridge.active`
   （插件原生 `onMessage` 没判空，引擎不在会 NPE）。
5. **后台启动 Activity 被 ROM 拦**：`SINGLE_TOP` / `singleTask` / `CLEAR_TOP+SINGLE_TOP` 命中已有实例时
   只返回 `START_DELIVERED_TO_TOP`，任务栈不会提到前台；MIUI 还会额外用 `MIUILOG- Permission Denied
Activity` 静默拒绝。最终方案：`NEW_TASK|CLEAR_TOP`（不带 SINGLE_TOP，让系统给
   `START_TASK_TO_FRONT`）+ **先启动 Activity、后关悬浮窗**（此时本应用还有可见窗口，
   属于 ROM 允许的后台启动场景），悬浮窗由原生延时 `stopService` 收掉
   （Activity 被重建后旧 isolate 已销毁，Dart 侧收尾不可靠）。

### 应用清单为什么走 launcher 查询

`getInstalledApplications()` 在 HyperOS / MIUI 上会弹系统「读取应用列表」授权框，拒绝后返回空列表；
改用 `queryIntentActivities(ACTION_MAIN + CATEGORY_LAUNCHER)` 既拿到「可启动」的应用（正是本功能需要的），
又不会被隐私拦截。真机实测 70 个可启动应用。

## 已修复的真机问题（记录）

- `EventSink.success` 必须在主线程调用，否则抓包线程里会抛
  `Methods marked with @UiThread must be executed on the main thread`，
  表现为「VPN 已建立但列表 0 条」。现在 `CaptureBridge.emit` 统一 post 到主线程。
- `RequestRecord.fromJson` 对 `id` / `requestTime` 做了兜底，单条脏数据不再中断整条事件流。
- RSA 密钥生成：pointycastle 返回 `AsymmetricKeyPair<PublicKey, PrivateKey>`，
  直接强转会抛 type cast；私钥序列化补上 `p`、`q`，否则 `RSAPrivateKey` 构造失败。
- 窗口化点了没反应：`flutter_overlay_window` 的 `OverlayService` 没有在 App 清单里声明
  （插件清单里只有权限），`startService` 直接失败且被 `try/catch` 吞掉。已补声明 +
  Android 14 要求的 `foregroundServiceType="specialUse"`。
- `ChipThemeData` 只覆盖 `labelStyle.fontSize`（不给颜色）时，未选中 chip 的文字会被解析成白色，
  表现成「chip 是空框」；紧凑化时已显式补上 `labelStyle/labelColor/side`。
- `Container` 同时传 `color` 与 `decoration` 会触发
  `Failed assertion: 'color == null || decoration == null'`，「构建请求」页整页红屏。
  已统一改为把 `color` 写进 `BoxDecoration`。
- TCP/UDP 隧道记录的 `path` 只有 `:port`，列表标题直接渲染会显示成「:14000」。
  现在标题用 `host:port`、副标题显示「TCP/UDP 连接」，且不再显示无意义的状态码图标。

## 构建

```bash
flutter build apk --debug      # 调试包
flutter build apk --release    # 正式包（需自行配置签名）
```

## 说明

本应用仅用于学习与安全测试，请勿用于未授权的网络流量截取。
