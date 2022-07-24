// ignore_for_file: public_member_api_docs, sort_constructors_first
/// [flutter pub run build_runner build]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'package:tabamewin32/tabamewin32.dart';

import '../main.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

extension Truncate on String {
  String truncate(int max, {String suffix = ''}) => length < max ? this : replaceRange(max, null, suffix);
}

extension StringExtension on String {
  String toUpperCaseFirst() {
    if (length < 2) return toUpperCase();
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }

  String toUperCaseAll() => toUpperCase();
  String toUpperCaseEach() => split(" ").map((String str) => str.toUpperCaseFirst()).join(" ");
  String numberFormat({int minNr = 10}) {
    return (int.parse(this) / minNr).toDouble().toString().replaceAll('.', '');
  }
}

num darkerColor(int color, {int darkenBy = 0x10, int floor = 0x0}) {
  final num darkerHex = (max((color >> 16) - darkenBy, floor) << 16) + (max(((color & 0xff00) >> 8) - darkenBy, floor) << 8) + max(((color & 0xff) - darkenBy), floor);
  return darkerHex;
}

enum TaskBarAppsStyle { onlyActiveMonitor, activeMonitorFirst, orderByActivity }

enum VolumeOSDStyle { normal, media, visible, thin }

enum ThemeType { system, light, dark, schedule }

class Settings {
  bool hideTaskbarOnStartup = true;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;
  String language = Platform.localeName.substring(0, 2);
  List<String> weather = <String>['10 C', "berlin, Germany", "m", "%c+%t"]; //u for US

  bool showMediaControlForApp = true;

  bool showTrayBar = true;

  bool showWeather = true;

  bool showPowerShell = true;

  bool runAsAdministrator = false;

  bool showSystemUsage = false;
  int themeScheduleMin = 0;
  int themeScheduleMax = 0;

  ThemeColors lightTheme = ThemeColors(background: 0xffD5E0FB, textColor: 0xff3A404A, accentColor: 0xff446EE9, gradientAlpha: 200, quickMenuBoldFont: true);

  ThemeColors darkTheme = ThemeColors(background: 0xFF3B414D, accentColor: 0xDCFFDCAA, gradientAlpha: 200, textColor: 0xFFFAF9F8, quickMenuBoldFont: true);

  bool quickMenuPinnedWithTrayAtBottom = false;

  String currentVersion = "0.5.1";

  String customLogo = "";

  String customSpash = "";

  String get themeScheduleMinFormat {
    final int hour = (themeScheduleMin ~/ 60);
    final int minute = (themeScheduleMin % 60);
    return "${hour.toString().numberFormat()}:${minute.toString().numberFormat()}";
  }

  String get themeScheduleMaxFormat {
    final int hour = (themeScheduleMax ~/ 60);
    final int minute = (themeScheduleMax % 60);
    return "${hour.toString().numberFormat()}:${minute.toString().numberFormat()}";
  }

  set weatherTemperature(String temp) => weather[0] = temp;
  String get weatherTemperature => weather[0];

  set weatherCity(String temp) => weather[1] = temp;
  String get weatherCity => weather[1];

  set weatherUnit(String temp) => weather[2] = temp;
  String get weatherUnit => weather[2]; //m for metric, u for US

  set weatherFormat(String temp) => weather[3] = temp;
  String get weatherFormat => weather[3];

  bool showQuickMenuAtTaskbarLevel = true;
  VolumeOSDStyle volumeOSDStyle = VolumeOSDStyle.normal;

  ThemeType themeType = ThemeType.system;
  ThemeType get themeTypeMode {
    if (themeType == ThemeType.system) {
      if (MediaQueryData.fromWindow(WidgetsBinding.instance.window).platformBrightness == Brightness.dark) return ThemeType.dark;
      return ThemeType.light;
    } else if (themeType == ThemeType.schedule) {
      final int minTime = globalSettings.themeScheduleMin;
      final int maxTime = globalSettings.themeScheduleMax;
      final int now = (DateTime.now().hour * 60) + DateTime.now().minute;
      ThemeType scheduled;
      if (minTime < maxTime) {
        scheduled = (now > minTime && now < maxTime) ? ThemeType.dark : ThemeType.light;
      } else {
        scheduled = (now > minTime || now < maxTime) ? ThemeType.dark : ThemeType.light;
      }
      return scheduled;
    }
    return themeType;
  }

  ThemeColors get themeColors {
    final ThemeType x = themeTypeMode;
    if (x == ThemeType.dark) return darkTheme;
    return lightTheme;
  }

  ThemeColors get theme => themeColors;
}

Settings globalSettings = Settings();

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

late Timer monitorChecker;
Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Main Handle
  Monitor.fetchMonitor();
  monitorChecker = Timer.periodic(const Duration(seconds: 10), (Timer timer) => Monitor.fetchMonitor());
  await Boxes.registerBoxes();
}

unregisterAll() {
  monitorChecker.cancel();
}

class Boxes {
  static late SharedPreferences pref;
  static List<String> mediaControls = <String>[];
  Boxes();
  static Future<void> registerBoxes() async {
    pref = await SharedPreferences.getInstance();
    //? Settings
    if (pref.getString("language") == null) {
      await pref.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await pref.setInt("volumeOSDStyle", VolumeOSDStyle.normal.index);

      await pref.setInt("themeType", ThemeType.system.index);
      await pref.setString("lightTheme", globalSettings.lightTheme.toJson());
      await pref.setString("darkTheme", globalSettings.darkTheme.toJson());

      await pref.setString("language", Platform.localeName.substring(0, 2));
      String city = "berlin, germany";
      // ? Get city from IP
      final http.Response ip = await http.get(Uri.parse("http://ifconfig.me/ip"));
      if (ip.statusCode == 200) {
        final http.Response response = await http.get(Uri.parse("http://ip-api.com/json/${ip.body}"));
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body);
          if (data.containsKey("city") && data.containsKey("country")) {
            city = "${data["city"]}, ${data["country"]}";
          }
        }
      }
      await pref.setStringList("weather", <String>["10 C", city, "m", "%c+%t"]);
      await pref.setBool("hideTaskbarOnStartup", false);
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setBool("showMediaControlForApp", true);
      await pref.setBool("showTrayBar", true);
      await pref.setBool("showWeather", true);
      await pref.setBool("showPowerShell", true);
      await pref.setBool("showSystemUsage", false);
      await pref.setBool("runAsAdministrator", false);
      await setStartOnSystemStartup(true);
      pref = await SharedPreferences.getInstance();
    }
    globalSettings
      ..hideTaskbarOnStartup = pref.getBool("hideTaskbarOnStartup") ?? false
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..themeType = ThemeType.values[pref.getInt("themeType") ?? 0]
      ..themeScheduleMin = pref.getInt("themeScheduleMin") ?? 0
      ..themeScheduleMax = pref.getInt("themeScheduleMax") ?? 0
      ..language = pref.getString("language") ?? Platform.localeName.substring(0, 2)
      ..customLogo = pref.getString("customLogo") ?? ""
      ..customSpash = pref.getString("customSpash") ?? ""
      ..weather = pref.getStringList("weather") ?? <String>["10 C", "berlin, germany", "m", "%c+%t"]
      ..volumeOSDStyle = VolumeOSDStyle.values[pref.getInt("volumeOSDStyle") ?? 0]
      ..showQuickMenuAtTaskbarLevel = pref.getBool("showQuickMenuAtTaskbarLevel") ?? true
      ..showMediaControlForApp = pref.getBool("showMediaControlForApp") ?? true
      ..showTrayBar = pref.getBool("showTrayBar") ?? false
      ..showWeather = pref.getBool("showWeather") ?? false
      ..showPowerShell = pref.getBool("showPowerShell") ?? false
      ..runAsAdministrator = pref.getBool("runAsAdministrator") ?? false
      ..quickMenuPinnedWithTrayAtBottom = pref.getBool("quickMenuPinnedWithTrayAtBottom") ?? false
      ..showSystemUsage = pref.getBool("showSystemUsage") ?? false;

    final String? lightTheme = pref.getString("lightTheme");
    final String? darkTheme = pref.getString("darkTheme");
    if (lightTheme == null || darkTheme == null) {
      pref.setString("lightTheme", globalSettings.lightTheme.toJson());
      pref.setString("darkTheme", globalSettings.darkTheme.toJson());
    }
    if (lightTheme != null) globalSettings.lightTheme = ThemeColors.fromJson(lightTheme);
    if (darkTheme != null) globalSettings.darkTheme = ThemeColors.fromJson(darkTheme);
    themeChangeNotifier.value = !themeChangeNotifier.value;
    //? Pinned Apps
    if (pref.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await pref.setStringList("pinnedApps", pinnedApps2);
    }

    if (pref.getString("powerShellScripts") == null) {
      final List<String> powerShellScripts = <String>[
        PowerShellScript(name: "Show IP", command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content", showTerminal: true).toJson()
      ];
      await pref.setString("powerShellScripts", jsonEncode(powerShellScripts));
    }
    //? Taskbar
    if (kReleaseMode) {
      if (globalSettings.hideTaskbarOnStartup) {
        WinUtils.toggleTaskbar(visible: false);
      }
    }

    //? Volume
    globalSettings.volumeOSDStyle = VolumeOSDStyle.media;
    if (globalSettings.volumeOSDStyle != VolumeOSDStyle.normal) {
      WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    }
    //? Media Controls
    mediaControls = pref.getStringList("mediaControls") ?? <String>["Spotify.exe", "chrome.exe", "firefox.exe", "Music.UI.exe"];
  }

  List<String> get pinnedApps => pref.getStringList("pinnedApps") ?? <String>[];
  Map<String, String> get taskBarRewrites {
    final String rewrites = pref.getString("taskBarRewrites") ?? "";
    if (rewrites == "") return <String, String>{"DevTools.*?\\.(.*?)\\..*?\$": "⚠DevTools: \$1 "};
    final Map<String, String> rewritesMap = Map<String, String>.from(json.decode(rewrites));
    return rewritesMap;
  }

  List<String> get topBarWidgets {
    List<String> defaultWidgets = <String>[
      "TaskManagerButton",
      "VirtualDesktopButton",
      "ToggleTaskbarButton",
      "PinWindowButton",
      "MicMuteButton",
      "AlwaysAwakeButton",
      "ChangeThemeButton",
      "HideDesktopFilesButton",
      "ToggleHiddenFilesButton",
    ];
    defaultWidgets.add("Deactivated:");
    final List<String> topBarWidgets = pref.getStringList("topBarWidgets") ?? defaultWidgets;
    if (topBarWidgets.length != defaultWidgets.length) {
      final Iterable<String> newItems = defaultWidgets.where((String widget) => !topBarWidgets.contains(widget));
      final int disabledIndex = topBarWidgets.indexWhere((String element) => element == "Deactivated:");
      topBarWidgets.insertAll(disabledIndex, newItems);
      pref.setStringList("topBarWidgets", topBarWidgets);
    }
    // pref.setStringList("topBarWidgets", defaultWidgets);

    return topBarWidgets;
  }

  List<PowerShellScript> getPowerShellScripts() {
    final String scriptsString = pref.getString("powerShellScripts") ?? "";
    if (scriptsString.isEmpty) return <PowerShellScript>[];
    final List<dynamic> list = jsonDecode(scriptsString);
    final List<PowerShellScript> scripts = <PowerShellScript>[];
    for (String script in list) {
      scripts.add(PowerShellScript.fromJson(script));
    }
    return scripts;
  }

  static Future<void> updateSettings(String key, dynamic value) async {
    if (value is bool) {
      await pref.setBool(key, value);
    } else if (value is int) {
      await pref.setInt(key, value);
    } else if (value is String) {
      await pref.setString(key, value);
    } else if (value is List<String>) {
      await pref.setStringList(key, value);
    } else if (value is Map) {
      await pref.setString(key, jsonEncode(value));
    } else {
      print("No asociated type $value");
    }

    pref = await SharedPreferences.getInstance();
  }
}

class PowerShellScript {
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

class AdjustableScrollController extends ScrollController {
  AdjustableScrollController([int extraScrollSpeed = 40]) {
    super.addListener(() {
      ScrollDirection scrollDirection = super.position.userScrollDirection;
      if (scrollDirection != ScrollDirection.idle) {
        double scrollEnd = super.offset + (scrollDirection == ScrollDirection.reverse ? extraScrollSpeed : -extraScrollSpeed);
        scrollEnd = min(super.position.maxScrollExtent, max(super.position.minScrollExtent, scrollEnd));
        jumpTo(scrollEnd);
      }
    });
  }
}
