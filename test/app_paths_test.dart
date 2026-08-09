import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/logic/error_handler.dart';
import 'package:tabame/platform/app_data_locations.dart';
import 'package:tabame/platform/app_paths.dart';
import 'package:tabame/platform/distribution_profile.dart';

void main() {
  late Directory workspace;
  late Directory canonicalRoot;
  late Directory legacyRoot;
  late Directory hostTemp;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('tabame_app_paths_test_');
    canonicalRoot = Directory(p.join(workspace.path, 'support', 'Tabame'));
    legacyRoot = Directory(p.join(workspace.path, 'legacy', 'Tabame'));
    hostTemp = Directory(p.join(workspace.path, 'host-temp'));

    final File legacySettings = File(p.join(legacyRoot.path, 'settings', 'settings.json'));
    await legacySettings.parent.create(recursive: true);
    await legacySettings.writeAsString('{"legacy":true}');

    final File legacyDatabase = File(p.join(legacyRoot.path, 'file_index.db'));
    await legacyDatabase.writeAsString('database');
    await File('${legacyDatabase.path}-wal').writeAsString('wal');
    await File('${legacyDatabase.path}-shm').writeAsString('shm');

    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: canonicalRoot.path,
      legacyRootOverride: legacyRoot.path,
    );
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  test('migrates app data and SQLite sidecars without deleting legacy files', () {
    expect(File(AppPaths.currentPath('settings/settings.json')).existsSync(), isTrue);
    expect(File(AppPaths.currentPath('file_index.db')).existsSync(), isTrue);
    expect(File(AppPaths.currentPath('file_index.db-wal')).existsSync(), isTrue);
    expect(File(AppPaths.currentPath('file_index.db-shm')).existsSync(), isTrue);

    expect(File(p.join(legacyRoot.path, 'settings', 'settings.json')).existsSync(), isTrue);
    expect(File(p.join(legacyRoot.path, 'file_index.db-wal')).existsSync(), isTrue);
    expect(AppPaths.temporaryPath('capture.png'), p.join(hostTemp.path, 'capture.png'));
    expect(AppPaths.migration.status, AppDataMigrationStatus.completed);
    expect(AppPaths.migration.version, 1);
    expect(File(p.join(canonicalRoot.path, '.tabame-data-migration.json')).existsSync(), isTrue);
  });

  test('retries an incomplete migration without deleting legacy data', () async {
    AppPaths.resetForTesting();
    final String retryRoot = p.join(workspace.path, 'retry', 'Tabame');
    int attempts = 0;
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'retry-support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'retry-cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: retryRoot,
      legacyRootOverride: legacyRoot.path,
      copyFile: (File source, File destination) async {
        attempts++;
        if (attempts == 1) throw const FileSystemException('simulated migration failure');
        await source.copy(destination.path);
      },
    );

    expect(AppPaths.migration.status, AppDataMigrationStatus.incomplete);
    expect(File(p.join(legacyRoot.path, 'settings', 'settings.json')).existsSync(), isTrue);

    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'retry-support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'retry-cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: retryRoot,
      legacyRootOverride: legacyRoot.path,
    );

    expect(AppPaths.migration.status, AppDataMigrationStatus.completed);
    expect(File(p.join(retryRoot, 'settings', 'settings.json')).readAsStringSync(), '{"legacy":true}');
    expect(File(p.join(legacyRoot.path, 'file_index.db-shm')).existsSync(), isTrue);
  });

  test('preserves canonical files during an upgrade retry', () async {
    AppPaths.resetForTesting();
    final String upgradeRoot = p.join(workspace.path, 'upgrade', 'Tabame');
    final File canonicalSettings = File(p.join(upgradeRoot, 'settings', 'settings.json'))..createSync(recursive: true);
    canonicalSettings.writeAsStringSync('{"canonical":true}');

    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'upgrade-support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'upgrade-cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: upgradeRoot,
      legacyRootOverride: legacyRoot.path,
    );

    expect(canonicalSettings.readAsStringSync(), '{"canonical":true}');
    expect(File(p.join(upgradeRoot, 'file_index.db-wal')).existsSync(), isTrue);
  });

  test('uses package-local folders for an injected MSIX provider on Windows', () async {
    if (!Platform.isWindows) return;
    AppPaths.resetForTesting();
    final Directory packageLocal = Directory(p.join(workspace.path, 'package-local'));
    final Directory packageCache = Directory(p.join(workspace.path, 'package-cache'));
    final Directory packageTemp = Directory(p.join(workspace.path, 'package-temp'));
    await AppPaths.initialize(
      profile: DistributionProfile.storeMsix,
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'unused-support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'unused-cache')),
      temporaryDirectory: () async => hostTemp,
      applicationDataLocations: () async => AppDataLocations(
        localFolder: packageLocal,
        localCacheFolder: packageCache,
        temporaryFolder: packageTemp,
      ),
      rootOverride: packageLocal.path,
      legacyRootOverride: legacyRoot.path,
      migrateLegacyData: false,
    );

    expect(AppPaths.profile, DistributionProfile.storeMsix);
    expect(AppPaths.root, packageLocal.path);
    expect(AppPaths.cacheDirectory, packageCache.path);
    expect(AppPaths.temporaryDirectory, packageTemp.path);
  });

  test('synchronous error handlers create a clean-install log directory', () async {
    AppPaths.resetForTesting();
    final String cleanRoot = p.join(workspace.path, 'clean', 'Tabame');
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support-clean')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache-clean')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: cleanRoot,
      legacyRootOverride: p.join(workspace.path, 'missing-legacy'),
      migrateLegacyData: false,
    );

    expect(handlePlatformErrors(StateError('clean install'), StackTrace.current), isTrue);
    expect(File(p.join(cleanRoot, 'errors.log')).existsSync(), isTrue);
  });

  test('resolves legacy reads without using the legacy path for writes', () async {
    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support-2')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache-2')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: p.join(workspace.path, 'canonical-2', 'Tabame'),
      legacyRootOverride: legacyRoot.path,
      migrateLegacyData: false,
    );

    expect(AppPaths.resolvePath('settings/settings.json'), p.join(legacyRoot.path, 'settings', 'settings.json'));
    expect(
      AppPaths.resolvePath('settings/settings.json', forWrite: true),
      p.join(workspace.path, 'canonical-2', 'Tabame', 'settings', 'settings.json'),
    );
  });

  test('requires settings.json instead of only the settings directory', () async {
    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support-3')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache-3')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: p.join(workspace.path, 'canonical-3', 'Tabame'),
      legacyRootOverride: p.join(workspace.path, 'missing-legacy-3', 'Tabame'),
      migrateLegacyData: false,
    );

    expect(AppPaths.hasSettingsFile, isFalse);
    await Directory(AppPaths.settingsDirectory).create(recursive: true);
    expect(AppPaths.hasSettingsFile, isFalse);

    await File(AppPaths.settingsPath('settings.json', forWrite: true)).writeAsString('{}');
    expect(AppPaths.hasSettingsFile, isTrue);
  });

  test('moves the complete plugin folder and remembers its location', () async {
    final Directory original = Directory(AppPaths.pluginsDirectory);
    await File(p.join(original.path, 'demo', 'plugin.json')).parent.create(recursive: true);
    await File(p.join(original.path, 'demo', 'plugin.json')).writeAsString('{"keyword":"demo"}');
    await File(p.join(original.path, 'demo', 'data.txt')).writeAsString('plugin data');

    final Directory custom = Directory(p.join(workspace.path, 'custom-plugins'))..createSync();
    expect(await AppPaths.setPluginsDirectory(custom.path), isNull);
    expect(AppPaths.pluginsDirectory, p.normalize(custom.absolute.path));
    expect(File(p.join(custom.path, 'demo', 'plugin.json')).existsSync(), isTrue);
    expect(File(p.join(custom.path, 'demo', 'data.txt')).readAsStringSync(), 'plugin data');
    expect(original.existsSync(), isFalse);

    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: canonicalRoot.path,
      legacyRootOverride: legacyRoot.path,
      migrateLegacyData: false,
    );
    expect(AppPaths.pluginsDirectory, p.normalize(custom.absolute.path));

    final String defaultPath = AppPaths.currentPath('plugins');
    expect(await AppPaths.setPluginsDirectory(defaultPath), isNull);
    expect(AppPaths.pluginsDirectory, p.normalize(defaultPath));
    expect(File(p.join(defaultPath, 'demo', 'plugin.json')).existsSync(), isTrue);

    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
      temporaryDirectory: () async => hostTemp,
      rootOverride: canonicalRoot.path,
      legacyRootOverride: legacyRoot.path,
      migrateLegacyData: false,
    );
    expect(AppPaths.pluginsDirectory, p.normalize(defaultPath));
  });

  test('does not move plugins into a non-empty destination', () async {
    final Directory original = Directory(AppPaths.pluginsDirectory);
    await File(p.join(original.path, 'demo', 'plugin.json')).parent.create(recursive: true);
    await File(p.join(original.path, 'demo', 'plugin.json')).writeAsString('{"keyword":"demo"}');

    final Directory destination = Directory(p.join(workspace.path, 'existing-plugins'))..createSync();
    final File existingFile = File(p.join(destination.path, 'keep.txt'));
    await existingFile.writeAsString('keep');

    expect(await AppPaths.setPluginsDirectory(destination.path), contains('not empty'));
    expect(File(p.join(original.path, 'demo', 'plugin.json')).existsSync(), isTrue);
    expect(existingFile.readAsStringSync(), 'keep');
    expect(AppPaths.pluginsDirectory, p.normalize(original.absolute.path));
  });
}
