import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/platform/app_catalog_service.dart';
import 'package:tabame/platform/app_paths.dart';
import 'package:tabame/platform/linux_app_catalog_provider.dart';
import 'package:tabame/platform/macos_app_catalog_provider.dart';
import 'package:tabame/platform/portable_file_search.dart';
import 'package:tabame/platform/portable_settings.dart';

void main() {
  group('Linux app catalog provider', () {
    late Directory workspace;
    late Directory userData;
    late Directory systemData;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('tabame_linux_catalog_test_');
      userData = Directory(p.join(workspace.path, 'user'));
      systemData = Directory(p.join(workspace.path, 'system'));
      await _writeDesktopEntry(
        userData,
        'demo.desktop',
        '''[Desktop Entry]
Type=Application
Name=User Demo
Exec=/usr/bin/demo --name "User Demo" %U
''',
      );
      await _writeDesktopEntry(
        systemData,
        'demo.desktop',
        '''[Desktop Entry]
Type=Application
Name=System Demo
Exec=/usr/bin/demo
''',
      );
      await _writeDesktopEntry(
        systemData,
        'hidden.desktop',
        '''[Desktop Entry]
Type=Application
Name=Hidden
Exec=/usr/bin/hidden
Hidden=true
''',
      );
      await _writeDesktopEntry(
        systemData,
        'nodisplay.desktop',
        '''[Desktop Entry]
Type=Application
Name=No Display
Exec=/usr/bin/nodisplay
NoDisplay=true
''',
      );
    });

    tearDown(() async {
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    });

    test('parses Exec values and gives user entries duplicate precedence', () async {
      final LinuxAppCatalogProvider provider = LinuxAppCatalogProvider(
        dataRoots: <String>[userData.path, systemData.path],
        available: true,
      );

      final AppCatalogSnapshot snapshot = await provider.discover();

      expect(snapshot.complete, isTrue);
      expect(snapshot.records, hasLength(1));
      expect(snapshot.records.single.name, 'User Demo');
      expect(snapshot.records.single.stableId, 'linux:desktop:demo.desktop');
      expect(
        LinuxAppCatalogProvider.parseExec(r'/usr/bin/demo --name "A B" --path=hello\ world %U'),
        <String>['/usr/bin/demo', '--name', 'A B', '--path=hello world'],
      );
    });

    test('honors hidden overrides and DBusActivatable desktop entries', () async {
      await _writeDesktopEntry(
        userData,
        'masked.desktop',
        '''[Desktop Entry]
Type=Application
Name=Masked by User
Hidden=true
''',
      );
      await _writeDesktopEntry(
        systemData,
        'masked.desktop',
        '''[Desktop Entry]
Type=Application
Name=System Masked
Exec=/usr/bin/masked
''',
      );
      await _writeDesktopEntry(
        systemData,
        'dbus.desktop',
        '''[Desktop Entry]
Type=Application
Name=DBus Demo
DBusActivatable=true
''',
      );

      final AppCatalogSnapshot snapshot = await LinuxAppCatalogProvider(
        dataRoots: <String>[userData.path, systemData.path],
        available: true,
      ).discover();

      expect(snapshot.records.map((AppCatalogRecord record) => record.name), contains('DBus Demo'));
      expect(snapshot.records.map((AppCatalogRecord record) => record.name), isNot(contains('System Masked')));
    });
  });

  group('macOS app catalog provider', () {
    late Directory workspace;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('tabame_macos_catalog_test_');
      final Directory resources = Directory(p.join(workspace.path, 'Demo.app', 'Contents', 'Resources'));
      await resources.create(recursive: true);
      await File(p.join(resources.parent.path, 'Info.plist')).writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.example.demo</string>
<key>CFBundleDisplayName</key><string>Demo &amp; Tools</string>
</dict></plist>
''');
      await File(p.join(resources.path, 'demo.icns')).writeAsString('icon');
    });

    tearDown(() async {
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    });

    test('discovers bundle identity and icon metadata without native APIs', () async {
      final MacOSAppCatalogProvider provider = MacOSAppCatalogProvider(
        applicationRoots: <String>[workspace.path],
        available: true,
      );

      final AppCatalogSnapshot snapshot = await provider.discover();

      expect(snapshot.complete, isTrue);
      expect(snapshot.records, hasLength(1));
      expect(snapshot.records.single.stableId, 'macos:com.example.demo');
      expect(snapshot.records.single.name, 'Demo & Tools');
      expect(snapshot.records.single.iconPath, endsWith(p.join('Resources', 'demo.icns')));
    });
  });

  test('portable file search skips hidden and build-heavy folders without AppPaths', () async {
    AppPaths.resetForTesting();
    final Directory workspace = await Directory.systemTemp.createTemp('tabame_portable_search_test_');
    try {
      await File(p.join(workspace.path, 'visible-match.txt')).writeAsString('match');
      await File(p.join(workspace.path, '.hidden-match.txt')).writeAsString('match');
      await File(p.join(workspace.path, 'build', 'ignored-match.txt')).create(recursive: true);
      await File(p.join(workspace.path, 'node_modules', 'ignored-match.txt')).create(recursive: true);
      await File(p.join(workspace.path, 'nested', 'target-note.md')).create(recursive: true);

      final List<PortableFileResult> explicitResults = await const PortableFileSearchService().search(
        'match',
        roots: <String>[workspace.path, workspace.path],
        maxDepth: 3,
      );
      expect(explicitResults.map((PortableFileResult result) => result.name), contains('visible-match.txt'));
      expect(explicitResults.map((PortableFileResult result) => result.name), isNot(contains('.hidden-match.txt')));
      expect(explicitResults.map((PortableFileResult result) => result.name), isNot(contains('ignored-match.txt')));

      final List<PortableFileResult> nestedResults = await const PortableFileSearchService().search(
        'target',
        roots: <String>[workspace.path],
        maxDepth: 3,
      );
      expect(nestedResults.map((PortableFileResult result) => result.name), contains('target-note.md'));
    } finally {
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    }
  });

  test('portable settings round-trip through AppPaths', () async {
    final Directory workspace = await Directory.systemTemp.createTemp('tabame_portable_settings_test_');
    try {
      AppPaths.resetForTesting();
      await AppPaths.initialize(
        applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
        applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
        temporaryDirectory: () async => Directory(p.join(workspace.path, 'temp')),
        rootOverride: p.join(workspace.path, 'support', 'Tabame'),
        legacyRootOverride: p.join(workspace.path, 'legacy', 'Tabame'),
        migrateLegacyData: false,
      );

      final PortableSettings settings = PortableSettings(
        darkMode: false,
        accentValue: const Color(0xff123456).toARGB32(),
        searchRoots: <String>[p.join(workspace.path, 'Documents')],
      );
      await settings.save();

      final PortableSettings loaded = await PortableSettings.load();
      expect(loaded.darkMode, isFalse);
      expect(loaded.accentColor, const Color(0xff123456));
      expect(loaded.searchRoots, <String>[p.join(workspace.path, 'Documents')]);
    } finally {
      AppPaths.resetForTesting();
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    }
  });
}

Future<void> _writeDesktopEntry(Directory dataRoot, String name, String content) async {
  final File file = File(p.join(dataRoot.path, 'applications', name));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}
