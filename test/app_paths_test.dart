import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/logic/error_handler.dart';
import 'package:tabame/platform/app_paths.dart';

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
}
