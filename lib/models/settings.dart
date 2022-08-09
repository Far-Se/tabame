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

  bool showTrayBar = true;
  bool showWeather = true;
  bool showPowerShell = true;
  bool showSystemUsage = false;
  bool runAsAdministrator = false;
  bool hideTaskbarOnStartup = true;
  bool showMediaControlForApp = true;

  String customLogo = "";
  String customSpash = "";
  String currentVersion = "0.5.1";
  bool showQuickMenuAtTaskbarLevel = true;
  bool quickMenuPinnedWithTrayAtBottom = false;
  bool usePowerShellAsToastNotification = false;
  String language = Platform.localeName.substring(0, 2);
  VolumeOSDStyle volumeOSDStyle = VolumeOSDStyle.normal;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;

  List<String> weather = <String>['10 C', "berlin, Germany", "m", "%c+%t"];

  RunCommands run = RunCommands();

  bool previewTheme = false;

  int quickRunState = 0;

  String quickRunText = "";

  bool noopKeyListener = false;

  bool hideTabameOnUnfocus = true;

  bool trktivityEnabled = false;

  bool trktivitySaveAllTitles = false;

  bool pauseSpotifyWhenNewSound = false;
  set weatherTemperature(String temp) => weather[0] = temp;
  String get weatherTemperature => weather[0];
  set weatherCity(String temp) => weather[1] = temp;
  String get weatherCity => weather[1];
  set weatherUnit(String temp) => weather[2] = temp;
  String get weatherUnit => weather[2]; //m for metric, u for US
  set weatherFormat(String temp) => weather[3] = temp;
  String get weatherFormat => weather[3];

  int themeScheduleMin = 8 * 60;
  int themeScheduleMax = 20 * 60;
  ThemeColors get theme => themeColors;
  ThemeType themeType = ThemeType.system;
  // ThemeType get themeType => _themeType;
  // set themeType(ThemeType t) {
  //   _themeType = t;
  //   // setScheduleThemeChange();
  // }

  bool settingsChanged = false;
  ThemeColors lightTheme = ThemeColors(background: 0xffD5E0FB, textColor: 0xff3A404A, accentColor: 0xff446EE9, gradientAlpha: 200, quickMenuBoldFont: true);
  ThemeColors darkTheme = ThemeColors(background: 0xff1E1F28, accentColor: 0xDCFFDCAA, gradientAlpha: 240, textColor: 0xFFFAF9F8, quickMenuBoldFont: true);
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;
  ThemeType get themeTypeMode {
    if (themeType == ThemeType.system) {
      if (MediaQueryData.fromWindow(WidgetsBinding.instance.window).platformBrightness == Brightness.dark) return ThemeType.dark;
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
      themeScheduleChangeTimer = Timer(Duration(minutes: themeScheduleMax - now), () {
        // if (globalSettings.args.isEmpty) WinUtils.startTabame(closeCurrent: true); /// !pizdishenia masiiii
      });
    } else {
      themeScheduleChangeTimer = Timer(Duration(minutes: 24 - now + themeScheduleMin), () {
        // if (globalSettings.args.isEmpty) WinUtils.startTabame(closeCurrent: true);
      });
    }
  }
}

Settings globalSettings = Settings();

Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Monitor Handle
  Monitor.fetchMonitor();
  Timer.periodic(const Duration(seconds: 10), (Timer timer) => Monitor.fetchMonitor());
  //register
  await Boxes.registerBoxes();
  //Schedule Theme
  globalSettings.setScheduleThemeChange();
  //
  await NativeHotkey.register();
  //Toast
  Future<void>.delayed(const Duration(seconds: 2), () async {
    if (!WinUtils.windowsNotificationRegistered) {
      await localNotifier.setup(appName: 'Tabame', shortcutPolicy: ShortcutPolicy.requireCreate);
      WinUtils.windowsNotificationRegistered = true;
    }
  });
}

typedef Maa = MainAxisAlignment;
typedef Caa = CrossAxisAlignment;

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
