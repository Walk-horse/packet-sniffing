/// 极简 curl 命令解析（支持 -X/-d/-H/--data/--header 及裸 URL）。
class ParsedCurl {
  final String method;
  final String url;
  final Map<String, String> headers;
  final String? body;
  ParsedCurl(
      {required this.method, required this.url, this.headers = const {}, this.body});
}

ParsedCurl parseCurl(String input) {
  var s = input.trim();
  if (s.startsWith('curl')) s = s.substring(4).trim();

  // 简易分词（支持单/双引号）
  final tokens = <String>[];
  var i = 0;
  while (i < s.length) {
    if (s[i] == ' ' || s[i] == '\n' || s[i] == '\t') {
      i++;
      continue;
    }
    var buf = StringBuffer();
    var quote = '';
    if (s[i] == "'" || s[i] == '"') {
      quote = s[i];
      i++;
    }
    while (i < s.length) {
      if (quote.isNotEmpty) {
        if (s[i] == quote) {
          i++;
          break;
        }
        buf.write(s[i]);
        i++;
      } else {
        if (s[i] == ' ' || s[i] == '\n' || s[i] == '\t') break;
        buf.write(s[i]);
        i++;
      }
    }
    tokens.add(buf.toString());
  }

  String method = 'GET';
  String? url;
  final headers = <String, String>{};
  String? body;
  String? userPass;

  for (var k = 0; k < tokens.length; k++) {
    final t = tokens[k];
    if (t == '-X' || t == '--request') {
      if (k + 1 < tokens.length) method = tokens[++k].toUpperCase();
    } else if (t == '-H' || t == '--header') {
      if (k + 1 < tokens.length) {
        final h = tokens[++k];
        final idx = h.indexOf(':');
        if (idx > 0) {
          headers[h.substring(0, idx).trim()] = h.substring(idx + 1).trim();
        }
      }
    } else if (t == '-d' ||
        t == '--data' ||
        t == '--data-raw' ||
        t == '--data-binary' ||
        t == '--data-urlencode') {
      if (k + 1 < tokens.length) body = tokens[++k];
      if (method == 'GET') method = 'POST';
    } else if (t == '-u' || t == '--user') {
      if (k + 1 < tokens.length) userPass = tokens[++k];
    } else if (t == '--url') {
      if (k + 1 < tokens.length) url = tokens[++k];
    } else if (!t.startsWith('-') && url == null) {
      url = t;
    }
  }

  if (userPass != null && !headers.containsKey('Authorization')) {
    final bytes = userPass.codeUnits;
    final b64 = _b64(bytes);
    headers['Authorization'] = 'Basic $b64';
  }

  return ParsedCurl(
      method: method, url: url ?? '', headers: headers, body: body);
}

String _b64(List<int> bytes) {
  // 内联 Base64，避免额外依赖
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  final out = StringBuffer();
  for (var i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out.write(chars[b0 >> 2]);
    out.write(chars[((b0 & 3) << 4) | (b1 >> 4)]);
    out.write(i + 1 < bytes.length ? chars[((b1 & 15) << 2) | (b2 >> 6)] : '=');
    out.write(i + 2 < bytes.length ? chars[b2 & 63] : '=');
  }
  return out.toString();
}
