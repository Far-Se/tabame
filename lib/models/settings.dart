// ignore_for_file: public_member_api_docs, sort_constructors_first
// vscode-fold=2
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'classes/boxes.dart';
import 'classes/saved_maps.dart';
import 'globals.dart';
import 'util/solar_calculator.dart';
import 'win32/mixed.dart';
import 'win32/win_utils.dart';

enum TPage {
  quickmenu,
  interface,
  views,
}

enum QuickMenuDesigns {
  classic,
  modern,
  serene,
  matrix,
  interface,
  ;

  String get name {
    return switch (this) {
      QuickMenuDesigns.modern => "Modern",
      QuickMenuDesigns.classic => "Classic",
      QuickMenuDesigns.interface => "Interface",
      QuickMenuDesigns.matrix => "Matrix",
      QuickMenuDesigns.serene => "Serene",
    };
  }
}

enum LightSwitchMode { off, fixed, sunrise }

class User {
  static ThemeColors get theme => userSettings.themeColors;
  static ThemeColors get t => userSettings.themeColors;
  static Settings get s => userSettings;
}

class Design {
  static Color get background => userSettings.theme.background;
  static Color get text => userSettings.theme.text;
  static Color get accent => userSettings.theme.accent;
  static int get gradientAlpha => userSettings.theme.gradientAlpha;
  static String get uiFontFamily => userSettings.theme.uiFontFamily;
  static int get uiFontWeight => userSettings.theme.uiFontWeight;
  static bool get uiFontItalic => userSettings.theme.uiFontItalic;
  static String get entryFontFamily => userSettings.theme.entryFontFamily;
  static int get entryFontWeight => userSettings.theme.entryFontWeight;
  static bool get entryFontItalic => userSettings.theme.entryFontItalic;
  static List<String> get backdropImages => userSettings.theme.backdropImages;
  static String get backdropType => userSettings.theme.backdropType;
  static double get backdropOpacity => userSettings.theme.backdropOpacity;
  static List<double> get panelOpacityPoints => userSettings.theme.panelOpacityPoints;
  static String get panelOpacityBegin => userSettings.theme.panelOpacityBegin;
  static String get panelOpacityEnd => userSettings.theme.panelOpacityEnd;
  static double get borderRadius => userSettings.theme.borderRadius;
}

class Settings {
  List<String> args = <String>[];
  TPage page = TPage.quickmenu;
  bool quickSnapOverlay = true;
  bool quickSnapGrid = true;
  // int quickRunState = 0;
  bool autoCheckForUpdates = false;
  int quickMenuDesign = QuickMenuDesigns.modern.index;
  bool showTrayBar = true;
  bool showWeather = true;
  bool libreStats = false;
  bool isWindows10 = false;
  bool previewTheme = false;
  bool volumeSetBack = false;
  bool keepPopupsOpen = true;
  bool expandedTaskbar = true;
  bool bottomBarOnTop = false;
  bool launcherFullPopups = false;
  bool noopKeyListener = false;
  bool showSystemUsage = false;
  bool taskManagerStats = false;
  bool autoOpenTaskManager = false;
  bool quickClickEnabled = false;
  QuickClickConfig quickClickConfig = QuickClickConfig();
  bool trktivityEnabled = false;
  bool runAsAdministrator = false;
  bool _hideTabameOnUnfocus = true;
  bool quickActionsAtBottom = false;
  bool dragPopupsByIconOnly = false;
  bool get hideTabameOnUnfocus => _hideTabameOnUnfocus;
  set hideTabameOnUnfocus(bool value) {
    _hideTabameOnUnfocus = value;
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
  }

  bool hideTaskbarOnStartup = true;
  bool hideDesktopFiles = false;
  bool showMediaControlForApp = true;
  bool showMusicPlayerInTaskbar = true;
  bool showMediaSessionsInTaskbar = true;
  bool trktivitySaveAllTitles = false;
  bool showQuickMenuAtTaskbarLevel = true;
  String customLogo = "";
  String customSpash = "";
  String launcherSearchText = "";
  String wallpapersFolder = "";
  String lastQuickSnapZoneId = "";
  String lastChangelog = Globals.version;
  String language = Platform.localeName.substring(0, 2);
  VolumeOSDStyle volumeOSDStyle = VolumeOSDStyle.normal;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;
  List<String> weather = <String>['10 C', "52.52437, 13.41053", "m"];
  String newVersion = "";
  List<String> persistentReminders = <String>[];
  List<String> audio = <String>["false", "true", "false"];
  String activeBackdropPath = "";

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
  bool isDark(BuildContext context) =>
      userSettings.themeType == ThemeType.dark ||
      (userSettings.themeType == ThemeType.system && MediaQuery.of(context).platformBrightness == Brightness.dark);

  // Light Switch
  LightSwitchMode lightSwitchMode = LightSwitchMode.off;
  int lightSwitchSunriseOffset = 0;
  int lightSwitchSunsetOffset = 0;
  int lightSwitchSunrise = 6 * 60; // 06:00
  int lightSwitchSunset = 18 * 60; // 18:00
  int lightSwitchLastFetch = 0;

  bool settingsChanged = false;
  ThemeColors lightTheme = Settings._defaultThemeColors(
    background: const Color(0xffD5E0FB),
    textColor: const Color(0xff3A404A),
    accentColor: const Color(0xff446EE9),
    gradientAlpha: 200,
  );
  ThemeColors darkTheme = Settings._defaultThemeColors(
    background: const Color(0xFF0A0A0A),
    textColor: const Color(0xFFFAF9F8),
    accentColor: const Color(0xFFA7CF3F),
    gradientAlpha: 20,
  );
  Map<String, QuickMenuDesignThemeSet> quickMenuDesignThemes = Settings.createDefaultQuickMenuDesignThemes();
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;

  static ThemeColors _defaultThemeColors({
    required Color background,
    required Color textColor,
    required Color accentColor,
    required int gradientAlpha,
    String uiFontFamily = 'Jura',
    int uiFontWeight = 400,
    bool uiFontItalic = false,
    String entryFontFamily = 'Jura',
    int entryFontWeight = 700,
    bool entryFontItalic = false,
    double borderRadius = 10,
    double baseFontSize = 10,
  }) {
    return ThemeColors(
      background: background,
      text: textColor,
      accent: accentColor,
      gradientAlpha: gradientAlpha,
      uiFontFamily: uiFontFamily,
      uiFontWeight: uiFontWeight,
      uiFontItalic: uiFontItalic,
      entryFontFamily: entryFontFamily,
      entryFontWeight: entryFontWeight,
      entryFontItalic: entryFontItalic,
      borderRadius: borderRadius,
      baseFontSize: baseFontSize,
    );
  }

  static Map<String, QuickMenuDesignThemeSet> createDefaultQuickMenuDesignThemes() {
    return <String, QuickMenuDesignThemeSet>{
      QuickMenuDesigns.modern.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffD5E0FB),
          textColor: const Color(0xff3A404A),
          accentColor: const Color(0xff446EE9),
          gradientAlpha: 200,
          uiFontFamily: 'Jura',
          entryFontFamily: 'Jura',
          borderRadius: 12,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xFF0A0A0A),
          textColor: const Color(0xFFFAF9F8),
          accentColor: const Color(0xFFA7CF3F),
          gradientAlpha: 20,
          uiFontFamily: 'Jura',
          entryFontFamily: 'Jura',
          borderRadius: 12,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.classic.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffECE2D7),
          textColor: const Color(0xff3D342B),
          accentColor: const Color(0xffB86F43),
          gradientAlpha: 150,
          uiFontFamily: 'Jura',
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff171317),
          textColor: const Color(0xFFF5EFE7),
          accentColor: const Color(0xFFE4A768),
          gradientAlpha: 205,
          uiFontFamily: 'Jura',
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.interface.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffEEF4F8),
          textColor: const Color(0xff223444),
          accentColor: const Color(0xff2D84B8),
          gradientAlpha: 220,
          uiFontFamily: 'Jura',
          uiFontWeight: 500,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 22,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff101923),
          textColor: const Color(0xFFEAF4FB),
          accentColor: const Color(0xFF68C9FF),
          gradientAlpha: 228,
          uiFontFamily: 'Jura',
          uiFontWeight: 500,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 22,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.matrix.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF2F2F2),
          textColor: const Color(0xff003B00),
          accentColor: const Color(0xff008F11),
          gradientAlpha: 0,
          uiFontFamily: 'Jura',
          uiFontWeight: 500,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 12,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff000000),
          textColor: const Color(0xff00FF41),
          accentColor: const Color(0xff008F11),
          gradientAlpha: 0,
          uiFontFamily: 'Jura',
          uiFontWeight: 500,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 12,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.serene.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF5F0EB),
          textColor: const Color(0xff2C2118),
          accentColor: const Color(0xffB07D4F),
          gradientAlpha: 180,
          uiFontFamily: 'Nunito',
          uiFontWeight: 400,
          entryFontFamily: 'Nunito',
          entryFontWeight: 600,
          borderRadius: 10,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff161618),
          textColor: const Color(0xffEDE8E3),
          accentColor: const Color(0xff445E91),
          gradientAlpha: 58,
          uiFontFamily: 'Nunito',
          uiFontWeight: 400,
          entryFontFamily: 'Nunito',
          entryFontWeight: 600,
          borderRadius: 10,
          baseFontSize: 10,
        ),
      ),
    };
  }

  QuickMenuDesigns get currentQuickMenuDesign {
    final int safeIndex = quickMenuDesign.clamp(0, QuickMenuDesigns.values.length - 1);
    return QuickMenuDesigns.values[safeIndex];
  }

  void hydrateQuickMenuDesignThemes([Map<String, QuickMenuDesignThemeSet>? source]) {
    final Map<String, QuickMenuDesignThemeSet> defaults = Settings.createDefaultQuickMenuDesignThemes();
    if (source != null) {
      for (final MapEntry<String, QuickMenuDesignThemeSet> entry in source.entries) {
        defaults[entry.key] = entry.value.copyWith();
      }
    }
    quickMenuDesignThemes = defaults.map(
      (String key, QuickMenuDesignThemeSet value) => MapEntry<String, QuickMenuDesignThemeSet>(key, value.copyWith()),
    );
  }

  void loadQuickMenuDesignThemesFromJson(String source) {
    if (source.trim().isEmpty) {
      hydrateQuickMenuDesignThemes();
      return;
    }
    final Map<String, dynamic> decoded = Map<String, dynamic>.from(jsonDecode(source) as Map<dynamic, dynamic>);
    hydrateQuickMenuDesignThemes(
      decoded.map(
        (String key, dynamic value) => MapEntry<String, QuickMenuDesignThemeSet>(
          key,
          QuickMenuDesignThemeSet.fromMap(Map<String, dynamic>.from(value as Map<dynamic, dynamic>)),
        ),
      ),
    );
  }

  String quickMenuDesignThemesToJson() {
    return jsonEncode(
      quickMenuDesignThemes.map(
        (String key, QuickMenuDesignThemeSet value) => MapEntry<String, dynamic>(key, value.toMap()),
      ),
    );
  }

  void saveActiveThemesToCurrentDesign([QuickMenuDesigns? design]) {
    final QuickMenuDesigns target = design ?? currentQuickMenuDesign;
    quickMenuDesignThemes[target.name] = QuickMenuDesignThemeSet(
      lightTheme: lightTheme.copyWith(),
      darkTheme: darkTheme.copyWith(),
    );
  }

  void applyThemesForDesign(
    QuickMenuDesigns design, {
    ThemeColors? fallbackLightTheme,
    ThemeColors? fallbackDarkTheme,
  }) {
    final QuickMenuDesignThemeSet? savedThemeSet = quickMenuDesignThemes[design.name];
    lightTheme = (savedThemeSet?.lightTheme ??
            fallbackLightTheme ??
            Settings.createDefaultQuickMenuDesignThemes()[design.name]!.lightTheme)
        .copyWith();
    darkTheme = (savedThemeSet?.darkTheme ??
            fallbackDarkTheme ??
            Settings.createDefaultQuickMenuDesignThemes()[design.name]!.darkTheme)
        .copyWith();
    saveActiveThemesToCurrentDesign(design);
  }

  /// Get Dark or Light Theme
  ThemeType get themeTypeMode {
    if (themeType == ThemeType.system) {
      if (MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first).platformBrightness ==
          Brightness.dark) {
        return ThemeType.dark;
      }
      return ThemeType.light;
    } else if (themeType == ThemeType.schedule) {
      final int start = lightSwitchMode == LightSwitchMode.sunrise
          ? (lightSwitchSunrise + lightSwitchSunriseOffset)
          : themeScheduleMin;
      final int end =
          lightSwitchMode == LightSwitchMode.sunrise ? (lightSwitchSunset + lightSwitchSunsetOffset) : themeScheduleMax;

      final int now = (DateTime.now().hour * 60) + DateTime.now().minute;
      return now.isBetweenEqual(start, end) ? ThemeType.light : ThemeType.dark;
    }
    return themeType;
  }

  String get logo => themeTypeMode == ThemeType.dark ? "resources/logo_light.png" : "resources/logo_dark.png";

  Timer? themeScheduleChangeTimer;
  void setScheduleThemeChange() {
    themeScheduleChangeTimer?.cancel();
    if (userSettings.lightSwitchMode == LightSwitchMode.off) return;

    final int start =
        lightSwitchMode == LightSwitchMode.sunrise ? (lightSwitchSunrise + lightSwitchSunriseOffset) : themeScheduleMin;
    final int end =
        lightSwitchMode == LightSwitchMode.sunrise ? (lightSwitchSunset + lightSwitchSunsetOffset) : themeScheduleMax;

    final int now = (DateTime.now().hour * 60) + DateTime.now().minute;

    // Initial sync
    final bool isLight = now.isBetweenEqual(start, end);
    WinUtils.setWindowsTheme(isLight ? 1 : 0);

    if (isLight) {
      // It's day/light time, wait for sunset (end)
      int minutesToEnd;
      if (end >= now) {
        minutesToEnd = end - now;
      } else {
        minutesToEnd = (1440 - now) + end;
      }
      themeScheduleChangeTimer = Timer(Duration(minutes: minutesToEnd), () {
        WinUtils.setWindowsTheme(0);
        setScheduleThemeChange();
      });
    } else {
      // It's night/dark time, calculate minutes to sunrise (start)
      int minutesToStart;
      if (start >= now) {
        minutesToStart = start - now;
      } else {
        minutesToStart = (1440 - now) + start;
      }
      themeScheduleChangeTimer = Timer(Duration(minutes: minutesToStart), () {
        WinUtils.setWindowsTheme(1);
        setScheduleThemeChange();
      });
    }
  }

  //other
  Map<int, List<int>> hookedWins = <int, List<int>>{};
}

Settings userSettings = Settings();

Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);
  Debug.add("Registered: Locale");

  // ? Monitor Handle
  Monitor.fetchMonitors();
  Debug.add("Registered: Monitor");
  Timer.periodic(const Duration(seconds: 10), (Timer timer) => Monitor.fetchMonitors());
  Timer.periodic(const Duration(seconds: 5), (Timer timer) {
    if (userSettings.hideDesktopFiles) {
      WinUtils.toggleDesktopFiles(visible: false);
    }
  });
  //register
  await Boxes.registerBoxes(justLoad: Globals.currentPage == Pages.interface ? true : false);
  Debug.add("Registered: Boxes");
  //Schedule Theme
  userSettings.setScheduleThemeChange();
  if (userSettings.lightSwitchMode == LightSwitchMode.sunrise) {
    SolarCalculator.updateSolarData();
  }
  Debug.add("Registered: ScheduleTheme");
  enableViews(true);
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

extension ColorEx on Color {
  static int floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  /// A 32 bit value representing this color.
  ///
  /// The bits are assigned as follows:
  ///
  /// * Bits 24-31 are the alpha value.
  /// * Bits 16-23 are the red value.
  /// * Bits 8-15 are the green value.
  /// * Bits 0-7 are the blue value.
  int get toInt32 {
    return floatToInt8(a) << 24 | floatToInt8(r) << 16 | floatToInt8(g) << 8 | floatToInt8(b) << 0;
  }
}

extension NumExtension on num {
  String formatNum2() {
    final String locale = Intl.systemLocale;
    final NumberFormat format = NumberFormat.decimalPattern(locale);
    return format.format(this);
  }

  String formatNum() {
    final NumberFormat format = NumberFormat("#,##0.00", "en_US");
    final String nr = format.format(this);
    if (nr.endsWith(".00")) return nr.substring(0, nr.lastIndexOf(".00"));
    return nr;
  }

  String ordinalSuffix() {
    final Map<int, String> dayMap = <int, String>{1: 'st', 2: 'nd', 3: 'rd'};
    return "$this${dayMap[this] ?? 'th'}";
  }
}

extension IntegerExtension on int {
  String formatTime() {
    final int hour = (this ~/ 60);
    final int minute = (this % 60);
    return "${hour.toString().numberFormat()}:${minute.toString().numberFormat()}";
  }

  String formatInt() {
    final NumberFormat format = NumberFormat.decimalPattern(Intl.systemLocale);
    return format.format(this);
  }

  String formatZeros([int count = 2]) {
    return toString().padLeft(count, '0');
  }

  String formatDouble() {
    final NumberFormat format = NumberFormat.decimalPattern(Intl.systemLocale);
    return format.format(this);
  }

  bool isBetween(num from, num to) {
    if (from <= to) {
      return from < this && this < to;
    } else {
      return this > from || this < to;
    }
  }

  bool isBetweenEqual(num from, num to) {
    if (from <= to) {
      return from <= this && this <= to;
    } else {
      return this >= from || this <= to;
    }
  }
}

extension StringExtension on String {
  String truncate(int max, {String suffix = ''}) => length < max ? this : replaceRange(max, null, suffix);
  String toUpperCaseFirst() {
    if (length < 2) return toUpperCase();
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }

  String toUpperCaseAll() => toUpperCase();
  String toUpperCaseEach() => split(" ").map((String str) => str.toUpperCaseFirst()).join(" ");
  String numberFormat({int minNr = 10}) {
    return (int.parse(this) / minNr).toDouble().toString().replaceAll('.', '');
  }

  String removeCharAtTheEnd(String char) {
    if (lastIndexOf(char) == char.length - 1) return substring(0, length - 1);
    return this;
  }

  String lastChars(int last, {bool addDots = true}) {
    if (length > last) return "${addDots ? '...' : ''}${substring(length - last)}";
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
  void toggle(T value) {
    if (contains(value)) {
      remove(value);
    } else {
      add(value);
    }
  }
}

int darkerColor(int color, {int darkenBy = 0x10, int floor = 0x0}) {
  final int darkerHex = (max((color >> 16) - darkenBy, floor) << 16) +
      (max(((color & 0xff00) >> 8) - darkenBy, floor) << 8) +
      max(((color & 0xff) - darkenBy), floor);
  return darkerHex;
}

class AdjustableScrollController extends ScrollController {
  int _lastScrollTime = 0;
  AdjustableScrollController([int extraScrollSpeed = 40]) {
    super.addListener(() {
      ScrollDirection scrollDirection = super.position.userScrollDirection;
      if (scrollDirection != ScrollDirection.idle) {
        int now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastScrollTime < 50) return; // Debounce rapid scroll events
        _lastScrollTime = now;

        double scrollEnd =
            super.offset + (scrollDirection == ScrollDirection.reverse ? extraScrollSpeed : -extraScrollSpeed);
        scrollEnd = min(super.position.maxScrollExtent, max(super.position.minScrollExtent, scrollEnd));
        animateTo(scrollEnd, duration: const Duration(milliseconds: 150), curve: Curves.easeOut);
      }
    });
  }
}

enum TaskBarAppsStyle { onlyActiveMonitor, activeMonitorFirst, orderByActivity }

enum VolumeOSDStyle { normal, media, visible, thin }

enum ThemeType { system, light, dark, schedule }

class Debug {
  Debug._();
  static File theFile = File("${WinUtils.getTabameAppDataFolder()}\\debug.log");
  static bool enabled = false;
  static void register({bool clean = true}) {
    enabled = true;
    theFile.writeAsStringSync("========\n", mode: clean ? FileMode.write : FileMode.append);
    File("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log")
        .writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
  }

  static void print(String text) {
    if (!enabled) return;
    if (kReleaseMode) {
      theFile.writeAsStringSync("$text\n", mode: FileMode.append);
    } else {
      print(text);
    }
  }

  static void add(String text) {
    if (!enabled) return;
    theFile.writeAsStringSync("$text\n", mode: FileMode.append);
  }

  static void error(String text) {
    if (!theFile.existsSync()) theFile.createSync(recursive: true);
    theFile.writeAsStringSync("ERROR: $text\n", mode: FileMode.append);
  }

  static void methodDebug({bool clean = true}) {
    File("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log")
        .writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
    enableDebug("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log");
  }
}

extension ColorExtensions on Color {
  int get value32bit {
    return _floatToInt8(a) << 24 | _floatToInt8(r) << 16 | _floatToInt8(g) << 8 | _floatToInt8(b) << 0;
  }

  int get alpha8bit => (0xff000000 & value32bit) >> 24;
  int get red8bit => (0x00ff0000 & value32bit) >> 16;
  int get green8bit => (0x0000ff00 & value32bit) >> 8;
  int get blue8bit => (0x000000ff & value32bit) >> 0;
  int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  Color lighten([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.white;
    final HSLColor hsl =
        this == const Color(0xFF000000) ? HSLColor.fromColor(this).withSaturation(0) : HSLColor.fromColor(this);
    return hsl.withLightness(math.min(1, math.max(0, hsl.lightness + amount / 100))).toColor();
  }

  Color darken([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.black;
    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl.withLightness(math.min(1, math.max(0, hsl.lightness - amount / 100))).toColor();
  }
}

final TextStyle baseEntryStyle = GoogleFonts.getFont(
  userSettings.themeColors.entryFontFamily,
  fontSize: userSettings.themeColors.baseFontSize + 2,
  color: User.theme.text,
  fontWeight: FontWeight(
    userSettings.themeColors.entryFontWeight,
  ),
  fontStyle: userSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
);
TextStyle entryStyle(bool? isSelected, {double? fontSize, double? letterSpacing, Color? color}) {
  return baseEntryStyle.copyWith(
    fontSize: fontSize ?? userSettings.themeColors.baseFontSize + 2,
    letterSpacing: letterSpacing,
    color: color ?? ((isSelected ?? false) ? User.theme.text : User.theme.text.withAlpha(200)),
  );
}

class FontThemeCache {
  static final Map<String, TextTheme> _cache = <String, TextTheme>{};

  static TextTheme getTextTheme({
    required String fontFamily,
    required bool isDark,
  }) {
    final String key = '$fontFamily-$isDark';

    return _cache.putIfAbsent(key, () {
      final ThemeData base = isDark ? ThemeData.dark() : ThemeData.light();

      return GoogleFonts.getTextTheme(
        fontFamily,
        base.textTheme,
      );
    });
  }

  static void clear() => _cache.clear();
}
