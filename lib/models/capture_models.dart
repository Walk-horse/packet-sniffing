import 'dart:convert';
import 'package:intl/intl.dart';

/// 一次抓包记录（对应参考 App 的 RequestRecord）
class RequestRecord {
  final String id;
  final String sessionId;
  final String method;
  final String scheme; // http / https
  final String host;
  final String path;
  final int? port;
  final int statusCode;
  final DateTime requestTime;
  final int durationMs;
  final Map<String, String> requestHeaders;
  final Map<String, String> responseHeaders;
  final String? requestBody;
  final String? responseBody;
  final int requestSize;
  final int responseSize;
  final String localAddress;
  final String remoteAddress;
  final bool isError;
  final String? errorReason;
  final bool isFavorite;
  final String contentType;
  final bool isTls;
  final bool mocked;
  final int uid;
  final String appPackage;
  final String appLabel;

  RequestRecord({
    required this.id,
    required this.sessionId,
    required this.method,
    required this.scheme,
    required this.host,
    required this.path,
    this.port,
    this.statusCode = 0,
    required this.requestTime,
    this.durationMs = 0,
    this.requestHeaders = const {},
    this.responseHeaders = const {},
    this.requestBody,
    this.responseBody,
    this.requestSize = 0,
    this.responseSize = 0,
    this.localAddress = '',
    this.remoteAddress = '',
    this.isError = false,
    this.errorReason,
    this.isFavorite = false,
    this.contentType = '',
    this.isTls = false,
    this.mocked = false,
    this.uid = -1,
    this.appPackage = '',
    this.appLabel = '',
  });

  String get url {
    final p = port != null && port != 80 && port != 443 ? ':$port' : '';
    return '$scheme://$host$p$path';
  }

  /// 非 HTTP 的裸连接（TCP/UDP 隧道），没有状态码与路径语义
  bool get isTunnel => method == 'TCP' || method == 'UDP';

  String get displayPath {
    // 隧道记录（HTTPS SNI / 裸 TCP）没有 path 语义，标题直接显示 host（域名或 IP）
    if (isTunnel) return host;
    final idx = path.indexOf('?');
    return idx < 0 ? path : path.substring(0, idx);
  }

  factory RequestRecord.fromJson(Map<String, dynamic> j) => RequestRecord(
        // 原生侧回传完整解析结果，id 缺失时兜底，避免整条流因一条脏数据中断
        id: (j['id'] as String?) ??
            '${DateTime.now().microsecondsSinceEpoch}_${j['host'] ?? ''}',
        sessionId: j['sessionId'] ?? '',
        method: (j['method'] as String?)?.toUpperCase() ?? 'GET',
        scheme: j['scheme'] ?? 'https',
        host: j['host'] ?? '',
        path: j['path'] ?? '/',
        port: j['port'],
        statusCode: j['statusCode'] ?? 0,
        requestTime: j['requestTime'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['requestTime'] as num).toInt())
            : DateTime.now(),
        durationMs: j['durationMs'] ?? 0,
        requestHeaders: Map<String, String>.from(j['requestHeaders'] ?? {}),
        responseHeaders: Map<String, String>.from(j['responseHeaders'] ?? {}),
        requestBody: _decodeBody(j['requestBody']),
        responseBody: _decodeBody(j['responseBody']),
        requestSize: j['requestSize'] ?? 0,
        responseSize: j['responseSize'] ?? 0,
        localAddress: j['localAddress'] ?? '',
        remoteAddress: j['remoteAddress'] ?? '',
        isError: j['isError'] ?? false,
        errorReason: j['errorReason'],
        isFavorite: j['isFavorite'] ?? false,
        contentType: j['contentType'] ?? '',
        isTls: j['isTls'] ?? false,
        mocked: j['mocked'] ?? false,
        uid: j['uid'] ?? -1,
        appPackage: j['appPackage'] ?? '',
        appLabel: j['appLabel'] ?? '',
      );

  /// 原生回传的 body 是 base64（可能已 gzip 解压后的字节），解码为文本展示
  static String? _decodeBody(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) {
      try {
        return utf8.decode(base64Decode(v), allowMalformed: true);
      } catch (_) {
        return v;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'method': method,
        'scheme': scheme,
        'host': host,
        'path': path,
        'port': port,
        'statusCode': statusCode,
        'requestTime': requestTime.millisecondsSinceEpoch,
        'durationMs': durationMs,
        'requestHeaders': requestHeaders,
        'responseHeaders': responseHeaders,
        'requestBody': requestBody,
        'responseBody': responseBody,
        'requestSize': requestSize,
        'responseSize': responseSize,
        'localAddress': localAddress,
        'remoteAddress': remoteAddress,
        'isError': isError,
        'errorReason': errorReason,
        'isFavorite': isFavorite,
        'contentType': contentType,
        'isTls': isTls,
        'mocked': mocked,
        'uid': uid,
        'appPackage': appPackage,
        'appLabel': appLabel,
      };

  RequestRecord copyWith({bool? isFavorite, String? id, String? sessionId}) =>
      RequestRecord(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        method: method,
        scheme: scheme,
        host: host,
        path: path,
        port: port,
        statusCode: statusCode,
        requestTime: requestTime,
        durationMs: durationMs,
        requestHeaders: requestHeaders,
        responseHeaders: responseHeaders,
        requestBody: requestBody,
        responseBody: responseBody,
        requestSize: requestSize,
        responseSize: responseSize,
        localAddress: localAddress,
        remoteAddress: remoteAddress,
        isError: isError,
        errorReason: errorReason,
        isFavorite: isFavorite ?? this.isFavorite,
        contentType: contentType,
        isTls: isTls,
        mocked: mocked,
        uid: uid,
        appPackage: appPackage,
        appLabel: appLabel,
      );
}

/// 一条未解密（透传）的 TCP 连接记录（黑/白名单排除、非 HTTP 流量等）
class PassthroughRecord {
  final String id;
  final String sessionId;
  final String host;
  final int port;
  final bool tls;
  final String reason;
  final int uid;
  final String appPackage;
  final String appLabel;
  final DateTime startTime;
  final DateTime? endTime;
  final int upBytes;
  final int downBytes;

  PassthroughRecord({
    required this.id,
    required this.sessionId,
    required this.host,
    required this.port,
    required this.tls,
    required this.reason,
    this.uid = -1,
    this.appPackage = '',
    this.appLabel = '',
    required this.startTime,
    this.endTime,
    this.upBytes = 0,
    this.downBytes = 0,
  });

  int get durationMs =>
      (endTime ?? DateTime.now()).difference(startTime).inMilliseconds;

  PassthroughRecord copyWith({String? sessionId}) => PassthroughRecord(
        id: id,
        sessionId: sessionId ?? this.sessionId,
        host: host,
        port: port,
        tls: tls,
        reason: reason,
        uid: uid,
        appPackage: appPackage,
        appLabel: appLabel,
        startTime: startTime,
        endTime: endTime,
        upBytes: upBytes,
        downBytes: downBytes,
      );

  factory PassthroughRecord.fromJson(Map<String, dynamic> j) => PassthroughRecord(
        id: (j['id'] as String?) ??
            '${DateTime.now().microsecondsSinceEpoch}_${j['host'] ?? ''}',
        sessionId: j['sessionId'] ?? '',
        host: j['host'] ?? '',
        port: j['port'] ?? 0,
        tls: j['tls'] ?? false,
        reason: j['reason'] ?? '',
        uid: j['uid'] ?? -1,
        appPackage: j['appPackage'] ?? '',
        appLabel: j['appLabel'] ?? '',
        startTime: j['startTime'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['startTime'] as num).toInt())
            : DateTime.now(),
        endTime: j['endTime'] is num
            ? DateTime.fromMillisecondsSinceEpoch((j['endTime'] as num).toInt())
            : null,
        upBytes: (j['upBytes'] as num?)?.toInt() ?? 0,
        downBytes: (j['downBytes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'host': host,
        'port': port,
      'tls': tls,
      'reason': reason,
      'uid': uid,
      'appPackage': appPackage,
      'appLabel': appLabel,
      'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime?.millisecondsSinceEpoch,
        'upBytes': upBytes,
        'downBytes': downBytes,
      };
}

/// 按应用（uid）分组后的聚合视图，用于「按应用」Tab。
class AppGroup {
  final int uid;
  final String package;
  final String label;
  final List<RequestRecord> requests;
  final List<PassthroughRecord> passthroughs;

  AppGroup({
    required this.uid,
    this.package = '',
    this.label = '',
    List<RequestRecord>? requests,
    List<PassthroughRecord>? passthroughs,
  })  : requests = requests ?? [],
        passthroughs = passthroughs ?? [];

  int get totalCount => requests.length + passthroughs.length;

  /// 展示名：优先应用显示名 → 包名 → UID → 未知应用
  String get displayName {
    if (label.isNotEmpty) return label;
    if (package.isNotEmpty) return package;
    return uid >= 0 ? 'UID $uid' : '未知应用';
  }
}

/// 抓包 SESSION（一次开始/停止为一个批次）
class CaptureSession {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final int requestCount;

  CaptureSession({
    required this.id,
    required this.startTime,
    this.endTime,
    this.requestCount = 0,
  });

  int get durationSec =>
      (endTime ?? DateTime.now()).difference(startTime).inSeconds;

  factory CaptureSession.fromJson(Map<String, dynamic> j) => CaptureSession(
        id: j['id'],
        startTime:
            DateTime.fromMillisecondsSinceEpoch((j['startTime'] as num).toInt()),
        endTime: j['endTime'] != null
            ? DateTime.fromMillisecondsSinceEpoch((j['endTime'] as num).toInt())
            : null,
        requestCount: j['requestCount'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.millisecondsSinceEpoch,
        'endTime': endTime?.millisecondsSinceEpoch,
        'requestCount': requestCount,
      };
}

/// 抓包模式（黑白名单）
class CaptureFilter {
  bool blacklistEnabled;
  bool whitelistEnabled;
  bool quicFallback;
  List<String> blacklist;
  List<String> whitelist;
  CaptureFilter({
    this.blacklistEnabled = false,
    this.whitelistEnabled = false,
    this.quicFallback = true,
    this.blacklist = const [],
    this.whitelist = const [],
  });

  factory CaptureFilter.fromJson(Map<String, dynamic> j) => CaptureFilter(
        blacklistEnabled: j['blacklistEnabled'] ?? false,
        whitelistEnabled: j['whitelistEnabled'] ?? false,
        quicFallback: j['quicFallback'] ?? true,
        blacklist: List<String>.from(j['blacklist'] ?? []),
        whitelist: List<String>.from(j['whitelist'] ?? []),
      );
  Map<String, dynamic> toJson() => {
        'blacklistEnabled': blacklistEnabled,
        'whitelistEnabled': whitelistEnabled,
        'quicFallback': quicFallback,
        'blacklist': blacklist,
        'whitelist': whitelist,
      };
}

/// 日志文件描述
class LogFile {
  final String name;
  final DateTime createdAt;
  final int size;
  LogFile(this.name, this.createdAt, this.size);
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0B';
  const units = ['B', 'KB', 'MB', 'GB'];
  int i = 0;
  double v = bytes.toDouble();
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 10 || i == 0 ? 0 : 1)}${units[i]}';
}

String formatTime(DateTime t) =>
    DateFormat('MM-dd HH:mm:ss').format(t);

String formatDuration(int ms) {
  if (ms < 1000) return '${ms}ms';
  return '${(ms / 1000).toStringAsFixed(2)}s';
}
