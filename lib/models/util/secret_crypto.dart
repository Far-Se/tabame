import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

/// Portable password-based secret envelopes and legacy password migration.
///
/// This file deliberately contains no operating-system API. Machine-bound
/// sealing and field protection live behind [SecretStore] and its Windows
/// implementation so password-protected data can be opened on every target.
class SecretCrypto {
  SecretCrypto._();

  static const int envelopeVersion = 2;
  static const String pbkdf2Kdf = 'pbkdf2-sha256';

  /// Format identifiers are kept here because shared envelope readers need to
  /// recognize a Windows-bound value without implementing DPAPI.
  static const String dpapiKdf = 'dpapi';
  static const String dpapiFieldPrefix = 'dpapi:v1:';

  /// macOS uses a random AES key stored in the user's Keychain. The ciphertext
  /// remains in the existing JSON/settings files so callers can keep their
  /// synchronous SecretStore contract.
  static const String keychainKdf = 'keychain-aes-gcm';
  static const String keychainFieldPrefix = 'keychain:v1:';

  /// Linux uses a random AES key stored in the freedesktop Secret Service.
  /// Keep this distinct from the macOS Keychain envelope so a platform-bound
  /// value is never mistaken for a value that can be opened by another adapter.
  static const String secretServiceKdf = 'secret-service-aes-gcm';
  static const String secretServiceFieldPrefix = 'secret-service:v1:';

  static const int _pbkdf2Iterations = 120000;
  static const int _saltLength = 16;
  static const int _ivLength = 12; // 96-bit GCM nonce (standard)
  static const int _keyLength = 32; // AES-256
  static const int _hashLength = 32; // SHA-256 output

  static final Random _random = Random.secure();

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (int _) => _random.nextInt(256)));

  // ---------------------------------------------------------------------------
  // Password-based sealing (PBKDF2-HMAC-SHA256 -> AES-256-GCM)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> sealWithPassword(String plaintext, String password) {
    final Uint8List salt = _randomBytes(_saltLength);
    final Key key = Key(_pbkdf2(password, salt, _pbkdf2Iterations, _keyLength));
    final IV iv = IV(_randomBytes(_ivLength));
    final Encrypter encrypter = Encrypter(AES(key, mode: AESMode.gcm));
    final Encrypted encrypted = encrypter.encrypt(plaintext, iv: iv);
    return <String, dynamic>{
      'v': envelopeVersion,
      'kdf': pbkdf2Kdf,
      'iter': _pbkdf2Iterations,
      'salt': base64Encode(salt),
      'iv': iv.base64,
      'data': encrypted.base64,
    };
  }

  static String? openWithPassword(Map<String, dynamic> envelope, String password) {
    try {
      final int iterations = (envelope['iter'] as num?)?.toInt() ?? _pbkdf2Iterations;
      final Uint8List salt = base64Decode(envelope['salt'] as String);
      final Key key = Key(_pbkdf2(password, salt, iterations, _keyLength));
      final IV iv = IV.fromBase64(envelope['iv'] as String);
      final Encrypter encrypter = Encrypter(AES(key, mode: AESMode.gcm));
      return encrypter.decrypt(Encrypted.fromBase64(envelope['data'] as String), iv: iv);
    } catch (_) {
      // Wrong password (GCM tag mismatch), corrupt data, or malformed envelope.
      return null;
    }
  }

  /// Seals data with a random 256-bit key that is owned by a platform adapter.
  /// The macOS and Linux adapters obtain that key from their desktop secret
  /// stores during startup.
  static Map<String, dynamic> sealWithKey(
    String plaintext,
    Uint8List key, {
    String kdf = keychainKdf,
  }) {
    final IV iv = IV(_randomBytes(_ivLength));
    final Encrypter encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
    final Encrypted encrypted = encrypter.encrypt(plaintext, iv: iv);
    return <String, dynamic>{
      'v': envelopeVersion,
      'kdf': kdf,
      'iv': iv.base64,
      'data': encrypted.base64,
    };
  }

  static String? openWithKey(Map<String, dynamic> envelope, Uint8List key) {
    try {
      final IV iv = IV.fromBase64(envelope['iv'] as String);
      final Encrypter encrypter = Encrypter(AES(Key(key), mode: AESMode.gcm));
      return encrypter.decrypt(Encrypted.fromBase64(envelope['data'] as String), iv: iv);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Shared format helpers
  // ---------------------------------------------------------------------------

  static bool isProtectedField(String stored) => stored.startsWith(dpapiFieldPrefix);

  static bool isKeychainProtectedField(String stored) => stored.startsWith(keychainFieldPrefix);

  static bool isSecretServiceProtectedField(String stored) => stored.startsWith(secretServiceFieldPrefix);

  // ---------------------------------------------------------------------------
  // Legacy read path — old format was unsalted sha256(password) + AES-CBC.
  // Kept only so existing vault/authenticator files remain readable and can be
  // migrated forward on the next save.
  // ---------------------------------------------------------------------------

  static String? legacyDecryptCbcSha256(String ivBase64, String dataBase64, String password) {
    try {
      final Key key = Key(Uint8List.fromList(sha256.convert(utf8.encode(password)).bytes));
      final IV iv = IV.fromBase64(ivBase64);
      final Encrypter encrypter = Encrypter(AES(key, mode: AESMode.cbc));
      return encrypter.decrypt(Encrypted.fromBase64(dataBase64), iv: iv);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// PBKDF2-HMAC-SHA256, implemented on top of `package:crypto` so no extra
  /// dependency is required.
  static Uint8List _pbkdf2(String password, Uint8List salt, int iterations, int keyLength) {
    final Hmac hmac = Hmac(sha256, utf8.encode(password));
    final int blocks = (keyLength + _hashLength - 1) ~/ _hashLength;
    final Uint8List output = Uint8List(blocks * _hashLength);

    for (int block = 1; block <= blocks; block++) {
      final Uint8List blockIndex = Uint8List(4)
        ..[0] = (block >> 24) & 0xff
        ..[1] = (block >> 16) & 0xff
        ..[2] = (block >> 8) & 0xff
        ..[3] = block & 0xff;

      List<int> u = hmac.convert(<int>[...salt, ...blockIndex]).bytes;
      final Uint8List accumulator = Uint8List.fromList(u);
      for (int i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (int j = 0; j < _hashLength; j++) {
          accumulator[j] ^= u[j];
        }
      }
      output.setRange((block - 1) * _hashLength, block * _hashLength, accumulator);
    }

    return Uint8List.sublistView(output, 0, keyLength);
  }
}
