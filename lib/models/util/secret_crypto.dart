import 'dart:convert';
import 'dart:ffi';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' as win32;

/// Versioned, authenticated secret-at-rest helpers shared by the vault and the
/// authenticator.
///
/// Two sealing strategies are provided:
///
///  * [sealWithPassword] / [openWithPassword] — PBKDF2-HMAC-SHA256 (salted, many
///    iterations) feeding AES-256-**GCM**. Use when the user supplies a
///    passphrase. GCM is authenticated, so tampering/corruption is detected on
///    open (a wrong password simply fails the tag check and returns `null`).
///
///  * [sealWithMachineKey] / [openWithMachineKey] — Windows **DPAPI** in
///    current-user scope. Use when there is no user passphrase. The ciphertext
///    is bound to the Windows account and cannot be decrypted by other users or
///    on another machine, which replaces the previous "encrypt with a constant
///    password baked into the source" behaviour.
///
/// [protectField] / [unprotectField] wrap a single string value with DPAPI for
/// places that must keep a usable secret around (e.g. a Subsonic password the
/// app has to replay) but should not store it as plaintext.
class SecretCrypto {
  SecretCrypto._();

  static const int envelopeVersion = 2;
  static const String pbkdf2Kdf = 'pbkdf2-sha256';
  static const String dpapiKdf = 'dpapi';

  static const int _pbkdf2Iterations = 120000;
  static const int _saltLength = 16;
  static const int _ivLength = 12; // 96-bit GCM nonce (standard)
  static const int _keyLength = 32; // AES-256
  static const int _hashLength = 32; // SHA-256 output

  // CRYPTPROTECT_UI_FORBIDDEN — the win32 package does not export the constant.
  static const int _cryptProtectUiForbidden = 0x1;

  static const String _fieldPrefix = 'dpapi:v1:';

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

  // ---------------------------------------------------------------------------
  // Machine-bound sealing (DPAPI, current-user scope)
  // ---------------------------------------------------------------------------

  static Map<String, dynamic> sealWithMachineKey(String plaintext) {
    final Uint8List? sealed = _dpapi(Uint8List.fromList(utf8.encode(plaintext)), protect: true);
    if (sealed == null) {
      throw StateError('DPAPI CryptProtectData failed.');
    }
    return <String, dynamic>{
      'v': envelopeVersion,
      'kdf': dpapiKdf,
      'data': base64Encode(sealed),
    };
  }

  static String? openWithMachineKey(Map<String, dynamic> envelope) {
    try {
      final Uint8List? plain = _dpapi(base64Decode(envelope['data'] as String), protect: false);
      if (plain == null) return null;
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Single-field DPAPI protection (e.g. replayable server passwords)
  // ---------------------------------------------------------------------------

  static bool isProtectedField(String stored) => stored.startsWith(_fieldPrefix);

  /// DPAPI-protects [value], returning a self-describing `dpapi:v1:<base64>`
  /// string. Empty or already-protected values are returned unchanged. If DPAPI
  /// is somehow unavailable the original value is returned so the caller does
  /// not silently lose data (DPAPI does not fail in practice on Windows).
  static String protectField(String value) {
    if (value.isEmpty || isProtectedField(value)) return value;
    final Uint8List? sealed = _dpapi(Uint8List.fromList(utf8.encode(value)), protect: true);
    if (sealed == null) return value;
    return '$_fieldPrefix${base64Encode(sealed)}';
  }

  /// Reverses [protectField]. A value without the prefix is assumed to be legacy
  /// plaintext and returned as-is (so existing configs keep working until the
  /// next save re-protects them).
  static String unprotectField(String stored) {
    if (!isProtectedField(stored)) return stored;
    try {
      final Uint8List? plain = _dpapi(base64Decode(stored.substring(_fieldPrefix.length)), protect: false);
      if (plain == null) return '';
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

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

  static Uint8List? _dpapi(Uint8List input, {required bool protect}) {
    if (input.isEmpty) return null;
    return using<Uint8List?>((Arena arena) {
      final Pointer<win32.CRYPT_INTEGER_BLOB> blobIn = arena<win32.CRYPT_INTEGER_BLOB>();
      final Pointer<Uint8> inBuffer = arena<Uint8>(input.length);
      inBuffer.asTypedList(input.length).setAll(0, input);
      blobIn.ref
        ..cbData = input.length
        ..pbData = inBuffer;

      final Pointer<win32.CRYPT_INTEGER_BLOB> blobOut = arena<win32.CRYPT_INTEGER_BLOB>();

      final int ok = protect
          ? win32.CryptProtectData(
              blobIn, nullptr, nullptr, nullptr, nullptr, _cryptProtectUiForbidden, blobOut)
          : win32.CryptUnprotectData(
              blobIn, nullptr, nullptr, nullptr, nullptr, _cryptProtectUiForbidden, blobOut);
      if (ok == 0) return null;

      try {
        return Uint8List.fromList(blobOut.ref.pbData.asTypedList(blobOut.ref.cbData));
      } finally {
        // The output buffer is allocated by Windows and must be released here.
        win32.LocalFree(blobOut.ref.pbData);
      }
    });
  }
}
