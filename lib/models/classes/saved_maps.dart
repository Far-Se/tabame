import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../utils.dart';

abstract class SavedMap {
  const SavedMap();
}

class Reminder extends SavedMap {
  bool enabled;
  List<bool> weekDays;
  int time;
  bool repetitive;
  List<int> interval;
  String message;
  bool voiceNotification;
  Timer? timer;
  Reminder({
    required this.enabled,
    required this.weekDays,
    required this.time,
    required this.repetitive,
    required this.interval,
    required this.message,
    required this.voiceNotification,
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
    bool? repetitive,
    List<int>? interval,
    String? message,
    bool? voiceNotification,
  }) {
    return Reminder(
      enabled: enabled ?? this.enabled,
      weekDays: weekDays ?? this.weekDays,
      time: time ?? this.time,
      repetitive: repetitive ?? this.repetitive,
      interval: interval ?? this.interval,
      message: message ?? this.message,
      voiceNotification: voiceNotification ?? this.voiceNotification,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'weekDays': weekDays,
      'time': time,
      'repetitive': repetitive,
      'interval': interval,
      'message': message,
      'voiceNotification': voiceNotification,
    };
  }

  factory Reminder.fromMap(Map<String, dynamic> map) {
    return Reminder(
      enabled: (map['enabled'] ?? false) as bool,
      weekDays: List<bool>.from(map['weekDays'] ?? const <bool>[]),
      time: (map['time'] ?? 0) as int,
      repetitive: (map['repetitive'] ?? false) as bool,
      interval: List<int>.from(map['interval'] ?? const <int>[]),
      message: (map['message'] ?? '') as String,
      voiceNotification: (map['voiceNotification'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory Reminder.fromJson(String source) => Reminder.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Reminder(enabled: $enabled, weekDays: $weekDays, time: $time, repetitive: $repetitive, interval: $interval, message: $message, voiceNotification: $voiceNotification)';
  }

  @override
  bool operator ==(covariant Reminder other) {
    if (identical(this, other)) return true;

    return other.enabled == enabled &&
        listEquals(other.weekDays, weekDays) &&
        other.time == time &&
        other.repetitive == repetitive &&
        listEquals(other.interval, interval) &&
        other.message == message &&
        other.voiceNotification == voiceNotification;
  }

  @override
  int get hashCode {
    return enabled.hashCode ^ weekDays.hashCode ^ time.hashCode ^ repetitive.hashCode ^ interval.hashCode ^ message.hashCode ^ voiceNotification.hashCode;
  }
}

class PageWatcher extends SavedMap {
  String url;
  String regex;
  String lastMatch;
  bool enabled;
  int checkPeriod;
  bool voiceNotification;
  Timer? timer;
  PageWatcher({
    required this.url,
    required this.regex,
    required this.lastMatch,
    required this.enabled,
    required this.checkPeriod,
    required this.voiceNotification,
    this.timer,
  });

  PageWatcher copyWith({
    String? url,
    String? regex,
    String? lastMatch,
    bool? enabled,
    int? checkPeriod,
    bool? voiceNotification,
    Timer? timer,
  }) {
    return PageWatcher(
      url: url ?? this.url,
      regex: regex ?? this.regex,
      lastMatch: lastMatch ?? this.lastMatch,
      enabled: enabled ?? this.enabled,
      checkPeriod: checkPeriod ?? this.checkPeriod,
      voiceNotification: voiceNotification ?? this.voiceNotification,
      timer: timer ?? this.timer,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'url': url,
      'regex': regex,
      'lastMatch': lastMatch,
      'enabled': enabled,
      'checkPeriod': checkPeriod,
      'voiceNotification': voiceNotification,
    };
  }

  factory PageWatcher.fromMap(Map<String, dynamic> map) {
    return PageWatcher(
      url: (map['url'] ?? '') as String,
      regex: (map['regex'] ?? '') as String,
      lastMatch: (map['lastMatch'] ?? '') as String,
      enabled: (map['enabled'] ?? false) as bool,
      checkPeriod: (map['checkPeriod'] ?? 0) as int,
      voiceNotification: (map['voiceNotification'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory PageWatcher.fromJson(String source) => PageWatcher.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'PageWatcher(url: $url, regex: $regex, lastMatch: $lastMatch, enabled: $enabled, checkPeriod: $checkPeriod, voiceNotification: $voiceNotification, timer: $timer)';
  }

  @override
  bool operator ==(covariant PageWatcher other) {
    if (identical(this, other)) return true;

    return other.url == url &&
        other.regex == regex &&
        other.lastMatch == lastMatch &&
        other.enabled == enabled &&
        other.checkPeriod == checkPeriod &&
        other.voiceNotification == voiceNotification &&
        other.timer == timer;
  }

  @override
  int get hashCode {
    return url.hashCode ^ regex.hashCode ^ lastMatch.hashCode ^ enabled.hashCode ^ checkPeriod.hashCode ^ voiceNotification.hashCode ^ timer.hashCode;
  }
}

class ProjectGroup extends SavedMap {
  String title;
  String emoji;
  List<ProjectInfo> projects;
  ProjectGroup({
    required this.title,
    required this.emoji,
    required this.projects,
  });

  ProjectGroup copyWith({
    String? title,
    String? emoji,
    List<ProjectInfo>? projects,
  }) {
    return ProjectGroup(
      title: title ?? this.title,
      emoji: emoji ?? this.emoji,
      projects: projects ?? this.projects,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'title': title,
      'emoji': emoji,
      'projects': projects.map((ProjectInfo x) => x.toMap()).toList(),
    };
  }

  factory ProjectGroup.fromMap(Map<String, dynamic> map) {
    return ProjectGroup(
      title: map['title'] as String,
      emoji: map['emoji'] as String,
      projects: List<ProjectInfo>.from(
        (map['projects'] as List<dynamic>).map<ProjectInfo>(
          (dynamic x) => ProjectInfo.fromMap(x as Map<String, dynamic>),
        ),
      ),
    );
  }

  String toJson() => json.encode(toMap());

  factory ProjectGroup.fromJson(String source) => ProjectGroup.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ProjectGroup(title: $title, emoji: $emoji, projects: $projects)';

  @override
  bool operator ==(covariant ProjectGroup other) {
    if (identical(this, other)) return true;

    return other.title == title && other.emoji == emoji && listEquals(other.projects, projects);
  }

  @override
  int get hashCode => title.hashCode ^ emoji.hashCode ^ projects.hashCode;
}

class ProjectInfo {
  String emoji;
  String title;
  // ProjectType type;
  String stringToExecute;
  ProjectInfo({
    required this.emoji,
    required this.title,
    required this.stringToExecute,
  });

  ProjectInfo copyWith({
    String? emoji,
    String? title,
    String? stringToExecute,
  }) {
    return ProjectInfo(
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

  factory ProjectInfo.fromMap(Map<String, dynamic> map) {
    return ProjectInfo(
      emoji: map['emoji'] as String,
      title: map['title'] as String,
      stringToExecute: map['stringToExecute'] as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory ProjectInfo.fromJson(String source) => ProjectInfo.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'ProjectInfo(emoji: $emoji, title: $title, stringToExecute: $stringToExecute)';

  @override
  bool operator ==(covariant ProjectInfo other) {
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

  factory PowerShellScript.fromJson(String source) => PowerShellScript.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'PowerShellScript(command: $command, name: $name, showTerminal: $showTerminal, disabled: $disabled)';
  }

  @override
  bool operator ==(covariant PowerShellScript other) {
    if (identical(this, other)) return true;

    return other.command == command && other.name == name && other.showTerminal == showTerminal && other.disabled == disabled;
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
    return background.hashCode ^ gradientAlpha.hashCode ^ textColor.hashCode ^ accentColor.hashCode ^ quickMenuBoldFont.hashCode;
  }
// #endregion
}
