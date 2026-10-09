import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:fl_clash/common/common.dart';
import 'package:flutter_test/flutter_test.dart';

String _encryptLikeServer(String password, String plainText) {
  final passHash = md5.convert(utf8.encode(password)).toString();
  final key = encrypt.Key(
    Uint8List.fromList(
      List.generate(
        16,
        (i) => int.parse(passHash.substring(i * 2, i * 2 + 2), radix: 16),
      ),
    ),
  );
  final iv = encrypt.IV.fromSecureRandom(16);
  final encrypter = encrypt.Encrypter(
    encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
  );
  final secret = encrypter.encrypt(plainText, iv: iv);
  final raw = Uint8List.fromList([...iv.bytes, ...secret.bytes]);
  return base64Encode(raw);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recognizes the subscription-encryption header', () {
    expect(isSubscriptionEncrypted('true'), isTrue);
    expect(isSubscriptionEncrypted(' True \n'), isTrue);
    expect(isSubscriptionEncrypted('false'), isFalse);
    expect(isSubscriptionEncrypted(null), isFalse);
    expect(isSubscriptionEncrypted(''), isFalse);
  });

  test('decrypts an encrypted subscription payload', () {
    const password = 'site-password';
    const plain = 'mixed-port: 7890\nproxies: []\n';
    final payload = _encryptLikeServer(password, plain);

    final decrypted = tryDecryptSubscription(password, payload);

    expect(decrypted, isNotNull);
    expect(utf8.decode(decrypted!), plain);
  });

  test('tolerates line breaks inside the base64 payload', () {
    const password = 'site-password';
    final payload = _encryptLikeServer(password, 'proxies: []');
    final wrapped = payload.replaceAllMapped(
      RegExp('.{40}'),
      (match) => '${match.group(0)}\n',
    );

    expect(tryDecryptSubscription(password, wrapped), isNotNull);
  });

  test('a wrong password fails to decrypt', () {
    final payload = _encryptLikeServer('right', 'proxies: []');

    expect(tryDecryptSubscription('wrong', payload), isNull);
  });

  test('rejects malformed payloads', () {
    expect(tryDecryptSubscription('pwd', ''), isNull);
    expect(tryDecryptSubscription('', 'Zm9v'), isNull);
    expect(tryDecryptSubscription('pwd', 'not base64!'), isNull);
    expect(
      tryDecryptSubscription('pwd', base64Encode('short'.codeUnits)),
      isNull,
    );
  });
}
