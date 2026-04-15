import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../classes/boxes/quick_menu_box.dart';
import '../win32/win32.dart';

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
  ColorPickerController._();

  static const String quickActionName = 'ColorPickerButton';
  static const String pickerWindowTitle = 'Color Picker';
  static final ColorPickerController instance = ColorPickerController._();

  Timer? _pollTimer;
  DateTime? _launchTime;
  bool _pickerWindowSeen = false;
  bool _isMonitoring = false;
  bool _isPickerWindowOpen = false;
  bool _isCompleting = false;
  String? _statusMessage;
  String? _errorMessage;
  ColorPickerCapture? _capture;

  bool get isMonitoring => _isMonitoring;
  bool get isPickerWindowOpen => _isPickerWindowOpen;
  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  ColorPickerCapture? get capture => _capture;
  ColorGridSample? get latestSample => _capture?.center;
  Offset position = const Offset(0, 0);
  Future<void> startPicking() async {
    if (_isMonitoring) return;
    position = Win32.getPosition();
    _launchTime = DateTime.now();
    _pickerWindowSeen = false;
    _isMonitoring = true;
    _isPickerWindowOpen = false;
    _isCompleting = false;
    _statusMessage = 'Launching the picker...';
    _errorMessage = null;
    notifyListeners();

    _deleteStaleGridFile();
    WinUtils.startTabame(closeCurrent: false, arguments: "-colorPicker");
    // WinUtils.runScript(Scripts.colorPicker);

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 180), (Timer timer) {
      unawaited(_pollPickerWindow(timer));
    });
  }

  Future<void> _pollPickerWindow(Timer timer) async {
    if (!_isMonitoring || _launchTime == null) {
      timer.cancel();
      return;
    }

    final bool windowOpen = _isPickerWindowPresent();
    final bool freshGridExists = _hasFreshGridFile();

    if (windowOpen) {
      if (!_pickerWindowSeen || !_isPickerWindowOpen) {
        _pickerWindowSeen = true;
        _isPickerWindowOpen = true;
        _statusMessage = 'Picker open. Click anywhere to sample a color.';
        notifyListeners();
      }
      return;
    }

    if (_isPickerWindowOpen) {
      _isPickerWindowOpen = false;
      _statusMessage = 'Reading sampled colors...';
      notifyListeners();
    }

    if (_pickerWindowSeen || freshGridExists) {
      timer.cancel();
      await _completeFromGrid();
      return;
    }

    final int secondsWaiting = DateTime.now().difference(_launchTime!).inSeconds;
    if (secondsWaiting >= 15) {
      timer.cancel();
      _finishWithError('The Color Picker window did not appear.');
      return;
    }

    if (_statusMessage != 'Waiting for the Color Picker window...') {
      _statusMessage = 'Waiting for the Color Picker window...';
      notifyListeners();
    }
  }

  Future<void> _completeFromGrid() async {
    if (_isCompleting) return;
    _isCompleting = true;
    _isMonitoring = false;
    _pollTimer?.cancel();
    _pollTimer = null;

    final ColorPickerCapture? loadedCapture = await _readCaptureWithRetry();
    if (loadedCapture == null) {
      _finishWithError('No sampled grid was found. Pick a color and try again.');
      await _reopenEditorIfNeeded();
      return;
    }

    _capture = loadedCapture;
    _statusMessage = 'Sampled ${loadedCapture.center.hex}.';
    _errorMessage = null;
    _isCompleting = false;
    notifyListeners();

    await _reopenEditorIfNeeded();
  }

  void _finishWithError(String message) {
    _isMonitoring = false;
    _isPickerWindowOpen = false;
    _isCompleting = false;
    _statusMessage = null;
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _reopenEditorIfNeeded() async {
    if (QuickMenuFunctions.isQuickMenuVisible) return;

    await QuickMenuFunctions.toggleQuickMenu(visible: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (position.dx > 0) Win32.setPosition(position);
    await Future<void>.delayed(const Duration(milliseconds: 160));
    QuickMenuFunctions.triggerQuickAction(quickActionName);
  }

  bool _isPickerWindowPresent() {
    final int handle = Win32.findWindow(pickerWindowTitle);
    if (handle == 0) return false;
    return Win32.winExists(handle);
  }

  Future<ColorPickerCapture?> _readCaptureWithRetry() async {
    final File file = _gridFile;
    for (int attempt = 0; attempt < 8; attempt++) {
      if (file.existsSync()) {
        try {
          final String raw = await file.readAsString();
          final String cleaned = raw.replaceFirst('\uFEFF', '').trim();
          if (cleaned.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            continue;
          }
          final Map<String, dynamic> map = (jsonDecode(cleaned) as Map<dynamic, dynamic>).cast<String, dynamic>();
          return ColorPickerCapture.fromMap(map);
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    return null;
  }

  bool _hasFreshGridFile() {
    final File file = _gridFile;
    if (!file.existsSync() || _launchTime == null) return false;
    return file.statSync().modified.isAfter(_launchTime!.subtract(const Duration(milliseconds: 250)));
  }

  void _deleteStaleGridFile() {
    final File file = _gridFile;
    if (file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
  }

  Directory get _scriptsDirectory => Directory('${WinUtils.getTabameAppDataFolder()}');

  File get _gridFile => File('${_scriptsDirectory.path}\\grid.json');

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
