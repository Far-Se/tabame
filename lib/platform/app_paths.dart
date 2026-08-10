import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_data_locations.dart';
import 'distribution_profile.dart';
import 'windows/windows_application_data.dart';

enum AppDataMigrationStatus {
  notRun,
  skipped,
  notNeeded,
  completed,
  incomplete,
}

class AppDataMigrationReport {
  const AppDataMigrationReport({
    required this.status,
    required this.version,
    required this.copiedFiles,
    this.error,
  });

  const AppDataMigrationReport.notRun()
      : status = AppDataMigrationStatus.notRun,
        version = 0,
        copiedFiles = 0,
        error = null;

  const AppDataMigrationReport.skipped()
      : status = AppDataMigrationStatus.skipped,
        version = 0,
        copiedFiles = 0,
        error = null;

  const AppDataMigrationReport.notNeeded()
      : status = AppDataMigrationStatus.notNeeded,
        version = 1,
        copiedFiles = 0,
        error = null;

  const AppDataMigrationReport.completed({required this.version, required this.copiedFiles})
      : status = AppDataMigrationStatus.completed,
        error = null;

  const AppDataMigrationReport.failed({required this.version, required this.copiedFiles, required this.error})
      : status = AppDataMigrationStatus.incomplete;

  final AppDataMigrationStatus status;
  final int version;
  final int copiedFiles;
  final String? error;
}

class _MigrationFile {
  const _MigrationFile({required this.source, required this.relativePath});

  final File source;
  final String relativePath;
}

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
  String? _cacheRootPath;
  String? _temporaryBasePath;
  String? _pluginsDirectoryPath;
  DistributionProfile? _profile;
  AppDataMigrationReport _migration = const AppDataMigrationReport.notRun();

  /// Initializes the path service and performs an idempotent legacy migration.
  ///
  /// The provider callbacks exist for focused tests and do not change the
  /// production path-provider behavior. [rootOverride] and
  /// [legacyRootOverride] are likewise test/import hooks; normal application
  /// startup leaves them null. [applicationDataLocations] allows tests to
  /// provide package-like locations without requiring a package identity.
  static Future<void> initialize({
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? applicationCacheDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<AppDataLocations?> Function()? applicationDataLocations,
    DistributionProfile? profile,
    String? rootOverride,
    String? legacyRootOverride,
    bool migrateLegacyData = true,
    Future<void> Function(File source, File destination)? copyFile,
  }) {
    return instance._initialize(
      applicationSupportDirectory: applicationSupportDirectory,
      applicationCacheDirectory: applicationCacheDirectory,
      temporaryDirectory: temporaryDirectory,
      applicationDataLocations: applicationDataLocations,
      profile: profile,
      rootOverride: rootOverride,
      legacyRootOverride: legacyRootOverride,
      migrateLegacyData: migrateLegacyData,
      copyFile: copyFile,
    );
  }

  Future<void> _initialize({
    Future<Directory> Function()? applicationSupportDirectory,
    Future<Directory> Function()? applicationCacheDirectory,
    Future<Directory> Function()? temporaryDirectory,
    Future<AppDataLocations?> Function()? applicationDataLocations,
    DistributionProfile? profile,
    String? rootOverride,
    String? legacyRootOverride,
    required bool migrateLegacyData,
    Future<void> Function(File source, File destination)? copyFile,
  }) async {
    final Directory supportDirectory =
        await (applicationSupportDirectory == null ? getApplicationSupportDirectory() : applicationSupportDirectory());
    final Directory hostCacheDirectory =
        await (applicationCacheDirectory == null ? getApplicationCacheDirectory() : applicationCacheDirectory());
    final Directory hostTemporaryDirectory =
        await (temporaryDirectory == null ? getTemporaryDirectory() : temporaryDirectory());

    final DistributionProfile selectedProfile = profile ?? DistributionProfileConfig.current;
    AppDataLocations? packageLocations;
    if (selectedProfile == DistributionProfile.storeMsix && Platform.isWindows) {
      packageLocations =
          await (applicationDataLocations == null ? WindowsApplicationData.resolve() : applicationDataLocations());
      if (packageLocations == null) {
        throw StateError('Windows.Storage.ApplicationData is unavailable for the storeMsix profile.');
      }
    }

    final String localAppData = _environmentPath('LOCALAPPDATA') ?? hostCacheDirectory.path;
    final String legacyRoot = legacyRootOverride ?? p.join(localAppData, 'Tabame');
    final String canonicalRoot;
    final String cacheRoot;
    final String temporaryRoot;
    if (packageLocations != null) {
      canonicalRoot = rootOverride ?? packageLocations.localFolder.path;
      cacheRoot = packageLocations.localCacheFolder.path;
      temporaryRoot = packageLocations.temporaryFolder.path;
    } else {
      canonicalRoot = rootOverride ??
          (Platform.isWindows ? p.join(localAppData, 'Tabame') : p.join(supportDirectory.path, 'Tabame'));
      cacheRoot = p.join(canonicalRoot, 'cache');
      temporaryRoot = hostTemporaryDirectory.path;
    }

    _rootPath = canonicalRoot;
    _legacyRootPath = legacyRoot;
    _cacheRootPath = cacheRoot;
    _temporaryBasePath = temporaryRoot;
    _profile = selectedProfile;
    _pluginsDirectoryPath = null;
    _migration = const AppDataMigrationReport.notRun();

    if (migrateLegacyData) {
      await _migrateLegacyData(copyFile: copyFile);
    } else {
      _migration = const AppDataMigrationReport.skipped();
    }
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
    instance._cacheRootPath = null;
    instance._temporaryBasePath = null;
    instance._pluginsDirectoryPath = null;
    instance._profile = null;
    instance._migration = const AppDataMigrationReport.notRun();
  }

  static bool get isInitialized => instance._rootPath != null;
  static DistributionProfile get profile => instance._profile ?? DistributionProfileConfig.current;
  static AppDataMigrationReport get migration => instance._migration;

  /// Whether persisted settings are available. A settings directory alone
  /// does not mean that first-run setup has been completed. The last-known-good
  /// backup also counts while settings.json is being replaced, so a second
  /// Tabame process cannot mistake a normal write window for first run.
  static bool get hasSettingsFile {
    final String readablePath = settingsPath('settings.json');
    if (File(readablePath).existsSync()) return true;

    final String writablePath = settingsPath('settings.json', forWrite: true);
    return File('$readablePath.bk').existsSync() || File('$writablePath.bk').existsSync();
  }

  static String get root => instance._requireRoot();
  static String get legacyRoot => instance._requireLegacyRoot();
  static String get settingsDirectory => currentPath(
        kDebugMode ? p.join('settings', 'debug') : 'settings',
      );
  static String get cacheDirectory => instance._requireCacheRoot();
  static String get pluginsDirectory => instance._pluginsDirectoryPath ?? currentPath('plugins');
  static String get fancyshotDirectory => currentPath('fancyshot');
  // static String get rewindlyDirectory => currentPath('rewindly');
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
    return instance._resolveCachePath(relativePath, forWrite: forWrite);
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

  /// Database files are opened read/write, so they always use the canonical
  /// root after migration. WAL and SHM sidecars therefore stay beside the same
  /// database instead of silently reopening a legacy copy.
  static String databasePath(String fileName, {bool forWrite = true}) {
    return resolvePath(fileName, forWrite: forWrite);
  }

  static String temporaryPath(String relativePath) {
    return p.join(temporaryDirectory, relativePath);
  }

  /// Removes only disposable cache data. Settings, databases, secrets, logs,
  /// plugins, and user-created output are deliberately preserved.
  static Future<void> clearCache() async {
    final Directory directory = Directory(cacheDirectory);
    if (await directory.exists()) await directory.delete(recursive: true);
    await directory.create(recursive: true);
  }

  /// Deletes all app-owned data after an explicit user decision. Installers do
  /// not call this automatically; it is separate from uninstall lifecycle.
  static Future<void> deleteAllData() async {
    final String rootPath = root;
    final String cachePath = cacheDirectory;
    if (!instance._samePath(rootPath, cachePath)) {
      final Directory cache = Directory(cachePath);
      if (await cache.exists()) await cache.delete(recursive: true);
    }
    final Directory data = Directory(rootPath);
    if (await data.exists()) await data.delete(recursive: true);
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

  String _resolveCachePath(String relativePath, {required bool forWrite}) {
    final String normalized = relativePath.trim().replaceAll('\\', '/');
    final String canonical = _join(_requireCacheRoot(), normalized);
    if (forWrite || _exists(canonical)) return canonical;
    final String legacy = _join(_requireLegacyRoot(), p.join('cache', normalized));
    return _exists(legacy) ? legacy : canonical;
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

  String _requireCacheRoot() {
    final String? value = _cacheRootPath;
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

  Future<void> _migrateLegacyData({Future<void> Function(File source, File destination)? copyFile}) async {
    final String sourcePath = _requireLegacyRoot();
    final String destinationPath = _requireRoot();
    if (_samePath(sourcePath, destinationPath)) {
      _migration = const AppDataMigrationReport.notNeeded();
      return;
    }

    final Directory source = Directory(sourcePath);
    if (!source.existsSync()) {
      _migration = const AppDataMigrationReport.notNeeded();
      return;
    }

    const int version = 1;
    final File marker = File(p.join(destinationPath, '.tabame-data-migration.json'));
    if (marker.existsSync()) {
      try {
        final Object? decoded = jsonDecode(marker.readAsStringSync());
        if (decoded is Map &&
            decoded['status'] == 'complete' &&
            decoded['version'] is num &&
            (decoded['version'] as num).toInt() >= version) {
          _migration = AppDataMigrationReport.completed(
            version: (decoded['version'] as num).toInt(),
            copiedFiles: (decoded['copiedFiles'] as num?)?.toInt() ?? 0,
          );
          return;
        }
      } catch (_) {}
    }
    final Directory staging = Directory(p.join(destinationPath, '.tabame-data-migration-staging'));
    int copiedFiles = 0;
    try {
      if (staging.existsSync()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      await _writeMigrationMarker(marker, version: version, status: 'in_progress');

      final List<_MigrationFile> files = <_MigrationFile>[];
      await _collectMigrationFiles(source, source, files);
      for (final _MigrationFile file in files) {
        final String targetPath = _migrationTarget(file.relativePath);
        if (File(targetPath).existsSync()) continue;
        final String stagedPath = p.join(staging.path, file.relativePath);
        await File(stagedPath).parent.create(recursive: true);
        if (copyFile == null) {
          await file.source.copy(stagedPath);
        } else {
          await copyFile(file.source, File(stagedPath));
        }
        final File staged = File(stagedPath);
        if (!staged.existsSync()) throw StateError('Migration copy produced no file: $stagedPath');
        await File(targetPath).parent.create(recursive: true);
        if (!File(targetPath).existsSync()) {
          await staged.rename(targetPath);
          copiedFiles++;
        }
      }

      await _writeMigrationMarker(
        marker,
        version: version,
        status: 'complete',
        copiedFiles: copiedFiles,
      );
      await staging.delete(recursive: true);
      _migration = AppDataMigrationReport.completed(version: version, copiedFiles: copiedFiles);
    } catch (error) {
      // Never delete source data or overwrite a destination file. The staging
      // directory is disposable, so a later startup can retry cleanly.
      _migration = AppDataMigrationReport.failed(version: version, copiedFiles: copiedFiles, error: '$error');
      try {
        await _writeMigrationMarker(
          marker,
          version: version,
          status: 'incomplete',
          copiedFiles: copiedFiles,
          error: '$error',
        );
      } catch (_) {}
    }
  }

  Future<void> _collectMigrationFiles(Directory root, Directory current, List<_MigrationFile> files) async {
    for (final FileSystemEntity entity in current.listSync(followLinks: false)) {
      if (entity is Link) continue;
      if (entity is Directory) {
        await _collectMigrationFiles(root, entity, files);
      } else if (entity is File) {
        files.add(_MigrationFile(
          source: entity,
          relativePath: p.relative(entity.path, from: root.path),
        ));
      }
    }
  }

  String _migrationTarget(String relativePath) {
    final String normalized = relativePath.replaceAll('\\', '/');
    if (normalized == 'cache' || normalized.startsWith('cache/')) {
      final String cacheRelative = normalized == 'cache' ? '' : normalized.substring('cache/'.length);
      return _join(_requireCacheRoot(), cacheRelative);
    }
    return _join(_requireRoot(), normalized);
  }

  Future<void> _writeMigrationMarker(
    File marker, {
    required int version,
    required String status,
    int copiedFiles = 0,
    String? error,
  }) async {
    await marker.parent.create(recursive: true);
    final Map<String, Object?> data = <String, Object?>{
      'version': version,
      'status': status,
      'copiedFiles': copiedFiles,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      if (error != null) 'error': error,
    };
    await marker.writeAsString(jsonEncode(data), flush: true);
  }

  bool _samePath(String left, String right) {
    final String normalizedLeft = p.normalize(left);
    final String normalizedRight = p.normalize(right);
    if (Platform.isWindows) return normalizedLeft.toLowerCase() == normalizedRight.toLowerCase();
    return normalizedLeft == normalizedRight;
  }
}
