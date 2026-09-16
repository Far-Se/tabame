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

import '../platform/audio_system_service.dart';
import '../platform/monitor_service.dart';
import '../platform/quick_snap_service.dart';
import '../platform/windows/tabamewin32_api.dart';
import '../services/rewindly_service.dart';
import 'classes/boxes.dart';
import 'classes/saved_maps.dart';
import 'design_settings.dart';
import 'globals.dart';
import '../platform/app_paths.dart';
import 'util/solar_calculator.dart';

import 'win32/win_utils.dart';

enum TPage {
  quickmenu,
  interface,
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
  static String get uiFontFamily => quickMenuContentFont(_colors.uiFontFamily);
  static int get uiFontWeight => _colors.uiFontWeight;
  static bool get uiFontItalic => _colors.uiFontItalic;
  static bool get useCustomFont => _isLauncher && user.launcherUseCustomFont;
  static String get entryFontFamily => quickMenuContentFont(_colors.entryFontFamily);
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
  static bool get arcadeTypography =>
      !_isLauncher &&
      user.page == TPage.quickmenu &&
      (user.currentQuickMenuDesign == QuickMenuDesigns.retro ||
          user.currentQuickMenuDesign == QuickMenuDesigns.superMario);

  // Older saved arcade palettes used display fonts for everyday controls.
  // Resolve those defaults at render time without rewriting saved preferences.
  static String quickMenuContentFont(String family) =>
      arcadeTypography && (family == 'Press Start 2P' || family == 'VT323') ? 'Jura' : family;
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
  // int quickRunState = 0;
  bool showTrayBar = true;
  bool showWeather = true;
  bool libreStats = false;
  bool isWindows10 = false;
  bool quickSnapGrid = true;
  bool previewTheme = false;
  bool volumeSetBack = false;
  bool keepPopupsOpen = true;
  bool useCustomCursor = true;
  bool expandedTaskbar = true;
  bool bottomBarOnTop = false;
  bool quickSnapOverlay = true;
  bool noopKeyListener = false;
  bool showSystemUsage = false;
  bool mergePinnedTray = false;
  bool taskbarHoverSlide = true;
  bool trktivityEnabled = false;
  bool taskManagerStats = false;
  bool quickClickEnabled = false;
  bool runAsAdministrator = false;
  bool launcherFullPopups = false;
  bool trayBarAlternative = false;
  bool _hideTabameOnUnfocus = true;
  bool autoOpenTaskManager = false;
  bool autoCheckForUpdates = false;
  bool pluginAutoUpdate = false;

  /// Optional prefix shared by launcher plugin keywords, e.g. `;` makes
  /// `weather` launch as `;weather`.
  String pluginShortcut = '';
  bool dragPopupsByIconOnly = true;
  bool keepPopupOpenOnDemand = false;
  bool quickActionsAtBottom = false;
  int quickMenuDesign = Random().nextInt(QuickMenuDesigns.values.length);
  LauncherDesign launcherDesign = LauncherDesign.values[Random().nextInt(LauncherDesign.values.length)];
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
  bool aiCodingUsageInTaskbar = false;
  List<String> aiCodingUsageAgents = <String>['codex', 'claude'];
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
  int mouseGestureMaxDelay = 600;
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
  ThemeColors lightTheme = DesignSettings.defaultThemeColors(
    background: const Color(0xffD5E0FB),
    textColor: const Color(0xff3A404A),
    accentColor: const Color(0xff446EE9),
    gradientAlpha: 200,
  );
  ThemeColors darkTheme = DesignSettings.defaultThemeColors(
    background: const Color(0xFF0A0A0A),
    textColor: const Color(0xFFFAF9F8),
    accentColor: const Color(0xFFA7CF3F),
    gradientAlpha: 20,
  );
  Map<String, LauncherDesignThemeSet> launcherDesignThemes = DesignSettings.createDefaultLauncherDesignThemes();

  LauncherDesignThemeSet get currentLauncherDesignThemeSet {
    final String key = launcherDesign.displayName;
    final LauncherDesignThemeSet? savedThemeSet = launcherDesignThemes[key];
    if (savedThemeSet != null) return savedThemeSet;

    final LauncherDesignThemeSet fallback = DesignSettings.createDefaultLauncherDesignThemes()[key]!;
    launcherDesignThemes[key] = fallback;
    return fallback;
  }

  ThemeColors get launcherLightTheme => currentLauncherDesignThemeSet.lightTheme;
  set launcherLightTheme(ThemeColors value) => currentLauncherDesignThemeSet.lightTheme = value;
  ThemeColors get launcherDarkTheme => currentLauncherDesignThemeSet.darkTheme;
  set launcherDarkTheme(ThemeColors value) => currentLauncherDesignThemeSet.darkTheme = value;
  bool get launcherLightThemeCustomized => currentLauncherDesignThemeSet.lightThemeCustomized;
  set launcherLightThemeCustomized(bool value) => currentLauncherDesignThemeSet.lightThemeCustomized = value;
  bool get launcherDarkThemeCustomized => currentLauncherDesignThemeSet.darkThemeCustomized;
  set launcherDarkThemeCustomized(bool value) => currentLauncherDesignThemeSet.darkThemeCustomized = value;
  bool get launcherLightFontCustomized => currentLauncherDesignThemeSet.lightFontCustomized;
  set launcherLightFontCustomized(bool value) => currentLauncherDesignThemeSet.lightFontCustomized = value;
  bool get launcherDarkFontCustomized => currentLauncherDesignThemeSet.darkFontCustomized;
  set launcherDarkFontCustomized(bool value) => currentLauncherDesignThemeSet.darkFontCustomized = value;
  bool get launcherUseCustomFont => currentLauncherDesignThemeSet.useCustomFont;
  set launcherUseCustomFont(bool value) => currentLauncherDesignThemeSet.useCustomFont = value;
  bool get launcherShowTitlebar => currentLauncherDesignThemeSet.showTitlebar;
  set launcherShowTitlebar(bool value) => currentLauncherDesignThemeSet.showTitlebar = value;
  Map<String, QMDesignThemeSet> quickMenuDesignThemes = DesignSettings.createDefaultQuickMenuDesignThemes();
  ThemeColors get themeColors => themeTypeMode == ThemeType.dark ? darkTheme : lightTheme;
  ThemeColors get launcherThemeColors => themeTypeMode == ThemeType.dark ? launcherDarkTheme : launcherLightTheme;

  ThemeColors appThemeColors({required bool isDark}) {
    final QuickMenuDesigns design = currentQuickMenuDesign;
    final bool useClassicInterfaceTheme =
        page == TPage.interface && (design == QuickMenuDesigns.windowsXp || design == QuickMenuDesigns.windows98);
    if (!useClassicInterfaceTheme) return isDark ? darkTheme : lightTheme;

    final QMDesignThemeSet classicThemes = quickMenuDesignThemes[QuickMenuDesigns.classic.displayName] ??
        DesignSettings.createDefaultQuickMenuDesignThemes()[QuickMenuDesigns.classic.displayName]!;
    return (isDark ? classicThemes.darkTheme : classicThemes.lightTheme).copyWith();
  }

  QuickMenuDesigns get currentQuickMenuDesign {
    final int safeIndex = quickMenuDesign.clamp(0, QuickMenuDesigns.values.length - 1);
    return QuickMenuDesigns.values[safeIndex];
  }

  void hydrateQuickMenuDesignThemes([Map<String, QMDesignThemeSet>? source]) {
    final Map<String, QMDesignThemeSet> defaults = DesignSettings.createDefaultQuickMenuDesignThemes();
    if (source != null) {
      for (final MapEntry<String, QMDesignThemeSet> entry in source.entries) {
        final QMDesignThemeSet saved = entry.value.copyWith();

        // The arcade designs originally stored their dark palette in both
        // theme slots. Upgrade that exact old light palette while preserving
        // custom fonts, radius, backdrops, and other appearance settings.
        bool matchesPalette(ThemeColors theme, Color background, Color text, Color accent) =>
            theme.background == background && theme.text == text && theme.accent == accent;

        void migrateLightPalette(QuickMenuDesigns design, Color background, Color text, Color accent) {
          if (entry.key != design.displayName || !matchesPalette(saved.lightTheme, background, text, accent)) return;
          final ThemeColors light = defaults[entry.key]!.lightTheme;
          saved.lightTheme = saved.lightTheme.copyWith(
            background: light.background,
            text: light.text,
            accent: light.accent,
          );
        }

        migrateLightPalette(
          QuickMenuDesigns.crt,
          const Color(0xFF130F09),
          const Color(0xFFFFDDA0),
          const Color(0xFFFFBE62),
        );
        migrateLightPalette(
          QuickMenuDesigns.retro,
          const Color(0xFF090B1A),
          const Color(0xFFFFF0C6),
          const Color(0xFFFF4F9A),
        );
        migrateLightPalette(
          QuickMenuDesigns.superMario,
          const Color(0xFF15264A),
          const Color(0xFFFCF4DC),
          const Color(0xFFF8C840),
        );

        defaults[entry.key] = saved;
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
    final LauncherDesignThemeSet current = currentLauncherDesignThemeSet;
    current.lightTheme = ThemeColors.fromMap(lightTheme.toMap());
    current.darkTheme = ThemeColors.fromMap(darkTheme.toMap());
    current.lightThemeCustomized = false;
    current.darkThemeCustomized = false;
    current.lightFontCustomized = false;
    current.darkFontCustomized = false;
    current.useCustomFont = false;
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
    for (final LauncherDesignThemeSet themeSet in launcherDesignThemes.values) {
      if (!themeSet.lightThemeCustomized) {
        themeSet.lightTheme = _inheritedLauncherTheme(
          lightTheme,
          themeSet.lightTheme,
          fontCustomized: themeSet.lightFontCustomized,
        );
      } else {
        themeSet.lightTheme = _launcherThemeWithInheritedFonts(
          themeSet.lightTheme,
          lightTheme,
          fontCustomized: themeSet.lightFontCustomized,
        );
      }
      if (!themeSet.darkThemeCustomized) {
        themeSet.darkTheme = _inheritedLauncherTheme(
          darkTheme,
          themeSet.darkTheme,
          fontCustomized: themeSet.darkFontCustomized,
        );
      } else {
        themeSet.darkTheme = _launcherThemeWithInheritedFonts(
          themeSet.darkTheme,
          darkTheme,
          fontCustomized: themeSet.darkFontCustomized,
        );
      }
    }
  }

  void hydrateLauncherDesignThemes([Map<String, LauncherDesignThemeSet>? source]) {
    final Map<String, LauncherDesignThemeSet> defaults = DesignSettings.createDefaultLauncherDesignThemes();
    if (source != null) {
      for (final MapEntry<String, LauncherDesignThemeSet> entry in source.entries) {
        final LauncherDesignThemeSet saved = entry.value.copyWith();
        // Capillary originally saved the light palette in both theme slots.
        // Upgrade that exact old palette while preserving fonts and appearance settings.
        if (entry.key == LauncherDesign.capillary.displayName &&
            saved.darkTheme.background == const Color(0xFFF3F0E6) &&
            saved.darkTheme.text == const Color(0xFF252C3C) &&
            saved.darkTheme.accent == const Color(0xFF354B82)) {
          final ThemeColors dark = defaults[entry.key]!.darkTheme;
          saved.darkTheme = saved.darkTheme.copyWith(background: dark.background, text: dark.text, accent: dark.accent);
        }

        bool matchesPalette(ThemeColors theme, Color background, Color text, Color accent) =>
            theme.background == background && theme.text == text && theme.accent == accent;

        void migrateLightPalette(LauncherDesign design, Color background, Color text, Color accent) {
          if (entry.key != design.displayName || !matchesPalette(saved.lightTheme, background, text, accent)) return;
          final ThemeColors light = defaults[entry.key]!.lightTheme;
          saved.lightTheme = saved.lightTheme.copyWith(
            background: light.background,
            text: light.text,
            accent: light.accent,
          );
        }

        void migrateDarkPalette(LauncherDesign design, Color background, Color text, Color accent) {
          if (entry.key != design.displayName || !matchesPalette(saved.darkTheme, background, text, accent)) return;
          final ThemeColors dark = defaults[entry.key]!.darkTheme;
          saved.darkTheme = saved.darkTheme.copyWith(
            background: dark.background,
            text: dark.text,
            accent: dark.accent,
          );
        }

        migrateLightPalette(
          LauncherDesign.thermal,
          const Color(0xFF14181C),
          const Color(0xFFEEE9DF),
          const Color(0xFFE1AD70),
        );
        migrateDarkPalette(
          LauncherDesign.opticalGlass,
          const Color(0xFFE5EAF2),
          const Color(0xFF202D45),
          const Color(0xFF435B91),
        );
        migrateLightPalette(
          LauncherDesign.liquidMetal,
          const Color(0xFF12151A),
          const Color(0xFFECEAE4),
          const Color(0xFFCEC5AF),
        );
        migrateLightPalette(
          LauncherDesign.crt,
          const Color(0xFF130F09),
          const Color(0xFFFFDDA0),
          const Color(0xFFFFBE62),
        );
        migrateLightPalette(
          LauncherDesign.retro,
          const Color(0xFF090B1A),
          const Color(0xFFFFF0C6),
          const Color(0xFFFF4F9A),
        );
        migrateLightPalette(
          LauncherDesign.toon,
          const Color(0xFF292C30),
          const Color(0xFFFFF3D6),
          const Color(0xFFFFB642),
        );
        migrateLightPalette(
          LauncherDesign.phosphor,
          const Color(0xFF090F0E),
          const Color(0xFFDCE3DF),
          const Color(0xFF58EF92),
        );
        migrateLightPalette(
          LauncherDesign.strata,
          const Color(0xFF0C151A),
          const Color(0xFFEEF3F7),
          const Color(0xFF20DFE3),
        );
        defaults[entry.key] = saved;
      }
    }
    launcherDesignThemes = defaults.map(
      (String key, LauncherDesignThemeSet value) => MapEntry<String, LauncherDesignThemeSet>(key, value.copyWith()),
    );
  }

  void loadLauncherDesignSettingsFromJson(String source) {
    final Map<String, dynamic> decoded = Map<String, dynamic>.from(jsonDecode(source) as Map<dynamic, dynamic>);
    final dynamic serializedThemes = decoded['launcherDesignThemes'];
    if (serializedThemes is Map) {
      final Map<String, LauncherDesignThemeSet> parsedThemes = <String, LauncherDesignThemeSet>{};
      for (final MapEntry<dynamic, dynamic> entry in serializedThemes.entries) {
        parsedThemes[entry.key as String] =
            LauncherDesignThemeSet.fromMap(Map<String, dynamic>.from(entry.value as Map<dynamic, dynamic>));
      }
      hydrateLauncherDesignThemes(parsedThemes);
    } else {
      // Migrate the former single launcher palette into the currently selected
      // design while all other designs keep their new built-in defaults.
      hydrateLauncherDesignThemes();
      final LauncherDesignThemeSet current = currentLauncherDesignThemeSet;
      current.lightTheme =
          ThemeColors.fromMap(Map<String, dynamic>.from(decoded['lightTheme'] as Map<dynamic, dynamic>));
      current.darkTheme = ThemeColors.fromMap(Map<String, dynamic>.from(decoded['darkTheme'] as Map<dynamic, dynamic>));
      current.lightThemeCustomized = (decoded['lightThemeCustomized'] ?? false) as bool;
      current.darkThemeCustomized = (decoded['darkThemeCustomized'] ?? false) as bool;
      current.useCustomFont = (decoded['useCustomFont'] ?? false) as bool;
      current.lightFontCustomized = (decoded['lightFontCustomized'] ?? current.useCustomFont) as bool;
      current.darkFontCustomized = (decoded['darkFontCustomized'] ?? current.useCustomFont) as bool;
    }
    syncInheritedLauncherThemes();
  }

  String launcherDesignSettingsToJson() {
    return jsonEncode(<String, dynamic>{
      'launcherDesignThemes': launcherDesignThemes.map(
        (String key, LauncherDesignThemeSet value) => MapEntry<String, dynamic>(key, value.toMap()),
      ),
    });
  }

  void applyLauncherThemesForDesign(LauncherDesign design) {
    launcherDesign = design;
    launcherDesignThemes[design.displayName] ??=
        DesignSettings.createDefaultLauncherDesignThemes()[design.displayName]!;
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
            DesignSettings.createDefaultQuickMenuDesignThemes()[design.displayName]!.lightTheme)
        .copyWith();
    darkTheme = (savedThemeSet?.darkTheme ??
            fallbackDarkTheme ??
            DesignSettings.createDefaultQuickMenuDesignThemes()[design.displayName]!.darkTheme)
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

  // QuickSnap receives monitor geometry through the neutral adapter.
  if (MonitorService.instance.isAvailable) {
    await MonitorService.instance.enumerate();
  }
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
  await QuickSnapService.instance.enable();
  //

  await AudioSystemService.instance.initialize();
  await MediaSessionService.instance.initialize();

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

  static File get theFile => File(AppPaths.resolvePath('debug.log', forWrite: true));

  static bool enabled = false;

  static void register({bool clean = true}) {
    enabled = true;

    _trimToLastLines(theFile, maxLines);

    theFile.writeAsStringSync("========\n", mode: clean ? FileMode.writeOnlyAppend : FileMode.append);

    File(AppPaths.currentPath('debug_cpp.log'))
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
    final String debugPath = AppPaths.currentPath('debug_cpp.log');
    File(debugPath).writeAsStringSync("=======\n", mode: clean ? FileMode.write : FileMode.append);

    enableDebug(debugPath);
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
  final TextStyle style = Design.arcadeTypography
      ? GoogleFonts.getFont(Design.entryFontFamily,
          fontWeight: FontWeight(Design.entryFontWeight),
          fontStyle: Design.entryFontItalic ? FontStyle.italic : FontStyle.normal)
      : baseEntryStyle;
  return style.copyWith(
    fontSize: fontSize ?? Design.baseFontSize + (Design.arcadeTypography ? 1 : 2),
    letterSpacing: letterSpacing ?? (Design.arcadeTypography ? 0.2 : 1.4),
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
