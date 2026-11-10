import 'dart:convert';
import 'package:packet_sniffing/models/capture_models.dart';

/// 生成 cURL 命令
String buildCurl(RequestRecord r) {
  final buf = StringBuffer();
  buf.write("curl -X ${r.method} '${r.url}'");
  r.requestHeaders.forEach((k, v) {
    buf.write(" \\\n  -H '$k: $v'");
  });
  if (r.requestBody != null && r.requestBody!.isNotEmpty) {
    final body = r.requestBody!.replaceAll("'", "'\\''");
    buf.write(" \\\n  -d '$body'");
  }
  return buf.toString();
}

/// 导出 HAR（单条记录）
String buildHar(List<RequestRecord> records) {
  final entries = records.map((r) {
    return {
      'request': {
        'method': r.method,
        'url': r.url,
        'headers': r.requestHeaders.entries
            .map((e) => {'name': e.key, 'value': e.value})
            .toList(),
        'body': r.requestBody ?? '',
      },
      'response': {
        'status': r.statusCode,
        'headers': r.responseHeaders.entries
            .map((e) => {'name': e.key, 'value': e.value})
            .toList(),
        'body': r.responseBody ?? '',
      },
      'time': r.durationMs,
      'timings': {'receive': r.durationMs},
    };
  }).toList();

  final har = {
    'log': {
      'version': '1.2',
      'creator': {'name': 'PacketSniffer', 'version': '0.1'},
      'entries': entries,
    }
  };
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(har);
}

/// JSON 美化（失败则原样返回）
String prettyJson(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  try {
    final obj = jsonDecode(raw);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(obj);
  } catch (_) {
    return raw;
  }
}

bool looksLikeJson(String? s) {
  if (s == null || s.isEmpty) return false;
  final t = s.trim();
  return t.startsWith('{') || t.startsWith('[');
}
