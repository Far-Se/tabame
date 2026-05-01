import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../win32/win_utils.dart';

class ColorGridSample {
  const ColorGridSample({
    required this.r,
    required this.g,
    required this.b,
    required this.hex,
  });

  final int r;
  final int g;
  final int b;
  final String hex;

  Color get color => Color.fromARGB(255, r, g, b);

  factory ColorGridSample.fromMap(Map<String, dynamic> map) {
    return ColorGridSample(
      r: (map['r'] as num?)?.toInt() ?? 0,
      g: (map['g'] as num?)?.toInt() ?? 0,
      b: (map['b'] as num?)?.toInt() ?? 0,
      hex: ((map['hex'] as String?) ?? '#000000').toUpperCase(),
    );
  }
}

class ColorPickerCapture {
  const ColorPickerCapture({
    required this.center,
    required this.grid,
  });

  final ColorGridSample center;
  final List<List<ColorGridSample>> grid;

  int get rowCount => grid.length;
  int get columnCount => grid.isEmpty ? 0 : grid.first.length;

  int get centerRow => rowCount == 0 ? 0 : rowCount ~/ 2;
  int get centerColumn => columnCount == 0 ? 0 : columnCount ~/ 2;

  factory ColorPickerCapture.fromMap(Map<String, dynamic> map) {
    final List<dynamic> gridRows = (map['grid'] as List<dynamic>? ?? <dynamic>[]);
    final Map<String, dynamic> centerMap =
        (map['center'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).cast<String, dynamic>();
    return ColorPickerCapture(
      center: ColorGridSample.fromMap(centerMap),
      grid: gridRows
          .map(
            (dynamic row) => (row as List<dynamic>)
                .map((dynamic cell) => ColorGridSample.fromMap((cell as Map<dynamic, dynamic>).cast<String, dynamic>()))
                .toList(),
          )
          .toList(),
    );
  }
}

class ColorPickerController extends ChangeNotifier {
  ColorPickerController._() {
    loadCapture();
  }

  static final ColorPickerController instance = ColorPickerController._();

  ColorPickerCapture? _capture;
  ColorPickerCapture? get capture => _capture;
  ColorGridSample? get latestSample => _capture?.center;

  Future<void> loadCapture() async {
    final ColorPickerCapture? loadedCapture = await _readCaptureWithRetry();
    if (loadedCapture != null) {
      _capture = loadedCapture;
      notifyListeners();
    }
  }

  void updateCapture(ColorPickerCapture capture) {
    _capture = capture;
    notifyListeners();
  }

  Future<ColorPickerCapture?> _readCaptureWithRetry() async {
    final File file = _gridFile;
    for (int attempt = 0; attempt < 5; attempt++) {
      if (file.existsSync()) {
        try {
          final String raw = await file.readAsString();
          final String cleaned = raw.replaceFirst('\uFEFF', '').trim();
          if (cleaned.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            continue;
          }
          final Map<String, dynamic> map = (jsonDecode(cleaned) as Map<dynamic, dynamic>).cast<String, dynamic>();
          return ColorPickerCapture.fromMap(map);
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      } else {
        return null;
      }
    }
    return null;
  }

  Directory get _appDataDirectory => Directory(WinUtils.getTabameAppDataFolder());

  File get _gridFile => File('${_appDataDirectory.path}\\grid.json');
}
