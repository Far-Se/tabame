import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/util/secret_crypto.dart';
import '../app_paths.dart';
import '../secret_store.dart';
import 'linux_platform_channel.dart';

/// Secret Service-backed machine/user storage for Linux.
///
/// The Secret Service owns one random AES-256 key. Tabame keeps ciphertext in
/// its existing settings files so the synchronous [SecretStore] contract stays
/// compatible with the rest of the application. If the service is absent,
/// locked, or inaccessible, password-based encryption and explicit re-entry
/// remain the safe fallback.
class LinuxSecretStore implements SecretStore {
  LinuxSecretStore({LinuxPlatformChannel? channel}) : channel = channel ?? LinuxPlatformChannel.instance;

  static final LinuxSecretStore instance = LinuxSecretStore();

  final LinuxPlatformChannel channel;
  Uint8List? _masterKey;
  bool _initialized = false;

  Future<bool> initialize() async {
    if (_initialized && isAvailable) return true;
    // A Secret Service may appear or unlock after startup; failed probes remain
    // retryable without weakening the synchronous SecretStore contract.
    _initialized = true;
    final String? encodedKey = await channel.ensureSecretServiceKey();
    if (encodedKey == null) return false;
    try {
      final Uint8List decoded = Uint8List.fromList(base64Decode(encodedKey));
      if (decoded.length != 32) return false;
      _masterKey = decoded;
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isAvailable => _masterKey != null;

  @override
  bool get requiresReentry => !isAvailable;

  @override
  String get reentryMessage => isAvailable
      ? ''
      : 'Tabame could not open its Linux Secret Service key. Unlock a Secret Service provider or re-enter the secret.';

  @override
  Map<String, dynamic> sealWithMachineKey(String plaintext) {
    return SecretCrypto.sealWithKey(
      plaintext,
      _requireKey(),
      kdf: SecretCrypto.secretServiceKdf,
    );
  }

  @override
  String? openWithMachineKey(Map<String, dynamic> envelope) {
    if (envelope['kdf'] == SecretCrypto.dpapiKdf) {
      throw const SecretStoreUnavailableException(
        'This secret was protected by Windows DPAPI and cannot be opened by Linux. Re-enter it or use an explicit password export.',
      );
    }
    if (envelope['kdf'] == SecretCrypto.keychainKdf) {
      throw const SecretStoreUnavailableException(
        'This secret was protected by the macOS Keychain and cannot be opened by Linux. Re-enter it or use an explicit password export.',
      );
    }
    if (envelope['kdf'] != SecretCrypto.secretServiceKdf) return null;
    return SecretCrypto.openWithKey(envelope, _requireKey());
  }

  @override
  String protectField(String value) {
    if (value.isEmpty || SecretCrypto.isSecretServiceProtectedField(value)) return value;
    // Preserve a foreign platform-bound value until the user explicitly
    // migrates it instead of replacing it during an unrelated settings save.
    if (SecretCrypto.isProtectedField(value) || SecretCrypto.isKeychainProtectedField(value)) return value;
    final Map<String, dynamic> envelope = sealWithMachineKey(value);
    return '${SecretCrypto.secretServiceFieldPrefix}${_encodeEnvelope(envelope)}';
  }

  @override
  String unprotectField(String stored) {
    if (stored.isEmpty) return stored;
    if (SecretCrypto.isProtectedField(stored)) {
      throw const SecretStoreUnavailableException(
        'This field was protected by Windows DPAPI and cannot be opened by Linux. Re-enter it to migrate the value.',
      );
    }
    if (SecretCrypto.isKeychainProtectedField(stored)) {
      throw const SecretStoreUnavailableException(
        'This field was protected by the macOS Keychain and cannot be opened by Linux. Re-enter it to migrate the value.',
      );
    }
    if (!SecretCrypto.isSecretServiceProtectedField(stored)) return stored;
    try {
      final String encoded = stored.substring(SecretCrypto.secretServiceFieldPrefix.length);
      final int padding = (4 - encoded.length % 4) % 4;
      final dynamic decoded = jsonDecode(utf8.decode(base64Url.decode('$encoded${'=' * padding}')));
      if (decoded is! Map<dynamic, dynamic>) return '';
      return SecretCrypto.openWithKey(Map<String, dynamic>.from(decoded), _requireKey()) ?? '';
    } catch (error) {
      if (error is SecretStoreUnavailableException) rethrow;
      return '';
    }
  }

  @override
  String? readPluginSecret(String pluginId, String key) {
    try {
      final Map<String, dynamic> all = _readPluginSecrets();
      final dynamic value = (all[pluginId] as Map<dynamic, dynamic>?)?[key];
      if (value is! Map<dynamic, dynamic>) return null;
      return SecretCrypto.openWithKey(Map<String, dynamic>.from(value), _requireKey());
    } on SecretStoreUnavailableException {
      return null;
    }
  }

  @override
  void writePluginSecret(String pluginId, String key, String value) {
    final Map<String, dynamic> all = _readPluginSecrets();
    final Map<String, dynamic> plugin = all[pluginId] is Map<dynamic, dynamic>
        ? Map<String, dynamic>.from(all[pluginId] as Map<dynamic, dynamic>)
        : <String, dynamic>{};
    plugin[key] = SecretCrypto.sealWithKey(
      value,
      _requireKey(),
      kdf: SecretCrypto.secretServiceKdf,
    );
    all[pluginId] = plugin;
    _writePluginSecrets(all);
  }

  @override
  void deletePluginSecret(String pluginId, String key) {
    if (!isAvailable) return;
    final Map<String, dynamic> all = _readPluginSecrets();
    final dynamic rawPlugin = all[pluginId];
    if (rawPlugin is! Map<dynamic, dynamic>) return;
    final Map<String, dynamic> plugin = Map<String, dynamic>.from(rawPlugin)..remove(key);
    if (plugin.isEmpty) {
      all.remove(pluginId);
    } else {
      all[pluginId] = plugin;
    }
    _writePluginSecrets(all);
  }

  Uint8List _requireKey() {
    final Uint8List? key = _masterKey;
    if (key == null) throw SecretStoreUnavailableException(reentryMessage);
    return key;
  }

  Map<String, dynamic> _readPluginSecrets() {
    _requireKey();
    final File file = File(AppPaths.settingsPath('linux_plugin_secrets.json'));
    if (!file.existsSync()) return <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<dynamic, dynamic>) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  void _writePluginSecrets(Map<String, dynamic> values) {
    _requireKey();
    final File file = File(AppPaths.settingsPath('linux_plugin_secrets.json', forWrite: true));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(values), flush: true);
  }

  String _encodeEnvelope(Map<String, dynamic> envelope) {
    return base64UrlEncode(utf8.encode(jsonEncode(envelope))).replaceAll('=', '');
  }
}
