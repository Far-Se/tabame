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
import '../services/rewindly_service.dart';
import 'classes/boxes.dart';
import 'classes/saved_maps.dart';
import 'globals.dart';
import 'util/solar_calculator.dart';
import 'win32/mixed.dart';
import 'win32/win_utils.dart';

enum TPage {
  quickmenu,
  interface,
}

enum QuickMenuDesigns {
  classic,
  modern,
  serene,
  matrix,
  interface,
  aurora,
  terminal,
  cassette,
  fluent,
  gazette,
  player,
  steam,
  manifesto,
  vector,
  ledger,
  console,
  foundry,
  anime,
  anime2,
  cyber,
  tech,
  manga,
  // impact,
  outrun,
  outrun2,
  winamp,
  windowsXp,
  windows98,
  notion,
  // familyGuy,
  ;

  String get displayName => switch (this) {
        QuickMenuDesigns.windowsXp => 'Windows XP',
        QuickMenuDesigns.windows98 => 'Windows 98',
        _ => name.toUpperCaseFirst(),
      };
}

enum LauncherDesign {
  classic,
  serene,
  command,
  terminal,
  zen,
  glass,
  blueprint,
  transit,
  fluent,
  manifesto,

  /// Spacecraft guidance-computer HUD. Persisted by index — always append new
  /// designs at the end so stored preferences keep pointing at the right design.
  orbit,

  /// Kawaii character-card panel with ribbons, tape and sparkles.
  ///
  /// Persisted by index — append-only to preserve stored preferences.
  anime,

  /// Launcher counterparts to the named Quick Menu visual languages.
  /// Kept append-only because this preference is persisted by index.
  tech,
  vector,
  outrun2,
  matrix,
  steam,
  cyber,
  manga,

  /// Windows XP "Luna" launcher. Append-only: launcher preferences are stored
  /// by enum index.
  windowsXp,

  /// Windows 98 shell launcher. Append-only to preserve stored preferences.
  windows98,

  /// Notion-inspired workspace launcher. Append-only to preserve preferences.
  notion;

  String get displayName => switch (this) {
        LauncherDesign.windowsXp => 'Windows XP',
        LauncherDesign.windows98 => 'Windows 98',
        _ => name.toUpperCaseFirst(),
      };
}

enum LightSwitchMode { off, fixed, sunrise }

class User {
  // static ThemeColors get theme => Design;
  // static ThemeColors get t => Design;
  static Settings get s => user;
}

class Design {
  static bool get _isLauncher => Globals.quickMenuPage == QuickMenuPage.launcher;
  static ThemeColors get _colors => _isLauncher ? user.launcherThemeColors : user.themeColors;

  static Color get background => _colors.background;
  static Color get text => _colors.text;
  static Color get accent => _colors.accent;
  static int get gradientAlpha => _colors.gradientAlpha;
  static String get uiFontFamily => _colors.uiFontFamily;
  static int get uiFontWeight => _colors.uiFontWeight;
  static bool get uiFontItalic => _colors.uiFontItalic;
  static bool get useCustomFont => _isLauncher && user.launcherUseCustomFont;
  static String get entryFontFamily => _colors.entryFontFamily;
  static int get entryFontWeight => _colors.entryFontWeight;
  static bool get entryFontItalic => _colors.entryFontItalic;
  static List<String> get backdropImages => _colors.backdropImages;
  static String get backdropType => _colors.backdropType;
  static String get backdropPath => _colors.backdropPath;
  static double get backdropOpacity => _colors.backdropOpacity;
  static List<double> get panelOpacityPoints => _colors.panelOpacityPoints;
  static String get panelOpacityBegin => _colors.panelOpacityBegin;
  static String get panelOpacityEnd => _colors.panelOpacityEnd;
  static double get borderRadius => _colors.borderRadius;
  static double get baseFontSize => _colors.baseFontSize;
  static bool get hasBackdrop => backdropType.isNotEmpty && backdropPath.isNotEmpty;
  static final TextStyle fontSize2Alpha80 =
      TextStyle(fontSize: baseFontSize + 2, color: user.themeColors.text.withAlpha(80));
  static Color accentHue(int hue, {double saturation = 1.0}) {
    final HSLColor accentHsl = HSLColor.fromColor(Design.accent);
    return accentHsl
        .withHue((accentHsl.hue + hue) % 360)
        .withSaturation((accentHsl.saturation * saturation).clamp(0.0, 1.0))
        .toColor();
  }

  static Color backgroundHue(int hue, {double saturation = 1.0}) {
    final HSLColor backgroundHsl = HSLColor.fromColor(Design.background);
    return backgroundHsl
        .withHue((backgroundHsl.hue + hue) % 360)
        .withSaturation((backgroundHsl.saturation * saturation).clamp(0.0, 1.0))
        .toColor();
  }

  static HSLColor backgroundHsl() {
    return HSLColor.fromColor(Design.background);
  }
}

class C {
  static CrossAxisAlignment get stretch => CrossAxisAlignment.stretch;
  static CrossAxisAlignment get baseline => CrossAxisAlignment.baseline;
  static CrossAxisAlignment get start => CrossAxisAlignment.start;
  static CrossAxisAlignment get center => CrossAxisAlignment.center;
  static CrossAxisAlignment get end => CrossAxisAlignment.end;
}

class M {
  static MainAxisAlignment get center => MainAxisAlignment.center;
  static MainAxisAlignment get end => MainAxisAlignment.end;
  static MainAxisAlignment get spaceAround => MainAxisAlignment.spaceAround;
  static MainAxisAlignment get spaceBetween => MainAxisAlignment.spaceBetween;
  static MainAxisAlignment get spaceEvenly => MainAxisAlignment.spaceEvenly;
  static MainAxisAlignment get start => MainAxisAlignment.start;
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
  bool mergePinnedTray = false;
  bool showWeather = true;
  bool libreStats = false;
  bool isWindows10 = false;
  bool previewTheme = false;
  bool volumeSetBack = false;
  bool keepPopupsOpen = true;
  bool expandedTaskbar = true;
  bool taskbarHoverSlide = true;
  bool bottomBarOnTop = false;
  bool launcherFullPopups = false;
  bool noopKeyListener = false;
  bool showSystemUsage = false;
  bool taskManagerStats = false;
  bool trayBarAlternative = false;
  bool autoOpenTaskManager = false;
  bool quickClickEnabled = false;
  bool trktivityEnabled = false;
  bool runAsAdministrator = false;
  bool _hideTabameOnUnfocus = true;
  bool quickActionsAtBottom = false;
  bool dragPopupsByIconOnly = false;
  LauncherDesign launcherDesign = LauncherDesign.classic;
  QuickClickConfig quickClickConfig = QuickClickConfig();
  bool get hideTabameOnUnfocus => _hideTabameOnUnfocus;
  set hideTabameOnUnfocus(bool value) {
    _hideTabameOnUnfocus = value;
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
  }

  bool hideTaskbarOnStartup = true;
  bool hideDesktopFiles = false;
  bool mediaControlForApp = true;
  bool musicPlayerInTaskbar = true;
  bool mediaSessionsInTaskbar = true;
  bool trktivitySaveAllTitles = false;
  bool quickMenuAtTaskbarLevel = true;
  // Rewindly (background "instant replay" DVR)
  bool rewindlyEnabled = false;
  int rewindlyFps = 2; // capture frame rate, 1-10
  int rewindlyClipMinutes = 1; // length of an exported clip, 1-10
  int rewindlyRetentionMinutes = 60; // rolling buffer history to keep
  // Keystroke & Click Visualizer overlay
  bool keystrokesShowClicks = true; // render mouse click ripples
  bool keystrokesModifiersOnly = false; // only show chords that use a modifier
  int keystrokesPosition = 2; // 0 top-left, 1 top-center, 2 bottom-center, 3 bottom-right, 4 bottom-left
  int keystrokesScale = 100; // badge size, percent 60-200
  int keystrokesFadeMs = 2500; // how long a key badge stays before fading
  String customLogo = "";
  String customSpash = "";
  String launcherSearchText = "";
  String wallpapersFolder = "";
  String fancyshotFolder = "";
  String lastQuickSnapZoneId = "";
  String lastChangelog = Globals.version;
  String language = Platform.localeName.substring(0, 2);
  VolumeOSDStyle volumeOSDStyle = VolumeOSDStyle.normal;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;
  List<String> weather = <String>['10 C', "52.52437, 13.41053", "m"];
  String newVersion = Globals.version;
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
      user.themeType == ThemeType.dark ||
      (user.themeType == ThemeType.system && MediaQuery.of(context).platformBrightness == Brightness.dark);

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
  ThemeColors launcherLightTheme = Settings._defaultThemeColors(
    background: const Color(0xffD5E0FB),
    textColor: const Color(0xff3A404A),
    accentColor: const Color(0xff446EE9),
    gradientAlpha: 200,
  );
  ThemeColors launcherDarkTheme = Settings._defaultThemeColors(
    background: const Color(0xFF0A0A0A),
    textColor: const Color(0xFFFAF9F8),
    accentColor: const Color(0xFFA7CF3F),
    gradientAlpha: 20,
  );
  bool launcherLightThemeCustomized = false;
  bool launcherDarkThemeCustomized = false;
  bool launcherLightFontCustomized = false;
  bool launcherDarkFontCustomized = false;
  bool launcherUseCustomFont = false;
  Map<String, QMDesignThemeSet> quickMenuDesignThemes = Settings.createDefaultQuickMenuDesignThemes();
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;
  ThemeColors get launcherThemeColors => themeTypeMode == ThemeType.dark ? launcherDarkTheme : launcherLightTheme;

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

  static Map<String, QMDesignThemeSet> createDefaultQuickMenuDesignThemes() {
    return <String, QMDesignThemeSet>{
      QuickMenuDesigns.modern.displayName: QMDesignThemeSet(
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
      QuickMenuDesigns.classic.displayName: QMDesignThemeSet(
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
      QuickMenuDesigns.interface.displayName: QMDesignThemeSet(
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
      QuickMenuDesigns.matrix.displayName: QMDesignThemeSet(
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
      QuickMenuDesigns.serene.displayName: QMDesignThemeSet(
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
      QuickMenuDesigns.aurora.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xff080706),
          textColor: const Color(0xff241B3A),
          accentColor: const Color(0xffC9D0D0),
          gradientAlpha: 0,
          uiFontFamily: 'Sora',
          uiFontWeight: 500,
          entryFontFamily: 'Sora',
          entryFontWeight: 600,
          borderRadius: 14,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff0B0B14),
          textColor: const Color(0xffEDEAFB),
          accentColor: const Color(0xff9B83FF),
          gradientAlpha: 78,
          uiFontFamily: 'Sora',
          uiFontWeight: 500,
          entryFontFamily: 'Sora',
          entryFontWeight: 600,
          borderRadius: 14,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.terminal.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xFF1E1E1E),
          textColor: const Color(0xFFD4D4D4),
          accentColor: const Color(0xFF00C7FF),
          gradientAlpha: 0,
          uiFontFamily: 'JetBrains Mono',
          uiFontWeight: 500,
          entryFontFamily: 'JetBrains Mono',
          entryFontWeight: 600,
          borderRadius: 4,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xFF0C0C0C),
          textColor: const Color(0xFFCCCCCC),
          accentColor: const Color(0xFF39D353),
          gradientAlpha: 0,
          uiFontFamily: 'JetBrains Mono',
          uiFontWeight: 500,
          entryFontFamily: 'JetBrains Mono',
          entryFontWeight: 600,
          borderRadius: 4,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.cassette.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffD9D2C3),
          textColor: const Color(0xff3B3428),
          accentColor: const Color(0xffC2551E),
          gradientAlpha: 110,
          uiFontFamily: 'Jura',
          uiFontWeight: 600,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 14,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff17130E),
          textColor: const Color(0xffEAD9B4),
          accentColor: const Color(0xffFFB000),
          gradientAlpha: 140,
          uiFontFamily: 'Jura',
          uiFontWeight: 600,
          entryFontFamily: 'Jura',
          entryFontWeight: 700,
          borderRadius: 14,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.fluent.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF3F3F3),
          textColor: const Color(0xff1B1B1B),
          accentColor: const Color(0xff005FB8),
          gradientAlpha: 60,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 8,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff202020),
          textColor: const Color(0xffFFFFFF),
          accentColor: const Color(0xff60CDFF),
          gradientAlpha: 60,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 8,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.gazette.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF6F1E5),
          textColor: const Color(0xff26211A),
          accentColor: const Color(0xffA3271E),
          gradientAlpha: 120,
          uiFontFamily: 'Georgia',
          uiFontWeight: 400,
          entryFontFamily: 'Georgia',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff1C1913),
          textColor: const Color(0xffE9E1CE),
          accentColor: const Color(0xffD8563F),
          gradientAlpha: 120,
          uiFontFamily: 'Georgia',
          uiFontWeight: 400,
          entryFontFamily: 'Georgia',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.player.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffC7CBD4),
          textColor: const Color(0xff23262C),
          accentColor: const Color(0xff2F6FD6),
          gradientAlpha: 120,
          uiFontFamily: 'Tahoma',
          uiFontWeight: 400,
          entryFontFamily: 'Tahoma',
          entryFontWeight: 700,
          borderRadius: 6,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff31353D),
          textColor: const Color(0xffD9DEE7),
          accentColor: const Color(0xff53C4EF),
          gradientAlpha: 140,
          uiFontFamily: 'Tahoma',
          uiFontWeight: 400,
          entryFontFamily: 'Tahoma',
          entryFontWeight: 700,
          borderRadius: 6,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.steam.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffDFE7EF),
          textColor: const Color(0xff1B2838),
          accentColor: const Color(0xff1A9FFF),
          gradientAlpha: 90,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 4,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff1B2838),
          textColor: const Color(0xffC7D5E0),
          accentColor: const Color(0xff66C0F4),
          gradientAlpha: 90,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 4,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.manifesto.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF2EEDB),
          textColor: const Color(0xff171713),
          accentColor: const Color(0xffE13A27),
          gradientAlpha: 0,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 500,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff171713),
          textColor: const Color(0xffF2EEDB),
          accentColor: const Color(0xffF0D83A),
          gradientAlpha: 0,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 500,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.vector.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffEEF3EE),
          textColor: const Color(0xff15211B),
          accentColor: const Color(0xff0C7A45),
          gradientAlpha: 55,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff0B100E),
          textColor: const Color(0xffCFE3D6),
          accentColor: const Color(0xff3CE68C),
          gradientAlpha: 70,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.ledger.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF3EDDC),
          textColor: const Color(0xff2B2419),
          accentColor: const Color(0xff8C2F1E),
          gradientAlpha: 45,
          uiFontFamily: 'Courier New',
          uiFontWeight: 400,
          entryFontFamily: 'Courier New',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff17130F),
          textColor: const Color(0xffE7DCC0),
          accentColor: const Color(0xffD9812E),
          gradientAlpha: 62,
          uiFontFamily: 'Courier New',
          uiFontWeight: 400,
          entryFontFamily: 'Courier New',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.console.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffDCDFE2),
          textColor: const Color(0xff23272B),
          accentColor: const Color(0xffD98A2B),
          gradientAlpha: 40,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 500,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 700,
          borderRadius: 6,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff1B1D1F),
          textColor: const Color(0xffC9CDD1),
          accentColor: const Color(0xff36D6C4),
          gradientAlpha: 55,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 500,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 700,
          borderRadius: 6,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.foundry.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffE7E2D8),
          textColor: const Color(0xff2B2A26),
          accentColor: const Color(0xffA5472A),
          gradientAlpha: 48,
          uiFontFamily: 'Aldrich',
          uiFontWeight: 500,
          entryFontFamily: 'Aldrich',
          entryFontWeight: 700,
          borderRadius: 4,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff171816),
          textColor: const Color(0xffDDD9CF),
          accentColor: const Color(0xffD96D3B),
          gradientAlpha: 65,
          uiFontFamily: 'Aldrich',
          uiFontWeight: 500,
          entryFontFamily: 'Aldrich',
          entryFontWeight: 700,
          borderRadius: 4,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.anime.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffFFF3F8),
          textColor: const Color(0xff4A2E3B),
          accentColor: const Color(0xffFF6FA3),
          gradientAlpha: 90,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 600,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 700,
          borderRadius: 14,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff211622),
          textColor: const Color(0xffF7D9E6),
          accentColor: const Color(0xffFF8FC0),
          gradientAlpha: 110,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 600,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 700,
          borderRadius: 14,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.cyber.name: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF3E8FF), // Soft lavender blush
          textColor: const Color(0xff3B0764), // Deep violet
          accentColor: const Color(0xffD946EF), // Fuchsia neon
          gradientAlpha: 65,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 500,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 700,
          borderRadius: 2, // Sharp, mecha-style corners
          baseFontSize: 11,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff050217), // Near-black with blue tint
          textColor: const Color(0xffE2E8F0), // Slate-100
          accentColor: const Color(0xff22D3EE), // Cyan neon
          gradientAlpha: 90,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 500,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 700,
          borderRadius: 2,
          baseFontSize: 11,
        ),
      ),
      QuickMenuDesigns.tech.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF8FAFC), // Clean slate
          textColor: const Color(0xff1E293B), // Deep navy/slate
          accentColor: const Color(0xff2563EB), // Electric blue
          gradientAlpha: 50,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 12, // Modern, soft rounded corners
          baseFontSize: 11,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff0B1120), // Deep space blue/black
          textColor: const Color(0xffE2E8F0), // Crisp off-white
          accentColor: const Color(0xff38BDF8), // Bright sky blue
          gradientAlpha: 70,
          uiFontFamily: 'Segoe UI',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI',
          entryFontWeight: 600,
          borderRadius: 12,
          baseFontSize: 11,
        ),
      ),
      QuickMenuDesigns.manga.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF7F3EA), // aged manga page
          textColor: const Color(0xff1B1B1B), // ink black
          accentColor: const Color(0xffD62839), // classic "impact" red
          gradientAlpha: 45,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 700,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 800,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff121212), // noir black page
          textColor: const Color(0xffECECEC), // paper white ink
          accentColor: const Color(0xffFF3B4E), // pop red glowing on black
          gradientAlpha: 85,
          uiFontFamily: 'Bahnschrift',
          uiFontWeight: 700,
          entryFontFamily: 'Bahnschrift',
          entryFontWeight: 800,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      // QuickMenuDesigns.impact.displayName: QMDesignThemeSet(
      //   lightTheme: _defaultThemeColors(
      //     background: const Color(0xffFFFCF6), // manga paper white
      //     textColor: const Color(0xff17171B), // ink black
      //     accentColor: const Color(0xffE8354C), // shonen red
      //     gradientAlpha: 60,
      //     uiFontFamily: 'Segoe UI',
      //     uiFontWeight: 600,
      //     entryFontFamily: 'Segoe UI',
      //     entryFontWeight: 800,
      //     borderRadius: 2,
      //     baseFontSize: 10,
      //   ),
      //   darkTheme: _defaultThemeColors(
      //     background: const Color(0xff0C0C11), // night-arc black
      //     textColor: const Color(0xffF3F3F6),
      //     accentColor: const Color(0xff35E6E0), // electric cyan
      //     gradientAlpha: 75,
      //     uiFontFamily: 'Segoe UI',
      //     uiFontWeight: 600,
      //     entryFontFamily: 'Segoe UI',
      //     entryFontWeight: 800,
      //     borderRadius: 2,
      //     baseFontSize: 10,
      //   ),
      // ),
      QuickMenuDesigns.outrun.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffF8F0FF), // Very light pastel lavender
          textColor: const Color(0xff1A0B2E), // Deep purple
          accentColor: const Color(0xffD300C5), // Hot magenta
          gradientAlpha: 60,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 2, // Sharp retro edges
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff0D0221), // Deep midnight purple
          textColor: const Color(0xffE0AAFF), // Soft neon lavender
          accentColor: const Color(0xff05D9E8), // Electric cyan
          gradientAlpha: 85,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 2,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.anime2.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffFFF5FA),
          textColor: const Color(0xff2D182E),
          accentColor: const Color(0xffE85D9A),
          gradientAlpha: 55,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 12,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff1A0F1E),
          textColor: const Color(0xffF8D4E8),
          accentColor: const Color(0xffFF7EB9),
          gradientAlpha: 70,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 12,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.outrun2.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xff2D1B4E), // Twilight purple
          textColor: const Color(0xff00F0FF), // Electric cyan
          accentColor: const Color(0xffFF00AA), // Hot magenta
          gradientAlpha: 55,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 2, // Sharp 80s CRT angles
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff0A0514), // Midnight void
          textColor: const Color(0xff00F0FF), // Electric cyan
          accentColor: const Color(0xffFF00AA), // Hot magenta
          gradientAlpha: 70,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 2,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.winamp.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xffD6D2CE), // Brushed aluminium
          textColor: const Color(0xff1A1A1A), // Dark pixel readout
          accentColor: const Color(0xff00C853), // LED green
          gradientAlpha: 55,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 1, // Sharp Winamp corners
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xff1E1E1E), // Charcoal chassis
          textColor: const Color(0xffC0C0C0), // Silver LCD text
          accentColor: const Color(0xff00FF41), // Bright LED green
          gradientAlpha: 70,
          uiFontFamily: 'Consolas',
          uiFontWeight: 400,
          entryFontFamily: 'Consolas',
          entryFontWeight: 700,
          borderRadius: 1,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.windowsXp.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xFFECE9D8),
          textColor: const Color(0xFF000000),
          accentColor: const Color(0xFF245EDC),
          gradientAlpha: 255,
          uiFontFamily: 'Tahoma',
          uiFontWeight: 400,
          entryFontFamily: 'Tahoma',
          entryFontWeight: 700,
          borderRadius: 7,
          baseFontSize: 10,
        ),
        // XP never shipped with a dark Luna shell. Keep the authentic palette
        // when the host application follows the system dark-mode setting.
        darkTheme: _defaultThemeColors(
          background: const Color(0xFFECE9D8),
          textColor: const Color(0xFF000000),
          accentColor: const Color(0xFF245EDC),
          gradientAlpha: 255,
          uiFontFamily: 'Tahoma',
          uiFontWeight: 400,
          entryFontFamily: 'Tahoma',
          entryFontWeight: 700,
          borderRadius: 7,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.windows98.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xFFC0C0C0),
          textColor: const Color(0xFF000000),
          accentColor: const Color(0xFF000080),
          gradientAlpha: 0,
          uiFontFamily: 'MS Sans Serif',
          uiFontWeight: 400,
          entryFontFamily: 'MS Sans Serif',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xFFC0C0C0),
          textColor: const Color(0xFF000000),
          accentColor: const Color(0xFF000080),
          gradientAlpha: 0,
          uiFontFamily: 'MS Sans Serif',
          uiFontWeight: 400,
          entryFontFamily: 'MS Sans Serif',
          entryFontWeight: 700,
          borderRadius: 0,
          baseFontSize: 10,
        ),
      ),
      QuickMenuDesigns.notion.displayName: QMDesignThemeSet(
        lightTheme: _defaultThemeColors(
          background: const Color(0xFFF7F6F3),
          textColor: const Color(0xFF37352F),
          accentColor: const Color(0xFF2383E2),
          gradientAlpha: 0,
          uiFontFamily: 'Segoe UI Variable Text',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI Variable Text',
          entryFontWeight: 600,
          borderRadius: 8,
          baseFontSize: 10,
        ),
        darkTheme: _defaultThemeColors(
          background: const Color(0xFF191919),
          textColor: const Color(0xFFE6E6E6),
          accentColor: const Color(0xFF529CCA),
          gradientAlpha: 0,
          uiFontFamily: 'Segoe UI Variable Text',
          uiFontWeight: 400,
          entryFontFamily: 'Segoe UI Variable Text',
          entryFontWeight: 600,
          borderRadius: 8,
          baseFontSize: 10,
        ),
      ),
      // QuickMenuDesigns.familyGuy.displayName: QMDesignThemeSet(
      //   lightTheme: _defaultThemeColors(
      //     background: const Color(0xffF0EBE0), // Living-room wall beige
      //     textColor: const Color(0xff1A1A1A), // Thick cartoon black
      //     accentColor: const Color(0xffFFE135), // Peter's shirt yellow
      //     gradientAlpha: 55,
      //     uiFontFamily: 'Consolas',
      //     uiFontWeight: 400,
      //     entryFontFamily: 'Consolas',
      //     entryFontWeight: 700,
      //     borderRadius: 6, // Slightly rounded like the show's shapes
      //     baseFontSize: 10,
      //   ),
      //   darkTheme: _defaultThemeColors(
      //     background: const Color(0xff1E1E28), // Night-time Quahog
      //     textColor: const Color(0xffF5F5F5), // Off-white
      //     accentColor: const Color(0xffFFE135), // Same iconic yellow
      //     gradientAlpha: 70,
      //     uiFontFamily: 'Consolas',
      //     uiFontWeight: 400,
      //     entryFontFamily: 'Consolas',
      //     entryFontWeight: 700,
      //     borderRadius: 6,
      //     baseFontSize: 10,
      //   ),
      // ),
    };
  }

  QuickMenuDesigns get currentQuickMenuDesign {
    final int safeIndex = quickMenuDesign.clamp(0, QuickMenuDesigns.values.length - 1);
    return QuickMenuDesigns.values[safeIndex];
  }

  void hydrateQuickMenuDesignThemes([Map<String, QMDesignThemeSet>? source]) {
    final Map<String, QMDesignThemeSet> defaults = Settings.createDefaultQuickMenuDesignThemes();
    if (source != null) {
      for (final MapEntry<String, QMDesignThemeSet> entry in source.entries) {
        defaults[entry.key] = entry.value.copyWith();
      }
    }
    quickMenuDesignThemes = defaults.map(
      (String key, QMDesignThemeSet value) => MapEntry<String, QMDesignThemeSet>(key, value.copyWith()),
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
        (String key, dynamic value) => MapEntry<String, QMDesignThemeSet>(
          key,
          QMDesignThemeSet.fromMap(Map<String, dynamic>.from(value as Map<dynamic, dynamic>)),
        ),
      ),
    );
  }

  String quickMenuDesignThemesToJson() {
    return jsonEncode(
      quickMenuDesignThemes.map(
        (String key, QMDesignThemeSet value) => MapEntry<String, dynamic>(key, value.toMap()),
      ),
    );
  }

  void inheritLauncherThemesFromQuickMenu() {
    launcherLightTheme = ThemeColors.fromMap(lightTheme.toMap());
    launcherDarkTheme = ThemeColors.fromMap(darkTheme.toMap());
    launcherLightThemeCustomized = false;
    launcherDarkThemeCustomized = false;
    launcherLightFontCustomized = false;
    launcherDarkFontCustomized = false;
    launcherUseCustomFont = false;
  }

  ThemeColors _inheritedLauncherTheme(
    ThemeColors quickMenuTheme,
    ThemeColors launcherTheme, {
    required bool fontCustomized,
  }) {
    final ThemeColors inheritedTheme = ThemeColors.fromMap(quickMenuTheme.toMap());
    if (!fontCustomized) return inheritedTheme;

    return inheritedTheme.copyWith(
      uiFontFamily: launcherTheme.uiFontFamily,
      uiFontWeight: launcherTheme.uiFontWeight,
      uiFontItalic: launcherTheme.uiFontItalic,
      entryFontFamily: launcherTheme.entryFontFamily,
      entryFontWeight: launcherTheme.entryFontWeight,
      entryFontItalic: launcherTheme.entryFontItalic,
    );
  }

  ThemeColors _launcherThemeWithInheritedFonts(
    ThemeColors launcherTheme,
    ThemeColors quickMenuTheme, {
    required bool fontCustomized,
  }) {
    if (fontCustomized) return launcherTheme;
    return launcherTheme.copyWith(
      uiFontFamily: quickMenuTheme.uiFontFamily,
      uiFontWeight: quickMenuTheme.uiFontWeight,
      uiFontItalic: quickMenuTheme.uiFontItalic,
      entryFontFamily: quickMenuTheme.entryFontFamily,
      entryFontWeight: quickMenuTheme.entryFontWeight,
      entryFontItalic: quickMenuTheme.entryFontItalic,
    );
  }

  void syncInheritedLauncherThemes() {
    if (!launcherLightThemeCustomized) {
      launcherLightTheme = _inheritedLauncherTheme(
        lightTheme,
        launcherLightTheme,
        fontCustomized: launcherLightFontCustomized,
      );
    } else {
      launcherLightTheme = _launcherThemeWithInheritedFonts(
        launcherLightTheme,
        lightTheme,
        fontCustomized: launcherLightFontCustomized,
      );
    }
    if (!launcherDarkThemeCustomized) {
      launcherDarkTheme = _inheritedLauncherTheme(
        darkTheme,
        launcherDarkTheme,
        fontCustomized: launcherDarkFontCustomized,
      );
    } else {
      launcherDarkTheme = _launcherThemeWithInheritedFonts(
        launcherDarkTheme,
        darkTheme,
        fontCustomized: launcherDarkFontCustomized,
      );
    }
  }

  void loadLauncherDesignSettingsFromJson(String source) {
    final Map<String, dynamic> decoded = Map<String, dynamic>.from(jsonDecode(source) as Map<dynamic, dynamic>);
    launcherLightTheme = ThemeColors.fromMap(Map<String, dynamic>.from(decoded['lightTheme'] as Map<dynamic, dynamic>));
    launcherDarkTheme = ThemeColors.fromMap(Map<String, dynamic>.from(decoded['darkTheme'] as Map<dynamic, dynamic>));
    launcherLightThemeCustomized = (decoded['lightThemeCustomized'] ?? false) as bool;
    launcherDarkThemeCustomized = (decoded['darkThemeCustomized'] ?? false) as bool;
    launcherUseCustomFont = (decoded['useCustomFont'] ?? false) as bool;
    launcherLightFontCustomized = (decoded['lightFontCustomized'] ?? launcherUseCustomFont) as bool;
    launcherDarkFontCustomized = (decoded['darkFontCustomized'] ?? launcherUseCustomFont) as bool;
    syncInheritedLauncherThemes();
  }

  String launcherDesignSettingsToJson() {
    return jsonEncode(<String, dynamic>{
      'lightTheme': launcherLightTheme.toMap(),
      'darkTheme': launcherDarkTheme.toMap(),
      'lightThemeCustomized': launcherLightThemeCustomized,
      'darkThemeCustomized': launcherDarkThemeCustomized,
      'lightFontCustomized': launcherLightFontCustomized,
      'darkFontCustomized': launcherDarkFontCustomized,
      'useCustomFont': launcherUseCustomFont,
    });
  }

  void saveActiveThemesToCurrentDesign([QuickMenuDesigns? design]) {
    final QuickMenuDesigns target = design ?? currentQuickMenuDesign;
    quickMenuDesignThemes[target.displayName] = QMDesignThemeSet(
      lightTheme: lightTheme.copyWith(),
      darkTheme: darkTheme.copyWith(),
    );
  }

  void applyThemesForDesign(
    QuickMenuDesigns design, {
    ThemeColors? fallbackLightTheme,
    ThemeColors? fallbackDarkTheme,
  }) {
    final QMDesignThemeSet? savedThemeSet = quickMenuDesignThemes[design.displayName];
    lightTheme = (savedThemeSet?.lightTheme ??
            fallbackLightTheme ??
            Settings.createDefaultQuickMenuDesignThemes()[design.displayName]!.lightTheme)
        .copyWith();
    darkTheme = (savedThemeSet?.darkTheme ??
            fallbackDarkTheme ??
            Settings.createDefaultQuickMenuDesignThemes()[design.displayName]!.darkTheme)
        .copyWith();
    saveActiveThemesToCurrentDesign(design);
  }

  ThemeType themeTypeMode = ThemeType.system;

  /// Get Dark or Light Theme
  ThemeType get themeTypeMode2 {
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
    if (user.lightSwitchMode == LightSwitchMode.off) return;

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

Settings user = Settings();
void checkThemeChange() {
  ThemeType newType = user.themeTypeMode;
  if (user.themeType == ThemeType.system) {
    if (WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark) {
      newType = ThemeType.dark;
    } else {
      newType = ThemeType.light;
    }
  } else if (user.themeType == ThemeType.schedule) {
    final int start = user.lightSwitchMode == LightSwitchMode.sunrise
        ? (user.lightSwitchSunrise + user.lightSwitchSunriseOffset)
        : user.themeScheduleMin;
    final int end = user.lightSwitchMode == LightSwitchMode.sunrise
        ? (user.lightSwitchSunset + user.lightSwitchSunsetOffset)
        : user.themeScheduleMax;
    final DateTime now0 = DateTime.now();
    final int now = (now0.hour * 60) + now0.minute;
    newType = now.isBetweenEqual(start, end) ? ThemeType.light : ThemeType.dark;
  } else {
    newType = user.themeType;
  }
  if (user.themeTypeMode != newType) {
    user.themeTypeMode = newType;
    QuickMenuFunctions.refreshQuickMenu();
    // QmTaskbarRewrites
    // InterfaceQMBookmarksSettings
  }
}

Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);
  Debug.add("Registered: Locale");

  // ? Monitor Handle
  Monitor.fetchMonitors();
  Debug.add("Registered: Monitor");
  // Timer.periodic(const Duration(seconds: 10), (Timer timer) {
  //   if (!QuickMenuFunctions.isQuickMenuVisible) return;
  //   Monitor.fetchMonitors();
  // });
  checkThemeChange();
  Timer.periodic(const Duration(seconds: 1), (Timer timer) {
    if (QuickMenuFunctions.isQuickMenuVisible) checkThemeChange();
  });
  Timer.periodic(const Duration(seconds: 5), (Timer timer) {
    if (!user.hideDesktopFiles) return;
    WinUtils.toggleDesktopFiles(visible: false);
  });
  //register
  await Boxes.registerBoxes(justLoad: Globals.currentPage == Pages.interface ? true : false);
  Debug.add("Registered: Boxes");
  //Schedule Theme
  user.setScheduleThemeChange();
  if (user.lightSwitchMode == LightSwitchMode.sunrise) {
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

  // Rewindly background DVR — main/QuickMenu process only, never the Interface
  // settings window (which runs as a separate process).
  if (Globals.currentPage != Pages.interface) {
    RewindlyService.instance.init();
    Debug.add("Registered: Rewindly");
  }
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
  String addDots(int max, {String suffix = '...'}) => length < max ? this : replaceRange(max, null, suffix);
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

  static const int maxLines = 500;

  static File theFile = File("${WinUtils.getTabameAppDataFolder()}\\debug.log");

  static bool enabled = false;

  static void register({bool clean = true}) {
    enabled = true;

    _trimToLastLines(theFile, maxLines);

    theFile.writeAsStringSync("========\n", mode: clean ? FileMode.writeOnlyAppend : FileMode.append);

    File("${WinUtils.getTabameAppDataFolder()}\\debug_cpp.log")
        .writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);
  }

  static void _trimToLastLines(File file, int keepLines) {
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      return;
    }

    final List<String> lines = file.readAsLinesSync();

    if (lines.length > keepLines) {
      final List<String> trimmed = lines.sublist(lines.length - keepLines);
      file.writeAsStringSync("${trimmed.join('\n')}\n");
    }
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
    if (!theFile.existsSync()) {
      theFile.createSync(recursive: true);
    }

    theFile.writeAsStringSync(
      "ERROR: $text\n",
      mode: FileMode.append,
    );
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

TextStyle baseEntryStyle = GoogleFonts.getFont(
  Design.entryFontFamily,
  fontSize: Design.baseFontSize + 2,
  color: Design.text,
  fontWeight: FontWeight(
    Design.entryFontWeight,
  ),
  fontStyle: Design.entryFontItalic ? FontStyle.italic : FontStyle.normal,
);
TextStyle entryStyle(bool? isSelected, {double? fontSize, double? letterSpacing, Color? color}) {
  return baseEntryStyle.copyWith(
    fontSize: fontSize ?? Design.baseFontSize + 2,
    letterSpacing: letterSpacing ?? 1.4,
    color: color ?? ((isSelected ?? false) ? Design.text : Design.text.withAlpha(200)),
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
