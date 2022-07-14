// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
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
  static List<int> _monitors = <int>[];
  static Map<int, Map<int, int>> dpi = <int, Map<int, int>>{};
  static final Map<int, int> _monitorIds = <int, int>{};
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
    final Map<int, Square> monitorsData = enumMonitors();
    _monitors = monitorsData.keys.toList();
    monitorSizes = monitorsData;
    for (int i = 0; i < _monitors.length; i++) {
      final Pointer<Uint32> dpiX = calloc<Uint32>();
      final Pointer<Uint32> dpiY = calloc<Uint32>();
      GetDpiForMonitor(_monitors[i], 0, dpiX, dpiY);
      dpi[_monitors[i]] = <int, int>{0: dpiX.value, 1: dpiY.value};
      free(dpiX);
      free(dpiY);
      _monitorIds[_monitors[i]] = i + 1;
    }
  }

  static int getWindowMonitor(int hwnd) {
    final Pointer<RECT> lpPoint = calloc<RECT>();
    GetWindowRect(hwnd, lpPoint);
    final int monitor = MonitorFromRect(lpPoint, 0);
    free(lpPoint);
    return monitor;
  }

  static int getCursorMonitor() {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);
    return monitor;
  }

  static int getMonitorFromPoint(Point point) {
    final Pointer<POINT> winPoint = calloc<POINT>()
      ..ref.x = point.X
      ..ref.y = point.Y;
    final int monitor = MonitorFromPoint(winPoint.ref, 0);
    free(winPoint);
    return monitor;
  }

  static Point adjustPointToDPI(Point point) {
    Point newPoint = Point(X: 0, Y: 0);
    final int monitor = getMonitorFromPoint(point);
    final double dpiCoefX = dpi[monitor]![0]! / 96.0;
    final double dpiCoefY = dpi[monitor]![1]! / 96.0;
    newPoint.X = (point.X / dpiCoefX).round();
    newPoint.Y = (point.Y / dpiCoefY).round();

    return newPoint;
  }
}

class Point {
  int X;
  int Y;
  Point({
    required this.X,
    required this.Y,
  });

  @override
  String toString() => 'Point(X: $X, Y: $Y)';

  Point copyWith({
    int? X,
    int? Y,
  }) {
    return Point(
      X: X ?? this.X,
      Y: Y ?? this.Y,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'X': X,
      'Y': Y,
    };
  }

  factory Point.fromMap(Map<String, dynamic> map) {
    return Point(
      X: map['X'] as int,
      Y: map['Y'] as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory Point.fromJson(String source) => Point.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(covariant Point other) {
    if (identical(this, other)) return true;

    return other.X == X && other.Y == Y;
  }

  @override
  int get hashCode => X.hashCode ^ Y.hashCode;
}

class AppCommand {
  static const int appCommand = 0x319;
  static const int bassBoost = 20 << 16;
  static const int bassDown = 19 << 16;
  static const int bassUp = 21 << 16;
  static const int browserBackward = 1 << 16;
  static const int browserFavorites = 6 << 16;
  static const int browserForward = 2 << 16;
  static const int browserHome = 7 << 16;
  static const int browserRefresh = 3 << 16;
  static const int browserSearch = 5 << 16;
  static const int browserStop = 4 << 16;
  static const int close = 31 << 16;
  static const int copy = 36 << 16;
  static const int correctionList = 45 << 16;
  static const int cut = 37 << 16;
  static const int dictateOrCommandControlToggle = 43 << 16;
  static const int find = 28 << 16;
  static const int forwardMail = 40 << 16;
  static const int help = 27 << 16;
  static const int launchApp1 = 17 << 16;
  static const int launchApp2 = 18 << 16;
  static const int launchMail = 15 << 16;
  static const int launchMediaSelect = 16 << 16;
  static const int mediaChannelDown = 52 << 16;
  static const int mediaChannelUp = 51 << 16;
  static const int mediaFastForward = 49 << 16;
  static const int mediaNexttrack = 11 << 16;
  static const int mediaPause = 47 << 16;
  static const int mediaPlay = 46 << 16;
  static const int mediaPlayPause = 14 << 16;
  static const int mediaPrevioustrack = 12 << 16;
  static const int mediaRecord = 48 << 16;
  static const int mediaRewind = 50 << 16;
  static const int mediaStop = 13 << 16;
  static const int micOnOffToggle = 44 << 16;
  static const int microphoneVolumeDown = 25 << 16;
  static const int microphoneVolumeMute = 24 << 16;
  static const int microphoneVolumeUp = 26 << 16;
  static const int newFile = 29 << 16;
  static const int open = 30 << 16;
  static const int paste = 38 << 16;
  static const int print = 33 << 16;
  static const int redo = 35 << 16;
  static const int replyToMail = 39 << 16;
  static const int save = 32 << 16;
  static const int sendMail = 41 << 16;
  static const int spellCheck = 42 << 16;
  static const int trebleDown = 22 << 16;
  static const int trebleUp = 23 << 16;
  static const int undo = 34 << 16;
  static const int volumeDown = 9 << 16;
  static const int volumeMute = 8 << 16;
  static const int volumeUp = 10 << 16;
}
