import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/services/capture_apps_store.dart';

const _methodChannel = MethodChannel('packetsniffing/capture');
const _eventChannel = EventChannel('packetsniffing/events');

/// 抓包引擎：管理 SESSION、请求记录、透传记录、实时统计，并通过平台通道与原生 VPN 通信。
class CaptureService extends ChangeNotifier {
  bool _capturing = false;
  bool get capturing => _capturing;

  int _uploadBytes = 0;
  int _downloadBytes = 0;
  int get uploadBytes => _uploadBytes;
  int get downloadBytes => _downloadBytes;

  DateTime? _captureStart;
  Duration get elapsed =>
      _captureStart == null ? Duration.zero : DateTime.now().difference(_captureStart!);

  // 请求记录：id -> 记录 + 顺序（最新在前）
  final Map<String, RequestRecord> _reqMap = {};
  final List<String> _reqOrder = [];
  // 透传记录
  final Map<String, PassthroughRecord> _ptMap = {};
  final List<String> _ptOrder = [];

  final List<CaptureSession> _sessions = [];

  /// 抓包日志：原生每次抓包落一个文件（filesDir/capture_logs/capture-*.log），
  /// 这里只缓存列表与已读内容，真正的数据在原生，进程重启后仍在。
  final List<LogFile> _logList = [];
  final Map<String, String> _logCache = {}; // name -> content

  String _currentNativeSessionId = '';
  String get currentSessionId => _currentNativeSessionId;

  List<CaptureSession> get sessions => List.unmodifiable(_sessions);
  List<RequestRecord> get allRecords =>
      _reqOrder.map((id) => _reqMap[id]!).toList();
  List<PassthroughRecord> get passthroughRecords =>
      _ptOrder.map((id) => _ptMap[id]!).toList();

  /// 本次（当前 SESSION）的请求。抓包列表页只看当前批次，旧批次归「抓包历史」。
  List<RequestRecord> get currentRecords {
    final sid = _currentSessionIdOrLatest;
    if (sid.isEmpty) return allRecords;
    return allRecords.where((r) => r.sessionId == sid).toList();
  }

  List<PassthroughRecord> get currentPassthroughs {
    final sid = _currentSessionIdOrLatest;
    if (sid.isEmpty) return passthroughRecords;
    return passthroughRecords.where((p) => p.sessionId == sid).toList();
  }

  /// 当前 SESSION id；停止抓包后回落到最近一批，方便查看刚抓到的记录
  String get _currentSessionIdOrLatest {
    if (_currentNativeSessionId.isNotEmpty) return _currentNativeSessionId;
    return _sessions.isNotEmpty ? _sessions.first.id : '';
  }

  List<RequestRecord> get favorites =>
      allRecords.where((r) => r.isFavorite).toList();

  List<RequestRecord> recordsOfSession(String sid) =>
      allRecords.where((r) => r.sessionId == sid).toList();

  /// 按应用（uid）分组：用于「按应用」Tab。请求与透传合并统计，按总量降序。
  List<AppGroup> get appGroups {
    final byUid = <int, AppGroup>{};
    for (final r in currentRecords) {
      final g = byUid.putIfAbsent(
          r.uid, () => AppGroup(uid: r.uid, package: r.appPackage, label: r.appLabel));
      g.requests.add(r);
    }
    for (final p in currentPassthroughs) {
      final g = byUid.putIfAbsent(
          p.uid, () => AppGroup(uid: p.uid, package: p.appPackage, label: p.appLabel));
      g.passthroughs.add(p);
    }
    final list = byUid.values.toList();
    list.sort((a, b) => b.totalCount.compareTo(a.totalCount));
    return list;
  }

  int get requestCount => _reqOrder.length;

  String get targetPackage => _targetPackage;
  String get targetLabel => _targetLabel;
  String _targetPackage = '';
  String _targetLabel = '';

  late StreamSubscription _eventSub;
  Timer? _tickTimer;

  CaptureService() {
    _loadPersisted();
  }

  /// 开始抓包。
  ///
  /// [package] 非空时只把该应用纳入 VPN（窗口化选中的目标应用）。
  /// [packages] 非空时按「抓包应用」勾选的多应用白名单纳入 VPN。
  /// 两个都不传时读取「抓包应用」页保存的勾选；勾选为空则抓取全部应用。
  /// 返回 false 表示 VPN 权限被拒或服务没起来。
  Future<bool> startCapture(
      {String? package, String? label, List<String>? packages}) async {
    if (_capturing) return true;
    _capturing = true;
    _targetPackage = package ?? '';
    _targetLabel = label ?? '';
    _captureStart = DateTime.now();
    notifyListeners();

    // 目标应用解析顺序：显式列表 > 单包（窗口化） > 设置里勾选的「抓包应用」
    List<String> targets;
    if (packages != null) {
      targets = packages;
    } else if (_targetPackage.isNotEmpty) {
      targets = [_targetPackage];
    } else {
      final selected = await CaptureAppsStore.load();
      targets = selected.toList();
    }

    bool ok = false;
    String? failMsg;
    try {
      // Android 返回 bool；iOS 返回 {ok: bool, message: String?}。
      final resp = await _methodChannel.invokeMethod('startCapture', {
        'package': _targetPackage,
        'packages': targets,
      });
      if (resp is bool) {
        ok = resp;
      } else if (resp is Map) {
        ok = (resp['ok'] as bool?) ?? false;
        failMsg = resp['message'] as String?;
      }
    } catch (e) {
      _logCache['vpn_error.log'] = '启动抓包失败：$e\n请确认已授予 VPN 权限后重试。';
      ok = false;
    }
    if (!ok) {
      _logCache['vpn_error.log'] = failMsg ?? '未授予 VPN 权限，抓包未能启动。';
      _logList.removeWhere((l) => l.name == 'vpn_error.log');
      _logList.insert(
          0, LogFile('vpn_error.log', DateTime.now(), _logCache['vpn_error.log']!.length));
      _capturing = false;
      _targetPackage = '';
      _targetLabel = '';
      notifyListeners();
      return false;
    }
    // 开始新的批次：结束上一轮 SESSION（记录留在历史里），再建一个本地 SESSION 占位。
    // 原生 session 事件在 Dart 订阅之前就发出来了，会被丢弃，所以这里必须自己建一条，
    // 否则「抓包历史」永远是空态。
    _closeActiveSession();
    _uploadBytes = 0;
    _downloadBytes = 0;
    _beginSession();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_onNativeEvent);
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      notifyListeners();
    });
    // 原生刚建好新的日志文件，把列表刷出来
    unawaited(refreshLogs());
    notifyListeners();
    return true;
  }

  Future<void> stopCapture() async {
    if (!_capturing) {
      // 即使状态位已复位，也把可能残留的 SESSION 收尾并落盘
      if (_currentNativeSessionId.isEmpty) return;
    }
    _capturing = false;
    _targetPackage = '';
    _targetLabel = '';
    _tickTimer?.cancel();
    try {
      await _methodChannel.invokeMethod('stopCapture');
    } catch (_) {}
    try {
      await _eventSub.cancel();
    } catch (_) {}
    _closeActiveSession();
    notifyListeners();
    await _persist();
    // VPN 服务停止是异步的，稍等它把汇总行写进日志文件后再刷新列表
    Future.delayed(const Duration(milliseconds: 900), () {
      unawaited(refreshLogs());
    });
  }

  void _onNativeEvent(dynamic event) {
    if (event is! Map) return;
    try {
      final map = Map<String, dynamic>.from(event);
      final type = map['type'];
      switch (type) {
        case 'request_add':
          _upsertRequest(map['data'], isUpdate: false);
          break;
        case 'request_update':
          _upsertRequest(map['data'], isUpdate: true);
          break;
        case 'passthrough_add':
          _upsertPassthrough(map['data'], isUpdate: false);
          break;
        case 'passthrough_update':
          _upsertPassthrough(map['data'], isUpdate: true);
          break;
        case 'session':
          // 原生把 session 状态放在 data 里（EventBridge.startSession/endSession），
          // 这里同时兼容顶层字段，避免事件结构变动后静默失效。
          final raw = map['data'];
          final payload =
              raw is Map ? Map<String, dynamic>.from(raw) : map;
          final state = payload['state'];
          if (state == 'started') {
            _capturing = true;
            _captureStart ??= DateTime.now();
            _adoptSessionId((payload['id'] as String?) ?? '');
          } else if (state == 'stopped') {
            _capturing = false;
            _closeActiveSession();
          }
          _schedulePersist();
          notifyListeners();
          break;
        case 'stats':
          _uploadBytes = (map['upload'] as num?)?.toInt() ?? _uploadBytes;
          _downloadBytes = (map['download'] as num?)?.toInt() ?? _downloadBytes;
          notifyListeners();
          break;
        case 'log':
          _logCache[map['name'] as String? ?? 'capture.log'] =
              map['content'] as String? ?? '';
          notifyListeners();
          break;
        case 'log_append':
          final name = map['name'] as String? ?? 'capture.log';
          final chunk = map['content'] as String? ?? '';
          _logCache[name] = (_logCache[name] ?? '') +
              (chunk.endsWith('\n') ? chunk : '$chunk\n');
          notifyListeners();
          break;
        case 'clear_history':
          _reqMap.clear();
          _reqOrder.clear();
          _ptMap.clear();
          _ptOrder.clear();
          _sessions.clear();
          _schedulePersist();
          notifyListeners();
          break;
        case 'clear_current':
          if (_currentNativeSessionId.isNotEmpty) {
            _clearSessionRecords(_currentNativeSessionId);
          }
          _schedulePersist();
          notifyListeners();
          break;
      }
    } catch (_) {
      // 单条事件解析失败不影响后续抓包
    }
  }

  void _upsertRequest(dynamic data, {required bool isUpdate}) {
    if (data is! Map) return;
    var r = RequestRecord.fromJson(Map<String, dynamic>.from(data));
    // 原生记录自带 sessionId：首条记录到达时把本地占位 SESSION 换成原生 id
    if (r.sessionId.isNotEmpty) _adoptSessionId(r.sessionId);
    if (r.sessionId.isEmpty && _currentNativeSessionId.isNotEmpty) {
      r = r.copyWith(sessionId: _currentNativeSessionId);
    }
    final existing = _reqMap[r.id];
    if (existing != null) {
      // 保留本地收藏标记，避免被原生更新覆盖
      _reqMap[r.id] = r.copyWith(isFavorite: existing.isFavorite);
    } else {
      _reqMap[r.id] = r;
      _reqOrder.insert(0, r.id);
      _trimHistory();
    }
    _schedulePersist();
    notifyListeners();
  }

  void _upsertPassthrough(dynamic data, {required bool isUpdate}) {
    if (data is! Map) return;
    var p = PassthroughRecord.fromJson(Map<String, dynamic>.from(data));
    if (p.sessionId.isNotEmpty) _adoptSessionId(p.sessionId);
    if (p.sessionId.isEmpty && _currentNativeSessionId.isNotEmpty) {
      p = p.copyWith(sessionId: _currentNativeSessionId);
    }
    if (_ptMap.containsKey(p.id)) {
      _ptMap[p.id] = p;
    } else {
      _ptMap[p.id] = p;
      _ptOrder.insert(0, p.id);
      _trimHistory();
    }
    _schedulePersist();
    notifyListeners();
  }

  // ---- SESSION 生命周期 ----

  /// 新建本地 SESSION 占位。原生 `session started` 事件在 Dart 订阅之前就发出，
  /// 会被 EventChannel 丢弃，所以本地必须先建一条，否则历史页永远空。
  void _beginSession() {
    final now = DateTime.now();
    _currentNativeSessionId = 'local-${now.microsecondsSinceEpoch}';
    _captureStart = now;
    _sessions.insert(0, CaptureSession(id: _currentNativeSessionId, startTime: now));
    _schedulePersist();
    notifyListeners();
  }

  /// 采纳原生 SESSION id：替换本地占位 id，并把已入库的记录重新打标
  void _adoptSessionId(String nativeId) {
    final id = nativeId.trim();
    if (id.isEmpty || id == _currentNativeSessionId) return;
    final old = _currentNativeSessionId;
    final oldIdx = old.isEmpty ? -1 : _sessions.indexWhere((s) => s.id == old);
    final existIdx = _sessions.indexWhere((s) => s.id == id);
    _currentNativeSessionId = id;
    if (oldIdx >= 0) {
      final s = _sessions.removeAt(oldIdx);
      if (existIdx < 0) {
        _sessions.insert(
            0, CaptureSession(id: id, startTime: s.startTime, endTime: s.endTime));
      }
    } else if (existIdx < 0) {
      _sessions.insert(0, CaptureSession(id: id, startTime: DateTime.now()));
    }
    if (old.isNotEmpty) {
      for (final key in _reqMap.keys.toList()) {
        final rec = _reqMap[key]!;
        if (rec.sessionId == old) {
          _reqMap[key] = rec.copyWith(sessionId: id);
        }
      }
      for (final key in _ptMap.keys.toList()) {
        final rec = _ptMap[key]!;
        if (rec.sessionId == old) {
          _ptMap[key] = rec.copyWith(sessionId: id);
        }
      }
    }
  }

  /// 结束当前 SESSION：写入 endTime，并把请求数固化到 SESSION 上（记录可能被裁剪）
  void _closeActiveSession() {
    final sid = _currentNativeSessionId;
    if (sid.isEmpty) return;
    final idx = _sessions.indexWhere((s) => s.id == sid);
    if (idx >= 0) {
      final s = _sessions[idx];
      _sessions[idx] = CaptureSession(
        id: s.id,
        startTime: s.startTime,
        endTime: s.endTime ?? DateTime.now(),
        requestCount: recordsOfSession(sid).length,
      );
    }
    _currentNativeSessionId = '';
  }

  static const _maxRecords = 3000;
  static const _maxSessions = 50;

  /// 裁剪历史，避免长时间抓包把内存撑爆（新记录在列表头部，裁剪尾部）
  void _trimHistory() {
    while (_reqOrder.length > _maxRecords) {
      _reqMap.remove(_reqOrder.removeLast());
    }
    while (_ptOrder.length > _maxRecords) {
      _ptMap.remove(_ptOrder.removeLast());
    }
    if (_sessions.length > _maxSessions) {
      final dropped =
          _sessions.skip(_maxSessions).map((s) => s.id).toSet();
      _sessions.removeRange(_maxSessions, _sessions.length);
      _reqOrder.removeWhere((id) {
        if (!dropped.contains(_reqMap[id]?.sessionId)) return false;
        _reqMap.remove(id);
        return true;
      });
      _ptOrder.removeWhere((id) {
        if (!dropped.contains(_ptMap[id]?.sessionId)) return false;
        _ptMap.remove(id);
        return true;
      });
    }
  }

  /// 清空某个 SESSION 的记录，但保留 SESSION 条目（历史里显示 0 条）
  void _clearSessionRecords(String sid) {
    _reqOrder.removeWhere((id) {
      if (_reqMap[id]?.sessionId == sid) {
        _reqMap.remove(id);
        return true;
      }
      return false;
    });
    _ptOrder.removeWhere((id) {
      if (_ptMap[id]?.sessionId == sid) {
        _ptMap.remove(id);
        return true;
      }
      return false;
    });
  }

  // ---- 收藏 ----
  void toggleFavorite(String id) {
    final rec = _reqMap[id];
    if (rec == null) return;
    _reqMap[id] = rec.copyWith(isFavorite: !rec.isFavorite);
    notifyListeners();
    _persist();
  }

  // ---- 历史/清空 ----
  void clearHistory() {
    _reqMap.clear();
    _reqOrder.clear();
    _ptMap.clear();
    _ptOrder.clear();
    _sessions.clear();
    _currentNativeSessionId = '';
    notifyListeners();
    _persist();
  }

  /// 清空「本次」记录：历史会话保留（对应抓包页的垃圾桶按钮）
  void clearCurrentRecords() {
    final sid = _currentNativeSessionId.isNotEmpty
        ? _currentNativeSessionId
        : (_sessions.isNotEmpty ? _sessions.first.id : '');
    if (sid.isEmpty) {
      _reqMap.clear();
      _reqOrder.clear();
      _ptMap.clear();
      _ptOrder.clear();
    } else {
      _clearSessionRecords(sid);
    }
    notifyListeners();
    _persist();
  }

  // ---- Hosts / 过滤 / 证书（转发原生） ----
  Future<void> installCa() async {
    try {
      await _methodChannel.invokeMethod('installCa');
    } catch (_) {}
  }

  /// 导出 CA 证书到下载目录。返回下载路径（成功）或错误信息（失败）。
  Future<String?> exportCa() async {
    try {
      final r = await _methodChannel.invokeMethod<String>('exportCa');
      return r;
    } catch (e) {
      return '导出失败：$e';
    }
  }

  Future<void> clearMitmCache() async {
    try {
      await _methodChannel.invokeMethod('clearMitmCache');
    } catch (_) {}
  }

  Future<void> setFilter(CaptureFilter f) async {
    try {
      await _methodChannel.invokeMethod('setFilter', f.toJson());
    } catch (_) {}
  }

  /// 清空全部日志（同时删除原生落盘文件）
  Future<void> clearLogs() async {
    _logCache.clear();
    _logList.clear();
    try {
      await _methodChannel.invokeMethod('clearLogs');
    } catch (_) {}
    notifyListeners();
  }

  List<LogFile> get logFiles => List.unmodifiable(_logList);

  String? logContent(String name) => _logCache[name];

  /// 从原生拉取日志文件列表（文件名 / 大小 / 修改时间）
  Future<void> refreshLogs() async {
    try {
      final raw = await _methodChannel.invokeMethod<List<dynamic>>('getLogs');
      if (raw == null) return;
      final list = <LogFile>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final name = (m['name'] as String?) ?? '';
        if (name.isEmpty) continue;
        final size = (m['size'] as num?)?.toInt() ?? 0;
        final ms = (m['time'] as num?)?.toInt() ?? 0;
        list.add(LogFile(
            name,
            ms > 0 ? DateTime.fromMillisecondsSinceEpoch(ms) : DateTime.now(),
            size));
      }
      _logList
        ..clear()
        ..addAll(list);
      // VPN 授权失败这类问题是 Dart 侧合成的，原生没有对应文件：单独补一条，别让用户看不到原因
      final vpnError = _logCache['vpn_error.log'];
      if (vpnError != null && !_logList.any((l) => l.name == 'vpn_error.log')) {
        _logList.insert(0, LogFile('vpn_error.log', DateTime.now(), vpnError.length));
      }
      // 已被删除的文件，缓存里也一并清掉
      final names = _logList.map((l) => l.name).toSet();
      _logCache.removeWhere((k, _) => !names.contains(k) && k != 'vpn_error.log');
      notifyListeners();
    } catch (_) {}
  }

  /// 读取某个日志文件全文
  Future<String> readLog(String name) async {
    try {
      final content = await _methodChannel.invokeMethod<String>('readLog', name);
      if (content != null) {
        _logCache[name] = content;
        return content;
      }
    } catch (_) {}
    return _logCache[name] ?? '';
  }

  Future<void> setWindowMode(bool on) async {
    try {
      await _methodChannel.invokeMethod('setWindowMode', on);
    } catch (_) {}
  }

  Future<void> setHttpsProxy(bool on) async {
    try {
      await _methodChannel.invokeMethod('setHttpsProxy', on);
    } catch (_) {}
  }

  // ---- 持久化 ----
  Timer? _persistTimer;
  bool _persisting = false;

  /// 抓包过程中节流落盘（5 秒），进程被杀也能把已有记录留在「抓包历史」里
  void _schedulePersist() {
    if (_persistTimer?.isActive ?? false) return;
    _persistTimer = Timer(const Duration(seconds: 5), () {
      _persistTimer = null;
      _persist();
    });
  }

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/capture_store.json');
  }

  Future<void> _persist() async {
    if (_persisting) return;
    _persisting = true;
    try {
      final f = await _file;
      final data = {
        'version': 2,
        'sessions': _sessions.take(_maxSessions).map((s) => s.toJson()).toList(),
        'records':
            _reqOrder.take(800).map((id) => _reqMap[id]!.toJson()).toList(),
        'passthrough':
            _ptOrder.take(800).map((id) => _ptMap[id]!.toJson()).toList(),
      };
      // 先写临时文件再改名：进程被杀时不会留下半截 JSON 导致历史彻底读不出来
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode(data), flush: true);
      await tmp.rename(f.path);
    } catch (_) {}
    _persisting = false;
  }

  Future<void> _loadPersisted() async {
    try {
      final f = await _file;
      if (!await f.exists()) return;
      final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final r in (data['records'] as List? ?? [])) {
        final rec = RequestRecord.fromJson(r);
        _reqMap[rec.id] = rec;
        _reqOrder.add(rec.id);
      }
      for (final p in (data['passthrough'] as List? ?? [])) {
        final rec = PassthroughRecord.fromJson(p);
        _ptMap[rec.id] = rec;
        _ptOrder.add(rec.id);
      }
      // 上次进程被杀时 SESSION 可能没来得及收尾：补上 endTime 并回填请求数，
      // 否则历史页会把它当"未结束"过滤掉，表现就是历史永远是空的。
      for (final s in (data['sessions'] as List? ?? [])) {
        final sess = CaptureSession.fromJson(s);
        final records = recordsOfSession(sess.id);
        // 进程被杀时 SESSION 没来得及收尾：用最后一条记录的时间补 endTime，
        // 否则历史页要么不显示（旧逻辑），要么时长显示 0 秒。
        var end = sess.endTime ?? sess.startTime;
        if (sess.endTime == null) {
          for (final r in records) {
            if (r.requestTime.isAfter(end)) end = r.requestTime;
          }
        }
        _sessions.add(CaptureSession(
          id: sess.id,
          startTime: sess.startTime,
          endTime: end,
          requestCount: records.isNotEmpty ? records.length : sess.requestCount,
        ));
      }
      _sessions.sort((a, b) => b.startTime.compareTo(a.startTime));
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _persistTimer?.cancel();
    _tickTimer?.cancel();
    try {
      _eventSub.cancel();
    } catch (_) {}
    super.dispose();
  }
}
