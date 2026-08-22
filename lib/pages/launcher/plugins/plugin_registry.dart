import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../logic/error_handler.dart';
import '../../../models/settings.dart';
import '../../../platform/app_paths.dart';
import 'plugin_manifest.dart';

/// Scans the plugins folder and answers keyword lookups for the launcher.
///
/// The registry is a process-wide cache: [load] rescans disk (cheap — a handful
/// of tiny `plugin.json` files) and is called each time the launcher opens so
/// newly-dropped plugins appear without a restart.
abstract final class PluginRegistry {
  static const String shortcutSettingKey = 'pluginShortcut';

  static List<PluginManifest> _manifests = <PluginManifest>[];
  static Map<String, PluginManifest> _byKeyword = <String, PluginManifest>{};
  static bool _loaded = false;

  static List<PluginManifest> get manifests => _manifests;
  static bool get isLoaded => _loaded;

  /// The optional prefix shared by every plugin keyword. An empty value keeps
  /// the legacy behavior where a plugin's bare keyword activates it.
  static String get shortcut => user.pluginShortcut.trim();

  /// Validates the launcher-wide plugin prefix. A single non-alphanumeric
  /// character keeps the prefix unambiguous and quick to type.
  static String? validateShortcut(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.runes.length != 1) return 'Use one symbol, or leave the shortcut empty.';
    if (RegExp(r'[A-Za-z0-9]').hasMatch(trimmed)) return 'Use a symbol instead of a letter or number.';
    return null;
  }

  /// Returns the text users type to activate [manifest].
  static String launchKeyword(PluginManifest manifest) => launchKeywordFor(manifest.keyword);

  /// Returns the text users type to activate a plugin with [keyword].
  static String launchKeywordFor(String keyword) => '$shortcut${keyword.trim()}';

  /// Returns the launch prefix used by launcher shortcut rows.
  static String launchPrefix(PluginManifest manifest) => '${launchKeyword(manifest)} ';

  /// Rescans Tabame's platform-correct plugin root. Malformed manifests are
  /// logged and skipped rather than aborting the whole scan.
  static Future<void> load() async {
    final List<PluginManifest> found = <PluginManifest>[];
    try {
      final Directory root = Directory(AppPaths.pluginsDirectory);
      if (root.existsSync()) {
        final List<FileSystemEntity> pluginDirectories = root
            .listSync(followLinks: false)
            .whereType<Directory>()
            .toList()
          ..sort((FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path));
        for (final FileSystemEntity entity in pluginDirectories) {
          if (entity is! Directory) continue;
          final File manifestFile = File(p.join(entity.path, 'plugin.json'));
          if (!manifestFile.existsSync()) continue;
          try {
            final Object? decoded = jsonDecode(await manifestFile.readAsString());
            if (decoded is! Map) continue;
            final String folderName = p.basename(entity.path);
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

    _manifests = await _resolveDuplicateKeywords(found);
    // Only enabled plugins answer keyword lookups; disabled ones stay in
    // [_manifests] so the manager can still list and re-enable them.
    _byKeyword = <String, PluginManifest>{};
    for (final PluginManifest manifest in _manifests) {
      if (manifest.enabled) _byKeyword.putIfAbsent(manifest.keywordLower, () => manifest);
    }
    _loaded = true;
  }

  /// Renames later duplicate keywords and persists the correction to their
  /// manifests. Every original keyword is reserved first, so a generated name
  /// never collides with a plugin that already uses it.
  static Future<List<PluginManifest>> _resolveDuplicateKeywords(List<PluginManifest> found) async {
    final Set<String> reserved = found.map((PluginManifest manifest) => manifest.keywordLower).toSet();
    final Set<String> used = <String>{};
    final List<PluginManifest> resolved = <PluginManifest>[];

    for (final PluginManifest manifest in found) {
      if (used.add(manifest.keywordLower)) {
        resolved.add(manifest);
        continue;
      }

      final String keyword = _nextAvailableKeyword(manifest.keyword.trim(), reserved);
      final PluginManifest? renamed = await _renameKeyword(manifest, keyword);
      if (renamed == null) {
        // Keep it visible in the manager, but preserve the first plugin as the
        // one the launcher routes to until the manifest can be corrected.
        resolved.add(manifest);
        continue;
      }
      reserved.add(renamed.keywordLower);
      used.add(renamed.keywordLower);
      resolved.add(renamed);
    }
    return resolved;
  }

  static String _nextAvailableKeyword(String baseKeyword, Set<String> reserved) {
    for (int suffix = 2;; suffix++) {
      final String candidate = '$baseKeyword$suffix';
      if (!reserved.contains(candidate.toLowerCase())) return candidate;
    }
  }

  static Future<PluginManifest?> _renameKeyword(PluginManifest manifest, String keyword) async {
    try {
      final File manifestFile = File(p.join(manifest.directory, 'plugin.json'));
      final Object? decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) return null;
      final Map<String, dynamic> json = decoded.cast<String, dynamic>();
      json['keyword'] = keyword;
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString(encoder.convert(json));
      final String folderName = p.basename(manifest.directory);
      return PluginManifest.fromJson(json, directory: manifest.directory, folderName: folderName);
    } catch (error, stack) {
      unawaited(
        ErrorLogger.log('PluginRegistry', 'Failed to rename duplicate keyword for ${manifest.id}: $error', stack),
      );
      return null;
    }
  }

  /// Persists a plugin's on/off state by rewriting the `"enabled"` key in its
  /// `plugin.json`, preserving every other field, then rescans so the in-memory
  /// state matches disk. Returns whether the write succeeded.
  static Future<bool> setEnabled(PluginManifest manifest, bool enabled) async {
    try {
      final File manifestFile = File(p.join(manifest.directory, 'plugin.json'));
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

  /// Persists a plugin's keyword in its `plugin.json`, preserving every other
  /// field, then rescans so launcher matching uses the new keyword. Returns
  /// null on success, or a short human-readable error.
  static Future<String?> setKeyword(PluginManifest manifest, String keyword) async {
    final String trimmedKeyword = keyword.trim();
    if (trimmedKeyword.isEmpty) return 'Plugin keyword cannot be empty.';

    final bool alreadyUsed = _manifests.any(
      (PluginManifest other) =>
          other.directory != manifest.directory && other.keywordLower == trimmedKeyword.toLowerCase(),
    );
    if (alreadyUsed) return 'That keyword is already used by another plugin.';

    try {
      final File manifestFile = File(p.join(manifest.directory, 'plugin.json'));
      if (!manifestFile.existsSync()) return 'Plugin manifest not found.';
      final Object? decoded = jsonDecode(await manifestFile.readAsString());
      if (decoded is! Map) return 'Plugin manifest is invalid.';
      final Map<String, dynamic> json = decoded.cast<String, dynamic>();
      json['keyword'] = trimmedKeyword;
      const JsonEncoder encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString(encoder.convert(json));
    } catch (error, stack) {
      unawaited(ErrorLogger.log('PluginRegistry', 'Failed to update keyword for ${manifest.id}: $error', stack));
      return 'Could not save the plugin keyword.';
    }
    await load();
    return null;
  }

  /// Returns the plugin whose effective launcher keyword activates [query], or
  /// null. When a global shortcut is configured, it is included before the
  /// manifest keyword (so `;weather` and `;weather rome` match when the shortcut
  /// is `;`, while bare `weather` remains available to other launcher results).
  static PluginManifest? matchKeyword(String query) {
    if (_byKeyword.isEmpty) return null;
    final String lower = query.toLowerCase();
    for (final MapEntry<String, PluginManifest> entry in _byKeyword.entries) {
      final String keyword = launchKeywordFor(entry.key);
      if (lower == keyword || lower.startsWith('$keyword ')) return entry.value;
    }
    return null;
  }

  /// Strips the effective plugin keyword (and following space) from a raw
  /// query, leaving the text the plugin should treat as its own query.
  static String queryAfterKeyword(String query, PluginManifest manifest) {
    final String lower = query.toLowerCase();
    final String keyword = launchKeyword(manifest).toLowerCase();
    if (lower == keyword) return '';
    if (lower.startsWith('$keyword ')) return query.substring(keyword.length + 1);
    return query;
  }
}
