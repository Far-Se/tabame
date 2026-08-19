import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'windows/win32_api.dart' as win32;

import '../logic/error_handler.dart';
import '../models/util/secret_crypto.dart';
import 'secret_store.dart';

/// Windows DPAPI implementation of [SecretStore].
///
/// This is the only Phase 1 implementation that knows about DPAPI. The shared
/// vault, authenticator, and music models depend on [SecretStore] instead of
/// importing Win32 APIs directly.
class WindowsSecretStore implements SecretStore {
  WindowsSecretStore._();

  static final WindowsSecretStore instance = WindowsSecretStore._();

  // CRYPTPROTECT_UI_FORBIDDEN — the win32 package does not export the constant.
  static const int _cryptProtectUiForbidden = 0x1;

  @override
  bool get isAvailable => true;

  @override
  bool get requiresReentry => false;

  @override
  String get reentryMessage => '';

  @override
  Map<String, dynamic> sealWithMachineKey(String plaintext) {
    final Uint8List? sealed = _dpapi(Uint8List.fromList(utf8.encode(plaintext)), protect: true);
    if (sealed == null) {
      throw StateError('DPAPI CryptProtectData failed.');
    }
    return <String, dynamic>{
      'v': SecretCrypto.envelopeVersion,
      'kdf': SecretCrypto.dpapiKdf,
      'data': base64Encode(sealed),
    };
  }

  @override
  String? openWithMachineKey(Map<String, dynamic> envelope) {
    try {
      final Uint8List? plain = _dpapi(base64Decode(envelope['data'] as String), protect: false);
      if (plain == null) return null;
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  @override
  String protectField(String value) {
    if (value.isEmpty || SecretCrypto.isProtectedField(value)) return value;
    final Uint8List? sealed = _dpapi(Uint8List.fromList(utf8.encode(value)), protect: true);
    // Preserve the existing Windows fail-safe: a transient DPAPI failure must
    // not silently discard the value during a settings write.
    if (sealed == null) return value;
    return '${SecretCrypto.dpapiFieldPrefix}${base64Encode(sealed)}';
  }

  @override
  String unprotectField(String stored) {
    if (!SecretCrypto.isProtectedField(stored)) return stored;
    try {
      final Uint8List? plain =
          _dpapi(base64Decode(stored.substring(SecretCrypto.dpapiFieldPrefix.length)), protect: false);
      if (plain == null) return '';
      return utf8.decode(plain);
    } catch (_) {
      return '';
    }
  }

  static String _credentialTarget(String pluginId, String key) => 'Tabame:plugin:$pluginId:$key';

  @override
  void writePluginSecret(String pluginId, String key, String value) {
    final String target = _credentialTarget(pluginId, key);
    using((Arena arena) {
      final List<int> blob = utf8.encode(value);
      final Pointer<Uint8> blobPointer = arena<Uint8>(blob.length);
      blobPointer.asTypedList(blob.length).setAll(0, blob);
      final Pointer<win32.CREDENTIAL> credential = arena<win32.CREDENTIAL>();
      credential.ref
        ..Type = win32.CRED_TYPE_GENERIC
        ..TargetName = target.toNativeUtf16(allocator: arena)
        ..CredentialBlobSize = blob.length
        ..CredentialBlob = blobPointer
        ..Persist = win32.CRED_PERSIST_LOCAL_MACHINE
        ..UserName = 'tabame-plugin'.toNativeUtf16(allocator: arena);
      if (win32.CredWrite(credential, 0) == 0) {
        unawaited(
          ErrorLogger.log(
            'PluginStorage',
            'CredWrite failed for $target (error ${win32.GetLastError()})',
            null,
          ),
        );
      }
    });
  }

  @override
  String? readPluginSecret(String pluginId, String key) {
    final String target = _credentialTarget(pluginId, key);
    return using((Arena arena) {
      final Pointer<Pointer<win32.CREDENTIAL>> output = arena<Pointer<win32.CREDENTIAL>>();
      if (win32.CredRead(target.toNativeUtf16(allocator: arena), win32.CRED_TYPE_GENERIC, 0, output) == 0) {
        return null;
      }
      final win32.CREDENTIAL credential = output.value.ref;
      try {
        return credential.CredentialBlobSize == 0
            ? ''
            : utf8.decode(credential.CredentialBlob.asTypedList(credential.CredentialBlobSize));
      } finally {
        win32.CredFree(output.value);
      }
    });
  }

  @override
  void deletePluginSecret(String pluginId, String key) {
    final String target = _credentialTarget(pluginId, key);
    using((Arena arena) {
      win32.CredDelete(target.toNativeUtf16(allocator: arena), win32.CRED_TYPE_GENERIC, 0);
    });
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
              blobIn,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _cryptProtectUiForbidden,
              blobOut,
            )
          : win32.CryptUnprotectData(
              blobIn,
              nullptr,
              nullptr,
              nullptr,
              nullptr,
              _cryptProtectUiForbidden,
              blobOut,
            );
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
