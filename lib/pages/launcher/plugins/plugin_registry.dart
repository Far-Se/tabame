import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../logic/error_handler.dart';
import '../../../platform/app_paths.dart';
import '../../../platform/distribution_profile.dart';
import '../../../services/extension_policy.dart';
import 'plugin_manifest.dart';

/// Origin metadata written beside a gallery-installed plugin. It is useful for
/// classification and diagnostics, but it is not a trust grant: Store policy
/// still requires a verified allow-listed artifact before any execution.
class PluginOrigin {
  const PluginOrigin({
    this.source = PluginSource.localUserAuthored,
    this.publisher = '',
    this.artifactSha256 = '',
    this.artifactSignature = '',
  });

  final PluginSource source;
  final String publisher;
  final String artifactSha256;
  final String artifactSignature;

  factory PluginOrigin.fromJson(Map<String, dynamic> json) {
    return PluginOrigin(
      source: parsePluginSource(json['source']),
      publisher: json['publisher'] is String ? json['publisher'] as String : '',
      artifactSha256: json['artifactSha256'] is String ? json['artifactSha256'] as String : '',
      artifactSignature: json['artifactSignature'] is String ? json['artifactSignature'] as String : '',
    );
  }

  Map<String, String> toJson() => <String, String>{
        'source': source.value,
        if (publisher.trim().isNotEmpty) 'publisher': publisher,
        if (artifactSha256.trim().isNotEmpty) 'artifactSha256': artifactSha256,
        if (artifactSignature.trim().isNotEmpty) 'artifactSignature': artifactSignature,
      };
}

/// Scans the plugins folder and answers keyword lookups for the launcher.
///
/// The registry is a process-wide cache: [load] rescans disk (cheap — a handful
/// of tiny `plugin.json` files) and is called each time the launcher opens so
/// newly-dropped plugins appear without a restart. Store profiles may retain
/// manifests in [manifests] for data-preservation UX, but blocked manifests are
/// never added to [_byKeyword].
abstract final class PluginRegistry {
  static const String originFileName = '.tabame-origin.json';

  static List<PluginManifest> _manifests = <PluginManifest>[];
  static Map<String, PluginManifest> _byKeyword = <String, PluginManifest>{};
  static bool _loaded = false;
  static ExtensionPolicy _policy = ExtensionPolicy.current;

  static List<PluginManifest> get manifests => _manifests;
  static bool get isLoaded => _loaded;
  static ExtensionPolicy get policy => _policy;

  /// Rescans Tabame's platform-correct plugin root. Malformed manifests are
  /// logged and skipped rather than aborting the whole scan.
  ///
  /// [extensionPolicy] is injectable for deterministic policy tests; normal
  /// application code uses the compile-time profile policy.
  static Future<void> load({DistributionProfile? profile, ExtensionPolicy? extensionPolicy}) async {
    _policy = extensionPolicy ?? ExtensionPolicy.forProfile(profile ?? DistributionProfileConfig.current);
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
            final PluginOrigin origin = _readOrigin(entity.path);
            final PluginManifest manifest = PluginManifest.fromJson(
              decoded.cast<String, dynamic>(),
              directory: entity.path,
              folderName: folderName,
              source: origin.source,
              publisher: origin.publisher.trim().isEmpty ? null : origin.publisher,
              artifactSha256: origin.artifactSha256,
              artifactSignature: origin.artifactSignature,
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
      if (canExecute(manifest)) _byKeyword.putIfAbsent(manifest.keywordLower, () => manifest);
    }
    _loaded = true;
  }

  static PluginOrigin _readOrigin(String directory) {
    try {
      final File file = File(p.join(directory, originFileName));
      if (!file.existsSync()) return const PluginOrigin();
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map) return PluginOrigin.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      // Invalid or user-edited provenance is treated as local data.
    }
    return const PluginOrigin();
  }

  /// Final registry-side execution gate. An imported `enabled: true` value is
  /// only one input; it cannot override the selected distribution policy.
  static bool canExecute(PluginManifest manifest, {ExtensionPolicy? extensionPolicy}) {
    final ExtensionPolicy selectedPolicy = extensionPolicy ?? _policy;
    return selectedPolicy.canExecutePlugin(
      id: manifest.id,
      source: manifest.source,
      enabled: manifest.enabled,
      publisher: manifest.publisher,
      // No artifact is considered verified by the legacy portable registry.
      // Portable policy does not require these values; a future Store policy
      // must add verification before enabling a source.
      artifactHashVerified: false,
      signatureVerified: false,
      consentGranted: false,
    );
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

      if (!_policy.canEditLocalPluginConfiguration) {
        // Store scans are read-only: preserve imported plugin data exactly and
        // leave duplicate keywords unavailable rather than rewriting manifests.
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
      final PluginOrigin origin = _readOrigin(manifest.directory);
      return PluginManifest.fromJson(
        json,
        directory: manifest.directory,
        folderName: folderName,
        source: origin.source,
        publisher: origin.publisher.trim().isEmpty ? null : origin.publisher,
        artifactSha256: origin.artifactSha256,
        artifactSignature: origin.artifactSignature,
      );
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
    if (!_policy.canEditLocalPluginConfiguration) return false;
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
    if (!_policy.canEditLocalPluginConfiguration) return _policy.pluginDisabledMessage;
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
