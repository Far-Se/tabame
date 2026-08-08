import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../logic/error_handler.dart';
import '../../../platform/secret_store_registry.dart';
import 'plugin_manifest.dart';

/// Per-plugin persistent key-value storage, backed by the `storage` command.
///
/// Plain values live in a `.tabame-store.json` file inside the plugin folder
/// (so a plugin stays self-contained and portable, mirroring `.pluginlibs`).
/// Values written with `"secret": true` go to the Windows Credential Manager
/// instead, under a `Tabame:plugin:<id>:<key>` generic credential, so API
/// tokens never sit in a plaintext file.
class PluginStorage {
  PluginStorage._();

  /// File name is ignored by the dev-mode hot-reload watcher (see
  /// `plugin_host.dart`) so storage writes don't restart the plugin.
  static const String storeFileName = '.tabame-store.json';

  static File _storeFile(PluginManifest manifest) => File(p.join(manifest.directory, storeFileName));

  static Map<String, dynamic> _readStore(PluginManifest manifest) {
    try {
      final File file = _storeFile(manifest);
      if (!file.existsSync()) return <String, dynamic>{};
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (error) {
      unawaited(ErrorLogger.log('PluginStorage', 'read failed for ${manifest.id}: $error', null));
    }
    return <String, dynamic>{};
  }

  static void _writeStore(PluginManifest manifest, Map<String, dynamic> store) {
    try {
      _storeFile(manifest).writeAsStringSync(jsonEncode(store));
    } catch (error) {
      unawaited(ErrorLogger.log('PluginStorage', 'write failed for ${manifest.id}: $error', null));
    }
  }

  /// Returns the stored value for [key] (any JSON value), or null when absent.
  static Object? get(PluginManifest manifest, String key, {bool secret = false}) {
    if (secret) return SecretStores.instance.readPluginSecret(manifest.id, key);
    return _readStore(manifest)[key];
  }

  /// Stores [value] under [key]. A null [value] behaves like delete.
  static void set(PluginManifest manifest, String key, Object? value, {bool secret = false}) {
    if (value == null) {
      delete(manifest, key, secret: secret);
      return;
    }
    if (secret) {
      SecretStores.instance.writePluginSecret(manifest.id, key, value is String ? value : jsonEncode(value));
      return;
    }
    final Map<String, dynamic> store = _readStore(manifest);
    store[key] = value;
    _writeStore(manifest, store);
  }

  static void delete(PluginManifest manifest, String key, {bool secret = false}) {
    if (secret) {
      SecretStores.instance.deletePluginSecret(manifest.id, key);
      return;
    }
    final Map<String, dynamic> store = _readStore(manifest);
    if (store.remove(key) != null) _writeStore(manifest, store);
  }

  /// Lists the plugin's non-secret keys (Credential Manager entries are not
  /// enumerable by design).
  static List<String> keys(PluginManifest manifest) => _readStore(manifest).keys.toList(growable: false);

  // Machine-bound plugin secrets are delegated to the platform secret boundary.
}
