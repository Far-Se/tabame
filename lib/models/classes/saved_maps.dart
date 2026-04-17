// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../settings.dart';
import '../win32/win32.dart';

abstract class SavedMap {
  const SavedMap();
}

class AppAudioControl extends SavedMap {
  String name;
  String exe;
  String path;
  String iconPath;
  int iconCodePoint;
  String hotkeyForward;
  String hotkeyRewind;
  String hotkeyNext;
  String hotkeyPrev;
  String hotkeyPause;
  bool showAnimation;

  AppAudioControl({
    required this.name,
    required this.exe,
    required this.path,
    required this.iconPath,
    required this.iconCodePoint,
    required this.hotkeyForward,
    required this.hotkeyRewind,
    required this.hotkeyNext,
    required this.hotkeyPrev,
    required this.hotkeyPause,
    this.showAnimation = true,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'exe': exe,
      'path': path,
      'iconPath': iconPath,
      'iconCodePoint': iconCodePoint,
      'hotkeyForward': hotkeyForward,
      'hotkeyRewind': hotkeyRewind,
      'hotkeyNext': hotkeyNext,
      'hotkeyPrev': hotkeyPrev,
      'hotkeyPause': hotkeyPause,
      'showAnimation': showAnimation,
    };
  }

  factory AppAudioControl.fromMap(Map<String, dynamic> map) {
    return AppAudioControl(
      name: (map['name'] ?? '') as String,
      exe: (map['exe'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      iconPath: (map['iconPath'] ?? '') as String,
      iconCodePoint: (map['iconCodePoint'] ?? 0) as int,
      hotkeyForward: (map['hotkeyForward'] ?? '') as String,
      hotkeyRewind: (map['hotkeyRewind'] ?? '') as String,
      hotkeyNext: (map['hotkeyNext'] ?? '') as String,
      hotkeyPrev: (map['hotkeyPrev'] ?? '') as String,
      hotkeyPause: (map['hotkeyPause'] ?? '') as String,
      showAnimation: (map['showAnimation'] ?? true) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory AppAudioControl.fromJson(String source) =>
      AppAudioControl.fromMap(json.decode(source) as Map<String, dynamic>);
}

class Reminder extends SavedMap {
  bool enabled;
  List<bool> weekDays;
  int time;
  bool repetitive;
  List<int> interval;
  String message;
  bool voiceNotification;
  int voiceVolume;
  bool persistent;
  Timer? timer;
  List<int> multipleTimes;

  Reminder({
    required this.enabled,
    required this.weekDays,
    required this.time,
    required this.multipleTimes,
    required this.repetitive,
    required this.interval,
    required this.message,
    required this.voiceNotification,
    required this.voiceVolume,
    this.persistent = false,
  });
  String get timeFormat {
    final int hour = (time ~/ 60);
    final int minute = (time % 60);
    return "${hour.toString().numberFormat()}:${minute.toString().numberFormat()}";
  }

  Reminder copyWith({
    bool? enabled,
    List<bool>? weekDays,
    int? time,
    List<int>? multipleTimes,
    bool? repetitive,
    List<int>? interval,
    String? message,
    bool? voiceNotification,
    int? voiceVolume,
    bool? persistent,
  }) {
    return Reminder(
      enabled: enabled ?? this.enabled,
      weekDays: weekDays ?? this.weekDays,
      time: time ?? this.time,
      multipleTimes: multipleTimes ?? this.multipleTimes,
      repetitive: repetitive ?? this.repetitive,
      interval: interval ?? this.interval,
      message: message ?? this.message,
      voiceNotification: voiceNotification ?? this.voiceNotification,
      voiceVolume: voiceVolume ?? this.voiceVolume,
      persistent: persistent ?? this.persistent,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'weekDays': weekDays,
      'time': time,
      'multipleTimes': multipleTimes,
      'repetitive': repetitive,
      'interval': interval,
      'message': message,
      'voiceNotification': voiceNotification,
      'voiceVolume': voiceVolume,
      'persistent': persistent,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    bool isPersistent = (map['persistent'] ?? false) as bool;
    String msg = (map['message'] ?? '') as String;

    if (msg.startsWith('p:')) {
      isPersistent = true;
      msg = msg.substring(2);
    }

    return Reminder(
      enabled: (map['enabled'] ?? false) as bool,
      weekDays: List<bool>.from(map['weekDays'] ?? const <bool>[]),
      time: (map['time'] ?? 0) as int,
      multipleTimes: List<int>.from(map['multipleTimes'] ?? const <int>[]),
      repetitive: (map['repetitive'] ?? false) as bool,
      interval: List<int>.from(map['interval'] ?? const <int>[]),
      message: msg,
      voiceNotification: (map['voiceNotification'] ?? false) as bool,
      voiceVolume: (map['voiceVolume'] ?? 100) as int,
      persistent: isPersistent,
    );
  }

  String toJson() => json.encode(toMap());

  factory Reminder.fromJson(String source) => Reminder.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Reminder(enabled: $enabled, weekDays: $weekDays, time: $time, repetitive: $repetitive, interval: $interval, message: $message, voiceNotification: $voiceNotification, voiceVolume: $voiceVolume, persistent: $persistent)';
  }

  @override
  bool operator ==(covariant Reminder other) {
    if (identical(this, other)) return true;

    return other.enabled == enabled &&
        listEquals(other.weekDays, weekDays) &&
        other.time == time &&
        other.multipleTimes == multipleTimes &&
        other.repetitive == repetitive &&
        listEquals(other.interval, interval) &&
        other.message == message &&
        other.voiceNotification == voiceNotification &&
        other.voiceVolume == voiceVolume &&
        other.persistent == persistent;
  }

  @override
  int get hashCode {
    return enabled.hashCode ^
        weekDays.hashCode ^
        time.hashCode ^
        multipleTimes.hashCode ^
        repetitive.hashCode ^
        interval.hashCode ^
        message.hashCode ^
        voiceNotification.hashCode ^
        voiceVolume.hashCode ^
        persistent.hashCode;
  }
}

class CliBookItem {
  String key;
  String value;
  String workingDirectory;
  CliBookItem({
    required this.key,
    required this.value,
    this.workingDirectory = "",
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'value': value,
        'workingDirectory': workingDirectory,
      };

  factory CliBookItem.fromJson(Map<String, dynamic> json) => CliBookItem(
        key: json['key'] as String,
        value: json['value'] as String,
        workingDirectory: (json['workingDirectory'] ?? "") as String,
      );
}

class BookmarkGroup extends SavedMap {
  String title;
  String emoji;
  List<BookmarkInfo> bookmarks;
  BookmarkGroup({
    required this.title,
    required this.emoji,
    required this.bookmarks,
  });

  BookmarkGroup copyWith({
    String? title,
    String? emoji,
    List<BookmarkInfo>? bookmarks,
  }) {
    return BookmarkGroup(
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'emoji': emoji,
      'projects': bookmarks.map((BookmarkInfo x) => x.toMap()).toList(),
    };
  }

  factory BookmarkGroup.fromMap(Map<String, dynamic> map) {
    return BookmarkGroup(
      title: map['title'] as String,
      emoji: map['emoji'] as String,
      bookmarks: List<BookmarkInfo>.from(
        (map['projects'] as List<dynamic>).map<BookmarkInfo>(
          (dynamic x) => BookmarkInfo.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory BookmarkGroup.fromJson(String source) => BookmarkGroup.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ProjectGroup(title: $title, emoji: $emoji, projects: $bookmarks)';

  @override
  bool operator ==(covariant BookmarkGroup other) {
    if (identical(this, other)) return true;

    return other.title == title && other.emoji == emoji && listEquals(other.bookmarks, bookmarks);
  }

  @override
  int get hashCode => title.hashCode ^ emoji.hashCode ^ bookmarks.hashCode;
}

class BookmarkInfo {
  String emoji;
  String title;
  // ProjectType type;
  String stringToExecute;
  BookmarkInfo({
    required this.emoji,
    required this.title,
    required this.stringToExecute,
  });

  BookmarkInfo copyWith({
    String? emoji,
    String? title,
    String? stringToExecute,
  }) {
    return BookmarkInfo(
      emoji: emoji ?? this.emoji,
      title: title ?? this.title,
      stringToExecute: stringToExecute ?? this.stringToExecute,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'emoji': emoji,
      'title': title,
      'stringToExecute': stringToExecute,
    };
  }

  factory BookmarkInfo.fromMap(Map<String, dynamic> map) {
    return BookmarkInfo(
      emoji: map['emoji'] as String,
      title: map['title'] as String,
      stringToExecute: map['stringToExecute'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory BookmarkInfo.fromJson(String source) => BookmarkInfo.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ProjectInfo(emoji: $emoji, title: $title, stringToExecute: $stringToExecute)';

  @override
  bool operator ==(covariant BookmarkInfo other) {
    if (identical(this, other)) return true;

    return other.emoji == emoji && other.title == title && other.stringToExecute == stringToExecute;
  }

  @override
  int get hashCode => emoji.hashCode ^ title.hashCode ^ stringToExecute.hashCode;
}

class PowerShellScript extends SavedMap {
  String command;
  String name;
  bool showTerminal;
  bool disabled = false;
  PowerShellScript({
    required this.command,
    required this.name,
    required this.showTerminal,
    this.disabled = false,
  });

  PowerShellScript copyWith({
    String? command,
    String? name,
    bool? showTerminal,
    bool? disabled,
  }) {
    return PowerShellScript(
      command: command ?? this.command,
      name: name ?? this.name,
      showTerminal: showTerminal ?? this.showTerminal,
      disabled: disabled ?? this.disabled,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'command': command,
      'name': name,
      'showTerminal': showTerminal,
      'disabled': disabled,
    };
  }

  factory PowerShellScript.fromMap(Map<String, dynamic> map) {
    return PowerShellScript(
      command: map['command'] as String,
      name: map['name'] as String,
      showTerminal: map['showTerminal'] as bool,
      disabled: map['disabled'] as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory PowerShellScript.fromJson(String source) =>
      PowerShellScript.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'PowerShellScript(command: $command, name: $name, showTerminal: $showTerminal, disabled: $disabled)';
  }

  @override
  bool operator ==(covariant PowerShellScript other) {
    if (identical(this, other)) return true;

    return other.command == command &&
        other.name == name &&
        other.showTerminal == showTerminal &&
        other.disabled == disabled;
  }

  @override
  int get hashCode {
    return command.hashCode ^ name.hashCode ^ showTerminal.hashCode ^ disabled.hashCode;
  }
}

class ThemeColors {
  int background;
  int gradientAlpha;
  int textColor;
  int accentColor;
  bool quickMenuBoldFont;
  ThemeColors({
    required this.background,
    required this.gradientAlpha,
    required this.textColor,
    required this.accentColor,
    required this.quickMenuBoldFont,
  });

// #region (collapsed) [ThemeColors]

  ThemeColors copyWith({
    int? background,
    int? gradientAlpha,
    int? textColor,
    int? accentColor,
    bool? quickMenuBoldFont,
  }) {
    return ThemeColors(
      background: background ?? this.background,
      gradientAlpha: gradientAlpha ?? this.gradientAlpha,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      quickMenuBoldFont: quickMenuBoldFont ?? this.quickMenuBoldFont,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'background': background,
      'gradientAlpha': gradientAlpha,
      'textColor': textColor,
      'accentColor': accentColor,
      'quickMenuBoldFont': quickMenuBoldFont,
    };
  }

  factory ThemeColors.fromMap(Map<String, dynamic> map) {
    return ThemeColors(
      background: map['background'] as int,
      gradientAlpha: map['gradientAlpha'] as int,
      textColor: map['textColor'] as int,
      accentColor: map['accentColor'] as int,
      quickMenuBoldFont: map['quickMenuBoldFont'] ?? false,
    );
  }

  String toJson() => json.encode(toMap());

  factory ThemeColors.fromJson(String source) => ThemeColors.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ThemeColors(background: $background, gradientAlpha: $gradientAlpha, textColor: $textColor, accentColor: $accentColor, quickMenuBoldFont: $quickMenuBoldFont)';
  }

  @override
  bool operator ==(covariant ThemeColors other) {
    if (identical(this, other)) return true;

    return other.background == background &&
        other.gradientAlpha == gradientAlpha &&
        other.textColor == textColor &&
        other.accentColor == accentColor &&
        other.quickMenuBoldFont == quickMenuBoldFont;
  }

  @override
  int get hashCode {
    return background.hashCode ^
        gradientAlpha.hashCode ^
        textColor.hashCode ^
        accentColor.hashCode ^
        quickMenuBoldFont.hashCode;
  }
// #endregion
}

class QuickMenuDesignThemeSet {
  ThemeColors lightTheme;
  ThemeColors darkTheme;

  QuickMenuDesignThemeSet({
    required this.lightTheme,
    required this.darkTheme,
  });

  QuickMenuDesignThemeSet copyWith({
    ThemeColors? lightTheme,
    ThemeColors? darkTheme,
  }) {
    return QuickMenuDesignThemeSet(
      lightTheme: lightTheme ?? this.lightTheme.copyWith(),
      darkTheme: darkTheme ?? this.darkTheme.copyWith(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'lightTheme': lightTheme.toMap(),
      'darkTheme': darkTheme.toMap(),
    };
  }

  factory QuickMenuDesignThemeSet.fromMap(Map<String, dynamic> map) {
    return QuickMenuDesignThemeSet(
      lightTheme: ThemeColors.fromMap(Map<String, dynamic>.from(map['lightTheme'] as Map<dynamic, dynamic>)),
      darkTheme: ThemeColors.fromMap(Map<String, dynamic>.from(map['darkTheme'] as Map<dynamic, dynamic>)),
    );
  }

  String toJson() => json.encode(toMap());

  factory QuickMenuDesignThemeSet.fromJson(String source) =>
      QuickMenuDesignThemeSet.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'QuickMenuDesignThemeSet(lightTheme: $lightTheme, darkTheme: $darkTheme)';

  @override
  bool operator ==(covariant QuickMenuDesignThemeSet other) {
    if (identical(this, other)) return true;

    return other.lightTheme == lightTheme && other.darkTheme == darkTheme;
  }

  @override
  int get hashCode => lightTheme.hashCode ^ darkTheme.hashCode;
}

class ApiRequest {
  String url;
  List<String> headers;
  List<String> data;
  String toMatch;
  List<String> matched = <String>[""];
  String result = "";
  bool parseAsJson = true;
  ApiRequest({
    required this.url,
    required this.headers,
    required this.data,
    required this.toMatch,
    this.parseAsJson = true,
  });

  ApiRequest copyWith({
    String? url,
    List<String>? headers,
    List<String>? data,
    String? toMatch,
    bool? parseAsJson,
  }) {
    return ApiRequest(
      url: url ?? this.url,
      headers: headers ?? this.headers,
      data: data ?? this.data,
      toMatch: toMatch ?? this.toMatch,
      parseAsJson: parseAsJson ?? this.parseAsJson,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'url': url,
      'headers': headers,
      'data': data,
      'toMatch': toMatch,
      'parseAsJson': parseAsJson,
    };
  }

  factory ApiRequest.fromMap(Map<String, dynamic> map) {
    return ApiRequest(
      url: (map['url'] ?? '') as String,
      headers: List<String>.from(map['headers'] ?? const <String>[]),
      data: List<String>.from(map['data'] ?? const <String>[]),
      toMatch: (map['toMatch'] ?? '') as String,
      parseAsJson: (map['parseAsJson'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory ApiRequest.fromJson(String source) => ApiRequest.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ApiRequest(url: $url, headers: $headers, data: $data, toMatch: $toMatch, matched: $matched, result: $result, parseAsJson: $parseAsJson)';
  }

  @override
  bool operator ==(covariant ApiRequest other) {
    if (identical(this, other)) return true;

    return other.url == url &&
        listEquals(other.headers, headers) &&
        listEquals(other.data, data) &&
        other.toMatch == toMatch &&
        listEquals(other.matched, matched) &&
        other.result == result &&
        other.parseAsJson == parseAsJson;
  }

  @override
  int get hashCode {
    return url.hashCode ^
        headers.hashCode ^
        data.hashCode ^
        toMatch.hashCode ^
        matched.hashCode ^
        result.hashCode ^
        parseAsJson.hashCode;
  }
}

class ApiQuery {
  String name;
  List<ApiRequest> requests;
  ApiQuery({
    required this.name,
    required this.requests,
  });

  ApiQuery copyWith({
    String? name,
    List<ApiRequest>? requests,
  }) {
    return ApiQuery(
      name: name ?? this.name,
      requests: requests ?? this.requests,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'requests': requests.map((ApiRequest x) => x.toMap()).toList(),
    };
  }

  factory ApiQuery.fromMap(Map<String, dynamic> map) {
    return ApiQuery(
      name: (map['name'] ?? '') as String,
      requests: List<ApiRequest>.from(
        (map['requests'] as List<dynamic>).map<ApiRequest>(
          (dynamic x) => ApiRequest.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory ApiQuery.fromJson(String source) => ApiQuery.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ApiQuery(name: $name, requests: $requests)';

  @override
  bool operator ==(covariant ApiQuery other) {
    if (identical(this, other)) return true;

    return other.name == name && listEquals(other.requests, requests);
  }

  @override
  int get hashCode => name.hashCode ^ requests.hashCode;
}

class RunAPI {
  String name;
  ApiRequest token = ApiRequest(url: "", headers: <String>[""], data: <String>[""], toMatch: "");
  int refreshTokenAfterMinutes = 1 * 60 * 24;
  List<ApiQuery> queries = <ApiQuery>[];
  Map<String, String> variables = <String, String>{};
  RunAPI({
    required this.name,
    ApiRequest? token,
    this.refreshTokenAfterMinutes = 1 * 60 * 24,
    this.queries = const <ApiQuery>[],
    this.variables = const <String, String>{},
  }) {
    if (token != null) this.token = token;
  }

  RunAPI copyWith({
    String? name,
    ApiRequest? token,
    int? refreshTokenAfterMinutes,
    List<ApiQuery>? queries,
  }) {
    return RunAPI(
      name: name ?? this.name,
      token: token ?? this.token,
      refreshTokenAfterMinutes: refreshTokenAfterMinutes ?? this.refreshTokenAfterMinutes,
      queries: queries ?? this.queries,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'token': token.toMap(),
      'refreshTokenAfterMinutes': refreshTokenAfterMinutes,
      'queries': queries.map((ApiQuery x) => x.toMap()).toList(),
      'variables': variables,
    };
  }

  factory RunAPI.fromMap(Map<String, dynamic> map) {
    return RunAPI(
      name: (map['name'] ?? '') as String,
      token: ApiRequest.fromMap(map['token'] as Map<String, dynamic>),
      refreshTokenAfterMinutes: (map['refreshTokenAfterMinutes'] ?? 0) as int,
      variables: map['variables'] ?? <String, String>{},
      queries: List<ApiQuery>.from(
        (map['queries'] as List<dynamic>).map<ApiQuery>(
          (dynamic x) => ApiQuery.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory RunAPI.fromJson(String source) => RunAPI.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'RunAPIBearer(name: $name, token: $token, refreshTokenAfterMinutes: $refreshTokenAfterMinutes, queries: $queries)';
  }

  @override
  bool operator ==(covariant RunAPI other) {
    if (identical(this, other)) return true;

    return other.name == name &&
        other.token == token &&
        other.refreshTokenAfterMinutes == refreshTokenAfterMinutes &&
        listEquals(other.queries, queries);
  }

  @override
  int get hashCode {
    return name.hashCode ^ token.hashCode ^ refreshTokenAfterMinutes.hashCode ^ queries.hashCode;
  }
}

class DefaultVolume {
  String type;
  String match;
  int volume;
  DefaultVolume({
    required this.type,
    required this.match,
    required this.volume,
  });

  DefaultVolume copyWith({
    String? type,
    String? match,
    int? volume,
  }) {
    return DefaultVolume(
      type: type ?? this.type,
      match: match ?? this.match,
      volume: volume ?? this.volume,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type,
      'match': match,
      'volume': volume,
    };
  }

  factory DefaultVolume.fromMap(Map<String, dynamic> map) {
    return DefaultVolume(
      type: (map['type'] ?? '') as String,
      match: (map['match'] ?? '') as String,
      volume: (map['volume'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory DefaultVolume.fromJson(String source) => DefaultVolume.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'DefaultVolume(type: $type, match: $match, volume: $volume)';

  @override
  bool operator ==(covariant DefaultVolume other) {
    if (identical(this, other)) return true;

    return other.type == type && other.match == match && other.volume == volume;
  }

  @override
  int get hashCode => type.hashCode ^ match.hashCode ^ volume.hashCode;
}

// ---------------------------------------------------------------------------
// QuickGrids – FancyZones-style custom window zones
// ---------------------------------------------------------------------------

/// Layout type for how zones are arranged inside a QuickGrid.
enum QuickGridLayoutType {
  horizontal,
  vertical,
  freestyle;

  String get label {
    switch (this) {
      case QuickGridLayoutType.horizontal:
        return 'Horizontal';
      case QuickGridLayoutType.vertical:
        return 'Vertical';
      case QuickGridLayoutType.freestyle:
        return 'Freestyle';
    }
  }

  String toJson() => name;
  static QuickGridLayoutType fromJson(String s) => QuickGridLayoutType.values.firstWhere(
        (QuickGridLayoutType v) => v.name == s,
        orElse: () {
          if (s == 'grid') return QuickGridLayoutType.freestyle; // legacy migration
          return QuickGridLayoutType.horizontal;
        },
      );
}

/// A single rectangular zone expressed as fractions of the screen (0.0–1.0).
class QuickGridRect {
  double left;
  double top;
  double right;
  double bottom;

  QuickGridRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  QuickGridRect copyWith({double? left, double? top, double? right, double? bottom}) {
    return QuickGridRect(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };

  factory QuickGridRect.fromMap(Map<String, dynamic> map) => QuickGridRect(
        left: (map['left'] as num?)?.toDouble() ?? 0.0,
        top: (map['top'] as num?)?.toDouble() ?? 0.0,
        right: (map['right'] as num?)?.toDouble() ?? 1.0,
        bottom: (map['bottom'] as num?)?.toDouble() ?? 1.0,
      );

  @override
  String toString() => 'Rect($left,$top → $right,$bottom)';
}

/// A named collection of zones (a "QuickGrid preset").
class QuickGrid {
  String id;
  String name;
  QuickGridLayoutType layoutType;

  /// Gap between zones in screen pixels when applied.
  int gap;

  /// Each entry is one rectangular zone expressed in screen fractions.
  List<QuickGridRect> zones;

  QuickGrid({
    required this.id,
    required this.name,
    this.layoutType = QuickGridLayoutType.horizontal,
    this.gap = 0,
    List<QuickGridRect>? zones,
  }) : zones = zones ?? <QuickGridRect>[];

  QuickGrid copyWith({
    String? id,
    String? name,
    QuickGridLayoutType? layoutType,
    int? gap,
    List<QuickGridRect>? zones,
  }) {
    return QuickGrid(
      id: id ?? this.id,
      name: name ?? this.name,
      layoutType: layoutType ?? this.layoutType,
      gap: gap ?? this.gap,
      zones: zones ?? this.zones.map((QuickGridRect r) => r.copyWith()).toList(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'layoutType': layoutType.toJson(),
        'gap': gap,
        'zones': zones.map((QuickGridRect r) => r.toMap()).toList(),
      };

  factory QuickGrid.fromMap(Map<String, dynamic> map) => QuickGrid(
        id: (map['id'] ?? '') as String,
        name: (map['name'] ?? 'Zone') as String,
        layoutType: QuickGridLayoutType.fromJson((map['layoutType'] ?? 'horizontal') as String),
        gap: (map['gap'] as num?)?.toInt() ?? 0,
        zones: (map['zones'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => QuickGridRect.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  String toJson() => json.encode(toMap());
  factory QuickGrid.fromJson(String source) => QuickGrid.fromMap(json.decode(source) as Map<String, dynamic>);

  /// Build an equally-divided default layout based on [layoutType].
  static List<QuickGridRect> buildDefault(QuickGridLayoutType type, int count) {
    if (count <= 0) return <QuickGridRect>[];
    final List<QuickGridRect> rects = <QuickGridRect>[];
    for (int i = 0; i < count; i++) {
      switch (type) {
        case QuickGridLayoutType.horizontal:
          rects.add(QuickGridRect(
            left: i / count,
            top: 0,
            right: (i + 1) / count,
            bottom: 1,
          ));
        case QuickGridLayoutType.vertical:
          rects.add(QuickGridRect(
            left: 0,
            top: i / count,
            right: 1,
            bottom: (i + 1) / count,
          ));
        case QuickGridLayoutType.freestyle:
          // Default freestyle: equal side-by-side columns
          rects.add(QuickGridRect(
            left: i / count,
            top: 0,
            right: (i + 1) / count,
            bottom: 1,
          ));
      }
    }
    return rects;
  }
}

class ViewsSettings {
  int minW = 10;
  int maxW = 40;
  int minH = 10;
  int maxH = 40;
  int scaleW = 15;
  int scaleH = 15;
  int scrollStepW = 5;
  int scrollStepH = 5;
  bool setPreviousSize = true;
  Color bgColor = const Color(0xff202020);
  ViewsSettings();
  Future<void> load() async {
    final String file = "${WinUtils.getTabameAppDataFolder(settings: true)}\\views.json";
    if (!File(file).existsSync()) File(file).createSync();
    String fileData = File(file).readAsStringSync();
    if (fileData.isEmpty) {
      File(file).writeAsStringSync(toJson());
      fileData = File(file).readAsStringSync();
    }
    final Map<String, dynamic> map = json.decode(fileData);
    minW = (map['minW'] ?? 10) as int;
    maxW = (map['maxW'] ?? 10) as int;
    minH = (map['minH'] ?? 30) as int;
    maxH = (map['maxH'] ?? 30) as int;
    scaleW = (map['scaleW'] ?? 15) as int;
    scaleH = (map['scaleH'] ?? 15) as int;
    scrollStepW = (map['scrollStepW'] ?? 5) as int;
    scrollStepH = (map['scrollStepH'] ?? 5) as int;
    setPreviousSize = (map['setPreviousSize'] ?? setPreviousSize) as bool;
    bgColor = Color((map['bgColor'] ?? bgColor.value32bit));
  }

  Future<void> save() async {
    final String file = "${WinUtils.getTabameAppDataFolder(settings: true)}\\views.json";
    if (!File(file).existsSync()) File(file).createSync();
    File(file).writeAsStringSync(toJson());
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'minW': minW,
      'maxW': maxW,
      'minH': minH,
      'maxH': maxH,
      'scaleW': scaleW,
      'scaleH': scaleH,
      'scrollStepW': scrollStepW,
      'scrollStepH': scrollStepH,
      'bgColor': bgColor.value32bit,
      'setPreviousSize': setPreviousSize,
    };
  }

  String toJson() => json.encode(toMap());

  @override
  String toString() {
    return 'ViewsSettings(minW: $minW, maxW: $maxW, minH: $minH, maxH: $maxH, scaleW: $scaleW, scaleH: $scaleH, scrollStepW: $scrollStepW, scrollStepH: $scrollStepH, bgColor: $bgColor)';
  }
}
