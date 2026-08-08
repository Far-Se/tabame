import '../models/util/secret_crypto.dart';

/// Raised when a machine-bound secret cannot be opened on this platform.
///
/// Callers should preserve the original envelope and ask the user to re-enter
/// the secret or provide an explicit export from the source platform. They must
/// not replace it with plaintext or silently reinterpret it as a portable ID.
class SecretStoreUnavailableException implements Exception {
  const SecretStoreUnavailableException([
    this.message =
        'This machine-bound secret is unavailable here. Re-enter the secret or import an explicit export from Windows.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Narrow boundary for machine/user-bound secrets.
///
/// Password-based envelopes are intentionally not part of this interface; use
/// [SecretCrypto] for those so the portable path remains available everywhere.
abstract interface class SecretStore {
  bool get isAvailable;
  bool get requiresReentry;
  String get reentryMessage;

  Map<String, dynamic> sealWithMachineKey(String plaintext);
  String? openWithMachineKey(Map<String, dynamic> envelope);
  String protectField(String value);
  String unprotectField(String stored);

  String? readPluginSecret(String pluginId, String key);
  void writePluginSecret(String pluginId, String key, String value);
  void deletePluginSecret(String pluginId, String key);
}

/// Safe placeholder until a target-specific machine secret provider is added.
class UnavailableSecretStore implements SecretStore {
  const UnavailableSecretStore();

  @override
  bool get isAvailable => false;

  @override
  bool get requiresReentry => true;

  @override
  String get reentryMessage => const SecretStoreUnavailableException().message;

  @override
  Map<String, dynamic> sealWithMachineKey(String plaintext) {
    throw const SecretStoreUnavailableException();
  }

  @override
  String? openWithMachineKey(Map<String, dynamic> envelope) {
    if (envelope['kdf'] == SecretCrypto.dpapiKdf ||
        envelope['kdf'] == SecretCrypto.keychainKdf ||
        envelope['kdf'] == SecretCrypto.secretServiceKdf) {
      throw const SecretStoreUnavailableException();
    }
    return null;
  }

  @override
  String protectField(String value) {
    if (value.isEmpty ||
        SecretCrypto.isProtectedField(value) ||
        SecretCrypto.isKeychainProtectedField(value) ||
        SecretCrypto.isSecretServiceProtectedField(value)) {
      return value;
    }
    throw const SecretStoreUnavailableException();
  }

  @override
  String unprotectField(String stored) {
    if (!SecretCrypto.isProtectedField(stored) &&
        !SecretCrypto.isKeychainProtectedField(stored) &&
        !SecretCrypto.isSecretServiceProtectedField(stored)) return stored;
    throw const SecretStoreUnavailableException();
  }

  @override
  String? readPluginSecret(String pluginId, String key) => null;

  @override
  void writePluginSecret(String pluginId, String key, String value) {
    throw const SecretStoreUnavailableException();
  }

  @override
  void deletePluginSecret(String pluginId, String key) {}
}
