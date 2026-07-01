import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/util/secret_crypto.dart';

void main() {
  group('SecretCrypto password sealing (PBKDF2 + AES-GCM)', () {
    test('round-trips the plaintext with the correct password', () {
      const String secret = '{"items":[{"name":"github","value":"hunter2"}]}';
      final Map<String, dynamic> envelope = SecretCrypto.sealWithPassword(secret, 'correct horse');

      expect(envelope['kdf'], SecretCrypto.pbkdf2Kdf);
      expect(envelope['data'], isNot(contains('hunter2'))); // not stored in cleartext
      expect(SecretCrypto.openWithPassword(envelope, 'correct horse'), secret);
    });

    test('returns null for a wrong password (GCM integrity, no exception)', () {
      final Map<String, dynamic> envelope = SecretCrypto.sealWithPassword('top secret', 'right');
      expect(SecretCrypto.openWithPassword(envelope, 'wrong'), isNull);
    });

    test('returns null when the ciphertext is tampered with', () {
      final Map<String, dynamic> envelope = SecretCrypto.sealWithPassword('top secret', 'pw');
      final Uint8List bytes = base64Decode(envelope['data'] as String);
      bytes[0] = bytes[0] ^ 0xff; // flip a byte -> tag check must fail
      envelope['data'] = base64Encode(bytes);
      expect(SecretCrypto.openWithPassword(envelope, 'pw'), isNull);
    });

    test('uses a fresh salt and IV per seal', () {
      final Map<String, dynamic> a = SecretCrypto.sealWithPassword('same', 'pw');
      final Map<String, dynamic> b = SecretCrypto.sealWithPassword('same', 'pw');
      expect(a['salt'], isNot(b['salt']));
      expect(a['iv'], isNot(b['iv']));
      expect(a['data'], isNot(b['data']));
    });
  });

  group('SecretCrypto machine-key sealing (DPAPI)', () {
    test('round-trips the plaintext on this machine', () {
      const String secret = '[{"issuer":"acme","secret":"JBSWY3DPEHPK3PXP"}]';
      final Map<String, dynamic> envelope = SecretCrypto.sealWithMachineKey(secret);

      expect(envelope['kdf'], SecretCrypto.dpapiKdf);
      expect(envelope['data'], isNot(contains('JBSWY3DPEHPK3PXP')));
      expect(SecretCrypto.openWithMachineKey(envelope), secret);
    });
  });

  group('SecretCrypto field protection (DPAPI)', () {
    test('protect/unprotect is an identity round-trip', () {
      const String password = 's3rv3r-p@ss';
      final String protectedValue = SecretCrypto.protectField(password);

      expect(SecretCrypto.isProtectedField(protectedValue), isTrue);
      expect(protectedValue, isNot(contains(password)));
      expect(SecretCrypto.unprotectField(protectedValue), password);
    });

    test('empty stays empty and is never marked protected', () {
      expect(SecretCrypto.protectField(''), '');
      expect(SecretCrypto.isProtectedField(''), isFalse);
    });

    test('legacy plaintext passes through unprotectField unchanged', () {
      expect(SecretCrypto.unprotectField('legacy-plaintext'), 'legacy-plaintext');
    });

    test('does not double-protect an already protected value', () {
      final String once = SecretCrypto.protectField('value');
      expect(SecretCrypto.protectField(once), once);
    });
  });

  group('SecretCrypto legacy migration read path', () {
    test('decrypts the old unsalted sha256 + AES-CBC format', () {
      // Reproduce exactly how vault/authenticator files used to be sealed.
      const String plaintext = '{"legacy":true}';
      const String password = 'n0p@s5';
      final Key key = Key(Uint8List.fromList(sha256.convert(utf8.encode(password)).bytes));
      final IV iv = IV.fromSecureRandom(16);
      final Encrypted encrypted = Encrypter(AES(key, mode: AESMode.cbc)).encrypt(plaintext, iv: iv);

      expect(
        SecretCrypto.legacyDecryptCbcSha256(iv.base64, encrypted.base64, password),
        plaintext,
      );
      expect(
        SecretCrypto.legacyDecryptCbcSha256(iv.base64, encrypted.base64, 'wrong'),
        isNot(plaintext),
      );
    });
  });
}
