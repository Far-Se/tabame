import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../globals.dart';
import '../../settings.dart';
import '../../util/quick_action_list.dart';
import '../../win32/win_utils.dart';
import '../../win32/window.dart';
import '../app_items.dart';
import '../hotkeys.dart';
import '../save_settings.dart';
import '../saved_maps.dart';
import '../screen_draw_hotkeys.dart';
import 'quick_actions_box.dart';
// Import sub-boxes
import 'quick_menu_box.dart';
import 'quick_timers_box.dart';
import 'search_folder_box.dart';
import 'search_history.dart';
import 'tasks_box.dart';

// --------------------------------------------------------------------------
// Boxes
// --------------------------------------------------------------------------

class Boxes {
  static late SaveSettings pref;
  static List<String> mediaControls = <String>[];

  Boxes();

  // --------------------------------------------------------------------------
  // Group: App registration and startup bootstrapping
  // Purpose: Load persisted settings, apply defaults, and initialize startup services.
  // --------------------------------------------------------------------------

  static Future<void> registerBoxes({bool reload = false, bool justLoad = false}) async {
    if (reload) {
      await pref.reload();
    } else {
      pref = await SaveSettings.getInstance();
    }

    globalSettings.isWindows10 = WinUtils.isWindows10();
    Debug.add(
        "Registered: Loaded Box info (win10: ${globalSettings.isWindows10} | ${Platform.operatingSystemVersion})");

    // First-run defaults
    if (pref.getString("language") == null) {
      await pref.setBool("DEBUGGING", false);
      await pref.setInt("quickMenuDesign", QuickMenuDesigns.modern.index);
      await pref.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await pref.setInt("volumeOSDStyle", VolumeOSDStyle.normal.index);
      await pref.setInt("themeType", ThemeType.system.index);
      await pref.setString("quickMenuDesignThemes", globalSettings.quickMenuDesignThemesToJson());
      await pref.setString("lightTheme", globalSettings.lightTheme.toJson());
      await pref.setString("darkTheme", globalSettings.darkTheme.toJson());
      await pref.setString("language", Platform.localeName.substring(0, 2));
      await pref.setStringList("weather", <String>["10 C", "52.52437, 13.41053", "m"]);
      await pref.setBool("hideTaskbarOnStartup", false);
      await pref.setBool("hideDesktopFiles", false);
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setBool("showMediaControlForApp", true);
      await pref.setBool("showMusicPlayerInTaskbar", true);
      await pref.setBool("showTrayBar", true);
      await pref.setBool("showWeather", true);
      await pref.setBool("showSystemUsage", false);
      await pref.setBool("taskManagerStats", false);
      await pref.setBool("runAsAdministrator", false);
      await pref.setBool("hideTabameOnUnfocus", true);
      await pref.setString("wallpapersFolder", "");
      await pref.setString("lastQuickSnapZoneId", "");
      await pref.setInt("lightSwitchMode", LightSwitchMode.off.index);
      await pref.setInt("lightSwitchSunriseOffset", 0);
      await pref.setInt("lightSwitchSunsetOffset", 0);
      await pref.setInt("lightSwitchSunrise", 6 * 60);
      await pref.setInt("lightSwitchSunset", 18 * 60);
      await pref.setInt("lightSwitchLastFetch", 0);

      final List<Reminder> defaultReminders = <Reminder>[
        Reminder(
          enabled: false,
          interval: <int>[540, 1200],
          message: "Stretch",
          repetitive: true,
          time: 60,
          multipleTimes: <int>[],
          voiceNotification: true,
          weekDays: <bool>[true, true, true, true, true, false, false],
          voiceVolume: 100,
        ),
        Reminder(
          enabled: false,
          weekDays: <bool>[true, true, true, true, true, true, true],
          time: 540,
          multipleTimes: <int>[],
          repetitive: false,
          interval: <int>[480, 1200],
          message: "Take your meds",
          voiceNotification: false,
          voiceVolume: 100,
        ),
      ];
      await pref.setString("reminders", jsonEncode(defaultReminders));
      Debug.add("Registered: setDefault Settings");
    }

    // Fetch all settings
    globalSettings
      ..quickMenuDesign = pref.getInt("quickMenuDesign") ?? globalSettings.quickMenuDesign
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..volumeOSDStyle = VolumeOSDStyle.values[pref.getInt("volumeOSDStyle") ?? 0]
      ..language = pref.getString("language") ?? Platform.localeName.substring(0, 2)
      ..audio = pref.getStringList("audio") ?? globalSettings.audio
      ..weather = pref.getStringList("weather") ?? globalSettings.weather
      ..customLogo = pref.getString("customLogo") ?? globalSettings.customLogo
      ..newVersion = pref.getString("newVersion") ?? globalSettings.newVersion
      ..showTrayBar = pref.getBool("showTrayBar") ?? globalSettings.showTrayBar
      ..showWeather = pref.getBool("showWeather") ?? globalSettings.showWeather
      ..customSpash = pref.getString("customSpash") ?? globalSettings.customSpash
      ..volumeSetBack = pref.getBool("volumeSetBack") ?? globalSettings.volumeSetBack
      ..quickSnapGrid = pref.getBool("quickSnapGrid") ?? globalSettings.quickSnapGrid
      ..lastChangelog = pref.getString("lastChangelog") ?? globalSettings.lastChangelog
      ..keepPopupsOpen = pref.getBool("keepPopupsOpen") ?? globalSettings.keepPopupsOpen
      ..expandedTaskbar = pref.getBool("expandedTaskbar") ?? globalSettings.expandedTaskbar
      ..showSystemUsage = pref.getBool("showSystemUsage") ?? globalSettings.showSystemUsage
      ..themeScheduleMin = pref.getInt("themeScheduleMin") ?? globalSettings.themeScheduleMin
      ..themeScheduleMax = pref.getInt("themeScheduleMax") ?? globalSettings.themeScheduleMax
      ..taskManagerStats = pref.getBool("taskManagerStats") ?? globalSettings.taskManagerStats
      ..quickSnapOverlay = pref.getBool("quickSnapOverlay") ?? globalSettings.quickSnapOverlay
      ..hideDesktopFiles = pref.getBool("hideDesktopFiles") ?? globalSettings.hideDesktopFiles
      ..trktivityEnabled = pref.getBool("trktivityEnabled") ?? globalSettings.trktivityEnabled
      ..autoCheckForUpdates = pref.getBool("autoUpdate") ?? globalSettings.autoCheckForUpdates
      ..wallpapersFolder = pref.getString("wallpapersFolder") ?? globalSettings.wallpapersFolder
      ..runAsAdministrator = pref.getBool("runAsAdministrator") ?? globalSettings.runAsAdministrator
      ..hideTabameOnUnfocus = pref.getBool("hideTabameOnUnfocus") ?? globalSettings.hideTabameOnUnfocus
      ..lastQuickSnapZoneId = pref.getString("lastQuickSnapZoneId") ?? globalSettings.lastQuickSnapZoneId
      ..quickActionsAtBottom = pref.getBool("quickActionsAtBottom") ?? globalSettings.quickActionsAtBottom
      ..dragPopupsByIconOnly = pref.getBool("dragPopupsByIconOnly") ?? globalSettings.dragPopupsByIconOnly
      ..hideTaskbarOnStartup = pref.getBool("hideTaskbarOnStartup") ?? globalSettings.hideTaskbarOnStartup
      ..persistentReminders = pref.getStringList("persistentReminders") ?? globalSettings.persistentReminders
      ..showMediaControlForApp = pref.getBool("showMediaControlForApp") ?? globalSettings.showMediaControlForApp
      ..showMusicPlayerInTaskbar = pref.getBool("showMusicPlayerInTaskbar") ?? globalSettings.showMusicPlayerInTaskbar
      ..trktivitySaveAllTitles = pref.getBool("trktivitySaveAllTitles") ?? globalSettings.trktivitySaveAllTitles
      ..showQuickMenuAtTaskbarLevel =
          pref.getBool("showQuickMenuAtTaskbarLevel") ?? globalSettings.showQuickMenuAtTaskbarLevel
      ..lightSwitchMode = LightSwitchMode.values[pref.getInt("lightSwitchMode") ?? 0]
      ..lightSwitchSunriseOffset = pref.getInt("lightSwitchSunriseOffset") ?? 0
      ..lightSwitchSunsetOffset = pref.getInt("lightSwitchSunsetOffset") ?? 0
      ..lightSwitchSunrise = pref.getInt("lightSwitchSunrise") ?? 6 * 60
      ..lightSwitchSunset = pref.getInt("lightSwitchSunset") ?? 18 * 60
      ..lightSwitchLastFetch = pref.getInt("lightSwitchLastFetch") ?? 0
      ..themeType = ThemeType.values[pref.getInt("themeType") ?? 0]; // must be set after schedule

    Debug.add("Registered: Fetched All");

    if (pref.getBool("DEBUGGING") ?? false == true) {
      Debug.register(clean: false);
      Debug.methodDebug(clean: false);
    }

    final bool justInstalled = pref.getBool("justInstalled") ?? false;
    if (justInstalled) {
      updateSettings("justInstalled", false);
      Debug.add("Registered: Shortcut");
      createShortcut(
        Platform.resolvedExecutable,
        WinUtils.getKnownFolder(FOLDERID_Programs),
        args: "-interface",
        destExe: "Tabame Interface.lnk",
      );
      Debug.add("Registered: shortcut Installed");
    }

    if (!Directory("${WinUtils.getTabameAppDataFolder()}\\trktivity").existsSync()) {
      Directory("${WinUtils.getTabameAppDataFolder()}\\trktivity").createSync(recursive: true);
      Debug.add("Registered: Trktivity");
    }

    final String? savedLightThemeJson = pref.getString("lightTheme");
    final String? savedDarkThemeJson = pref.getString("darkTheme");
    final String? savedQuickMenuThemesJson = pref.getString("quickMenuDesignThemes");
    final ThemeColors? storedLightTheme =
        savedLightThemeJson == null ? null : ThemeColors.fromJson(savedLightThemeJson);
    final ThemeColors? storedDarkTheme = savedDarkThemeJson == null ? null : ThemeColors.fromJson(savedDarkThemeJson);

    if (savedQuickMenuThemesJson == null || savedQuickMenuThemesJson.trim().isEmpty) {
      globalSettings.hydrateQuickMenuDesignThemes();
      if (storedLightTheme != null || storedDarkTheme != null) {
        globalSettings.applyThemesForDesign(
          globalSettings.currentQuickMenuDesign,
          fallbackLightTheme: storedLightTheme,
          fallbackDarkTheme: storedDarkTheme,
        );
      } else {
        globalSettings.applyThemesForDesign(globalSettings.currentQuickMenuDesign);
      }
      await pref.setString("quickMenuDesignThemes", globalSettings.quickMenuDesignThemesToJson());
    } else {
      globalSettings.loadQuickMenuDesignThemesFromJson(savedQuickMenuThemesJson);
      globalSettings.applyThemesForDesign(
        globalSettings.currentQuickMenuDesign,
        fallbackLightTheme: storedLightTheme,
        fallbackDarkTheme: storedDarkTheme,
      );
    }

    await pref.setString("lightTheme", globalSettings.lightTheme.toJson());
    await pref.setString("darkTheme", globalSettings.darkTheme.toJson());
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    Debug.add("Registered: Theme");

    if (pref.getStringList("pinnedApps") == null) {
      final List<String> defaultPinnedApps = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") defaultPinnedApps.add(taskManagerPath);
      await pref.setStringList("pinnedApps", defaultPinnedApps);
      Debug.add("Registered: Pinned");
    }

    if (pref.getString("quickActions") == null) {
      final List<QuickActions> defaultQuickActions = <QuickActions>[
        QuickActions(name: "\u{1F50A} Volume", type: "Volume Slider", value: ""),
        QuickActions(name: "\u{1F509} Volume Level 3", type: "Set Volume", value: "3"),
        QuickActions(name: "\u{1F50A} Volume Level 100", type: "Set Volume", value: "100"),
        QuickActions(name: "\u{1F39A} Audio Devices", type: "Audio Output Devices", value: ""),
      ];
      await pref.setString("quickActions", jsonEncode(defaultQuickActions));
      Debug.add("Registered: quickActions");
    }

    final List<QuickActions> persistedQuickActions = getSavedMap<QuickActions>(QuickActions.fromJson, "quickActions");
    if (!persistedQuickActions.any((QuickActions action) => action.type == "Wallpapers")) {
      persistedQuickActions.add(QuickActions(name: "Wallpapers", type: "Wallpapers", value: ""));
      await pref.setString("quickActions", jsonEncode(persistedQuickActions));
      _quickActions = persistedQuickActions;
    }

    mediaControls = pref.getStringList("mediaControls") ??
        <String>["Spotify.exe", "chrome.exe", "firefox.exe", "brave.exe", "Music.UI.exe"];

    if (globalSettings.previewTheme) return;
    if (justLoad) return;
    loadQuickTimers();
    clearIconCache();

    if (globalSettings.page == TPage.quickmenu) {
      if (globalSettings.hideTaskbarOnStartup) {
        WinUtils.toggleTaskbar(visible: false);
        Debug.add("Registered: Taskbar");
      }
      if (globalSettings.isWindows10 && globalSettings.volumeOSDStyle != VolumeOSDStyle.normal) {
        WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
        WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
        Debug.add("Registered: Volume");
      }
      if (globalSettings.autoCheckForUpdates) checkForUpdates(autoInstall: false);
    }

    if (globalSettings.page == TPage.quickmenu) {
      if (reminders.any((Reminder reminder) => reminder.enabled)) Tasks().startReminders();
      Debug.add("Registered: Tasks");
    }

    shutDownScheduler();
  }

  static void clearIconCache() {
    final Directory iconCacheDir = Directory("${WinUtils.getTabameAppDataFolder()}/cache/icon_cache");
    if (!iconCacheDir.existsSync()) return;

    final DateTime oneWeekAgo = DateTime.now().subtract(const Duration(days: 7));
    for (final FileSystemEntity entity in iconCacheDir.listSync()) {
      if (entity is File) {
        final DateTime lastModified = entity.lastModifiedSync();
        if (lastModified.isBefore(oneWeekAgo)) {
          try {
            entity.deleteSync();
          } catch (e) {
            Debug.add("Failed to delete old icon cache file: $e");
          }
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // Group: Shutdown scheduling
  // Purpose: Schedule shutdown reminders and execute shutdown timers.
  // --------------------------------------------------------------------------

  static Timer? shutDownTimer;
  static Timer? shutDownWarningTimer;

  static void shutDownScheduler() {
    shutDownTimer?.cancel();
    shutDownWarningTimer?.cancel();

    bool isShutdownScheduled = pref.getBool("isShutDownScheduled") ?? false;
    final bool alwaysShutdownAtSavedTime = pref.getBool("alwaysShutDownAtTime") ?? false;
    final String savedShutdownTime = pref.getString("savedShutDownTime") ?? "";

    if (alwaysShutdownAtSavedTime && savedShutdownTime.isNotEmpty) {
      final List<String> timeParts = savedShutdownTime.split(":");
      if (timeParts.length == 2) {
        final int scheduledHour = int.tryParse(timeParts[0]) ?? -1;
        final int scheduledMinute = int.tryParse(timeParts[1]) ?? -1;
        if (scheduledHour != -1 && scheduledMinute != -1) {
          DateTime scheduledDateTime = DateTime.now();
          final int currentHour = scheduledDateTime.hour;
          scheduledDateTime = scheduledDateTime.subtract(Duration(
            hours: scheduledDateTime.hour,
            minutes: scheduledDateTime.minute,
            seconds: scheduledDateTime.second,
            milliseconds: scheduledDateTime.millisecond,
            microseconds: scheduledDateTime.microsecond,
          ));
          scheduledDateTime = scheduledDateTime.add(Duration(hours: scheduledHour, minutes: scheduledMinute));
          if (currentHour >= scheduledHour && DateTime.now().minute >= scheduledMinute) {
            scheduledDateTime = scheduledDateTime.add(const Duration(days: 1));
          }
          final int scheduledUnixTimestamp = scheduledDateTime.millisecondsSinceEpoch;
          pref.setBool("isShutDownScheduled", true);
          pref.setInt("shutDownUnix", scheduledUnixTimestamp);
          isShutdownScheduled = true;
        }
      }
    }

    if (!isShutdownScheduled) return;

    final int scheduledUnixTimestamp = pref.getInt("shutDownUnix") ?? 0;
    if (scheduledUnixTimestamp == 0) return;

    final int millisecondsUntilShutdown = scheduledUnixTimestamp - DateTime.now().millisecondsSinceEpoch;
    if (millisecondsUntilShutdown < 0) {
      pref.setBool("isShutDownScheduled", false);
      pref.setInt("shutDownUnix", 0);
      return;
    }

    final int warningDelayMs = millisecondsUntilShutdown - 60000;
    if (warningDelayMs > 0) {
      shutDownWarningTimer = Timer(Duration(milliseconds: warningDelayMs), () {
        WinUtils.msgBox("Shutting Down", "Your PC will close in 1 minute.\nYou can cancel it from the Quick Menu.",
            speak: "Shutting Down Alert");
      });
    } else if (millisecondsUntilShutdown > 0 && millisecondsUntilShutdown <= 60000) {
      WinUtils.msgBox("Shutting Down", "Your PC will close in 1 minute.\nYou can cancel it from the Quick Menu.",
          speak: "Shutting Down Alert");
    }

    shutDownTimer = Timer(Duration(milliseconds: millisecondsUntilShutdown), () async {
      if ((pref.getBool("isShutDownScheduled") ?? false) == false) return;
      pref.setBool("isShutDownScheduled", false);
      pref.setInt("shutDownUnix", 0);
      if (kReleaseMode) {
        WinUtils.runPowerShell(<String>["shutdown /s /t 0"]);
      } else {
        WinUtils.msgBox("Shutting Down", "Shut Down Timer Kicked in.");
      }
    });
  }

  // --------------------------------------------------------------------------
  // Group: Settings persistence and serialization helpers
  // Purpose: Save values and decode persisted lists used across the app.
  // --------------------------------------------------------------------------

  static Future<void> updateSettings(String key, dynamic value) async {
    if (value is bool) {
      await pref.setBool(key, value);
    } else if (value is int) {
      await pref.setInt(key, value);
    } else if (value is String) {
      await pref.setString(key, value);
    } else if (value is List<String>) {
      await pref.setStringList(key, value);
    } else if (value is List<dynamic>) {
      await pref.setString(key, jsonEncode(value));
    } else if (value is Map) {
      await pref.setString(key, jsonEncode(value));
    } else if (value is double) {
      await pref.setDouble(key, value);
    } else {
      throw ("No associated type $value");
    }
    pref = await SaveSettings.getInstance();
  }

  static Future<void> saveActiveQuickMenuThemes({bool notify = false}) async {
    globalSettings.saveActiveThemesToCurrentDesign();
    await pref.setString("quickMenuDesignThemes", globalSettings.quickMenuDesignThemesToJson());
    await pref.setString("lightTheme", globalSettings.lightTheme.toJson());
    await pref.setString("darkTheme", globalSettings.darkTheme.toJson());
    if (notify) Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
  }

  static Future<void> switchQuickMenuDesign(QuickMenuDesigns design, {bool notify = true}) async {
    globalSettings.saveActiveThemesToCurrentDesign();
    globalSettings.quickMenuDesign = design.index;
    globalSettings.applyThemesForDesign(design);
    QuickMenuFunctions.randomizeBackdrop();

    await pref.setInt("quickMenuDesign", design.index);
    await saveActiveQuickMenuThemes(notify: notify);

    for (final QuickMenuTriggers quickMenuListener in QuickMenuFunctions.listeners) {
      quickMenuListener.refreshQuickMenu();
    }
  }

  /// @deprecated Use [getSavedMap] instead.
  static List<T> getSavedMap2<T>(T Function(String json) fromJson, String key, {List<T>? def}) {
    final String savedJson = pref.getString(key) ?? "";
    if (savedJson.isEmpty) return def ?? <T>[];

    final List<dynamic> decodedItems = jsonDecode(savedJson);
    final List<T> mappedItems = <T>[];
    for (final String serializedItem in decodedItems) {
      mappedItems.add(fromJson(serializedItem));
    }
    return mappedItems;
  }

  static List<T> getSavedMap<T>(T Function(String json) fromJson, String key, {List<T>? def}) {
    final String savedJson = pref.getString(key) ?? '';
    if (savedJson.isEmpty) return def ?? <T>[];

    try {
      return (jsonDecode(savedJson) as List<dynamic>).cast<String>().map(fromJson).toList();
    } catch (e) {
      pref.setString(key, "");
      return def ?? <T>[];
    }
  }

  // --------------------------------------------------------------------------
  // Group: Window title and icon rewrites
  // Purpose: Keep app title rewrite rules and icon override lookups together.
  // --------------------------------------------------------------------------

  static Map<String, String> _taskBarRewrites = <String, String>{};
  static set taskBarRewrites(Map<String, String> value) => _taskBarRewrites = value;
  static Map<String, String> get taskBarRewrites {
    if (_taskBarRewrites.isNotEmpty) return _taskBarRewrites;
    final String rewriteJson = pref.getString("taskBarRewrites") ?? "";
    if (rewriteJson == "") {
      _taskBarRewrites = <String, String>{r"DevTools.*?([^\s\/]+\.\w+)\/.*?$": "\u{26A0} DevTools: \$1 "};
    } else {
      _taskBarRewrites = Map<String, String>.from(json.decode(rewriteJson));
    }
    return _taskBarRewrites;
  }

  static Map<String, String> _iconsRewrite = <String, String>{};
  static set iconsRewrite(Map<String, String> value) => _iconsRewrite = value;
  static Map<String, String> get iconsRewrite {
    if (_iconsRewrite.isNotEmpty) return _iconsRewrite;
    final String rewriteJson = pref.getString("iconsRewrite") ?? "";
    if (rewriteJson == "") {
      _iconsRewrite = <String, String>{};
    } else {
      _iconsRewrite = Map<String, String>.from(json.decode(rewriteJson));
    }
    return _iconsRewrite;
  }

  static Map<String, List<String>> _taskbarBadges = <String, List<String>>{};
  static set taskbarBadges(Map<String, List<String>> value) => _taskbarBadges = value;
  static Map<String, List<String>> get taskbarBadges {
    if (_taskbarBadges.isNotEmpty) return _taskbarBadges;
    final String badgeJson = pref.getString("taskbarBadges") ?? "";
    if (badgeJson == "") {
      _taskbarBadges = <String, List<String>>{
        "discord.exe": <String>["Discord", "No "],
        "whatsapp.exe": <String>["WhatsApp", "No "],
        "telegram.exe": <String>["Telegram", "No "]
      };
    } else {
      final dynamic decoded = json.decode(badgeJson);
      if (decoded is Map) {
        decoded.forEach((dynamic key, dynamic value) {
          if (value is String) {
            _taskbarBadges[key.toString()] = <String>[value, ""];
          } else if (value is List) {
            _taskbarBadges[key.toString()] = List<String>.from(value);
          }
        });
      }
    }
    return _taskbarBadges;
  }

  static Map<String, String> titleIconRewrite = <String, String>{
    "DevTools": "resources/devtools.png",
  };
  static String getIconRewriteByName(Window window) {
    for (final String rewriteTitle in titleIconRewrite.keys) {
      if (window.title.contains(rewriteTitle)) return titleIconRewrite[rewriteTitle] ?? "";
    }
    return "";
  }

  static String getIconRewrite(String exePath) {
    final Map<String, String> currentIconsRewrite = iconsRewrite;
    final String matchedAppName = currentIconsRewrite.keys.firstWhere(
      (String rewriteKey) => exePath.toLowerCase().contains(rewriteKey.toLowerCase()),
      orElse: () => "",
    );
    return currentIconsRewrite[matchedAppName] ?? "";
  }

  // --------------------------------------------------------------------------
  // Group: Quick launch and command preferences
  // Purpose: Store quick-run shortcuts, memos, CLI bookmarks, and top-bar order.
  // --------------------------------------------------------------------------

  List<List<String>> _runShortcuts = <List<String>>[];

  set runShortcuts(List<List<String>> items) {
    _runShortcuts = items;
    updateSettings("runShortcuts", jsonEncode(items));
  }

  List<List<String>> get runShortcuts {
    if (_runShortcuts.isNotEmpty) return _runShortcuts;

    final String savedShortcutsJson = pref.getString("runShortcuts") ?? "";
    if (savedShortcutsJson.isEmpty) {
      return <List<String>>[
        <String>["g", "https://github.com/search?q={params}"],
      ];
    }

    final List<dynamic> decodedShortcuts = jsonDecode(savedShortcutsJson);
    _runShortcuts.clear();
    for (final List<dynamic> shortcutEntry in decodedShortcuts) {
      _runShortcuts.add(<String>[shortcutEntry[0], shortcutEntry[1]]);
    }
    return _runShortcuts;
  }

  List<List<String>> _runMemos = <List<String>>[];

  set runMemos(List<List<String>> items) {
    _runMemos = items;
    updateSettings("runMemos", jsonEncode(items));
  }

  List<List<String>> get runMemos {
    if (_runMemos.isNotEmpty) return _runMemos;

    final String savedMemosJson = pref.getString("runMemos") ?? "";
    if (savedMemosJson.isEmpty) return _runMemos;

    final List<dynamic> decodedMemos = jsonDecode(savedMemosJson);
    _runMemos.clear();
    for (final List<dynamic> memoEntry in decodedMemos) {
      _runMemos.add(<String>[memoEntry[0], memoEntry[1]]);
    }
    return _runMemos;
  }

  List<CliBookCategory> _cliBook = <CliBookCategory>[];

  set cliBook(List<CliBookCategory> items) {
    _cliBook = items;
    updateSettings("cliBook", jsonEncode(items));
  }

  List<CliBookCategory> get cliBook {
    if (_cliBook.isNotEmpty) return _cliBook;

    final String savedCliBookJson = pref.getString("cliBook") ?? "";
    if (savedCliBookJson.isEmpty) return _cliBook;

    final List<dynamic> decodedCliBookEntries = jsonDecode(savedCliBookJson);
    if (decodedCliBookEntries.isEmpty) return _cliBook;

    _cliBook.clear();

    final dynamic firstEntry = decodedCliBookEntries.first;
    if (firstEntry is Map<String, dynamic> && firstEntry.containsKey('items')) {
      // New format
      for (final dynamic entry in decodedCliBookEntries) {
        _cliBook.add(CliBookCategory.fromJson(entry as Map<String, dynamic>));
      }
    } else {
      // Old format (Migration)
      final List<CliBookItem> items = <CliBookItem>[];
      for (final dynamic entry in decodedCliBookEntries) {
        items.add(CliBookItem.fromJson(entry as Map<String, dynamic>));
      }
      _cliBook.add(CliBookCategory(name: "General", items: items));
    }

    return _cliBook;
  }

  List<List<String>> _runKeys = <List<String>>[];

  set runKeys(List<List<String>> items) {
    _runKeys = items;
    updateSettings("runKeys", jsonEncode(items));
  }

  List<List<String>> get runKeys {
    if (_runKeys.isNotEmpty) return _runKeys;

    final String savedKeyBindingsJson = pref.getString("runKeys") ?? "";
    if (savedKeyBindingsJson.isEmpty) {
      return <List<String>>[
        <String>["m", "{MEDIA_NEXT_TRACK}"],
        <String>["p", "{MEDIA_PREV_TRACK}"],
      ];
    }

    final List<dynamic> decodedKeyBindings = jsonDecode(savedKeyBindingsJson);
    _runKeys.clear();
    for (final List<dynamic> keyBindingEntry in decodedKeyBindings) {
      _runKeys.add(<String>[keyBindingEntry[0], keyBindingEntry[1]]);
    }
    return _runKeys;
  }

  List<String> get topBarWidgets {
    final List<String> defaultWidgets = quickActionsMap.keys.toList()..add("Deactivated:");
    final List<String> configuredWidgets = pref.getStringList("topBarWidgets") ?? defaultWidgets;
    final Iterable<String> missingWidgets =
        defaultWidgets.where((String widgetName) => !configuredWidgets.contains(widgetName));
    final int deactivatedMarkerIndex =
        configuredWidgets.indexWhere((String widgetName) => widgetName == "Deactivated:");
    configuredWidgets.insertAll(deactivatedMarkerIndex, missingWidgets);
    pref.setStringList("topBarWidgets", configuredWidgets);
    return configuredWidgets;
  }

  static List<String> get pinnedApps => pref.getStringList("pinnedApps") ?? <String>[];

  static double? _quickMenuWidth;
  static set quickMenuWidth(double val) => _quickMenuWidth = val;
  static double get quickMenuWidth {
    _quickMenuWidth ??= pref.getDouble("quickMenuWidth") ?? 650.0;
    return _quickMenuWidth!;
  }

  static double? _launcherSizeWidth;
  static set launcherSizeWidth(double val) => _launcherSizeWidth = val;
  static double get launcherSizeWidth {
    _launcherSizeWidth ??= pref.getDouble("launcherSizeWidth") ?? 650.0;
    return _launcherSizeWidth!;
  }

  List<BookmarkGroup> get bookmarks => getSavedMap<BookmarkGroup>(BookmarkGroup.fromJson, "projects");

  // --------------------------------------------------------------------------
  // Group: Cached settings collections
  // Purpose: Keep all persisted list caches and collection accessors in one place.
  // --------------------------------------------------------------------------

  static List<Reminder>? _reminders;
  static set reminders(List<Reminder> list) => _reminders = list;
  static List<Reminder> get reminders =>
      _reminders == null ? _reminders = getSavedMap<Reminder>(Reminder.fromJson, "reminders") : _reminders!;

  static List<WallpaperSchedule>? _wallpaperSchedules;
  static set wallpaperSchedules(List<WallpaperSchedule> list) => _wallpaperSchedules = list;
  static List<WallpaperSchedule> get wallpaperSchedules => _wallpaperSchedules == null
      ? _wallpaperSchedules = getSavedMap<WallpaperSchedule>(WallpaperSchedule.fromJson, "wallpaperSchedules")
      : _wallpaperSchedules!;

  static List<Hotkeys> _remap = <Hotkeys>[];
  static set remap(List<Hotkeys> list) => _remap = list;
  static List<Hotkeys> get remap => _remap.isEmpty ? _remap = getSavedMap<Hotkeys>(Hotkeys.fromJson, "remap") : _remap;

  static List<ScreenDrawHotkeyBinding> _screenDrawHotkeys = <ScreenDrawHotkeyBinding>[];
  static set screenDrawHotkeys(List<ScreenDrawHotkeyBinding> list) => _screenDrawHotkeys = list;
  static List<ScreenDrawHotkeyBinding> get screenDrawHotkeys {
    if (_screenDrawHotkeys.isEmpty) {
      _screenDrawHotkeys = ScreenDrawHotkeyBinding.mergeWithDefaults(
        getSavedMap<ScreenDrawHotkeyBinding>(ScreenDrawHotkeyBinding.fromJson, "screenDrawHotkeys"),
      );
    }
    return _screenDrawHotkeys;
  }

  static List<RunAPI> _runApi = <RunAPI>[];
  static set runApi(List<RunAPI> list) => _runApi = list;
  static List<RunAPI> get runApi =>
      _runApi.isEmpty ? _runApi = getSavedMap<RunAPI>(RunAPI.fromJson, "runApi") : _runApi;

  static List<DefaultVolume> _defaultVolume = <DefaultVolume>[];
  static set defaultVolume(List<DefaultVolume> list) => _defaultVolume = list;
  static List<DefaultVolume> get defaultVolume => _defaultVolume.isEmpty
      ? _defaultVolume = getSavedMap<DefaultVolume>(DefaultVolume.fromJson, "defaultVolume")
      : _defaultVolume;

  static List<SearchFolder> _searchFolders = <SearchFolder>[];
  static set searchFolders(List<SearchFolder> list) => _searchFolders = list;

  static List<SearchFolder> get searchFolders {
    if (_searchFolders.isEmpty) {
      _searchFolders = getSavedMap<SearchFolder>(SearchFolder.fromJson, "searchFolders");
      if (_searchFolders.isEmpty) {
        return <SearchFolder>[
          SearchFolder(
            path: "${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
            includeFolders: false,
            maxDepth: 3,
          ),
          SearchFolder(
            path: "${Platform.environment['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
            includeFolders: false,
            maxDepth: 3,
          ),
          SearchFolder(
            path: "${Platform.environment['ProgramFiles']}\\WindowsApps",
            includeFolders: false,
            allowedExtensions: <String>[".exe", ".lnk", ".msi", ".bat"],
            maxDepth: 3,
          ),
        ];
      }
      return _searchFolders;
    } else {
      return _searchFolders;
    }
  }

  static List<SearchHistory> _searchHistory = <SearchHistory>[];
  static set searchHistory(List<SearchHistory> list) {
    _searchHistory = list;
    Boxes.pref.setString("searchHistory", jsonEncode(list));
  }

  static List<SearchHistory> get searchHistory {
    if (_searchHistory.isNotEmpty) return _searchHistory;

    final String savedHistoryJson = pref.getString("searchHistory") ?? '';
    if (savedHistoryJson.isEmpty) return <SearchHistory>[];

    try {
      return (jsonDecode(savedHistoryJson) as List<dynamic>)
          .map((dynamic historyEntry) => SearchHistory.fromMap(historyEntry as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return <SearchHistory>[];
    }
  }

  static List<QuickActions> _quickActions = <QuickActions>[];
  static set quickActions(List<QuickActions> list) => _quickActions = list;
  static List<QuickActions> get quickActions => _quickActions.isEmpty
      ? _quickActions = getSavedMap<QuickActions>(QuickActions.fromJson, "quickActions")
      : _quickActions;

  static List<AppAudioControl> _appAudioControls = <AppAudioControl>[];
  static set appAudioControls(List<AppAudioControl> list) {
    _appAudioControls = list;
    Boxes.updateSettings(
      "appAudioControls",
      jsonEncode(list.map((AppAudioControl control) => control.toMap()).toList()),
    );
  }

  static List<AppAudioControl> get appAudioControls {
    if (_appAudioControls.isNotEmpty) return _appAudioControls;

    final String savedAudioControlsJson = pref.getString("appAudioControls") ?? '';
    if (savedAudioControlsJson.isNotEmpty) {
      _appAudioControls = (jsonDecode(savedAudioControlsJson) as List<dynamic>)
          .map((dynamic controlEntry) => AppAudioControl.fromMap(controlEntry as Map<String, dynamic>))
          .toList();
    }
    return _appAudioControls;
  }

  static List<AppCategory> _appCategories = <AppCategory>[];
  static set appCategories(List<AppCategory> list) {
    _appCategories = list;
    Boxes.updateSettings(
      "appCategories",
      jsonEncode(list.map((AppCategory category) => category.toMap()).toList()),
    );
  }

  static List<AppCategory> get appCategories {
    if (_appCategories.isNotEmpty) return _appCategories;

    final String savedCategoriesJson = pref.getString("appCategories") ?? '';
    if (savedCategoriesJson.isNotEmpty) {
      _appCategories = (jsonDecode(savedCategoriesJson) as List<dynamic>)
          .map((dynamic categoryEntry) => AppCategory.fromMap(categoryEntry as Map<String, dynamic>))
          .toList();
    } else {
      _appCategories.add(AppCategory(
        name: "Games",
        items: <AppItem>[],
        folderPath: "${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Steam",
      ));
      _appCategories.add(AppCategory(
        name: "Desktop",
        items: <AppItem>[],
        folderPath: "${Platform.environment['USERPROFILE']}\\Desktop",
      ));
    }
    return _appCategories;
  }

  static List<QuickGrid> _quickGrids = <QuickGrid>[];
  static set quickGrids(List<QuickGrid> list) {
    _quickGrids = list;
    Boxes.updateSettings(
      'QuickGrids',
      jsonEncode(list.map((QuickGrid quickGrid) => quickGrid.toMap()).toList()),
    );
  }

  static List<QuickGrid> get quickGrids {
    if (_quickGrids.isNotEmpty) return _quickGrids;

    final String savedQuickGridsJson = pref.getString('QuickGrids') ?? '';
    if (savedQuickGridsJson.isNotEmpty) {
      try {
        _quickGrids = (jsonDecode(savedQuickGridsJson) as List<dynamic>)
            .map((dynamic quickGridEntry) => QuickGrid.fromMap(quickGridEntry as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _quickGrids = <QuickGrid>[];
      }
    } else {
      return <QuickGrid>[
        QuickGrid(
          id: "1776274379994",
          name: "DevGrid",
          layoutType: QuickGridLayoutType.freestyle,
          gap: 0,
          zones: <QuickGridRect>[
            QuickGridRect(left: 0.0, top: 0.0, right: 0.3279483037156705, bottom: 0.5),
            QuickGridRect(left: 0.0, top: 0.5, right: 0.3279483037156705, bottom: 1.0),
            QuickGridRect(left: 0.3279483037156705, top: 0.0, right: 0.7835218093699515, bottom: 0.5),
            QuickGridRect(left: 0.7835218093699515, top: 0.0, right: 1.0, bottom: 1.0),
            QuickGridRect(left: 0.3279483037156705, top: 0.5, right: 0.6284329563812602, bottom: 1.0),
            QuickGridRect(left: 0.6284329563812602, top: 0.5, right: 0.7835218093699515, bottom: 1.0),
          ],
        ),
      ];
    }
    return _quickGrids;
  }

  static List<Workspace> _workspaces = <Workspace>[];
  static set workspaces(List<Workspace> list) {
    _workspaces = list;
    Boxes.updateSettings(
      'Workspaces',
      jsonEncode(list.map((Workspace workspace) => workspace.toMap()).toList()),
    );
  }

  static List<Workspace> get workspaces {
    if (_workspaces.isNotEmpty) return _workspaces;

    final String savedWorkspacesJson = pref.getString('Workspaces') ?? '';
    if (savedWorkspacesJson.isNotEmpty) {
      try {
        _workspaces = (jsonDecode(savedWorkspacesJson) as List<dynamic>)
            .map((dynamic workspaceEntry) => Workspace.fromMap(workspaceEntry as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _workspaces = <Workspace>[];
      }
    }
    return _workspaces;
  }

  // --------------------------------------------------------------------------
  // Group: Quick timer runtime management
  // Purpose: Create, restore, and execute active quick timers.
  // --------------------------------------------------------------------------

  static final List<QuickTimer> quickTimers = <QuickTimer>[];

  void addQuickTimer(String name, int minutes, int type) {
    final QuickTimer quickTimer = QuickTimer();
    quickTimer.name = name;
    quickTimer.endTime = DateTime.now().add(Duration(minutes: minutes));
    quickTimer.type = type;
    _startQuickTimer(quickTimer);
    quickTimers.add(quickTimer);
    saveQuickTimers();
  }

  static void _startQuickTimer(QuickTimer quickTimer) {
    final int secondsRemaining = quickTimer.endTime.difference(DateTime.now()).inSeconds;
    if (secondsRemaining <= 0) return;

    quickTimer.timer = Timer(Duration(seconds: secondsRemaining), () {
      if (quickTimer.type == 0) {
        WinUtils.textToSpeech(quickTimer.name, repeat: -1);
      } else if (quickTimer.type == 1) {
        WinUtils.msgBox("Tabame Quick Timer", quickTimer.name, speak: "${quickTimer.name}");
      } else if (quickTimer.type == 2) {
        WinUtils.showWindowsNotification(
          title: "Tabame Quick Timer",
          body: "Timer Expired: ${quickTimer.name}",
          onClick: () {},
        );
      }
      quickTimers.remove(quickTimer);
      saveQuickTimers();
    });
  }

  static void saveQuickTimers() {
    final List<Map<String, dynamic>> serializedQuickTimers =
        quickTimers.map((QuickTimer quickTimer) => quickTimer.toMap()).toList();
    Boxes.pref.setString("quickTimers", jsonEncode(serializedQuickTimers));
  }

  static void loadQuickTimers() {
    final String? savedQuickTimersJson = Boxes.pref.getString("quickTimers");
    if (savedQuickTimersJson == null || savedQuickTimersJson.isEmpty) return;

    try {
      final List<dynamic> decodedQuickTimers = jsonDecode(savedQuickTimersJson);
      for (final dynamic quickTimerEntry in decodedQuickTimers) {
        final QuickTimer quickTimer = QuickTimer.fromMap(quickTimerEntry as Map<String, dynamic>);
        if (quickTimer.endTime.isAfter(DateTime.now())) {
          _startQuickTimer(quickTimer);
          quickTimers.add(quickTimer);
        }
      }
    } catch (e) {
      Debug.add("Error loading quick timers: $e");
    }
  }

  // --------------------------------------------------------------------------
  // Group: Quick timer history
  // Purpose: Persist and restore the quick timer presets used most recently.
  // --------------------------------------------------------------------------

  static final List<SavedQuickTimers> lastQuickTimers = <SavedQuickTimers>[];

  void loadLatestQuickTimers() {
    lastQuickTimers.clear();

    final String? savedQuickTimerHistoryJson = Boxes.pref.getString("lastQuickTimers");
    if (savedQuickTimerHistoryJson == null) return;

    final List<dynamic> decodedTimerHistory = jsonDecode(savedQuickTimerHistoryJson);
    if (decodedTimerHistory.isEmpty) return;

    for (final Map<dynamic, dynamic> timerHistoryEntry in decodedTimerHistory) {
      final SavedQuickTimers savedQuickTimer = SavedQuickTimers();
      savedQuickTimer.name = timerHistoryEntry["name"];
      savedQuickTimer.minutes = timerHistoryEntry["minutes"];
      savedQuickTimer.type = timerHistoryEntry["type"];
      lastQuickTimers.add(savedQuickTimer);
    }
  }

  void saveLatestQuickTimers() {
    final List<Map<String, dynamic>> serializedTimerHistory = <Map<String, dynamic>>[];
    for (final SavedQuickTimers savedQuickTimer in lastQuickTimers) {
      serializedTimerHistory.add(<String, dynamic>{
        "name": savedQuickTimer.name,
        "minutes": savedQuickTimer.minutes,
        "type": savedQuickTimer.type,
      });
    }
    Boxes.pref.setString("lastQuickTimers", jsonEncode(serializedTimerHistory));
  }

  // --------------------------------------------------------------------------
  // Group: Application update workflow
  // Purpose: Check GitHub releases and install downloaded updates.
  // --------------------------------------------------------------------------

  static String? updateDownloadLink;
  static Future<int> checkForUpdates({bool autoInstall = false}) async {
    try {
      final http.Response githubResponse =
          await http.get(Uri.parse("https://api.github.com/repos/far-se/tabame/releases"));
      if (githubResponse.statusCode != 200) return -1;
      final List<dynamic> releasePayload = jsonDecode(githubResponse.body);
      if (releasePayload.isEmpty) return -1;

      final Map<String, dynamic> latestRelease = releasePayload[0];
      if (latestRelease["tag_name"] == Globals.version) return 0;

      String assetDownloadLink = "";
      for (final Map<String, dynamic> releaseAsset in latestRelease["assets"]) {
        if (!releaseAsset["name"].endsWith("zip")) continue;
        if (releaseAsset.containsKey("browser_download_url")) {
          assetDownloadLink = releaseAsset["browser_download_url"];
          break;
        }
      }
      if (assetDownloadLink == "") return -1;

      updateDownloadLink = assetDownloadLink;
      globalSettings.newVersion = latestRelease["tag_name"];
      pref.setString("newVersion", globalSettings.newVersion);

      if (autoInstall) {
        unawaited(installUpdate(assetDownloadLink, globalSettings.newVersion));
      }
      Debug.add("Updates: Checked");
      return 1;
    } catch (e) {
      WinUtils.msgBox("Tabame", "Update Error: $e");
      Debug.error("Updates Error: $e");
      return -1;
    }
  }

  static Future<void> installUpdate(String downloadLink, String tagName) async {
    try {
      final String updateArchivePath = "${WinUtils.getTempFolder()}\\tabame_$tagName.zip";
      await WinUtils.downloadFile(downloadLink, updateArchivePath, () {
        final String installDirectory = File(Platform.resolvedExecutable).parent.path;
        WinUtils.open(
          'powershell.exe',
          arguments: '-Command "Start-Sleep -Seconds 1; '
              'Expand-Archive '
              '-LiteralPath \\"$updateArchivePath\\" '
              '-DestinationPath \\"$installDirectory\\" -Force; '
              'Invoke-Item \\"$installDirectory\\tabame.exe\\";"',
        );
        if (kReleaseMode) {
          Timer(const Duration(milliseconds: 100), () {
            WinUtils.closeAllTabameExProcesses();
            exit(0);
          });
        }
      });
    } catch (e) {
      WinUtils.msgBox("Tabame", "Update Error: $e");
      Debug.add("Updates Error: $e");
    }
  }
}
