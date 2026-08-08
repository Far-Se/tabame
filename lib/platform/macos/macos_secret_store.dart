import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/util/secret_crypto.dart';
import '../app_paths.dart';
import '../secret_store.dart';
import 'macos_platform_channel.dart';

/// Keychain-backed machine/user secret storage for macOS.
///
/// The native side owns a random 256-bit master key in the user's Keychain.
/// Envelopes and plugin values remain encrypted in Tabame's existing files so
/// the synchronous [SecretStore] API remains compatible with the current data
/// models. A missing Keychain key is a hard boundary: callers get the existing
/// re-entry path instead of a plaintext downgrade.
class MacOSSecretStore implements SecretStore {
  MacOSSecretStore({MacOSPlatformChannel? channel}) : channel = channel ?? MacOSPlatformChannel.instance;

  static final MacOSSecretStore instance = MacOSSecretStore();

  final MacOSPlatformChannel channel;
  Uint8List? _masterKey;
  Future<bool>? _initializationFuture;

  Future<bool> initialize() {
    if (isAvailable) return Future<bool>.value(true);
    return _initializationFuture ??= _initialize().whenComplete(() {
      _initializationFuture = null;
    });
  }

  Future<bool> _initialize() async {
    _masterKey = null;
    final String? encodedKey = await channel.ensureKeychainKey();
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
      : 'Tabame could not open its macOS Keychain key. Re-enter the secret or allow Keychain access and try again.';

  @override
  Map<String, dynamic> sealWithMachineKey(String plaintext) {
    return _seal(plaintext);
  }

  @override
  String? openWithMachineKey(Map<String, dynamic> envelope) {
    if (envelope['kdf'] == SecretCrypto.dpapiKdf) {
      throw const SecretStoreUnavailableException(
        'This secret was protected by Windows DPAPI and cannot be opened by macOS. Re-enter it or use an explicit password export.',
      );
    }
    if (envelope['kdf'] != SecretCrypto.keychainKdf) return null;
    return SecretCrypto.openWithKey(envelope, _requireKey());
  }

  @override
  String protectField(String value) {
    if (value.isEmpty || SecretCrypto.isKeychainProtectedField(value)) return value;
    // Preserve a Windows-bound field until the user explicitly migrates it.
    if (SecretCrypto.isProtectedField(value)) return value;
    final Map<String, dynamic> envelope = _seal(value);
    return '${SecretCrypto.keychainFieldPrefix}${_encodeEnvelope(envelope)}';
  }

  @override
  String unprotectField(String stored) {
    if (stored.isEmpty) return stored;
    if (SecretCrypto.isProtectedField(stored)) {
      throw const SecretStoreUnavailableException(
        'This field was protected by Windows DPAPI and cannot be opened by macOS. Re-enter it to migrate the value.',
      );
    }
    if (!SecretCrypto.isKeychainProtectedField(stored)) return stored;
    try {
      final String encoded = stored.substring(SecretCrypto.keychainFieldPrefix.length);
      final int padding = (4 - encoded.length % 4) % 4;
      final dynamic decoded = jsonDecode(utf8.decode(base64Url.decode('$encoded${'=' * padding}')));
      if (decoded is! Map<dynamic, dynamic>) return '';
      return SecretCrypto.openWithKey(Map<String, dynamic>.from(decoded), _requireKey()) ?? '';
    } catch (_) {
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
    try {
      final Map<String, dynamic> all = _readPluginSecrets();
      final Map<String, dynamic> plugin = all[pluginId] is Map<dynamic, dynamic>
          ? Map<String, dynamic>.from(all[pluginId] as Map<dynamic, dynamic>)
          : <String, dynamic>{};
      plugin[key] = _seal(value);
      all[pluginId] = plugin;
      _writePluginSecrets(all);
    } on SecretStoreUnavailableException {
      // Secret storage is optional; unavailable Keychain access must not break
      // a plugin's newline-delimited protocol callback.
    }
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

  Map<String, dynamic> _seal(String plaintext) {
    return SecretCrypto.sealWithKey(plaintext, _requireKey());
  }

  Uint8List _requireKey() {
    final Uint8List? key = _masterKey;
    if (key == null) throw SecretStoreUnavailableException(reentryMessage);
    return key;
  }

  Map<String, dynamic> _readPluginSecrets() {
    _requireKey();
    final File file = File(AppPaths.settingsPath('macos_plugin_secrets.json'));
    if (!file.existsSync()) return <String, dynamic>{};
    try {
      final dynamic decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<dynamic, dynamic>) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return <String, dynamic>{};
  }

  void _writePluginSecrets(Map<String, dynamic> values) {
    _requireKey();
    final File file = File(AppPaths.settingsPath('macos_plugin_secrets.json', forWrite: true));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(values), flush: true);
  }

  String _encodeEnvelope(Map<String, dynamic> envelope) {
    return base64UrlEncode(utf8.encode(jsonEncode(envelope))).replaceAll('=', '');
  }
}
