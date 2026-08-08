import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app_paths.dart';

/// Settings used by the portable MVP shell. It deliberately owns a small
/// additive file instead of importing the Windows-only Settings graph.
class PortableSettings extends ChangeNotifier {
  PortableSettings({
    required this.darkMode,
    required this.accentValue,
    required List<String> searchRoots,
  }) : searchRoots = <String>[...searchRoots];

  static const String fileName = 'portable_shell.json';

  bool darkMode;
  int accentValue;
  final List<String> searchRoots;

  Color get accentColor => Color(accentValue);

  ThemeData get theme {
    final Brightness brightness = darkMode ? Brightness.dark : Brightness.light;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: Color.lerp(scheme.surface, scheme.surfaceContainerHighest, 0.16),
    );
  }

  static Future<PortableSettings> load() async {
    final PortableSettings defaults = PortableSettings(
      darkMode: true,
      accentValue: 0xffa7cf3f,
      searchRoots: const <String>[],
    );
    final File file = File(AppPaths.resolvePath(fileName));
    if (!file.existsSync()) return defaults;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return defaults;
      final Object? rawAccent = decoded['accent'];
      final Object? rawRoots = decoded['searchRoots'];
      return PortableSettings(
        darkMode: decoded['darkMode'] != false,
        accentValue: rawAccent is num ? rawAccent.toInt() : defaults.accentValue,
        searchRoots: rawRoots is List ? rawRoots.whereType<String>().toList(growable: false) : const <String>[],
      );
    } catch (_) {
      return defaults;
    }
  }

  Future<void> save() => _writeValues();

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    notifyListeners();
    await _writeValues();
  }

  Future<void> setAccentColor(Color value) async {
    accentValue = value.toARGB32();
    notifyListeners();
    await _writeValues();
  }

  Future<void> addSearchRoot(String path) async {
    if (path.trim().isEmpty || searchRoots.contains(path)) return;
    searchRoots.add(path);
    notifyListeners();
    await _writeValues();
  }

  Future<void> _writeValues() async {
    final File file = File(AppPaths.currentPath(fileName));
    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'darkMode': darkMode,
        'accent': accentValue,
        'searchRoots': searchRoots,
      }),
    );
  }
}
