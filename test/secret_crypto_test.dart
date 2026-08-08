import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/util/secret_crypto.dart';
import 'package:tabame/platform/secret_store.dart';
import 'package:tabame/platform/windows_secret_store.dart';

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

  group('SecretStore unavailable boundary', () {
    test('keeps machine-bound storage explicit instead of downgrading it', () {
      const UnavailableSecretStore store = UnavailableSecretStore();

      expect(store.isAvailable, isFalse);
      expect(store.requiresReentry, isTrue);
      expect(
        () => store.sealWithMachineKey('secret'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
      expect(store.unprotectField('legacy-plaintext'), 'legacy-plaintext');
      expect(
        () => store.unprotectField('${SecretCrypto.dpapiFieldPrefix}not-readable-here'),
        throwsA(isA<SecretStoreUnavailableException>()),
      );
    });
  });

  if (Platform.isWindows) {
    group('WindowsSecretStore DPAPI adapter', () {
      test('round-trips machine-key sealing on Windows', () {
        const String secret = '[{"issuer":"acme","secret":"JBSWY3DPEHPK3PXP"}]';
        final Map<String, dynamic> envelope = WindowsSecretStore.instance.sealWithMachineKey(secret);

        expect(envelope['kdf'], SecretCrypto.dpapiKdf);
        expect(envelope['data'], isNot(contains('JBSWY3DPEHPK3PXP')));
        expect(WindowsSecretStore.instance.openWithMachineKey(envelope), secret);
      });

      test('protects and restores a field on Windows', () {
        const String password = 's3rv3r-p@ss';
        final String protectedValue = WindowsSecretStore.instance.protectField(password);

        expect(SecretCrypto.isProtectedField(protectedValue), isTrue);
        expect(protectedValue, isNot(contains(password)));
        expect(WindowsSecretStore.instance.unprotectField(protectedValue), password);
        expect(WindowsSecretStore.instance.protectField(''), '');
        expect(SecretCrypto.isProtectedField('legacy-plaintext'), isFalse);
      });
    });
  }
}
