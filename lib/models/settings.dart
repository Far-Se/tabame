// ignore_for_file: public_member_api_docs, sort_constructors_first
// vscode-fold=2
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:math' as math;
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

enum QuickMenuDesigns {
  modern,
  classic,
  interface;

  String get name {
    return switch (this) {
      QuickMenuDesigns.modern => "Modern",
      QuickMenuDesigns.classic => "Classic",
      QuickMenuDesigns.interface => "Interface",
    };
  }
}

class Settings {
  List<String> args = <String>[];
  TPage page = TPage.quickmenu;
  bool views = false;
  // int quickRunState = 0;
  bool autoUpdate = false;
  int quickMenuDesign = QuickMenuDesigns.modern.index;
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
  bool usePowerShellAsToastNotification = false;
  String customLogo = "";
  String customSpash = "";
  String textFileSearch = "";
  String wallpapersFolder = "";
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

  bool settingsChanged = false;
  ThemeColors lightTheme = Settings._defaultThemeColors(
    background: 0xffD5E0FB,
    textColor: 0xff3A404A,
    accentColor: 0xff446EE9,
    gradientAlpha: 200,
  );
  ThemeColors darkTheme = Settings._defaultThemeColors(
    background: 0xFF0A0A0A,
    textColor: 0xFFFAF9F8,
    accentColor: 0xFFA7CF3F,
    gradientAlpha: 20,
  );
  Map<String, QuickMenuDesignThemeSet> quickMenuDesignThemes = Settings.createDefaultQuickMenuDesignThemes();
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;

  static ThemeColors _defaultThemeColors({
    required int background,
    required int textColor,
    required int accentColor,
    required int gradientAlpha,
    bool quickMenuBoldFont = true,
  }) {
    return ThemeColors(
      background: background,
      textColor: textColor,
      accentColor: accentColor,
      gradientAlpha: gradientAlpha,
      quickMenuBoldFont: quickMenuBoldFont,
    );
  }

  static Map<String, QuickMenuDesignThemeSet> createDefaultQuickMenuDesignThemes() {
    return <String, QuickMenuDesignThemeSet>{
      QuickMenuDesigns.modern.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: 0xffD5E0FB,
          textColor: 0xff3A404A,
          accentColor: 0xff446EE9,
          gradientAlpha: 200,
        ),
        darkTheme: _defaultThemeColors(
          background: 0xFF0A0A0A,
          textColor: 0xFFFAF9F8,
          accentColor: 0xFFA7CF3F,
          gradientAlpha: 20,
        ),
      ),
      QuickMenuDesigns.classic.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: 0xffECE2D7,
          textColor: 0xff3D342B,
          accentColor: 0xffB86F43,
          gradientAlpha: 150,
        ),
        darkTheme: _defaultThemeColors(
          background: 0xff171317,
          textColor: 0xFFF5EFE7,
          accentColor: 0xFFE4A768,
          gradientAlpha: 205,
        ),
      ),
      QuickMenuDesigns.interface.name: QuickMenuDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: 0xffEEF4F8,
          textColor: 0xff223444,
          accentColor: 0xff2D84B8,
          gradientAlpha: 220,
        ),
        darkTheme: _defaultThemeColors(
          background: 0xff101923,
          textColor: 0xFFEAF4FB,
          accentColor: 0xFF68C9FF,
          gradientAlpha: 228,
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
  static File theFile = File("${WinUtils.getTabameAppDataFolder()}\\debug.log");
  static bool enabled = false;
  static void register({bool clean = true}) {
    enabled = true;
    theFile.writeAsStringSync("========\n", mode: clean ? FileMode.write : FileMode.append);
    File("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log")
        .writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
  }

  static void add(String text) {
    if (!enabled) return;
    theFile.writeAsStringSync("$text\n", mode: FileMode.append);
  }

  static void methodDebug({bool clean = true}) {
    File("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log")
        .writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
    enableDebug("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log");
  }
}

extension FlexColorPickerColorExtensions on Color {
  /// A 32 bit value representing this color.
  ///
  /// This feature brings back the Color.value API in a way that is not and
  /// will not be deprecated.
  ///
  /// The bits are assigned as follows:
  ///
  /// * Bits 24-31 are the alpha value.
  /// * Bits 16-23 are the red value.
  /// * Bits 8-15 are the green value.
  /// * Bits 0-7 are the blue value.
  int get value32bit {
    return _floatToInt8(a) << 24 | _floatToInt8(r) << 16 | _floatToInt8(g) << 8 | _floatToInt8(b) << 0;
  }

  /// The alpha channel of this color in an 8 bit value.
  ///
  /// A value of 0 means this color is fully transparent. A value of 255 means
  /// this color is fully opaque.
  ///
  /// This feature brings back the Color.alpha API in a way that is not and
  /// will not be deprecated.
  int get alpha8bit => (0xff000000 & value32bit) >> 24;

  /// The red channel of this color in an 8 bit value.
  ///
  /// This feature brings back the Color.red API in a way that is not and
  /// will not be deprecated.
  int get red8bit => (0x00ff0000 & value32bit) >> 16;

  /// The green channel of this color in an 8 bit value.
  ///
  /// This feature brings back the Color.green API in a way that is not and
  /// will not be deprecated.
  int get green8bit => (0x0000ff00 & value32bit) >> 8;

  /// The blue channel of this color in an 8 bit value.
  ///
  /// This feature brings back the Color.blue API in a way that is not and
  /// will not be deprecated.
  int get blue8bit => (0x000000ff & value32bit) >> 0;

  // Convert float to 8 bit integer.
  int _floatToInt8(double x) {
    return (x * 255.0).round() & 0xff;
  }

  /// Lightens the color with the given integer percentage amount.
  /// Defaults to 10%.
  Color lighten([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.white;
    // HSLColor returns saturation 1 for black, we want 0 instead to be able
    // lighten black color up along the grey scale from black.
    final HSLColor hsl =
        this == const Color(0xFF000000) ? HSLColor.fromColor(this).withSaturation(0) : HSLColor.fromColor(this);
    return hsl.withLightness(math.min(1, math.max(0, hsl.lightness + amount / 100))).toColor();
  }

  /// Darkens the color with the given integer percentage amount.
  /// Defaults to 10%.
  Color darken([final int amount = 10]) {
    if (amount <= 0) return this;
    if (amount > 100) return Colors.black;
    final HSLColor hsl = HSLColor.fromColor(this);
    return hsl.withLightness(math.min(1, math.max(0, hsl.lightness - amount / 100))).toColor();
  }
}
