// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'imports.dart';

enum ScreenState {
  notPresent,
  busy,
  runningD3dFullScreen,
  presentationMode,
  acceptsNotifications,
  quietTime,
  app,
}

class Square {
  int x = 0;
  int y = 0;
  int length = 0;
  int wide = 0;
  int width = 0;
  int height = 0;
  Square({
    required this.x,
    required this.y,
    this.length = 0,
    this.wide = 0,
    required this.width,
    required this.height,
  });

  @override
  String toString() {
    return 'Square(x: $x, y: $y, length: $length, wide: $wide, width: $width, height: $height)';
  }
}

class Monitor {
  static List<int> _monitors = [];
  static Map<int, Map<int, int>> dpi = <int, Map<int, int>>{};
  static final Map<int, int> _monitorIds = {};
  static Map<int, Square> monitorSizes = <int, Square>{};
  static List<int> get list {
    if (_monitors.isEmpty) fetchMonitor();
    return _monitors;
  }

  static Map<int, int> get monitorIds {
    if (_monitorIds.isEmpty) fetchMonitor();
    return _monitorIds;
  }

  static void fetchMonitor() {
    final monitorsData = enumMonitors();
    _monitors = monitorsData.keys.toList();
    monitorSizes = monitorsData;
    for (var i = 0; i < _monitors.length; i++) {
      final dpiX = calloc<Uint32>();
      final dpiY = calloc<Uint32>();
      GetDpiForMonitor(_monitors[i], 0, dpiX, dpiY);
      dpi[_monitors[i]] = {0: dpiX.value, 1: dpiY.value};
      free(dpiX);
      free(dpiY);
      _monitorIds[_monitors[i]] = i + 1;
    }
  }

  static int getWindowMonitor(hwnd) {
    final lpPoint = calloc<RECT>();
    GetWindowRect(hwnd, lpPoint);
    final monitor = MonitorFromRect(lpPoint, 0);
    free(lpPoint);
    return monitor;
  }

  static int getCursorMonitor() {
    final lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);
    return monitor;
  }
}

class Point {
  int X;
  int Y;
  Point({this.X = 0, this.Y = 0});
}

class AppCommand {
  static const appCommand = 0x319;
  static const bassBoost = 20 << 16;
  static const bassDown = 19 << 16;
  static const bassUp = 21 << 16;
  static const browserBackward = 1 << 16;
  static const browserFavorites = 6 << 16;
  static const browserForward = 2 << 16;
  static const browserHome = 7 << 16;
  static const browserRefresh = 3 << 16;
  static const browserSearch = 5 << 16;
  static const browserStop = 4 << 16;
  static const close = 31 << 16;
  static const copy = 36 << 16;
  static const correctionList = 45 << 16;
  static const cut = 37 << 16;
  static const dictateOrCommandControlToggle = 43 << 16;
  static const find = 28 << 16;
  static const forwardMail = 40 << 16;
  static const help = 27 << 16;
  static const launchApp1 = 17 << 16;
  static const launchApp2 = 18 << 16;
  static const launchMail = 15 << 16;
  static const launchMediaSelect = 16 << 16;
  static const mediaChannelDown = 52 << 16;
  static const mediaChannelUp = 51 << 16;
  static const mediaFastForward = 49 << 16;
  static const mediaNexttrack = 11 << 16;
  static const mediaPause = 47 << 16;
  static const mediaPlay = 46 << 16;
  static const mediaPlayPause = 14 << 16;
  static const mediaPrevioustrack = 12 << 16;
  static const mediaRecord = 48 << 16;
  static const mediaRewind = 50 << 16;
  static const mediaStop = 13 << 16;
  static const micOnOffToggle = 44 << 16;
  static const microphoneVolumeDown = 25 << 16;
  static const microphoneVolumeMute = 24 << 16;
  static const microphoneVolumeUp = 26 << 16;
  static const newFile = 29 << 16;
  static const open = 30 << 16;
  static const paste = 38 << 16;
  static const print = 33 << 16;
  static const redo = 35 << 16;
  static const replyToMail = 39 << 16;
  static const save = 32 << 16;
  static const sendMail = 41 << 16;
  static const spellCheck = 42 << 16;
  static const trebleDown = 22 << 16;
  static const trebleUp = 23 << 16;
  static const undo = 34 << 16;
  static const volumeDown = 9 << 16;
  static const volumeMute = 8 << 16;
  static const volumeUp = 10 << 16;
}
