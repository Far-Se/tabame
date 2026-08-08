import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Owns Tabame's platform-neutral application data locations.
///
/// The service is initialized once, before any storage-backed service is used.
/// On Windows the canonical root deliberately remains
/// `%LOCALAPPDATA%\\Tabame`; [path_provider] still supplies the host cache and
/// temporary locations used by the service. On other platforms application data
/// is rooted below the host's application-support directory.
///
/// A legacy root is probed during initialization and copied into the canonical
/// root without overwriting existing files. The copy is intentionally
/// non-destructive: the legacy root is never deleted, and database `-wal` and
/// `-shm` files are copied like every other sibling file.
class AppPaths {
  AppPaths._();

  static final AppPaths instance = AppPaths._();

  String? _rootPath;
  String? _legacyRootPath;
  String? _temporaryBasePath;

  /// Initializes the path service and performs an idempotent legacy migration.
  ///
  /// The provider callbacks exist for focused tests and do not change the
  /// production path-provider behavior. [rootOverride] and
  /// [legacyRootOverride] are likewise test/import hooks; normal application
  /// startup leaves them null.
  static Future<void> initialize({
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? applicationCacheDirectory,
    Future<Directory> Function()? temporaryDirectory,
    String? rootOverride,
    String? legacyRootOverride,
    bool migrateLegacyData = true,
  }) {
    return instance._initialize(
      applicationSupportDirectory: applicationSupportDirectory,
      applicationCacheDirectory: applicationCacheDirectory,
      temporaryDirectory: temporaryDirectory,
      rootOverride: rootOverride,
      legacyRootOverride: legacyRootOverride,
      migrateLegacyData: migrateLegacyData,
    );
  }

  Future<void> _initialize({
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? applicationCacheDirectory,
    Future<Directory> Function()? temporaryDirectory,
    String? rootOverride,
    String? legacyRootOverride,
    required bool migrateLegacyData,
  }) async {
    final Directory supportDirectory =
        await (applicationSupportDirectory == null ? getApplicationSupportDirectory() : applicationSupportDirectory());
    final Directory cacheDirectory =
        await (applicationCacheDirectory == null ? getApplicationCacheDirectory() : applicationCacheDirectory());
    final Directory hostTemporaryDirectory =
        await (temporaryDirectory == null ? getTemporaryDirectory() : temporaryDirectory());

    final String localAppData = _environmentPath('LOCALAPPDATA') ?? cacheDirectory.path;
    final String legacyRoot = legacyRootOverride ?? p.join(localAppData, 'Tabame');
    final String canonicalRoot =
        rootOverride ?? (Platform.isWindows ? p.join(localAppData, 'Tabame') : p.join(supportDirectory.path, 'Tabame'));

    _rootPath = canonicalRoot;
    _legacyRootPath = legacyRoot;
    _temporaryBasePath = hostTemporaryDirectory.path;

    if (migrateLegacyData) await _migrateLegacyData();
  }

  static String? _environmentPath(String key) {
    final String? value = Platform.environment[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  /// Clears the service for focused tests. Production code should initialize
  /// once from [main] and never call this.
  static void resetForTesting() {
    instance._rootPath = null;
    instance._legacyRootPath = null;
    instance._temporaryBasePath = null;
  }

  static bool get isInitialized => instance._rootPath != null;

  /// Whether the persisted settings file exists. A settings directory alone
  /// does not mean that first-run setup has been completed.
  static bool get hasSettingsFile => File(settingsPath('settings.json')).existsSync();

  static String get root => instance._requireRoot();
  static String get legacyRoot => instance._requireLegacyRoot();
  static String get settingsDirectory => currentPath(
        kDebugMode ? p.join('settings', 'debug') : 'settings',
      );
  static String get cacheDirectory => currentPath('cache');
  static String get pluginsDirectory => currentPath('plugins');
  static String get fancyshotDirectory => currentPath('fancyshot');
  static String get rewindlyDirectory => currentPath('rewindly');
  static String get temporaryDirectory => instance._requireTemporaryBasePath();

  /// Returns a canonical path for an app-owned relative storage location.
  static String currentPath(String relativePath) => instance._join(instance._requireRoot(), relativePath);

  /// Returns a legacy-root path without creating the legacy directory.
  static String legacyPath(String relativePath) => instance._join(instance._requireLegacyRoot(), relativePath);

  /// Resolves an app-owned file or directory for reading.
  ///
  /// The canonical location wins. If it does not exist, the legacy location is
  /// returned when present; otherwise the canonical location is returned so a
  /// caller can create it there. Use [currentPath] when writing explicitly.
  static String resolvePath(String relativePath, {bool forWrite = false}) {
    final String canonical = currentPath(relativePath);
    if (forWrite || _exists(canonical)) return canonical;

    final String legacy = legacyPath(relativePath);
    return _exists(legacy) ? legacy : canonical;
  }

  static String settingsPath(String fileName, {bool forWrite = false}) {
    final String relative = kDebugMode ? p.join('settings', 'debug', fileName) : p.join('settings', fileName);
    return resolvePath(relative, forWrite: forWrite);
  }

  static String cachePath(String relativePath, {bool forWrite = false}) {
    return resolvePath(p.join('cache', relativePath), forWrite: forWrite);
  }

  static String pluginsPath(String relativePath, {bool forWrite = false}) {
    return resolvePath(p.join('plugins', relativePath), forWrite: forWrite);
  }

  static String databasePath(String fileName, {bool forWrite = false}) {
    return resolvePath(fileName, forWrite: forWrite);
  }

  static String temporaryPath(String relativePath) {
    return p.join(temporaryDirectory, relativePath);
  }

  static Uri fileUri(String relativePath, {bool forWrite = false}) {
    return Uri.file(resolvePath(relativePath, forWrite: forWrite));
  }

  static String ensureDirectory(String relativePath) {
    final String directoryPath = currentPath(relativePath);
    Directory(directoryPath).createSync(recursive: true);
    return directoryPath;
  }

  static bool _exists(String path) {
    return FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;
  }

  String _requireRoot() {
    final String? value = _rootPath;
    if (value == null) throw StateError('AppPaths.initialize() must complete before paths are used.');
    return value;
  }

  String _requireLegacyRoot() {
    final String? value = _legacyRootPath;
    if (value == null) throw StateError('AppPaths.initialize() must complete before paths are used.');
    return value;
  }

  String _requireTemporaryBasePath() {
    final String? value = _temporaryBasePath;
    if (value == null) throw StateError('AppPaths.initialize() must complete before paths are used.');
    return value;
  }

  String _join(String base, String relativePath) {
    final String normalized = relativePath.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return base;
    if (p.isAbsolute(normalized)) {
      throw ArgumentError.value(relativePath, 'relativePath', 'must be relative');
    }

    final List<String> segments = normalized.split('/').where((String segment) => segment.isNotEmpty).toList();
    if (segments.any((String segment) => segment == '..')) {
      throw ArgumentError.value(relativePath, 'relativePath', 'must stay below the app root');
    }
    return p.joinAll(<String>[base, ...segments]);
  }

  Future<void> _migrateLegacyData() async {
    final String sourcePath = _requireLegacyRoot();
    final String destinationPath = _requireRoot();
    if (_samePath(sourcePath, destinationPath)) return;

    final Directory source = Directory(sourcePath);
    if (!source.existsSync()) return;

    await _copyDirectoryContents(source, Directory(destinationPath));
  }

  Future<void> _copyDirectoryContents(Directory source, Directory destination) async {
    if (_samePath(source.path, destination.path)) return;
    if (!destination.existsSync()) destination.createSync(recursive: true);

    for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
      if (entity is Link) continue;
      final String destinationPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectoryContents(entity, Directory(destinationPath));
      } else if (entity is File && !File(destinationPath).existsSync()) {
        try {
          await entity.copy(destinationPath);
        } catch (_) {
          // A locked or partially-written legacy file remains available through
          // [resolvePath] and can be retried during a later startup.
        }
      }
    }
  }

  bool _samePath(String left, String right) {
    final String normalizedLeft = p.normalize(left);
    final String normalizedRight = p.normalize(right);
    if (Platform.isWindows) return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    return normalizedLeft == normalizedRight;
  }
}
