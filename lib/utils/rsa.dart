import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// RSA-2048 工具（OAEP + SHA-256）。密钥以自有的可复制字符串格式保存，便于在本 App 内导入/导出。
AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> generateRSAKeyPair() {
  final keyGen = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 12),
      _secureRandom(),
    ));
  // pointycastle 返回的是 AsymmetricKeyPair<PublicKey, PrivateKey>，
  // 直接强转会在运行时抛 type cast 错误，这里逐字段重建。
  final pair = keyGen.generateKeyPair();
  return AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>(
    pair.publicKey as RSAPublicKey,
    pair.privateKey as RSAPrivateKey,
  );
}

SecureRandom _secureRandom() {
  final sr = SecureRandom('Fortuna')..seed(KeyParameter(_seed()));
  return sr;
}

Uint8List _seed() {
  final r = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
}

String rsaEncrypt(RSAPublicKey pub, String plain) {
  final oaep = OAEPEncoding.withSHA256(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(pub));
  final out = oaep.process(utf8.encode(plain));
  return base64Encode(out);
}

String rsaDecrypt(RSAPrivateKey priv, String b64) {
  final oaep = OAEPEncoding.withSHA256(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(priv));
  final out = oaep.process(base64Decode(b64));
  return utf8.decode(out);
}

String encodePublicKey(RSAPublicKey k) => base64.encode(
    utf8.encode('${k.modulus!.toRadixString(16)}|${k.exponent!.toRadixString(16)}'));

String encodePrivateKey(RSAPrivateKey k) => base64.encode(utf8.encode(
    '${k.modulus!.toRadixString(16)}|${k.privateExponent!.toRadixString(16)}|'
    '${k.p?.toRadixString(16) ?? ''}|${k.q?.toRadixString(16) ?? ''}'));

RSAPublicKey decodePublicKey(String s) {
  final p = utf8.decode(base64.decode(s)).split('|');
  return RSAPublicKey(BigInt.parse(p[0], radix: 16), BigInt.parse(p[1], radix: 16));
}

RSAPrivateKey decodePrivateKey(String s) {
  final p = utf8.decode(base64.decode(s)).split('|');
  if (p.length < 4 || p[2].isEmpty || p[3].isEmpty) {
    throw const FormatException('私钥格式不正确：需要包含 p、q 参数（请在 App 内重新生成密钥）');
  }
  return RSAPrivateKey(
    BigInt.parse(p[0], radix: 16),
    BigInt.parse(p[1], radix: 16),
    BigInt.parse(p[2], radix: 16),
    BigInt.parse(p[3], radix: 16),
  );
}
