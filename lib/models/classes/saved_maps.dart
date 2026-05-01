// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../settings.dart';
import '../win32/win_utils.dart';

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

  @override
  String toString() {
    return 'AppAudioControl(name: $name, exe: $exe, path: $path, iconPath: $iconPath, iconCodePoint: $iconCodePoint, hotkeyForward: $hotkeyForward, hotkeyRewind: $hotkeyRewind, hotkeyNext: $hotkeyNext, hotkeyPrev: $hotkeyPrev, hotkeyPause: $hotkeyPause, showAnimation: $showAnimation)';
  }
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

class CliBookCategory {
  String name;
  List<CliBookItem> items;
  bool isCollapsed;
  CliBookCategory({
    required this.name,
    required this.items,
    this.isCollapsed = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'items': items.map((CliBookItem x) => x.toJson()).toList(),
        'isCollapsed': isCollapsed,
      };

  factory CliBookCategory.fromJson(Map<String, dynamic> json) => CliBookCategory(
        name: (json['name'] ?? "") as String,
        items: List<CliBookItem>.from(
          (json['items'] as List<dynamic>? ?? <dynamic>[]).map<CliBookItem>(
            (dynamic x) => CliBookItem.fromJson(x as Map<String, dynamic>),
          ),
        ),
        isCollapsed: (json['isCollapsed'] ?? false) as bool,
      );
}

class BookmarkGroup extends SavedMap {
  String title;
  String emoji;
  String viewMode;
  List<BookmarkInfo> bookmarks;
  BookmarkGroup({
    required this.title,
    required this.emoji,
    required this.bookmarks,
    this.viewMode = 'list',
  });

  BookmarkGroup copyWith({
    String? title,
    String? emoji,
    String? viewMode,
    List<BookmarkInfo>? bookmarks,
  }) {
    return BookmarkGroup(
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      viewMode: viewMode ?? this.viewMode,
      bookmarks: bookmarks ?? this.bookmarks,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'emoji': emoji,
      'viewMode': viewMode,
      'projects': bookmarks.map((BookmarkInfo x) => x.toMap()).toList(),
    };
  }

  factory BookmarkGroup.fromMap(Map<String, dynamic> map) {
    return BookmarkGroup(
      title: map['title'] as String,
      emoji: map['emoji'] as String,
      viewMode: (map['viewMode'] ?? 'list') as String,
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
  String toString() => 'ProjectGroup(title: $title, emoji: $emoji, viewMode: $viewMode, projects: $bookmarks)';

  @override
  bool operator ==(covariant BookmarkGroup other) {
    if (identical(this, other)) return true;

    return other.title == title &&
        other.emoji == emoji &&
        other.viewMode == viewMode &&
        listEquals(other.bookmarks, bookmarks);
  }

  @override
  int get hashCode => title.hashCode ^ emoji.hashCode ^ viewMode.hashCode ^ bookmarks.hashCode;
}

class BookmarkInfo {
  String emoji;
  String title;
  String stringToExecute;
  bool preferInputIcon;
  BookmarkInfo({
    required this.emoji,
    required this.title,
    required this.stringToExecute,
    this.preferInputIcon = false,
  });

  BookmarkInfo copyWith({
    String? emoji,
    String? title,
    String? stringToExecute,
    bool? preferInputIcon,
  }) {
    return BookmarkInfo(
      emoji: emoji ?? this.emoji,
      title: title ?? this.title,
      stringToExecute: stringToExecute ?? this.stringToExecute,
      preferInputIcon: preferInputIcon ?? this.preferInputIcon,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'emoji': emoji,
      'title': title,
      'stringToExecute': stringToExecute,
      'preferInputIcon': preferInputIcon,
    };
  }

  factory BookmarkInfo.fromMap(Map<String, dynamic> map) {
    return BookmarkInfo(
      emoji: map['emoji'] as String,
      title: map['title'] as String,
      stringToExecute: map['stringToExecute'] as String,
      preferInputIcon: (map['preferInputIcon'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory BookmarkInfo.fromJson(String source) => BookmarkInfo.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'ProjectInfo(emoji: $emoji, title: $title, stringToExecute: $stringToExecute, preferInputIcon: $preferInputIcon)';

  @override
  bool operator ==(covariant BookmarkInfo other) {
    if (identical(this, other)) return true;

    return other.emoji == emoji &&
        other.title == title &&
        other.stringToExecute == stringToExecute &&
        other.preferInputIcon == preferInputIcon;
  }

  @override
  int get hashCode => emoji.hashCode ^ title.hashCode ^ stringToExecute.hashCode ^ preferInputIcon.hashCode;
}

class ThemeColors {
  Color background;
  int gradientAlpha;
  Color textColor;
  Color accentColor;
  String uiFontFamily;
  int uiFontWeight;
  bool uiFontItalic;
  String entryFontFamily;
  int entryFontWeight;
  bool entryFontItalic;
  List<String> backdropImages;
  String backdropType;
  double backdropOpacity;
  List<double> panelOpacityPoints;
  String panelOpacityBegin;
  String panelOpacityEnd;
  ThemeColors({
    required this.background,
    required this.gradientAlpha,
    required this.textColor,
    required this.accentColor,
    this.uiFontFamily = 'Jura',
    this.uiFontWeight = 400,
    this.uiFontItalic = false,
    this.entryFontFamily = 'Jura',
    this.entryFontWeight = 700,
    this.entryFontItalic = false,
    this.backdropImages = const <String>[],
    this.backdropType = '',
    this.backdropOpacity = 0.7,
    this.panelOpacityPoints = const <double>[0.0, 1.0, 1.0, 1.0],
    this.panelOpacityBegin = 'Top Left',
    this.panelOpacityEnd = 'Bottom Right',
  });

// #region (collapsed) [ThemeColors]

  ThemeColors copyWith({
    Color? background,
    int? gradientAlpha,
    Color? textColor,
    Color? accentColor,
    bool? quickMenuBoldFont,
    String? uiFontFamily,
    int? uiFontWeight,
    bool? uiFontItalic,
    String? entryFontFamily,
    int? entryFontWeight,
    bool? entryFontItalic,
    List<String>? backdropImages,
    String? backdropType,
    double? backdropOpacity,
    List<double>? panelOpacityPoints,
    String? panelOpacityBegin,
    String? panelOpacityEnd,
  }) {
    return ThemeColors(
      background: background ?? this.background,
      gradientAlpha: gradientAlpha ?? this.gradientAlpha,
      textColor: textColor ?? this.textColor,
      accentColor: accentColor ?? this.accentColor,
      uiFontFamily: uiFontFamily ?? this.uiFontFamily,
      uiFontWeight: uiFontWeight ?? this.uiFontWeight,
      uiFontItalic: uiFontItalic ?? this.uiFontItalic,
      entryFontFamily: entryFontFamily ?? this.entryFontFamily,
      entryFontWeight: entryFontWeight ?? this.entryFontWeight,
      entryFontItalic: entryFontItalic ?? this.entryFontItalic,
      backdropImages: backdropImages ?? this.backdropImages,
      backdropType: backdropType ?? this.backdropType,
      backdropOpacity: backdropOpacity ?? this.backdropOpacity,
      panelOpacityPoints: panelOpacityPoints ?? this.panelOpacityPoints,
      panelOpacityBegin: panelOpacityBegin ?? this.panelOpacityBegin,
      panelOpacityEnd: panelOpacityEnd ?? this.panelOpacityEnd,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'background': background.value32bit,
      'gradientAlpha': gradientAlpha,
      'textColor': textColor.value32bit,
      'accentColor': accentColor.value32bit,
      'uiFontFamily': uiFontFamily,
      'uiFontWeight': uiFontWeight,
      'uiFontItalic': uiFontItalic,
      'entryFontFamily': entryFontFamily,
      'entryFontWeight': entryFontWeight,
      'entryFontItalic': entryFontItalic,
      'backdropImages': backdropImages,
      'backdropType': backdropType,
      'backdropOpacity': backdropOpacity,
      'panelOpacityPoints': panelOpacityPoints,
      'panelOpacityBegin': panelOpacityBegin,
      'panelOpacityEnd': panelOpacityEnd,
    };
  }

  factory ThemeColors.fromMap(Map<String, dynamic> map) {
    return ThemeColors(
      background: Color(map['background'] as int),
      gradientAlpha: map['gradientAlpha'] as int,
      textColor: Color(map['textColor'] as int),
      accentColor: Color(map['accentColor'] as int),
      uiFontFamily: (map['uiFontFamily'] ?? 'Jura') as String,
      uiFontWeight: (map['uiFontWeight'] ?? 400) as int,
      uiFontItalic: (map['uiFontItalic'] ?? false) as bool,
      entryFontFamily: (map['entryFontFamily'] ?? 'Jura') as String,
      entryFontWeight: (map['entryFontWeight'] ?? 700) as int,
      entryFontItalic: (map['entryFontItalic'] ?? false) as bool,
      backdropImages: List<String>.from(map['backdropImages'] ?? const <String>[]),
      backdropType: (map['backdropType'] ?? '') as String,
      backdropOpacity: (map['backdropOpacity'] ?? 0.7) as double,
      panelOpacityPoints: List<double>.from(
          (map['panelOpacityPoints'] as List<dynamic>?)?.map((dynamic e) => (e as num).toDouble()) ??
              const <double>[0.0, 1.0, 1.0, 1.0]),
      panelOpacityBegin: (map['panelOpacityBegin'] ?? 'Top Left') as String,
      panelOpacityEnd: (map['panelOpacityEnd'] ?? 'Bottom Right') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory ThemeColors.fromJson(String source) => ThemeColors.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ThemeColors(background: $background, gradientAlpha: $gradientAlpha, textColor: $textColor, accentColor: $accentColor, uiFontFamily: $uiFontFamily, uiFontWeight: $uiFontWeight, uiFontItalic: $uiFontItalic, entryFontFamily: $entryFontFamily, entryFontWeight: $entryFontWeight, entryFontItalic: $entryFontItalic, backdropImages: $backdropImages, backdropType: $backdropType, backdropOpacity: $backdropOpacity, panelOpacityPoints: $panelOpacityPoints, panelOpacityBegin: $panelOpacityBegin, panelOpacityEnd: $panelOpacityEnd)';
  }

  @override
  bool operator ==(covariant ThemeColors other) {
    if (identical(this, other)) return true;

    return other.background == background &&
        other.gradientAlpha == gradientAlpha &&
        other.textColor == textColor &&
        other.accentColor == accentColor &&
        other.uiFontFamily == uiFontFamily &&
        other.uiFontWeight == uiFontWeight &&
        other.uiFontItalic == uiFontItalic &&
        other.entryFontFamily == entryFontFamily &&
        other.entryFontWeight == entryFontWeight &&
        other.entryFontItalic == entryFontItalic &&
        listEquals(other.backdropImages, backdropImages) &&
        other.backdropType == backdropType &&
        other.backdropOpacity == backdropOpacity &&
        listEquals(other.panelOpacityPoints, panelOpacityPoints) &&
        other.panelOpacityBegin == panelOpacityBegin &&
        other.panelOpacityEnd == panelOpacityEnd;
  }

  @override
  int get hashCode {
    return background.hashCode ^
        gradientAlpha.hashCode ^
        textColor.hashCode ^
        accentColor.hashCode ^
        uiFontFamily.hashCode ^
        uiFontWeight.hashCode ^
        uiFontItalic.hashCode ^
        entryFontFamily.hashCode ^
        entryFontWeight.hashCode ^
        entryFontItalic.hashCode ^
        backdropImages.hashCode ^
        backdropType.hashCode ^
        panelOpacityPoints.hashCode;
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

class WallpaperSchedule extends SavedMap {
  String id;
  String name;
  bool enabled;
  int monitorIndex; // -1 for all monitors
  int startHour;
  int startMinute;
  int endHour;
  int endMinute;
  List<String> images;
  String? folderPath;
  int shuffleDelayMinutes;
  int lastChangeTimestamp;
  int currentImageIndex;
  int fillMode; // WallpaperFillMode.index

  WallpaperSchedule({
    required this.id,
    required this.name,
    this.enabled = true,
    this.monitorIndex = -1,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    required this.images,
    this.folderPath,
    this.shuffleDelayMinutes = 30,
    this.lastChangeTimestamp = 0,
    this.currentImageIndex = 0,
    this.fillMode = 4, // Default to Fill
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'enabled': enabled,
      'monitorIndex': monitorIndex,
      'startHour': startHour,
      'startMinute': startMinute,
      'endHour': endHour,
      'endMinute': endMinute,
      'images': images,
      'folderPath': folderPath,
      'shuffleDelayMinutes': shuffleDelayMinutes,
      'lastChangeTimestamp': lastChangeTimestamp,
      'currentImageIndex': currentImageIndex,
      'fillMode': fillMode,
    };
  }

  factory WallpaperSchedule.fromMap(Map<String, dynamic> map) {
    return WallpaperSchedule(
      id: (map['id'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      enabled: (map['enabled'] ?? true) as bool,
      monitorIndex: (map['monitorIndex'] ?? -1) as int,
      startHour: (map['startHour'] ?? 0) as int,
      startMinute: (map['startMinute'] ?? 0) as int,
      endHour: (map['endHour'] ?? 0) as int,
      endMinute: (map['endMinute'] ?? 0) as int,
      images: List<String>.from(map['images'] ?? <String>[]),
      folderPath: map['folderPath'] as String?,
      shuffleDelayMinutes: (map['shuffleDelayMinutes'] ?? 30) as int,
      lastChangeTimestamp: (map['lastChangeTimestamp'] ?? 0) as int,
      currentImageIndex: (map['currentImageIndex'] ?? 0) as int,
      fillMode: (map['fillMode'] ?? 4) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory WallpaperSchedule.fromJson(String source) =>
      WallpaperSchedule.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  bool operator ==(covariant WallpaperSchedule other) {
    if (identical(this, other)) return true;

    return other.id == id &&
        other.name == name &&
        other.enabled == enabled &&
        other.monitorIndex == monitorIndex &&
        other.startHour == startHour &&
        other.startMinute == startMinute &&
        other.endHour == endHour &&
        other.endMinute == endMinute &&
        listEquals(other.images, images) &&
        other.folderPath == folderPath &&
        other.shuffleDelayMinutes == shuffleDelayMinutes &&
        other.lastChangeTimestamp == lastChangeTimestamp &&
        other.currentImageIndex == currentImageIndex &&
        other.fillMode == fillMode;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        enabled.hashCode ^
        monitorIndex.hashCode ^
        startHour.hashCode ^
        startMinute.hashCode ^
        endHour.hashCode ^
        endMinute.hashCode ^
        images.hashCode ^
        folderPath.hashCode ^
        shuffleDelayMinutes.hashCode ^
        lastChangeTimestamp.hashCode ^
        currentImageIndex.hashCode ^
        fillMode.hashCode;
  }
}

class WorkspaceArea {
  double left;
  double top;
  double right;
  double bottom;
  int monitorNumber;
  String windowTitle;
  String executable;
  String parameters;
  String hookTo;
  List<String> hooks;

  WorkspaceArea({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.monitorNumber = -1,
    this.windowTitle = '',
    this.executable = '',
    this.parameters = '',
    this.hookTo = '',
    List<String>? hooks,
  }) : hooks = hooks ?? <String>[];

  WorkspaceArea copyWith({
    double? left,
    double? top,
    double? right,
    double? bottom,
    int? monitorNumber,
    String? windowTitle,
    String? executable,
    String? parameters,
    String? hookTo,
    List<String>? hooks,
  }) {
    return WorkspaceArea(
      left: left ?? this.left,
      top: top ?? this.top,
      right: right ?? this.right,
      bottom: bottom ?? this.bottom,
      monitorNumber: monitorNumber ?? this.monitorNumber,
      windowTitle: windowTitle ?? this.windowTitle,
      executable: executable ?? this.executable,
      parameters: parameters ?? this.parameters,
      hookTo: hookTo ?? this.hookTo,
      hooks: hooks ?? List<String>.from(this.hooks),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
        'monitorNumber': monitorNumber,
        'windowTitle': windowTitle,
        'executable': executable,
        'parameters': parameters,
        'hookTo': hookTo,
        'hooks': hooks,
      };

  factory WorkspaceArea.fromMap(Map<String, dynamic> map) => WorkspaceArea(
        left: (map['left'] as num?)?.toDouble() ?? 0.0,
        top: (map['top'] as num?)?.toDouble() ?? 0.0,
        right: (map['right'] as num?)?.toDouble() ?? 1.0,
        bottom: (map['bottom'] as num?)?.toDouble() ?? 1.0,
        monitorNumber: (map['monitorNumber'] ?? -1) as int,
        windowTitle: (map['windowTitle'] ?? '') as String,
        executable: (map['executable'] ?? '') as String,
        parameters: (map['parameters'] ?? '') as String,
        hookTo: (map['hookTo'] ?? '') as String,
        hooks: List<String>.from(map['hooks'] ?? <String>[]),
      );
}

class Workspace extends SavedMap {
  String id;
  String name;
  List<WorkspaceArea> areas;

  Workspace({
    required this.id,
    required this.name,
    List<WorkspaceArea>? areas,
  }) : areas = areas ?? <WorkspaceArea>[];

  Workspace copyWith({
    String? id,
    String? name,
    List<WorkspaceArea>? areas,
  }) {
    return Workspace(
      id: id ?? this.id,
      name: name ?? this.name,
      areas: areas ?? this.areas.map((WorkspaceArea a) => a.copyWith()).toList(),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'areas': areas.map((WorkspaceArea a) => a.toMap()).toList(),
      };

  factory Workspace.fromMap(Map<String, dynamic> map) => Workspace(
        id: (map['id'] ?? '') as String,
        name: (map['name'] ?? 'Workspace') as String,
        areas: (map['areas'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => WorkspaceArea.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  String toJson() => json.encode(toMap());
  factory Workspace.fromJson(String source) => Workspace.fromMap(json.decode(source) as Map<String, dynamic>);
}
