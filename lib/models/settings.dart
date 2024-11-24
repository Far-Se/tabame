// ignore_for_file: public_member_api_docs, sort_constructors_first
// vscode-fold=2
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'classes/boxes.dart';
import 'classes/saved_maps.dart';
import 'globals.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

enum TPage {
  quickmenu,
  interface,
  views,
}

class Settings {
  List<String> args = <String>[];
  TPage page = TPage.quickmenu;
  bool views = false;
  int quickRunState = 0;
  bool autoUpdate = false;
  bool showTrayBar = true;
  bool showWeather = true;
  bool isWindows10 = false;
  bool previewTheme = false;
  bool volumeSetBack = false;
  bool showPowerShell = false;
  bool keepPopupsOpen = false;
  bool noopKeyListener = false;
  bool showSystemUsage = false;
  bool trktivityEnabled = false;
  bool runAsAdministrator = false;
  bool hideTabameOnUnfocus = true;
  bool hideTaskbarOnStartup = true;
  bool showMediaControlForApp = true;
  bool trktivitySaveAllTitles = false;
  bool pauseSpotifyWhenPlaying = true;
  bool pauseSpotifyWhenNewSound = false;
  bool showQuickMenuAtTaskbarLevel = true;
  bool quickMenuPinnedWithTrayAtBottom = true;
  bool usePowerShellAsToastNotification = false;
  String customLogo = "";
  String customSpash = "";
  String quickRunText = "";
  String lastChangelog = Globals.version;
  String language = Platform.localeName.substring(0, 2);
  VolumeOSDStyle volumeOSDStyle = VolumeOSDStyle.normal;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;
  List<String> weather = <String>['10 C', "52.52437, 13.41053", "m"];
  List<String> persistentReminders = <String>[];
  List<String> audio = <String>["false", "true", "false"];

  bool get audioConsole => audio[0] == "false" ? false : true;
  bool get audioMultimedia => audio[1] == "false" ? false : true;
  bool get audioCommunications => audio[2] == "false" ? false : true;

  set audioConsole(bool val) => audio[0] = val == false ? "false" : "true";
  set audioMultimedia(bool val) => audio[1] = val == false ? "false" : "true";
  set audioCommunications(bool val) => audio[2] = val == false ? "false" : "true";

  set weatherTemperature(String temp) => weather[0] = temp;
  String get weatherTemperature => weather[0];
  set weatherLatLong(String temp) => weather[1] = temp;
  String get weatherLatLong => weather[1];
  set weatherUnit(String temp) => weather[2] = temp;
  String get weatherUnit => weather[2]; //m for metric, u for US

  int themeScheduleMin = 8 * 60;
  int themeScheduleMax = 20 * 60;
  ThemeColors get theme => themeColors;
  ThemeType themeType = ThemeType.system;

  RunCommands run = RunCommands();
  bool settingsChanged = false;
  ThemeColors lightTheme = ThemeColors(background: 0xffD5E0FB, textColor: 0xff3A404A, accentColor: 0xff446EE9, gradientAlpha: 200, quickMenuBoldFont: true);
  ThemeColors darkTheme = ThemeColors(background: 0xff1E1F28, accentColor: 0xDCFFDCAA, gradientAlpha: 240, textColor: 0xFFFAF9F8, quickMenuBoldFont: true);
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;

  /// Get Dark or Light Theme
  ThemeType get themeTypeMode {
    if (themeType == ThemeType.system) {
      if (MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first).platformBrightness == Brightness.dark) return ThemeType.dark;
      return ThemeType.light;
    } else if (themeType == ThemeType.schedule) {
      final int minTime = globalSettings.themeScheduleMin;
      final int maxTime = globalSettings.themeScheduleMax;
      final int now = (DateTime.now().hour * 60) + DateTime.now().minute;
      ThemeType scheduled;
      scheduled = now.isBetween(minTime, maxTime) ? ThemeType.light : ThemeType.dark;
      return scheduled;
    }
    return themeType;
  }

  String get logo => themeTypeMode == ThemeType.dark ? "resources/logo_light.png" : "resources/logo_dark.png";
  Timer? themeScheduleChangeTimer;
  void setScheduleThemeChange() {
    themeScheduleChangeTimer?.cancel();
    if (themeType != ThemeType.schedule) return;
    final int now = (DateTime.now().hour * 60) + DateTime.now().minute;
    if (now.isBetween(themeScheduleMin, themeScheduleMax)) {
      themeScheduleChangeTimer = Timer(Duration(minutes: themeScheduleMax - now), () {});
    } else {
      themeScheduleChangeTimer = Timer(Duration(minutes: 24 - now + themeScheduleMin), () {});
    }
  }

  //other
  Map<int, List<int>> hookedWins = <int, List<int>>{};
}

Settings globalSettings = Settings();

Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);
  Debug.add("Registered: Locale");

  // ? Monitor Handle
  Monitor.fetchMonitor();
  Debug.add("Registered: Monitor");
  Timer.periodic(const Duration(seconds: 10), (Timer timer) => Monitor.fetchMonitor());
  //register
  await Boxes.registerBoxes();
  Debug.add("Registered: Boxes");
  //Schedule Theme
  globalSettings.setScheduleThemeChange();
  Debug.add("Registered: ScheduleTheme");
  if (globalSettings.views && globalSettings.args.contains("-views")) {
    enableViews(true);
    Debug.add("Registered: ViewsEnabled");
  }
  //

  await Audio.detectAudioSupport(AudioDeviceType.output);
  //Toast
  Timer(const Duration(seconds: 2), () async {
    if (!WinUtils.windowsNotificationRegistered) {
      Debug.add("Registered: Toast");
      await localNotifier.setup(appName: 'Tabame', shortcutPolicy: ShortcutPolicy.requireCreate);

      Debug.add("Registered: Toast Done");
      WinUtils.windowsNotificationRegistered = true;
    }
  });
}

typedef Maa = MainAxisAlignment;
typedef Caa = CrossAxisAlignment;

extension NumExtension on num {
  String formatNum() {
    final NumberFormat format = NumberFormat("#,##0.00", "en_US");
    final String nr = format.format(this);
    if (nr.endsWith(".00")) return nr.substring(0, nr.lastIndexOf(".00"));
    return nr;
  }
}

extension IntegerExtension on int {
  String formatTime() {
    final int hour = (this ~/ 60);
    final int minute = (this % 60);
    return "${hour.toString().numberFormat()}:${minute.toString().numberFormat()}";
  }

  String formatInt() {
    final NumberFormat format = NumberFormat("#,##0", "en_US");
    return format.format(this);
  }

  String formatZeros([int count = 2]) {
    return toString().padLeft(count, '0');
  }

  String formatDouble() {
    final NumberFormat format = NumberFormat("#,##0.00", "en_US");
    return format.format(this);
  }

  bool isBetween(num from, num to) {
    return from < this && this < to;
  }

  bool isBetweenEqual(num from, num to) {
    return from <= this && this <= to;
  }
}

extension StringExtension on String {
  String truncate(int max, {String suffix = ''}) => length < max ? this : replaceRange(max, null, suffix);
  String toUpperCaseFirst() {
    if (length < 2) return toUpperCase();
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }

  String toUperCaseAll() => toUpperCase();
  String toUpperCaseEach() => split(" ").map((String str) => str.toUpperCaseFirst()).join(" ");
  String numberFormat({int minNr = 10}) {
    return (int.parse(this) / minNr).toDouble().toString().replaceAll('.', '');
  }

  String removeCharAtTheEnd(String char) {
    if (lastIndexOf(char) == char.length - 1) return substring(0, length - 1);
    return this;
  }

  List<String> splitFirst(String char) {
    if (!contains(char)) return <String>[this];
    return <String>[substring(0, indexOf(char)), substring(indexOf(char) + char.length)];
  }

  String get splitAndUpcase {
    if (isEmpty) return "";
    return replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match match) => ' ${match[0]}').toUpperCaseEach();
  }
}

extension Toggle<T> on List<T> {
  toggle(T value) {
    if (contains(value)) {
      remove(value);
    } else {
      add(value);
    }
  }
}

int darkerColor(int color, {int darkenBy = 0x10, int floor = 0x0}) {
  final int darkerHex = (max((color >> 16) - darkenBy, floor) << 16) + (max(((color & 0xff00) >> 8) - darkenBy, floor) << 8) + max(((color & 0xff) - darkenBy), floor);
  return darkerHex;
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

enum TaskBarAppsStyle { onlyActiveMonitor, activeMonitorFirst, orderByActivity }

enum VolumeOSDStyle { normal, media, visible, thin }

enum ThemeType { system, light, dark, schedule }

class Debug {
  static File theFile = File("${WinUtils.getTabameSettingsFolder()}\\debug.log");
  static bool enabled = false;
  static void register({bool clean = true}) {
    enabled = true;
    theFile.writeAsStringSync("========\n", mode: clean ? FileMode.write : FileMode.append);
    File("${WinUtils.getTabameSettingsFolder()}\\debug_cpp.log").writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
  }

  static void add(String text) {
    if (!enabled) return;
    theFile.writeAsStringSync("$text\n", mode: FileMode.append);
  }

  static void methodDebug({bool clean = true}) {
    File("${WinUtils.getTabameSettingsFolder()}\\debug_cpp.log").writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
    enableDebug("${WinUtils.getTabameSettingsFolder()}\\debug_cpp.log");
  }
}
