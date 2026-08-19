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
  String? _pluginsDirectoryPath;

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
    _pluginsDirectoryPath = null;

    if (migrateLegacyData) await _migrateLegacyData();
    _pluginsDirectoryPath = _readConfiguredPluginsDirectory();
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
    instance._pluginsDirectoryPath = null;
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
  static String get pluginsDirectory => instance._pluginsDirectoryPath ?? currentPath('plugins');
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
    if (instance._pluginsDirectoryPath == null) {
      return resolvePath(p.join('plugins', relativePath), forWrite: forWrite);
    }
    return instance._join(pluginsDirectory, relativePath);
  }

  /// Moves the complete plugin folder to [directoryPath] and remembers the new
  /// location. An existing destination must be empty; existing data is never
  /// merged or overwritten.
  ///
  /// Returns null on success or a short error suitable for showing in the UI.
  static Future<String?> setPluginsDirectory(String directoryPath) {
    return instance._setPluginsDirectory(directoryPath);
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

  static const String _pluginsDirectoryConfigName = 'plugins_directory.txt';

  String _pluginsDirectoryConfigPath(String rootPath) {
    return p.join(
      rootPath,
      kDebugMode
          ? p.join('settings', 'debug', _pluginsDirectoryConfigName)
          : p.join('settings', _pluginsDirectoryConfigName),
    );
  }

  String? _readConfiguredPluginsDirectory() {
    final List<String> roots = <String>[_requireRoot()];
    final String legacy = _requireLegacyRoot();
    if (!_samePath(roots.first, legacy)) roots.add(legacy);

    for (final String rootPath in roots) {
      final File config = File(_pluginsDirectoryConfigPath(rootPath));
      if (!config.existsSync()) continue;
      try {
        final String value = config.readAsStringSync().trim();
        // An empty canonical config is an explicit reset to the default. This
        // also prevents the non-destructive legacy migration from re-enabling
        // an older custom path on every startup.
        if (value.isEmpty) return null;
        if (!p.isAbsolute(value)) return null;
        return _normalizeExternalPath(value);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _normalizeExternalPath(String path) {
    return p.normalize(Directory(path.trim()).absolute.path);
  }

  Future<void> _writeConfiguredPluginsDirectory(String? directoryPath) async {
    final File config = File(_pluginsDirectoryConfigPath(_requireRoot()));
    await config.parent.create(recursive: true);
    // Keep an empty marker rather than deleting the file so a reset masks a
    // copied legacy configuration, whose files are intentionally never removed.
    await config.writeAsString(directoryPath ?? '', flush: true);
  }

  Future<String?> _setPluginsDirectory(String requestedPath) async {
    final String trimmedPath = requestedPath.trim();
    if (trimmedPath.isEmpty) return 'Plugin folder path cannot be empty.';
    if (!p.isAbsolute(trimmedPath)) return 'Plugin folder path must be absolute.';

    final String sourcePath = pluginsDirectory;
    final String targetPath = _normalizeExternalPath(trimmedPath);
    if (_samePath(sourcePath, targetPath)) {
      try {
        final String? configuredPath = _samePath(targetPath, currentPath('plugins')) ? null : targetPath;
        await _writeConfiguredPluginsDirectory(configuredPath);
        _pluginsDirectoryPath = configuredPath;
        return null;
      } catch (error) {
        return 'Could not save the plugin folder setting: $error';
      }
    }

    if (_isWithin(sourcePath, targetPath) || _isWithin(targetPath, sourcePath)) {
      return 'The new plugin folder cannot contain or be inside the current folder.';
    }
    if (File(targetPath).existsSync()) return 'The selected plugin path is a file.';
    if (File(sourcePath).existsSync()) return 'The current plugin path is a file.';

    final Directory source = Directory(sourcePath);
    final Directory target = Directory(targetPath);
    final bool sourceExists = source.existsSync();
    bool destinationCreated = false;
    bool moved = false;

    try {
      if (sourceExists && target.existsSync()) {
        if (target.listSync(followLinks: false).isNotEmpty) {
          return 'The selected plugin folder is not empty.';
        }
        await target.delete();
      }

      if (sourceExists) {
        await _moveDirectory(source, target);
        moved = true;
      } else if (!target.existsSync()) {
        await target.create(recursive: true);
        destinationCreated = true;
      }

      final String? configuredPath = _samePath(targetPath, currentPath('plugins')) ? null : targetPath;
      await _writeConfiguredPluginsDirectory(configuredPath);
      _pluginsDirectoryPath = configuredPath;
      return null;
    } catch (error) {
      if (moved) {
        try {
          await _moveDirectory(target, source);
        } catch (_) {}
      } else if (destinationCreated) {
        try {
          await target.delete(recursive: true);
        } catch (_) {}
      }
      return 'Could not move the plugin folder: $error';
    }
  }

  Future<void> _moveDirectory(Directory source, Directory destination) async {
    await destination.parent.create(recursive: true);
    try {
      await source.rename(destination.path);
      return;
    } on FileSystemException {
      // Directory.rename cannot cross volumes on Windows. Fall back to a full
      // copy followed by deletion so a different drive remains a valid target.
    }

    try {
      await _copyDirectoryForMove(source, destination);
      await source.delete(recursive: true);
    } catch (_) {
      try {
        if (destination.existsSync()) await destination.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> _copyDirectoryForMove(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
      final String destinationPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectoryForMove(entity, Directory(destinationPath));
      } else if (entity is File) {
        await entity.copy(destinationPath);
      } else if (entity is Link) {
        await Link(destinationPath).create(await entity.target());
      }
    }
  }

  bool _isWithin(String child, String parent) {
    if (_samePath(child, parent)) return false;
    final String normalizedChild = _pathForComparison(p.normalize(child));
    final String normalizedParent = _pathForComparison(p.normalize(parent));
    final String separator = p.separator;
    final String prefix = normalizedParent.endsWith(separator) ? normalizedParent : '$normalizedParent$separator';
    return normalizedChild.startsWith(prefix);
  }

  String _pathForComparison(String path) {
    return Platform.isWindows ? path.toLowerCase() : path;
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
