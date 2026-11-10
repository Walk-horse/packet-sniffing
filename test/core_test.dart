import 'package:flutter_test/flutter_test.dart';
import 'package:packet_sniffing/models/capture_models.dart';
import 'package:packet_sniffing/utils/curl_parser.dart';
import 'package:packet_sniffing/utils/export_utils.dart';
import 'package:packet_sniffing/utils/rsa.dart';

void main() {
  test('RSA-2048 加解密往返（OAEP/SHA-256）', () {
    final kp = generateRSAKeyPair();
    const plain = '抓包精灵 hello rsa 123';
    final cipher = rsaEncrypt(kp.publicKey, plain);
    expect(cipher.isNotEmpty, true);
    expect(rsaDecrypt(kp.privateKey, cipher), plain);

    // 密钥编解码往返
    final pub = decodePublicKey(encodePublicKey(kp.publicKey));
    final pri = decodePrivateKey(encodePrivateKey(kp.privateKey));
    final c2 = rsaEncrypt(pub, plain);
    expect(rsaDecrypt(pri, c2), plain);
  });

  test('curl 解析：方法/URL/头/体', () {
    final p = parseCurl(
      "curl -X POST 'https://api.example.com/v1/orders' "
      "-H 'Content-Type: application/json' -d '{\"id\":1}'",
    );
    expect(p.method, 'POST');
    expect(p.url, 'https://api.example.com/v1/orders');
    expect(p.headers['Content-Type'], 'application/json');
    expect(p.body, '{"id":1}');
  });

  test('curl 解析：裸 URL 默认 GET', () {
    final p = parseCurl('https://a.com/x?y=1');
    expect(p.method, 'GET');
    expect(p.url, 'https://a.com/x?y=1');
  });

  test('导出 curl / HAR / JSON 美化', () {
    final r = RequestRecord(
      id: '1',
      sessionId: 's1',
      method: 'POST',
      scheme: 'https',
      host: 'api.example.com',
      path: '/v1/orders',
      requestTime: DateTime(2026, 10, 30, 15, 0, 0),
      durationMs: 120,
      statusCode: 200,
      requestHeaders: {'Content-Type': 'application/json'},
      requestBody: '{"a":1}',
      responseBody: '{"ok":true}',
      requestSize: 7,
      responseSize: 11,
    );
    final curl = buildCurl(r);
    expect(curl.contains('https://api.example.com/v1/orders'), true);
    expect(curl.contains('-X POST'), true);

    final har = buildHar([r]);
    expect(har.contains('"log"'), true);
    expect(har.contains('api.example.com'), true);

    expect(prettyJson('{"a":1}').contains('\n'), true);
  });
}
