import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../logic/error_handler.dart';
import '../../../models/win32/win_utils.dart';
import 'plugin_manifest.dart';

/// Scans the plugins folder and answers keyword lookups for the launcher.
///
/// The registry is a process-wide cache: [load] rescans disk (cheap — a handful
/// of tiny `plugin.json` files) and is called each time the launcher opens so
/// newly-dropped plugins appear without a restart.
abstract final class PluginRegistry {
  static List<PluginManifest> _manifests = <PluginManifest>[];
  static Map<String, PluginManifest> _byKeyword = <String, PluginManifest>{};
  static bool _loaded = false;

  static List<PluginManifest> get manifests => _manifests;
  static bool get isLoaded => _loaded;

  /// Rescans `%localappdata%\Tabame\plugins`. Malformed manifests are logged and
  /// skipped rather than aborting the whole scan.
  static Future<void> load() async {
    final List<PluginManifest> found = <PluginManifest>[];
    try {
      final Directory root = Directory(WinUtils.getPluginsFolder());
      if (root.existsSync()) {
        for (final FileSystemEntity entity in root.listSync(followLinks: false)) {
          if (entity is! Directory) continue;
          final File manifestFile = File('${entity.path}\\plugin.json');
          if (!manifestFile.existsSync()) continue;
          try {
            final Object? decoded = jsonDecode(await manifestFile.readAsString());
            if (decoded is! Map) continue;
            final String folderName = entity.path.split(Platform.pathSeparator).last;
            final PluginManifest manifest = PluginManifest.fromJson(
              decoded.cast<String, dynamic>(),
              directory: entity.path,
              folderName: folderName,
            );
            if (manifest.isValid) found.add(manifest);
          } catch (error, stack) {
            unawaited(ErrorLogger.log('PluginRegistry', 'Bad manifest in ${entity.path}: $error', stack));
          }
        }
      }
    } catch (error, stack) {
      unawaited(ErrorLogger.log('PluginRegistry', 'Failed to scan plugins folder: $error', stack));
    }

    _manifests = found;
    // Only enabled plugins answer keyword lookups; disabled ones stay in
    // [_manifests] so the manager can still list and re-enable them.
    _byKeyword = <String, PluginManifest>{
      for (final PluginManifest m in found)
        if (m.enabled) m.keywordLower: m,
    };
    _loaded = true;
  }

  /// Persists a plugin's on/off state by rewriting the `"enabled"` key in its
  /// `plugin.json`, preserving every other field, then rescans so the in-memory
  /// state matches disk. Returns whether the write succeeded.
  static Future<bool> setEnabled(PluginManifest manifest, bool enabled) async {
    try {
      final File manifestFile = File('${manifest.directory}\\plugin.json');
      if (!manifestFile.existsSync()) return false;
      final Object? decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) return false;
      final Map<String, dynamic> json = decoded.cast<String, dynamic>();
      json['enabled'] = enabled;
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString(encoder.convert(json));
    } catch (error, stack) {
      unawaited(ErrorLogger.log('PluginRegistry', 'Failed to toggle ${manifest.id}: $error', stack));
      return false;
    }
    await load();
    return true;
  }

  /// Returns the plugin whose keyword the raw launcher [query] activates, or
  /// null. Matches when the query equals the keyword or starts with
  /// `keyword + ' '` (so `weather` and `weather rome` both match, but
  /// `weatherman` does not).
  static PluginManifest? matchKeyword(String query) {
    if (_byKeyword.isEmpty) return null;
    final String lower = query.toLowerCase();
    for (final MapEntry<String, PluginManifest> entry in _byKeyword.entries) {
      final String keyword = entry.key;
      if (lower == keyword || lower.startsWith('$keyword ')) return entry.value;
    }
    return null;
  }

  /// Strips the plugin keyword (and following space) from a raw query, leaving
  /// the text the plugin should treat as its own query.
  static String queryAfterKeyword(String query, PluginManifest manifest) {
    final String lower = query.toLowerCase();
    final String keyword = manifest.keywordLower;
    if (lower == keyword) return '';
    if (lower.startsWith('$keyword ')) return query.substring(keyword.length + 1);
    return query;
  }
}
