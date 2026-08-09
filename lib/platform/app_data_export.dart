import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';
import 'sensitive_data_redactor.dart';

/// Provides explicit, secret-aware app-data operations for the interface.
class AppDataExport {
  AppDataExport._();

  static Future<File> exportSettings(File destination) async {
    final File source = File(AppPaths.settingsPath('settings.json'));
    if (!source.existsSync()) throw StateError('No settings file exists to export.');

    final Object? decoded = jsonDecode(await source.readAsString());
    if (decoded is! Map) throw const FormatException('The settings file is not a JSON object.');
    final Map<String, dynamic> safeSettings = Map<String, dynamic>.from(
      SensitiveDataRedactor.redactJson(decoded) as Map<Object?, Object?>,
    );
    final Map<String, dynamic> export = <String, dynamic>{
      'format': 'tabame-settings-export',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'settings': safeSettings,
    };
    await destination.parent.create(recursive: true);
    await destination.writeAsString('${const JsonEncoder.withIndent('  ').convert(export)}\n', flush: true);
    return destination;
  }
}
