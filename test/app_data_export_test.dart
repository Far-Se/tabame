import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/platform/app_data_export.dart';
import 'package:tabame/platform/app_paths.dart';
import 'package:tabame/platform/sensitive_data_redactor.dart';

void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('tabame_app_data_export_test_');
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
      temporaryDirectory: () async => Directory(p.join(workspace.path, 'temp')),
      rootOverride: p.join(workspace.path, 'Tabame'),
      legacyRootOverride: p.join(workspace.path, 'legacy', 'Tabame'),
      migrateLegacyData: false,
    );
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  test('redacts structured and text credentials', () {
    final dynamic redacted = SensitiveDataRedactor.redactJson(<String, dynamic>{
      'theme': 'dark',
      'apiKey': 'api-secret',
      'nested': '{"token":"nested-secret","enabled":true}',
      'url': 'otpauth://totp/example?secret=otp-secret&issuer=Example',
    });

    final String encoded = jsonEncode(redacted);
    expect(encoded, contains('dark'));
    expect(encoded, isNot(contains('api-secret')));
    expect(encoded, isNot(contains('nested-secret')));
    expect(encoded, isNot(contains('otp-secret')));
    expect(SensitiveDataRedactor.redactText('Authorization: Bearer bearer-secret'), isNot(contains('bearer-secret')));
  });

  test('exports settings without secret values or secret files', () async {
    final File settings = File(AppPaths.settingsPath('settings.json', forWrite: true));
    await settings.parent.create(recursive: true);
    await settings.writeAsString(jsonEncode(<String, dynamic>{
      'flutter.themeType': 1,
      'flutter.notionApiKey': 'notion-secret',
      'flutter.runApi': '{"token":"run-secret","name":"safe"}',
      'flutter.browserToken': 'browser-secret',
    }));
    final File vault = File(AppPaths.settingsPath('vault.json', forWrite: true));
    await vault.writeAsString('{"data":"vault-secret"}');

    final File destination = File(p.join(workspace.path, 'exports', 'settings.json'));
    await AppDataExport.exportSettings(destination);
    final String output = await destination.readAsString();

    expect(output, contains('themeType'));
    expect(output, contains('safe'));
    expect(output, isNot(contains('notion-secret')));
    expect(output, isNot(contains('run-secret')));
    expect(output, isNot(contains('browser-secret')));
    expect(output, isNot(contains('vault-secret')));
    expect(output, contains(SensitiveDataRedactor.redacted));
  });
}
