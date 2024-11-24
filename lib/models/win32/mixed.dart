// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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

class Dpi {
  int x;
  int y;
  double coef;
  Dpi({
    required this.x,
    required this.y,
    required this.coef,
  });
}

class Monitor {
  static List<int> _monitors = <int>[];
  static Map<int, Dpi> dpi = <int, Dpi>{};
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
      final double dpiCoef = dpiX.value / 96.0;
      dpi[_monitors[i]] = Dpi(coef: dpiCoef, x: dpiX.value, y: dpiY.value);
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

  static int getMonitorNumber(int monitorID) {
    if (_monitorIds.containsKey(monitorID)) {
      return _monitorIds[monitorID]!;
    }
    return -1;
  }

  static int getMonitorFromPoint(PointXY point) {
    final Pointer<POINT> winPoint = calloc<POINT>()
      ..ref.x = point.X
      ..ref.y = point.Y;
    final int monitor = MonitorFromPoint(winPoint.ref, 0);
    free(winPoint);
    return monitor;
  }

  static PointXY adjustPointToDPI(PointXY point) {
    PointXY newPoint = PointXY(X: 0, Y: 0);
    final int monitor = getMonitorFromPoint(point);
    if (!dpi.containsKey(monitor)) return newPoint;
    final double dpiCoefX = dpi[monitor]!.x / 96.0;
    final double dpiCoefY = dpi[monitor]!.y / 96.0;
    newPoint.X = (point.X / dpiCoefX).round();
    newPoint.Y = (point.Y / dpiCoefY).round();

    return newPoint;
  }

  static double dpiAdjust(double point, [int monitor = -1]) {
    if (monitor == -1) monitor = getCursorMonitor();
    return (point / dpi[monitor]!.coef);
  }
}

class PointXY {
  int X;
  int Y;
  PointXY({
    required this.X,
    required this.Y,
  });

  @override
  String toString() => 'Point(X: $X, Y: $Y)';

  PointXY copyWith({
    int? X,
    int? Y,
  }) {
    return PointXY(
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

  factory PointXY.fromMap(Map<String, dynamic> map) {
    return PointXY(
      X: map['X'] as int,
      Y: map['Y'] as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory PointXY.fromJson(String source) => PointXY.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(covariant PointXY other) {
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

class TimeZones {
  List<List<String>> zones = <List<String>>[
    <String>["-05:00", "ET", "US/Eastern", "America/New York"],
    <String>["-06:00", "CT", "US/Central", "America/Chicago"],
    <String>["-07:00", "MT", "US/Mountain", "America/Denver"],
    <String>["-08:00", "PT", "US/Pacific", "America/Los Angeles"],
    <String>["-09:00", "AK", "America/Anchorage", "America/Anchorage"],
    <String>["-10:00", "HAST", "Pacific/Honolulu", "Pacific/Honolulu"],
    <String>["-07:00", "MST", "US/Arizona", "America/Phoenix"],
    <String>["-04:00", "AST", "Canada/Atlantic", "America/Aruba"],
    <String>["+00:00", "MOST", "Africa/Casablanca", "Africa/Casablanca"],
    <String>["+00:00", "GMT", "Europe/London", "Europe/London"],
    <String>["+00:00", "GST", "Africa/Casablanca", "Africa/Casablanca"],
    <String>["+01:00", "WET", "Europe/Amsterdam", "Europe/Amsterdam"],
    <String>["+01:00", "CET", "Europe/Belgrade", "Europe/Belgrade"],
    <String>["+01:00", "RST", "Europe/Brussels", "Europe/Copenhagen"],
    <String>["+01:00", "CEST", "Europe/Sarajevo", "Europe/Sarajevo"],
    <String>["+01:00", "ECT", "Africa/Brazzaville", "Africa/Douala"],
    <String>["+02:00", "JST", "Europe/Athens", "Europe/Bucharest"],
    <String>["+02:00", "GTBST", "Europe/Athens", "Europe/Bucharest"],
    <String>["+02:00", "MEST", "Africa/Cairo", "Africa/Cairo"],
    <String>["+02:00", "EGST", "Africa/Cairo", "Africa/Cairo"],
    <String>["+02:00", "SST", "Africa/Cairo", "Africa/Cairo"],
    <String>["+02:00", "SAST", "Africa/Harare", "Africa/Harare"],
    <String>["+02:00", "EET", "Europe/Helsinki", "Europe/Helsinki"],
    <String>["+02:00", "ISST", "Asia/Jerusalem", "Asia/Jerusalem"],
    <String>["+02:00", "EEST", "Asia/Jerusalem", "Asia/Jerusalem"],
    <String>["+02:00", "NMST", "Asia/Jerusalem", "Asia/Jerusalem"],
    <String>["+03:00", "ARST", "Asia/Baghdad", "Asia/Baghdad"],
    <String>["+03:00", "ABST", "Asia/Kuwait", "Asia/Kuwait"],
    <String>["+03:00", "MSK", "Europe/Moscow", "Europe/Moscow"],
    <String>["+03:00", "EAT", "Asia/Kuwait", "Asia/Kuwait"],
    <String>["+03:30", "IRST", "Asia/Tehran", "Asia/Tehran"],
    <String>["+04:00", "ARBST", "Asia/Muscat", "Asia/Muscat"],
    <String>["+04:00", "AZT", "Asia/Baku", "Asia/Baku"],
    <String>["+04:00", "MUT", "Asia/Baku", "Asia/Baku"],
    <String>["+04:00", "GET", "Asia/Baku", "Asia/Baku"],
    <String>["+04:00", "AMT", "Asia/Baku", "Asia/Baku"],
    <String>["+04:30", "AFT", "Asia/Baku", "Asia/Baku"],
    <String>["+05:00", "YEKT", "Asia/Tashkent", "Asia/Yekaterinburg"],
    <String>["+05:00", "PKT", "Asia/Tashkent", "Asia/Karachi"],
    <String>["+05:00", "WAST", "Asia/Tashkent", "Asia/Yekaterinburg"],
    <String>["+05:30", "IST", "Asia/Calcutta", "Asia/Calcutta"],
    <String>["+05:30", "SLT", "Asia/Calcutta", "Asia/Calcutta"],
    <String>["+05:45", "NPT", "Asia/Katmandu", "Asia/Katmandu"],
    <String>["+06:00", "BTT", "Asia/Dhaka", "Asia/Dhaka"],
    <String>["+06:00", "BST", "Asia/Dhaka", "Asia/Dhaka"],
    <String>["+06:00", "NCAST", "Asia/Almaty", "Asia/Dhaka"],
    <String>["+06:30", "MYST", "Asia/Rangoon", "Asia/Rangoon"],
    <String>["+07:00", "THA", "Asia/Bangkok", "Asia/Bangkok"],
    <String>["+07:00", "KRAT", "Asia/Bangkok", "Asia/Bangkok"],
    <String>["+08:00", " ", "Asia/Hong Kong", "Asia/Hong Kong"],
    <String>["+08:00", "IRKT", "Asia/Irkutsk", "Asia/Irkutsk"],
    <String>["+08:00", "SNST", "Asia/Singapore", "Asia/Taipei"],
    <String>["+08:00", "AWST", "Australia/Perth", "Australia/Perth"],
    <String>["+08:00", "TIST", "Asia/Taipei", "Asia/Taipei"],
    <String>["+08:00", "UST", "Asia/Taipei", "Asia/Taipei"],
    <String>["+09:00", "TST", "Asia/Tokyo", "Asia/Tokyo"],
    <String>["+09:00", "KST", "Asia/Seoul", "Asia/Seoul"],
    <String>["+09:00", "YAKT", "Asia/Yakutsk", "Asia/Yakutsk"],
    <String>["+09:30", "CAUST", "Australia/Adelaide", "Australia/Adelaide"],
    <String>["+09:30", "ACST", "Australia/Darwin", "Australia/Darwin"],
    <String>["+10:00", "EAST", "Australia/Brisbane", "Australia/Brisbane"],
    <String>["+10:00", "AEST", "Australia/Sydney", "Australia/Sydney"],
    <String>["+10:00", "WPST", "Pacific/Guam", "Pacific/Guam"],
    <String>["+10:00", "TAST", "Australia/Hobart", "Australia/Hobart"],
    <String>["+10:00", "VLAT", "Asia/Vladivostok", "Asia/Vladivostok"],
    <String>["+11:00", "SBT", "Pacific/Guadalcanal", "Pacific/Guadalcanal"],
    <String>["+12:00", "NZST", "Pacific/Auckland", "Pacific/Auckland"],
    <String>["+12:00", "12", "Etc/GMT-12", "Etc/GMT-12"],
    <String>["+12:00", "FJT", "Pacific/Fiji", "Pacific/Fiji"],
    <String>["+12:00", "PETT", "Asia/Kamchatka", "Etc/GMT+12"],
    <String>["+13:00", "PHOT", "Pacific/Tongatapu", "Pacific/Tongatapu"],
    <String>["-01:00", "AZOST", "Atlantic/Azores", "Atlantic/Azores"],
    <String>["-01:00", "CVT", "Atlantic/Cape Verde", "Atlantic/Cape Verde"],
    <String>["-03:00", "ESAST", "America/Sao_Paulo", "America/Sao_Paulo"],
    <String>["-03:00", "ART", "America/Buenos Aires", "America/Buenos Aires"],
    <String>["-03:00", "SAEST", "SA Eastern Standard Time", "SA Eastern Standard Time"],
    <String>["-03:00", "GNST", "America/Godthab", "America/Godthab"],
    <String>["-03:00", "MVST", "America/Godthab", "America/Montevideo"],
    <String>["-03:30", "NST", "Canada/Newfoundland", "Canada/Newfoundland"],
    <String>["-04:00", "PRST", "Canada/Atlantic", "America/Aruba"],
    <String>["-04:00", "CBST", "Canada/Atlantic", "America/Aruba"],
    <String>["-04:00", "SAWST", "America/Santiago", "America/Santiago"],
    <String>["-04:00", "PSAST", "America/Santiago", "America/Santiago"],
    <String>["-04:30", "VST", "America/Caracas", "America/Caracas"],
    <String>["-05:00", "SAPST", "America/Bogota", "America/Bogota"],
    <String>["-05:00", "EST", "US/East-Indiana", "America/Halifax"],
    <String>["-06:00", "CAST", "America/El_Salvador", "America/Mexico_City"],
    <String>["-06:00", "CST", "America/Mexico_City", "America/Mexico_City"],
    <String>["-06:00", "CCST", "Canada/Saskatchewan", "Canada/Saskatchewan"],
    <String>["-07:00", "MSTM", "America/Chihuahua", "America/Mazatlan"],
    <String>["-08:00", "PST", "US/Pacific", "America/Los Angeles"],
    <String>["-11:00", "SMST", "Pacific/Midway", "Pacific/Midway"],
    <String>["-12:00", "BIT", "Etc/GMT+12", "Etc/GMT+12"]
  ];
  List<List<String>> getTime(String timezone) {
    List<List<String>> output = <List<String>>[];
    for (List<String> z in zones) {
      final List<String> names = <String>[...z];
      final String time = names.removeAt(0);
      for (String name in names) {
        if (name.toLowerCase().contains(timezone)) {
          output.add(<String>[time, ...names]);
          break;
        }
      }
    }
    return output;
  }
}
