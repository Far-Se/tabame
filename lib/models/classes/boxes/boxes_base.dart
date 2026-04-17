import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:win32/win32.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../../globals.dart';
import '../../settings.dart';
import '../../util/quick_action_list.dart';
import '../../win32/win32.dart';
import '../../win32/window.dart';
import '../hotkeys.dart';
import '../save_settings.dart';
import '../saved_maps.dart';

// Import sub-boxes
import 'quick_menu_box.dart';
import 'quick_timers_box.dart';
import 'tasks_box.dart';
import 'search_folder_box.dart';
import 'search_history.dart';
import 'quick_actions_box.dart';
import '../app_items.dart';

// --------------------------------------------------------------------------
// Boxes
// --------------------------------------------------------------------------

class Boxes {
  static late SaveSettings pref;
  static List<String> mediaControls = <String>[];

  Boxes();

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
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setBool("showMediaControlForApp", true);
      await pref.setBool("showTrayBar", true);
      await pref.setBool("showWeather", true);
      await pref.setBool("showPowerShell", false);
      await pref.setBool("showSystemUsage", false);
      await pref.setBool("runAsAdministrator", false);
      await pref.setBool("hideTabameOnUnfocus", true);
      await pref.setString("wallpapersFolder", "");

      final List<Reminder> demoReminders = <Reminder>[
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
      await pref.setString("reminders", jsonEncode(demoReminders));
      Debug.add("Registered: setDefault Settings");
    }

    // Fetch all settings
    globalSettings
      ..quickMenuDesign = pref.getInt("quickMenuDesign") ?? globalSettings.quickMenuDesign
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..volumeOSDStyle = VolumeOSDStyle.values[pref.getInt("volumeOSDStyle") ?? 0]
      ..language = pref.getString("language") ?? Platform.localeName.substring(0, 2)
      ..views = pref.getBool("views") ?? globalSettings.views
      ..audio = pref.getStringList("audio") ?? globalSettings.audio
      ..weather = pref.getStringList("weather") ?? globalSettings.weather
      ..autoUpdate = pref.getBool("autoUpdate") ?? globalSettings.autoUpdate
      ..customLogo = pref.getString("customLogo") ?? globalSettings.customLogo
      ..wallpapersFolder = pref.getString("wallpapersFolder") ?? globalSettings.wallpapersFolder
      ..showTrayBar = pref.getBool("showTrayBar") ?? globalSettings.showTrayBar
      ..showWeather = pref.getBool("showWeather") ?? globalSettings.showWeather
      ..customSpash = pref.getString("customSpash") ?? globalSettings.customSpash
      ..volumeSetBack = pref.getBool("volumeSetBack") ?? globalSettings.volumeSetBack
      ..lastChangelog = pref.getString("lastChangelog") ?? globalSettings.lastChangelog
      ..showPowerShell = pref.getBool("showPowerShell") ?? globalSettings.showPowerShell
      ..keepPopupsOpen = pref.getBool("keepPopupsOpen") ?? globalSettings.keepPopupsOpen
      ..showSystemUsage = pref.getBool("showSystemUsage") ?? globalSettings.showSystemUsage
      ..themeScheduleMin = pref.getInt("themeScheduleMin") ?? globalSettings.themeScheduleMin
      ..themeScheduleMax = pref.getInt("themeScheduleMax") ?? globalSettings.themeScheduleMax
      ..trktivityEnabled = pref.getBool("trktivityEnabled") ?? globalSettings.trktivityEnabled
      ..runAsAdministrator = pref.getBool("runAsAdministrator") ?? globalSettings.runAsAdministrator
      ..hideTabameOnUnfocus = pref.getBool("hideTabameOnUnfocus") ?? globalSettings.hideTabameOnUnfocus
      ..hideTaskbarOnStartup = pref.getBool("hideTaskbarOnStartup") ?? globalSettings.hideTaskbarOnStartup
      ..persistentReminders = pref.getStringList("persistentReminders") ?? globalSettings.persistentReminders
      ..showMediaControlForApp = pref.getBool("showMediaControlForApp") ?? globalSettings.showMediaControlForApp
      ..trktivitySaveAllTitles = pref.getBool("trktivitySaveAllTitles") ?? globalSettings.trktivitySaveAllTitles
      ..pauseSpotifyWhenPlaying = pref.getBool("pauseSpotifyWhenPlaying") ?? globalSettings.pauseSpotifyWhenPlaying
      ..pauseSpotifyWhenNewSound = pref.getBool("pauseSpotifyWhenNewSound") ?? globalSettings.pauseSpotifyWhenNewSound
      ..showQuickMenuAtTaskbarLevel =
          pref.getBool("showQuickMenuAtTaskbarLevel") ?? globalSettings.showQuickMenuAtTaskbarLevel
      ..usePowerShellAsToastNotification =
          pref.getBool("usePowerShellAsToastNotification") ?? globalSettings.usePowerShellAsToastNotification
      ..themeType = ThemeType.values[pref.getInt("themeType") ?? 0]; // must be set after schedule

    Debug.add("Registered: Fetched All");

    if (pref.getBool("DEBUGGING") ?? false == true) {
      Debug.register(clean: false);
      Debug.methodDebug(clean: false);
    }

    // Just installed
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

    // Trktivity folder
    if (!Directory("${WinUtils.getTabameAppDataFolder()}\\trktivity").existsSync()) {
      Directory("${WinUtils.getTabameAppDataFolder()}\\trktivity").createSync(recursive: true);
      Debug.add("Registered: Trktivity");
    }

    // Theme
    final String? lightTheme = pref.getString("lightTheme");
    final String? darkTheme = pref.getString("darkTheme");
    final String? quickMenuDesignThemes = pref.getString("quickMenuDesignThemes");
    final ThemeColors? storedLightTheme = lightTheme == null ? null : ThemeColors.fromJson(lightTheme);
    final ThemeColors? storedDarkTheme = darkTheme == null ? null : ThemeColors.fromJson(darkTheme);

    if (quickMenuDesignThemes == null || quickMenuDesignThemes.trim().isEmpty) {
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
      globalSettings.loadQuickMenuDesignThemesFromJson(quickMenuDesignThemes);
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

    // Pinned apps
    if (pref.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await pref.setStringList("pinnedApps", pinnedApps2);
      Debug.add("Registered: Pinned");
    }

    // PowerShell scripts
    if (pref.getString("powerShellScripts") == null) {
      final List<String> powerShellScripts = <String>[
        PowerShellScript(
          name: "🏠Show IP",
          command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content",
          showTerminal: true,
        ).toJson(),
      ];
      await pref.setString("powerShellScripts", jsonEncode(powerShellScripts));
      Debug.add("Registered: PowerShell");
    }

    // Quick actions
    if (pref.getString("quickActions") == null) {
      final List<QuickActions> quickActionList = <QuickActions>[
        QuickActions(name: "🎧 Spotify", type: "Spotify Controls", value: ""),
        QuickActions(name: "🔊 Volume", type: "Volume Slider", value: ""),
        QuickActions(name: "🔉 Volume Level 3", type: "Set Volume", value: "3"),
        QuickActions(name: "🔊 Volume Level 100", type: "Set Volume", value: "100"),
        QuickActions(name: "🎚 Audio Devices", type: "Audio Output Devices", value: ""),
      ];
      await pref.setString("quickActions", jsonEncode(quickActionList));
      Debug.add("Registered: quickActions");
    }

    final List<QuickActions> savedQuickActions = getSavedMap<QuickActions>(QuickActions.fromJson, "quickActions");
    if (!savedQuickActions.any((QuickActions action) => action.type == "Wallpapers")) {
      savedQuickActions.add(QuickActions(name: "Wallpapers", type: "Wallpapers", value: ""));
      await pref.setString("quickActions", jsonEncode(savedQuickActions));
      _quickActions = savedQuickActions;
    }

    // Media controls
    mediaControls =
        pref.getStringList("mediaControls") ?? <String>["Spotify.exe", "chrome.exe", "firefox.exe", "Music.UI.exe"];

    // Startup
    if (globalSettings.previewTheme) return;
    if (justLoad) return;
    loadQuickTimers();

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
      if (globalSettings.autoUpdate) checkForUpdates(autoInstall: true);
    }

    if (globalSettings.page == TPage.quickmenu) {
      if (reminders.any((Reminder element) => element.enabled)) Tasks().startReminders();
      Debug.add("Registered: Tasks");
    }

    shutDownScheduler();
  }

  // --------------------------------------------------------------------------
  // Shutdown scheduler
  // --------------------------------------------------------------------------

  static Timer? shutDownTimer;
  static Timer? shutDownWarningTimer;

  static void shutDownScheduler() {
    shutDownTimer?.cancel();
    shutDownWarningTimer?.cancel();

    bool isScheduled = pref.getBool("isShutDownScheduled") ?? false;
    final bool alwaysAtTime = pref.getBool("alwaysShutDownAtTime") ?? false;
    final String savedTime = pref.getString("savedShutDownTime") ?? "";

    if (alwaysAtTime && savedTime.isNotEmpty) {
      final List<String> parts = savedTime.split(":");
      if (parts.length == 2) {
        final int hour = int.tryParse(parts[0]) ?? -1;
        final int minute = int.tryParse(parts[1]) ?? -1;
        if (hour != -1 && minute != -1) {
          DateTime now = DateTime.now();
          final int nowHour = now.hour;
          now = now.subtract(Duration(
              hours: now.hour,
              minutes: now.minute,
              seconds: now.second,
              milliseconds: now.millisecond,
              microseconds: now.microsecond));
          now = now.add(Duration(hours: hour, minutes: minute));
          if (nowHour >= hour && DateTime.now().minute >= minute) {
            now = now.add(const Duration(days: 1));
          }
          final int unix = now.millisecondsSinceEpoch;
          pref.setBool("isShutDownScheduled", true);
          pref.setInt("shutDownUnix", unix);
          isScheduled = true;
        }
      }
    }

    if (isScheduled) {
      final int unix = pref.getInt("shutDownUnix") ?? 0;
      if (unix == 0) return;
      final int diff = unix - DateTime.now().millisecondsSinceEpoch;
      if (diff < 0) {
        pref.setBool("isShutDownScheduled", false);
        pref.setInt("shutDownUnix", 0);
        return;
      }

      // Warning timer (1 minute before)
      final int warningDiff = diff - 60000;
      if (warningDiff > 0) {
        shutDownWarningTimer = Timer(Duration(milliseconds: warningDiff), () {
          WinUtils.msgBox("Shutting Down", "Your PC will close in 1 minute.\nYou can cancel it from the Quick Menu.",
              speak: "Shutting Down Alert");
        });
      } else if (diff > 0 && diff <= 60000) {
        // Already within the 1-minute window
        WinUtils.msgBox("Shutting Down", "Your PC will close in 1 minute.\nYou can cancel it from the Quick Menu.",
            speak: "Shutting Down Alert");
      }

      // Final shutdown timer
      shutDownTimer = Timer(Duration(milliseconds: diff), () async {
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
  }

  // --------------------------------------------------------------------------
  // Settings helpers
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

    await pref.setInt("quickMenuDesign", design.index);
    await saveActiveQuickMenuThemes(notify: notify);

    for (final QuickMenuTriggers listener in QuickMenuFunctions.listeners) {
      listener.refreshQuickMenu();
    }
  }

  /// @deprecated Use [getSavedMap] instead.
  static List<T> getSavedMap2<T>(T Function(String json) fromJson, String key, {List<T>? def}) {
    final String savedString = pref.getString(key) ?? "";
    if (savedString.isEmpty) return def ?? <T>[];
    final List<dynamic> list = jsonDecode(savedString);
    final List<T> varMapped = <T>[];
    for (String value in list) {
      varMapped.add(fromJson(value));
    }
    return varMapped;
  }

  static List<T> getSavedMap<T>(T Function(String json) fromJson, String key, {List<T>? def}) {
    final String savedString = pref.getString(key) ?? '';
    if (savedString.isEmpty) return def ?? <T>[];
    try {
      return (jsonDecode(savedString) as List<dynamic>).cast<String>().map(fromJson).toList();
    } catch (e) {
      pref.setString(key, "");
      return def ?? <T>[];
    }
  }

  // --------------------------------------------------------------------------
  // Getters / setters
  // --------------------------------------------------------------------------

  Map<String, String> get taskBarRewrites {
    final String rewrites = pref.getString("taskBarRewrites") ?? "";
    if (rewrites == "") {
      return <String, String>{r"DevTools.*?([^\s\/]+\.\w+)\/.*?$": r"⚠ DevTools: $1 "};
    }
    return Map<String, String>.from(json.decode(rewrites));
  }

  Map<String, String> get iconsRewrite {
    final String rewrites = pref.getString("iconsRewrite") ?? "";
    if (rewrites == "") {
      return <String, String>{};
    }
    return Map<String, String>.from(json.decode(rewrites));
  }

  static Map<String, String> titleIconRewrite = <String, String>{
    "DevTools": "resources/devtools.png",
  };
  static String getIconRewrite(String exePath, {Window? window}) {
    if (window != null) {
      for (final String title in titleIconRewrite.keys) {
        if (window.title.contains(title)) return titleIconRewrite[title] ?? "";
      }
    }

    final Map<String, String> currentIconsRewrite = Boxes().iconsRewrite;
    final String appName = currentIconsRewrite.keys
        .firstWhere((String element) => exePath.toLowerCase().contains(element.toLowerCase()), orElse: () => "");
    return currentIconsRewrite[appName] ?? "";
  }

  List<List<String>> _runShortcuts = <List<String>>[];

  set runShortcuts(List<List<String>> items) {
    _runShortcuts = items;
    updateSettings("runShortcuts", jsonEncode(items));
  }

  List<List<String>> get runShortcuts {
    if (_runShortcuts.isNotEmpty) return _runShortcuts;
    final String prefString = pref.getString("runShortcuts") ?? "";
    if (prefString.isEmpty) {
      return <List<String>>[
        <String>["g", "https://github.com/search?q={params}"],
      ];
    }
    final List<dynamic> runShortcuts = jsonDecode(pref.getString("runShortcuts")!);
    _runShortcuts.clear();
    for (List<dynamic> x in runShortcuts) {
      _runShortcuts.add(<String>[x[0], x[1]]);
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
    final String prefString = pref.getString("runMemos") ?? "";
    if (prefString.isEmpty) return _runMemos;
    final List<dynamic> runMemos = jsonDecode(pref.getString("runMemos")!);
    _runMemos.clear();
    for (List<dynamic> x in runMemos) {
      _runMemos.add(<String>[x[0], x[1]]);
    }
    return _runMemos;
  }

  List<CliBookItem> _cliBook = <CliBookItem>[];

  set cliBook(List<CliBookItem> items) {
    _cliBook = items;
    updateSettings("cliBook", jsonEncode(items));
  }

  List<CliBookItem> get cliBook {
    if (_cliBook.isNotEmpty) return _cliBook;
    final String prefString = pref.getString("cliBook") ?? "";
    if (prefString.isEmpty) return _cliBook;
    final List<dynamic> cliBook = jsonDecode(pref.getString("cliBook")!);
    _cliBook.clear();
    for (Map<String, dynamic> x in cliBook) {
      _cliBook.add(CliBookItem.fromJson(x));
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
    final String prefString = pref.getString("runKeys") ?? "";
    if (prefString.isEmpty) {
      return <List<String>>[
        <String>["m", "{MEDIA_NEXT_TRACK}"],
        <String>["p", "{MEDIA_PREV_TRACK}"],
      ];
    }
    final List<dynamic> runKeys = jsonDecode(pref.getString("runKeys")!);
    _runKeys.clear();
    for (List<dynamic> x in runKeys) {
      _runKeys.add(<String>[x[0], x[1]]);
    }
    return _runKeys;
  }

  List<String> get topBarWidgets {
    final List<String> defaultWidgets = quickActionsMap.keys.toList()..add("Deactivated:");
    final List<String> topBarWidgets = pref.getStringList("topBarWidgets") ?? defaultWidgets;
    // if (topBarWidgets.length != defaultWidgets.length - 1) {
    final Iterable<String> newItems = defaultWidgets.where((String widget) => !topBarWidgets.contains(widget));
    final int disabledIndex = topBarWidgets.indexWhere((String element) => element == "Deactivated:");
    topBarWidgets.insertAll(disabledIndex, newItems);
    pref.setStringList("topBarWidgets", topBarWidgets);
    // }
    return topBarWidgets;
  }

  List<String> get pinnedApps => pref.getStringList("pinnedApps") ?? <String>[];

  static List<double> _quickMenuSize = <double>[];
  static set quickMenuSize(List<double> list) => _quickMenuSize = list;
  static List<double> get quickMenuSize {
    if (_quickMenuSize.isNotEmpty) return _quickMenuSize;
    _quickMenuSize = (jsonDecode(pref.getString("quickMenuSize") ?? "[299.0, 539.0]") as List<dynamic>)
        .map((dynamic x) => x as double)
        .toList();
    if (_quickMenuSize.length != 2) {
      _quickMenuSize = <double>[299.0, 539.0];
    }
    return _quickMenuSize;
  }

  List<PowerShellScript> get powerShellScripts =>
      getSavedMap<PowerShellScript>(PowerShellScript.fromJson, "powerShellScripts");
  List<BookmarkGroup> get bookmarks => getSavedMap<BookmarkGroup>(BookmarkGroup.fromJson, "projects");

  // Static cached collections
  static List<Reminder>? _reminders;
  static set reminders(List<Reminder> list) => _reminders = list;
  static List<Reminder> get reminders =>
      _reminders == null ? _reminders = getSavedMap<Reminder>(Reminder.fromJson, "reminders") : _reminders!;

  static List<Hotkeys> _remap = <Hotkeys>[];
  static set remap(List<Hotkeys> list) => _remap = list;
  static List<Hotkeys> get remap => _remap.isEmpty ? _remap = getSavedMap<Hotkeys>(Hotkeys.fromJson, "remap") : _remap;

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
              maxDepth: 3),
          SearchFolder(
              path: "${Platform.environment['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
              includeFolders: false,
              maxDepth: 3),
          SearchFolder(
              path: "${Platform.environment['ProgramFiles']}\\WindowsApps", includeFolders: false, maxDepth: 3),
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
    final String savedString = pref.getString("searchHistory") ?? '';
    if (savedString.isEmpty) return <SearchHistory>[];
    try {
      return (jsonDecode(savedString) as List<dynamic>)
          .map((dynamic item) => SearchHistory.fromMap(item as Map<String, dynamic>))
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
    Boxes.updateSettings("appAudioControls", jsonEncode(list.map((AppAudioControl e) => e.toMap()).toList()));
  }

  static List<AppAudioControl> get appAudioControls {
    if (_appAudioControls.isNotEmpty) return _appAudioControls;
    final String savedString = pref.getString("appAudioControls") ?? '';
    if (savedString.isNotEmpty) {
      _appAudioControls = (jsonDecode(savedString) as List<dynamic>)
          .map((dynamic item) => AppAudioControl.fromMap(item as Map<String, dynamic>))
          .toList();
    } else {
      // Migration from ancient MusicBeeLocation
      final String? mbLocation = pref.getString("MusicBeeLocation");
      if (mbLocation != null && mbLocation.isNotEmpty) {
        _appAudioControls.add(AppAudioControl(
          name: "MusicBee",
          exe: "MusicBee.exe",
          path: mbLocation,
          iconPath: "",
          iconCodePoint: 0xe415, // Icons.music_video_outlined
          hotkeyForward: "{#SHIFT}{#WIN}{#ALT}{F11}",
          hotkeyRewind: "{#SHIFT}{#WIN}{#ALT}{F10}",
          hotkeyNext: "{#SHIFT}{#WIN}{#ALT}{F6}",
          hotkeyPrev: "{#SHIFT}{#WIN}{#ALT}{F8}",
          hotkeyPause: "{#SHIFT}{#WIN}{#ALT}{F7}",
        ));
        appAudioControls = _appAudioControls;
      }
    }
    return _appAudioControls;
  }

  static List<AppCategory> _appCategories = <AppCategory>[];
  static set appCategories(List<AppCategory> list) {
    _appCategories = list;
    Boxes.updateSettings("appCategories", jsonEncode(list.map((AppCategory e) => e.toMap()).toList()));
  }

  static List<AppCategory> get appCategories {
    if (_appCategories.isNotEmpty) return _appCategories;
    final String savedString = pref.getString("appCategories") ?? '';
    if (savedString.isNotEmpty) {
      _appCategories = (jsonDecode(savedString) as List<dynamic>)
          .map((dynamic item) => AppCategory.fromMap(item as Map<String, dynamic>))
          .toList();
    } else {
      _appCategories.add(AppCategory(
          name: "Games",
          items: <AppItem>[],
          folderPath: "${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Steam"));
    }
    return _appCategories;
  }

  static List<QuickGrid> _quickGrids = <QuickGrid>[];
  static set quickGrids(List<QuickGrid> list) {
    _quickGrids = list;
    Boxes.updateSettings('QuickGrids', jsonEncode(list.map((QuickGrid e) => e.toMap()).toList()));
  }

  static List<QuickGrid> get quickGrids {
    if (_quickGrids.isNotEmpty) return _quickGrids;
    final String savedString = pref.getString('QuickGrids') ?? '';
    if (savedString.isNotEmpty) {
      try {
        _quickGrids = (jsonDecode(savedString) as List<dynamic>)
            .map((dynamic item) => QuickGrid.fromMap(item as Map<String, dynamic>))
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
            ])
      ];
    }
    return _quickGrids;
  }

  // --------------------------------------------------------------------------
  // Settings watcher (preview mode)
  // --------------------------------------------------------------------------

  void watchForSettingsChange() {
    globalSettings.previewTheme = true;
    String savedFileText = File(Boxes.pref.fileName).readAsStringSync();
    bool updating = false;

    Timer.periodic(const Duration(milliseconds: 100), (Timer timer) async {
      if (updating) return;
      final String newSavedFileText = File(Boxes.pref.fileName).readAsStringSync();
      if (savedFileText == newSavedFileText) return;

      updating = true;
      savedFileText = newSavedFileText;
      await Boxes.registerBoxes(reload: true);
      updating = false;

      Map<String, dynamic> js;
      try {
        js = jsonDecode(savedFileText);
      } catch (e) {
        return;
      }

      final String prevThemeLight = js["flutter.previewThemeLight"] ?? "";
      if (prevThemeLight.isNotEmpty) {
        globalSettings.lightTheme = ThemeColors.fromJson(prevThemeLight);
      }

      final String prevThemeDark = js["flutter.previewThemeDark"] ?? "";
      if (prevThemeDark.isNotEmpty) {
        globalSettings.darkTheme = ThemeColors.fromJson(prevThemeDark);
      }

      globalSettings.settingsChanged = !globalSettings.settingsChanged;
    });
  }

  // --------------------------------------------------------------------------
  // Quick timers
  // --------------------------------------------------------------------------

  static final List<QuickTimer> quickTimers = <QuickTimer>[];

  void addQuickTimer(String name, int minutes, int type) {
    final QuickTimer quick = QuickTimer();
    quick.name = name;
    quick.endTime = DateTime.now().add(Duration(minutes: minutes));
    quick.type = type;
    _startQuickTimer(quick);
    quickTimers.add(quick);
    saveQuickTimers();
  }

  void _startQuickTimer(QuickTimer quick) {
    final int secondsRemaining = quick.endTime.difference(DateTime.now()).inSeconds;
    if (secondsRemaining <= 0) return;

    quick.timer = Timer(Duration(seconds: secondsRemaining), () {
      if (quick.type == 0) {
        WinUtils.textToSpeech(quick.name, repeat: -1);
      } else if (quick.type == 1) {
        WinUtils.msgBox("Tabame Quick Timer", quick.name);
      } else if (quick.type == 2) {
        WinUtils.showWindowsNotification(
          title: "Tabame Quick Timer",
          body: "Timer Expired: ${quick.name}",
          onClick: () {},
        );
      }
      quickTimers.remove(quick);
      saveQuickTimers();
    });
  }

  void saveQuickTimers() {
    final List<Map<String, dynamic>> data = quickTimers.map((QuickTimer e) => e.toMap()).toList();
    Boxes.pref.setString("quickTimers", jsonEncode(data));
  }

  static void loadQuickTimers() {
    final String? data = Boxes.pref.getString("quickTimers");
    if (data == null || data.isEmpty) return;
    try {
      final List<dynamic> decoded = jsonDecode(data);
      for (final dynamic item in decoded) {
        final QuickTimer quick = QuickTimer.fromMap(item as Map<String, dynamic>);
        if (quick.endTime.isAfter(DateTime.now())) {
          Boxes()._startQuickTimer(quick);
          quickTimers.add(quick);
        }
      }
    } catch (e) {
      Debug.add("Error loading quick timers: $e");
    }
  }

  // --------------------------------------------------------------------------
  // Last quick timers
  // --------------------------------------------------------------------------

  static final List<SavedQuickTimers> lastQuickTimers = <SavedQuickTimers>[];

  void loadLatestQuickTimers() {
    lastQuickTimers.clear();
    final String? string = Boxes.pref.getString("lastQuickTimers");
    if (string == null) return;
    final List<dynamic> data = jsonDecode(string);
    if (data.isEmpty) return;
    for (Map<dynamic, dynamic> qt in data) {
      final SavedQuickTimers timer = SavedQuickTimers();
      timer.name = qt["name"];
      timer.minutes = qt["minutes"];
      timer.type = qt["type"];
      lastQuickTimers.add(timer);
    }
  }

  void saveLatestQuickTimers() {
    final List<Map<String, dynamic>> saveMap = <Map<String, dynamic>>[];
    for (SavedQuickTimers qt in lastQuickTimers) {
      saveMap.add(<String, dynamic>{
        "name": qt.name,
        "minutes": qt.minutes,
        "type": qt.type,
      });
    }
    Boxes.pref.setString("lastQuickTimers", jsonEncode(saveMap));
  }

  // --------------------------------------------------------------------------
  // Auto-update
  // --------------------------------------------------------------------------

  static String? updateDownloadLink;
  static String? updateVersion;

  static Future<int> checkForUpdates({bool autoInstall = false}) async {
    Debug.add("Updates: Checking");
    try {
      final http.Response response = await http.get(Uri.parse("https://api.github.com/repos/far-se/tabame/releases"));
      if (response.statusCode != 200) return -1;

      final List<dynamic> json = jsonDecode(response.body);
      if (json.isEmpty) return -1;

      final Map<String, dynamic> lastVersion = json[0];
      if (lastVersion["tag_name"] == "v${Globals.version}") return 0;

      String downloadLink = "";
      for (Map<String, dynamic> x in lastVersion["assets"]) {
        if (!x["name"].endsWith("zip")) continue;
        if (x.containsKey("browser_download_url")) {
          downloadLink = x["browser_download_url"];
          break;
        }
      }
      if (downloadLink == "") return -1;

      updateDownloadLink = downloadLink;
      updateVersion = lastVersion["tag_name"];

      if (autoInstall) {
        unawaited(installUpdate(downloadLink, updateVersion!));
      }

      Debug.add("Updates: Checked");
      return 1;
    } catch (e) {
      Debug.add("Updates Error: $e");
      return -1;
    }
  }

  static Future<void> installUpdate(String downloadLink, String tagName) async {
    final String fileName = "${WinUtils.getTempFolder()}\\tabame_$tagName.zip";
    await WinUtils.downloadFile(downloadLink, fileName, () {
      final String dir = Directory.current.absolute.path;
      WinUtils.open(
        'powershell.exe',
        arguments: ' Expand-Archive -LiteralPath \\"$fileName\\" -DestinationPath \\"$dir\\" -Force;'
            'Invoke-Item \\"$dir\\tabame.exe\\";',
      );
      if (kReleaseMode) {
        WinUtils.closeAllTabameExProcesses();
        exit(0);
      }
    });
  }
}
