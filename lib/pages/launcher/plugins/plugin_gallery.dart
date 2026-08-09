import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../logic/error_handler.dart';
import '../../../platform/app_paths.dart';
import '../../../services/extension_policy.dart';
import 'plugin_manifest.dart';
import 'plugin_registry.dart';

/// One community plugin as described by the remote gallery index.
///
/// A plugin installs either from a [files] map (`relative path → download URL`,
/// perfect for plugins hosted as plain files in a git repo) or from a [zip]
/// archive URL. The gallery index itself lives in the Tabame repo
/// (`resources/plugins.json` on master) — same hosting pattern as sponsor.json.
class PluginGalleryEntry {
  const PluginGalleryEntry({
    required this.id,
    required this.name,
    required this.keyword,
    required this.description,
    required this.icon,
    required this.runtime,
    required this.author,
    required this.version,
    required this.homepage,
    required this.zip,
    required this.files,
    this.source = PluginSource.firstPartyGallery,
    this.publisher = '',
    this.artifactSha256 = '',
    this.artifactSignature = '',
  });

  final String id;
  final String name;
  final String keyword;
  final String description;
  final String icon;
  final String runtime;
  final String author;
  final String version;
  final String homepage;
  final String zip;
  final Map<String, String> files;

  /// A feed entry is classified separately from the local manifest it creates.
  final PluginSource source;
  final String publisher;
  final String artifactSha256;
  final String artifactSignature;

  bool get installable => files.isNotEmpty || zip.isNotEmpty;

  static final RegExp _safeId = RegExp(r'^[a-zA-Z0-9_\-]+$');

  /// Returns null for malformed entries (missing id/name or an id that is not
  /// filesystem-safe) instead of aborting the whole index.
  static PluginGalleryEntry? fromJson(Map<String, dynamic> json) {
    String str(String key, [String fallback = '']) {
      final Object? value = json[key];
      return value is String ? value : fallback;
    }

    final String id = str('id').trim();
    final String name = str('name').trim();
    if (id.isEmpty || name.isEmpty || !_safeId.hasMatch(id)) return null;

    final Map<String, String> files = <String, String>{};
    final Object? rawFiles = json['files'];
    if (rawFiles is Map) {
      for (final MapEntry<dynamic, dynamic> entry in rawFiles.entries) {
        if (entry.key is String && entry.value is String) {
          files[entry.key as String] = entry.value as String;
        }
      }
    }

    final PluginSource parsedSource = parsePluginSource(
      json['source'],
      fallback: PluginSource.firstPartyGallery,
    );
    final PluginSource source = parsedSource == PluginSource.thirdPartyGallery
        ? PluginSource.thirdPartyGallery
        : PluginSource.firstPartyGallery;
    final String author = str('author', str('publisher'));

    return PluginGalleryEntry(
      id: id,
      name: name,
      keyword: str('keyword'),
      description: str('description'),
      icon: str('icon', 'extension'),
      runtime: str('runtime'),
      author: author,
      version: str('version'),
      homepage: str('homepage'),
      zip: str('zip'),
      files: files,
      source: source,
      publisher: str('publisher', author),
      artifactSha256: str('artifactSha256', str('sha256')),
      artifactSignature: str('artifactSignature', str('signature')),
    );
  }
}

/// Fetches the community plugin index and installs plugins into
/// Tabame's platform-correct plugin root.
abstract final class PluginGallery {
  static const String indexUrl = 'https://raw.githubusercontent.com/Far-Se/tabame/main/resources/plugins.json';

  static List<PluginGalleryEntry>? _cache;
  static List<PluginGalleryEntry>? get cached => _cache;

  static Future<List<PluginGalleryEntry>> fetchIndex({bool force = false, ExtensionPolicy? extensionPolicy}) async {
    final ExtensionPolicy policy = extensionPolicy ?? ExtensionPolicy.current;
    if (!policy.canFetchPluginGallery) return const <PluginGalleryEntry>[];
    if (!force && _cache != null) return _cache!;

    // Hour-based cache buster, same trick as the sponsor.json fetch.
    final http.Response response =
        await http.get(Uri.parse('$indexUrl?e=${DateTime.now().hour}')).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('Gallery index returned HTTP ${response.statusCode}');
    }

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    final List<PluginGalleryEntry> entries = <PluginGalleryEntry>[];
    if (decoded is Map && decoded['plugins'] is List) {
      for (final Object? raw in decoded['plugins'] as List<dynamic>) {
        if (raw is! Map) continue;
        final PluginGalleryEntry? entry = PluginGalleryEntry.fromJson(raw.cast<String, dynamic>());
        if (entry != null) entries.add(entry);
      }
    }
    _cache = entries;
    return entries;
  }

  static bool isInstalled(String id) {
    final String lower = id.toLowerCase();
    return PluginRegistry.manifests.any((PluginManifest m) => m.id.toLowerCase() == lower);
  }

  /// Installs [entry] into the plugins folder and rescans the registry.
  /// Returns null on success, or a short human-readable error.
  static Future<String?> install(PluginGalleryEntry entry, {ExtensionPolicy? extensionPolicy}) async {
    final ExtensionPolicy policy = extensionPolicy ?? ExtensionPolicy.current;
    if (!policy.canInstallRemotePlugins || !policy.allowsGallerySource(entry.source)) {
      return policy.pluginDisabledMessage;
    }
    try {
      final Directory target = Directory(p.join(AppPaths.pluginsDirectory, entry.id));
      String? error;
      if (entry.files.isNotEmpty) {
        error = await _installFromFiles(entry, target);
      } else if (entry.zip.isNotEmpty) {
        error = await _installFromZip(entry, target);
      } else {
        return 'Index entry has no download source';
      }
      if (error != null) return error;

      if (!File(p.join(target.path, 'plugin.json')).existsSync()) {
        return 'Downloaded plugin has no plugin.json';
      }
      final File originFile = File(p.join(target.path, PluginRegistry.originFileName));
      await originFile.writeAsString(
        jsonEncode(
          PluginOrigin(
            source: entry.source,
            publisher: entry.publisher,
            artifactSha256: entry.artifactSha256,
            artifactSignature: entry.artifactSignature,
          ).toJson(),
        ),
        flush: true,
      );
      await PluginRegistry.load();
      return null;
    } catch (e, s) {
      unawaited(ErrorLogger.log('PluginGallery', 'Install ${entry.id} failed: $e', s));
      return e.toString();
    }
  }

  static Future<String?> _installFromFiles(PluginGalleryEntry entry, Directory target) async {
    // Download everything before touching disk, so a mid-download failure
    // cannot leave a half-written plugin folder behind.
    final Map<String, List<int>> downloaded = <String, List<int>>{};
    for (final MapEntry<String, String> file in entry.files.entries) {
      final String relativePath = file.key.replaceAll('\\', '/');
      final List<String> relativeSegments = relativePath.split('/');
      if (relativePath.trim().isEmpty ||
          relativeSegments.any((String segment) => segment.isEmpty || segment == '..') ||
          p.isAbsolute(relativePath) ||
          relativePath.contains(':')) {
        return 'Unsafe file path in index: ${file.key}';
      }
      final http.Response response = await http.get(Uri.parse(file.value)).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return 'Download failed (${file.key}: HTTP ${response.statusCode})';
      }
      downloaded[relativePath] = response.bodyBytes;
    }

    target.createSync(recursive: true);
    for (final MapEntry<String, List<int>> file in downloaded.entries) {
      final List<String> relativeSegments = file.key.split('/');
      final File out = File(p.joinAll(<String>[target.path, ...relativeSegments]));
      out.parent.createSync(recursive: true);
      await out.writeAsBytes(file.value);
    }
    return null;
  }

  static Future<String?> _installFromZip(PluginGalleryEntry entry, Directory target) async {
    final http.Response response = await http.get(Uri.parse(entry.zip)).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) return 'Download failed: HTTP ${response.statusCode}';

    // Stage in the system temp dir — never inside the plugins folder, where the
    // registry could scan a half-extracted archive.
    final Directory tempDirectory = Directory(AppPaths.temporaryDirectory);
    if (!tempDirectory.existsSync()) tempDirectory.createSync(recursive: true);
    final Directory staging = tempDirectory.createTempSync('plugin_');
    final File zipFile = File(p.join(staging.path, '${entry.id}.zip'));
    final Directory extractDir = Directory(p.join(staging.path, 'extract'));
    try {
      await zipFile.writeAsBytes(response.bodyBytes);
      final ProcessResult result = await Process.run('powershell', <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Expand-Archive -LiteralPath '${zipFile.path.replaceAll("'", "''")}' "
            "-DestinationPath '${extractDir.path.replaceAll("'", "''")}' -Force",
      ]);
      if (result.exitCode != 0) {
        return 'Unzip failed: ${result.stderr.toString().trim()}';
      }

      // Accept both zip layouts: files at the root, or one wrapping folder.
      Directory sourceDir = extractDir;
      if (!File(p.join(sourceDir.path, 'plugin.json')).existsSync()) {
        final List<Directory> subDirs = sourceDir.listSync().whereType<Directory>().toList();
        if (subDirs.length == 1 && File(p.join(subDirs.first.path, 'plugin.json')).existsSync()) {
          sourceDir = subDirs.first;
        } else {
          return 'Archive has no plugin.json';
        }
      }

      if (target.existsSync()) target.deleteSync(recursive: true);
      _copyDirectory(sourceDir, target);
      return null;
    } finally {
      try {
        staging.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static void _copyDirectory(Directory source, Directory destination) {
    destination.createSync(recursive: true);
    for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
      final String name = p.basename(entity.path);
      if (entity is Directory) {
        _copyDirectory(entity, Directory(p.join(destination.path, name)));
      } else if (entity is File) {
        entity.copySync(p.join(destination.path, name));
      }
    }
  }
}
