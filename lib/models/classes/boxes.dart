// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:win32/win32.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../../main.dart';
import '../globals.dart';
import '../util/quick_action_list.dart';
import '../win32/keys.dart';
import '../settings.dart';
import '../win32/win32.dart';
import 'hotkeys.dart';
import 'save_settings.dart';
import 'saved_maps.dart';

class Boxes {
// vscode-fold=2
  static late SaveSettings pref;
  static List<String> mediaControls = <String>[];

  Boxes();
  static Future<void> registerBoxes({bool reload = false}) async {
    if (reload) {
      await pref.reload();
    } else {
      pref = await SaveSettings.getInstance();
    }
    globalSettings.isWindows10 = WinUtils.isWindows10();
    Debug.add("Registered: Loaded Box info (win10: ${globalSettings.isWindows10} | ${Platform.operatingSystemVersion})");
    //? Settings
    if (pref.getString("language") == null) {
      await pref.setBool("DEBUGGING", false);
      await pref.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await pref.setInt("volumeOSDStyle", VolumeOSDStyle.normal.index);

      await pref.setInt("themeType", ThemeType.system.index);
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
      final List<Reminder> demoReminders = <Reminder>[
        Reminder(
            enabled: false,
            interval: <int>[540, 1200],
            message: "Stretch",
            repetitive: true,
            time: 60,
            voiceNotification: true,
            weekDays: <bool>[true, true, true, true, true, false, false],
            voiceVolume: 100),
        Reminder(
            enabled: false,
            weekDays: <bool>[true, true, true, true, true, true, true],
            time: 540,
            repetitive: false,
            interval: <int>[480, 1200],
            message: "p:Take your meds",
            voiceNotification: false,
            voiceVolume: 100)
      ];
      await pref.setString("reminders", jsonEncode(demoReminders));
      Debug.add("Registered: setDefault Settings");
    }
    //!fetch
    globalSettings
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..volumeOSDStyle = VolumeOSDStyle.values[pref.getInt("volumeOSDStyle") ?? 0]
      ..language = pref.getString("language") ?? Platform.localeName.substring(0, 2)
      ..views = pref.getBool("views") ?? globalSettings.views
      ..audio = pref.getStringList("audio") ?? globalSettings.audio
      ..weather = pref.getStringList("weather") ?? globalSettings.weather
      ..autoUpdate = pref.getBool("autoUpdate") ?? globalSettings.autoUpdate
      ..customLogo = pref.getString("customLogo") ?? globalSettings.customLogo
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
      ..showQuickMenuAtTaskbarLevel = pref.getBool("showQuickMenuAtTaskbarLevel") ?? globalSettings.showQuickMenuAtTaskbarLevel
      ..quickMenuPinnedWithTrayAtBottom = pref.getBool("quickMenuPinnedWithTrayAtBottom") ?? globalSettings.quickMenuPinnedWithTrayAtBottom
      ..usePowerShellAsToastNotification = pref.getBool("usePowerShellAsToastNotification") ?? globalSettings.usePowerShellAsToastNotification
      ..themeType = ThemeType.values[pref.getInt("themeType") ?? 0]; // * always after schedule
    loadQuickTimers();
    Debug.add("Registered: Fetched All");
    if (pref.getBool("DEBUGGING") ?? false == true) {
      Debug.register(clean: false);
      Debug.methodDebug(clean: false);
    }
    // ? other
    // ? Just Installed
    final bool justInstalled = pref.getBool("justInstalled") ?? false;
    if (justInstalled) {
      updateSettings("justInstalled", false);
      Debug.add("Registered: Shortcut");
      createShortcut(Platform.resolvedExecutable, WinUtils.getKnownFolder(FOLDERID_Programs), args: "-interface", destExe: "Tabame Interface.lnk");
      Debug.add("Registered: shortcut Installed");
    }
    // ? Trktivity
    if (!Directory("${WinUtils.getTabameSettingsFolder()}\\trktivity").existsSync()) {
      Directory("${WinUtils.getTabameSettingsFolder()}\\trktivity").createSync(recursive: true);
      Debug.add("Registered: Trktivity");
    }

    // ? Theme
    final String? lightTheme = pref.getString("lightTheme");
    final String? darkTheme = pref.getString("darkTheme");
    if (lightTheme == null || darkTheme == null) {
      pref.setString("lightTheme", globalSettings.lightTheme.toJson());
      pref.setString("darkTheme", globalSettings.darkTheme.toJson());
    }
    if (lightTheme != null) globalSettings.lightTheme = ThemeColors.fromJson(lightTheme);
    if (darkTheme != null) globalSettings.darkTheme = ThemeColors.fromJson(darkTheme);
    themeChangeNotifier.value = !themeChangeNotifier.value;
    Debug.add("Registered: Theme");

    //? Pinned Apps
    if (pref.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await pref.setStringList("pinnedApps", pinnedApps2);
      Debug.add("Registered: Pinned");
    }

    //?PowerShell
    if (pref.getString("powerShellScripts") == null) {
      final List<String> powerShellScripts = <String>[
        PowerShellScript(name: "🏠Show IP", command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content", showTerminal: true).toJson()
      ];
      await pref.setString("powerShellScripts", jsonEncode(powerShellScripts));
      Debug.add("Registered: PowerShell");
    }
    if (pref.getString("quickActions") == null) {
      final List<QuickActions> quickActionList = <QuickActions>[
        QuickActions(name: "🎧 Spotify", type: "Spotify Controls", value: ""),
        QuickActions(name: "📷 Fancyshot", type: "Quick Action", value: "8"),
        QuickActions(name: "🔊 Volume", type: "Volume Slider", value: ""),
        QuickActions(name: "🔉 Volume Level 3", type: "Set Volume", value: "3"),
        QuickActions(name: "🔊 Volume Level 100", type: "Set Volume", value: "100"),
        QuickActions(name: "🖥 Toggle Taskbar", type: "Quick Action", value: "2"),
        QuickActions(name: "🔓 PowerShell", type: "Run Command", value: "powershell start-process powershell"),
        QuickActions(name: "🎚 Audio Devices", type: "Audio Output Devices", value: "")
      ];
      await pref.setString("quickActions", jsonEncode(quickActionList));
      Debug.add("Registered: quickActions");
    }

    //? Media Controls
    mediaControls = pref.getStringList("mediaControls") ?? <String>["Spotify.exe", "chrome.exe", "firefox.exe", "Music.UI.exe"];
    //? Run Shortcuts
    globalSettings.run.fetch();
    Debug.add("Registered: Shortcuts");
    //! Startup
    //? Taskbar
    if (globalSettings.previewTheme) return;
    //if (kReleaseMode) {
    if (globalSettings.page == TPage.quickmenu) {
      if (globalSettings.hideTaskbarOnStartup) {
        WinUtils.toggleTaskbar(visible: false);
        Debug.add("Registered: Taskbar");
      }

      //? Volume
      if (globalSettings.isWindows10 && globalSettings.volumeOSDStyle != VolumeOSDStyle.normal) {
        WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
        WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
        Debug.add("Registered: Volume");
      }
      if (globalSettings.autoUpdate) checkForUpdates();
    }
    if (globalSettings.page == TPage.quickmenu) {
      if (pageWatchers.any((PageWatcher element) => element.enabled)) Tasks().startPageWatchers();
      if (reminders.any((Reminder element) => element.enabled)) Tasks().startReminders();
      Debug.add("Registered: Tasks");
    }
    shutDownScheduler();
  }

  static Timer? shutDownTimer;
  static void shutDownScheduler() {
    if ((Boxes.pref.getBool("isShutDownScheduled") ?? false) == true) {
      final int unix = Boxes.pref.getInt("shutDownUnix") ?? 0;
      if (unix == 0) return;
      final int diff = unix - DateTime.now().millisecondsSinceEpoch;
      if (diff < 0) return;
      shutDownTimer = Timer(Duration(milliseconds: diff), () async {
        if ((Boxes.pref.getBool("isShutDownScheduled") ?? false) == false) return;
        await Boxes.pref.setBool("isShutDownScheduled", false);
        await Boxes.pref.setInt("shutDownUnix", 0);
        if (kReleaseMode) {
          WinUtils.runPowerShell(<String>["shutdown /s"]);
        }
      });
    } else {
      shutDownTimer?.cancel();
    }
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
      throw ("No associated type $value");
    }
    pref = await SaveSettings.getInstance();
  }

  static List<T> getSavedMap<T>(T Function(String json) fromJson, String key, {List<T>? def}) {
    final String savedString = pref.getString(key) ?? "";
    if (savedString.isEmpty) return def ?? <T>[];
    final List<dynamic> list = jsonDecode(savedString);
    final List<T> varMapped = <T>[];
    for (String value in list) {
      varMapped.add(fromJson(value));
    }
    return varMapped;
  }

  Map<String, String> get taskBarRewrites {
    final String rewrites = pref.getString("taskBarRewrites") ?? "";
    if (rewrites == "") return <String, String>{r"DevTools.*?([^\s\/]+\.\w+)\/.*?$": r"⚠ DevTools: $1 "};
    final Map<String, String> rewritesMap = Map<String, String>.from(json.decode(rewrites));
    return rewritesMap;
  }

  //?run shortcuts
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
        <String>["g", "https://github.com/search?q={params}"]
      ];
    }
    final List<dynamic> runShortcuts = jsonDecode(pref.getString("runShortcuts")!);
    _runShortcuts.clear();
    for (List<dynamic> x in runShortcuts) {
      _runShortcuts.add(<String>[x[0], x[1]]);
    }
    return _runShortcuts;
  }

  //?run shortcuts
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

  // ? run keys
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
        <String>["p", "{MEDIA_PREV_TRACK}"]
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
    List<String> defaultWidgets = quickActionsMap.keys.toList();
    defaultWidgets.add("Deactivated:");
    final List<String> topBarWidgets = pref.getStringList("topBarWidgets") ?? defaultWidgets;
    if (topBarWidgets.length != defaultWidgets.length) {
      final Iterable<String> newItems = defaultWidgets.where((String widget) => !topBarWidgets.contains(widget));
      final int disabledIndex = topBarWidgets.indexWhere((String element) => element == "Deactivated:");
      topBarWidgets.insertAll(disabledIndex, newItems);
      pref.setStringList("topBarWidgets", topBarWidgets);
    }
    return topBarWidgets;
  }

  List<String> get pinnedApps => pref.getStringList("pinnedApps") ?? <String>[];
  List<PowerShellScript> get powerShellScripts => getSavedMap<PowerShellScript>(PowerShellScript.fromJson, "powerShellScripts");
  List<BookmarkGroup> get bookmarks => getSavedMap<BookmarkGroup>(BookmarkGroup.fromJson, "projects");

  static List<PageWatcher> _pageWatchers = <PageWatcher>[];
  static set pageWatchers(List<PageWatcher> list) => _pageWatchers = list;
  static List<PageWatcher> get pageWatchers => _pageWatchers.isEmpty ? _pageWatchers = getSavedMap<PageWatcher>(PageWatcher.fromJson, "pageWatchers") : _pageWatchers;

  static List<Reminder> _reminders = <Reminder>[];
  static set reminders(List<Reminder> list) => _reminders = list;
  static List<Reminder> get reminders => _reminders.isEmpty ? _reminders = getSavedMap<Reminder>(Reminder.fromJson, "reminders") : _reminders;

  static List<Hotkeys> _remap = <Hotkeys>[];
  static set remap(List<Hotkeys> list) => _remap = list;
  static List<Hotkeys> get remap => _remap.isEmpty ? _remap = getSavedMap<Hotkeys>(Hotkeys.fromJson, "remap") : _remap;

  static List<RunAPI> _runApi = <RunAPI>[];
  static set runApi(List<RunAPI> list) => _runApi = list;
  static List<RunAPI> get runApi => _runApi.isEmpty ? _runApi = getSavedMap<RunAPI>(RunAPI.fromJson, "runApi") : _runApi;

  static List<Workspaces> _workspaces = <Workspaces>[];
  static set workspaces(List<Workspaces> list) => _workspaces = list;
  static List<Workspaces> get workspaces => _workspaces.isEmpty ? _workspaces = getSavedMap<Workspaces>(Workspaces.fromJson, "workspaces") : _workspaces;

  static List<DefaultVolume> _defaultVolume = <DefaultVolume>[];
  static set defaultVolume(List<DefaultVolume> list) => _defaultVolume = list;
  static List<DefaultVolume> get defaultVolume =>
      _defaultVolume.isEmpty ? _defaultVolume = getSavedMap<DefaultVolume>(DefaultVolume.fromJson, "defaultVolume") : _defaultVolume;

  static List<PredefinedSizes> _predefinedSizes = <PredefinedSizes>[];
  static set predefinedSizes(List<PredefinedSizes> list) => _predefinedSizes = list;
  static List<PredefinedSizes> get predefinedSizes =>
      _predefinedSizes.isEmpty ? _predefinedSizes = getSavedMap<PredefinedSizes>(PredefinedSizes.fromJson, "predefinedSizes") : _predefinedSizes;

  static List<QuickActions> _quickActions = <QuickActions>[];
  static set quickActions(List<QuickActions> list) => _quickActions = list;
  static List<QuickActions> get quickActions => _quickActions.isEmpty ? _quickActions = getSavedMap<QuickActions>(QuickActions.fromJson, "quickActions") : _quickActions;

  void watchForSettingsChange() {
    globalSettings.previewTheme = true;
    String savedFileText = File(Boxes.pref.fileName).readAsStringSync();
    bool updating = false;
    Timer.periodic(const Duration(milliseconds: 100), (Timer timer) async {
      if (updating) return;
      final String newSavedFileText = File(Boxes.pref.fileName).readAsStringSync();
      if (savedFileText != newSavedFileText) {
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
      }
    });
  }

  static final List<QuickTimer> quickTimers = <QuickTimer>[];
  void addQuickTimer(String name, int minutes, int type) {
    final QuickTimer quick = QuickTimer();
    quick.name = name;
    quick.endTime = DateTime.now().add(Duration(minutes: minutes));
    quick.type = type;
    quick.timer = Timer(Duration(minutes: minutes), () {
      if (type == 0) {
        WinUtils.textToSpeech(name, repeat: -1);
      } else if (type == 1) {
        WinUtils.msgBox(name, "Tabame Quick Timer");
      } else if (type == 2) {
        WinUtils.showWindowsNotification(
          title: "Tabame Quick Timer",
          body: "Timer Expired: $name",
          onClick: () {},
        );
      }
      quickTimers.remove(quick);
      saveQuickTimers();
    });
    quickTimers.add(quick);
    saveQuickTimers();
  }

  void saveQuickTimers() {
    final List<Map<String, dynamic>> saveMap = <Map<String, dynamic>>[];
    for (QuickTimer qt in quickTimers) {
      saveMap.add(<String, dynamic>{"name": qt.name, "end": qt.endTime.millisecondsSinceEpoch, "type": qt.type});
    }
    Boxes.pref.setString("quickTimersList", jsonEncode(saveMap));
  }

  static void loadQuickTimers() {
    final String? string = Boxes.pref.getString("quickTimersList");
    if (string == null) return;
    final List<dynamic> data = jsonDecode(string);
    if (data.isEmpty) return;
    for (Map<dynamic, dynamic> qt in data) {
      final DateTime endTime = DateTime.fromMillisecondsSinceEpoch(qt["end"]);
      final Duration minutes = endTime.difference(DateTime.now());
      if (minutes.inMinutes < 1) return;
      Boxes().addQuickTimer(qt["name"], minutes.inMinutes, qt["type"]);
    }
  }

  static Future<int> checkForUpdates() async {
    Debug.add("Updates: Checking");
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
    final String fileName = "${WinUtils.getTempFolder()}\\tabame_${lastVersion["tag_name"]}.zip";
    await WinUtils.downloadFile(downloadLink, fileName, () {
      final String dir = "${Directory.current.absolute.path}";
      WinUtils.open('powershell.exe',
          arguments: /* '-NoExit ' */
              ' Expand-Archive -LiteralPath \\"$fileName\\" -DestinationPath \\"$dir\\" -Force;'
              'Invoke-Item \\"$dir\\tabame.exe\\";');
      if (kReleaseMode) {
        WinUtils.closeAllTabameExProcesses();
        exit(0);
      }
    });
    Debug.add("Updates: Checked");
    return 1;
  }

  //
}

class TrktivityFilter {
  String exe;
  String titleSearch;
  String titleReplace;
  TrktivityFilter({
    required this.exe,
    required this.titleSearch,
    required this.titleReplace,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'exe': exe,
      'titleSearch': titleSearch,
      'titleReplace': titleReplace,
    };
  }

  factory TrktivityFilter.fromMap(Map<String, dynamic> map) {
    return TrktivityFilter(
      exe: (map['exe'] ?? '') as String,
      titleSearch: (map['titleSearch'] ?? '') as String,
      titleReplace: (map['titleReplace'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivityFilter.fromJson(String source) => TrktivityFilter.fromMap(json.decode(source) as Map<String, dynamic>);

  TrktivityFilter copyWith({
    String? exe,
    String? titleSearch,
    String? titleReplace,
  }) {
    return TrktivityFilter(
      exe: exe ?? this.exe,
      titleSearch: titleSearch ?? this.titleSearch,
      titleReplace: titleReplace ?? this.titleReplace,
    );
  }

  @override
  String toString() => 'TrktivityFilter(exe: $exe, titleSearch: $titleSearch, titleReplace: $titleReplace)';

  @override
  bool operator ==(covariant TrktivityFilter other) {
    if (identical(this, other)) return true;

    return other.exe == exe && other.titleSearch == titleSearch && other.titleReplace == titleReplace;
  }

  @override
  int get hashCode => exe.hashCode ^ titleSearch.hashCode ^ titleReplace.hashCode;
}

class QuickTimer {
  String name = "";
  Timer? timer;
  DateTime endTime = DateTime.now();
  int type = 0;
}

class Tasks {
  void startPageWatchers({int? specificIndex}) {
    int index = -1;

    for (PageWatcher watcher in Boxes.pageWatchers) {
      if (specificIndex != null) {
        index++;
        if (index != specificIndex) continue;
      }
      if (!watcher.enabled || watcher.url == "") continue;
      if (watcher.timer != null) watcher.timer?.cancel();
      watcher.timer = Timer.periodic(
        Duration(seconds: watcher.checkPeriod),
        (Timer timer) async {
          if (!watcher.enabled) timer.cancel();
          final String newValue = await pageWatcherGetValue(watcher.url, watcher.regex);
          if (newValue != watcher.lastMatch) {
            watcher.lastMatch = newValue;
            await Boxes.updateSettings("pageWatchers", jsonEncode(Boxes.pageWatchers));
            String siteName = "";
            final RegExp exp = RegExp(r'^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/?\n]+)');
            if (exp.hasMatch(watcher.url)) {
              final RegExpMatch match = exp.firstMatch(watcher.url)!;
              siteName = match.group(1)!;
            } else {
              siteName = watcher.url.replaceFirst("https://", "");
              if (siteName.contains("/")) {}
              siteName = siteName.substring(0, siteName.indexOf("/"));
            }
            if (watcher.voiceNotification) {
              WinUtils.textToSpeech('Value for $siteName has changed to $newValue');
            } else {
              WinUtils.showWindowsNotification(
                title: "Tabame Page Watcher",
                body: "Value for site $siteName has changed to $newValue",
                onClick: () {
                  WinUtils.open(watcher.url);
                },
              );
            }
          }
        },
      );
    }
  }

  Future<String> pageWatcherGetValue(String url, String regex) async {
    if (url == "") return "";
    final http.Response response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final RegExp exp = RegExp(regex);
      if (!exp.hasMatch(response.body)) return "No match";

      final RegExpMatch match = exp.firstMatch(response.body)!;
      return match.group(0)!;
    }
    return "Fetch Failed";
  }

  void startReminders() {
    for (Reminder reminder in Boxes.reminders) {
      reminder.timer?.cancel();
      if (!reminder.enabled) continue;
      if (reminder.repetitive) {
        // ? Periodic.
        int totalMinutes = reminder.interval[0];
        final DateTime now = DateTime.now();
        final int nowMinutes = now.hour * 60 + DateTime.now().minute;
        int differenceTime = 0;
        if (nowMinutes < reminder.interval[1]) {
          do {
            totalMinutes += reminder.time;
          } while (totalMinutes < nowMinutes);
          differenceTime = totalMinutes - nowMinutes;
        } else {
          differenceTime = 24 - nowMinutes + reminder.interval[0];
        }

        if (differenceTime == 0) {
          differenceTime = (60 - now.second) * 1000 - now.millisecond;
        } else {
          differenceTime = (differenceTime * 60 - now.second) * 1000 - now.millisecond;
        }
        reminder.timer = Timer(Duration(milliseconds: differenceTime), () => reminderPeriodic(reminder));
      } else {
        // ? One per day
        int minutes = 0;
        final DateTime dateTime = DateTime.now();
        final int now = dateTime.hour * 60 + DateTime.now().minute;
        if (now > reminder.time) {
          minutes = 24 * 60 - now + reminder.time;
        } else {
          minutes = reminder.time - now;
        }
        minutes = (minutes * 60 - dateTime.second) * 1000 - dateTime.millisecond;
        reminder.timer = Timer(Duration(milliseconds: minutes), () => reminderDaily(reminder));
      }
    }
  }

  void reminderPeriodic(Reminder reminder) {
    if (!reminder.enabled) return;
    final int now = DateTime.now().hour * 60 + DateTime.now().minute;
    final String cleanMessage = reminder.message.replaceFirst("p:", "");
    if (now.isBetweenEqual(reminder.interval[0], reminder.interval[1]) && reminder.weekDays[DateTime.now().weekday - 1]) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech('$cleanMessage', repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: $cleanMessage", onClick: () {});
      }
      if (reminder.message.startsWith("p:")) {
        globalSettings.persistentReminders.add("$cleanMessage each ${reminder.time} minutes");
        Boxes.pref.setStringList("persistentReminders", globalSettings.persistentReminders);
        for (final QuickMenuTriggers listener in QuickMenuFunctions.listeners) {
          if (!QuickMenuFunctions.listeners.contains(listener)) return;
          listener.refreshQuickMenu();
        }
      }
    }
    reminder.timer = Timer(Duration(minutes: reminder.time), () => reminderPeriodic(reminder));
  }

  reminderDaily(Reminder reminder) {
    if (!reminder.enabled) return;
    final String cleanMessage = reminder.message.replaceFirst("p:", "");
    bool correctDay = true;
    if (!reminder.weekDays[DateTime.now().weekday - 1]) correctDay = false;
    //? is it a bug? NO. its a feature (future self)
    if (correctDay && reminder.interval[0] < 0) {
      if (reminder.interval[1] <= 0) reminder.interval[1] = 1;
      final DateTime day = DateTime.fromMillisecondsSinceEpoch(reminder.interval[0].abs());
      final DateTime today = DateTime.now();
      DateTime span = day;
      int ticks = 0;
      while (span.millisecondsSinceEpoch < today.millisecondsSinceEpoch) {
        span = span.add(Duration(days: reminder.interval[1]));
        ticks++;
        if (ticks > 5000) break;
      }
      if (span.day != today.day) correctDay = false;
    }
    if (correctDay) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech('$cleanMessage', repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: $cleanMessage", onClick: () {});
      }
      if (reminder.message.startsWith("p:")) {
        globalSettings.persistentReminders.add("$cleanMessage at ${reminder.time.formatTime()}");
        Boxes.pref.setStringList("persistentReminders", globalSettings.persistentReminders);
        for (final QuickMenuTriggers listener in QuickMenuFunctions.listeners) {
          if (!QuickMenuFunctions.listeners.contains(listener)) return;
          listener.refreshQuickMenu();
        }
      }
    }
    reminder.timer = Timer(const Duration(days: 1), () => reminderDaily(reminder));
  }
}

class WinHotkeys {
  static Future<void> update() async {
    List<Map<String, dynamic>> allHotkeys = <Map<String, dynamic>>[];
    final List<Hotkeys> bindHotkeys = <Hotkeys>[...Boxes.remap];
    // order bindHotkeys by boundToRegion
    for (Hotkeys hotkeys in bindHotkeys) {
      // order hotkeys by boundToRegion
      hotkeys.keymaps.sort((KeyMap a, KeyMap b) {
        int pos = 0;
        if (a.boundToRegion == true) pos -= 1;
        return pos == 0 ? 1 : pos;
      });

      for (KeyMap hotkey in hotkeys.keymaps) {
        if (!hotkey.enabled) continue;
        allHotkeys.add(<String, dynamic>{
          "name": hotkey.name,
          "hotkey": hotkeys.hotkey.toUpperCase(),
          "keyVK": keyMap.containsKey("VK_${hotkeys.key.toUpperCase()}") ? keyMap["VK_${hotkeys.key.toUpperCase()}"] : -1,
          "modifisers": hotkeys.modifiers.isNotEmpty ? hotkeys.modifiers.join('+').toUpperCase() : "noModifiers",
          "listenToMovement": hotkeys.keymaps.any((KeyMap e) => e.triggerType == TriggerType.movement && e.triggerInfo[2] == -1),
          "matchWindowBy": hotkey.windowsInfo[0] == "any" ? "" : hotkey.windowsInfo[0],
          "matchWindowText": hotkey.windowsInfo[1],
          "activateWindowUnderCursor": hotkey.windowUnderMouse,
          "noopScreenBusy": hotkeys.noopScreenBusy,
          "prohibitedWindows": hotkeys.prohibited.join(";"),
          "regionasPercentage": hotkey.region.asPercentage,
          "regionOnScreen": hotkey.regionOnScreen, //-!hotkey.windowUnderMouse, // hotkey.windowsInfo[0] == "any" ? true : false, // hotkey.regionOnScreen,
          "regionX1": hotkey.region.x1,
          "regionX2": hotkey.region.x2,
          "regionY1": hotkey.region.y1,
          "regionY2": hotkey.region.y2,
          "anchorType": !hotkey.boundToRegion ? 0 : hotkey.region.anchorType.index + 1,
        });
      }
    }
    //!hook
    if (Globals.debugHooks || kReleaseMode) {
      NativeHooks.runHotkeys(allHotkeys);
    }
  }
}

abstract class QuickMenuTriggers {
  Future<void> onQuickMenuToggled(bool visible, int type) async {}
  Future<void> onQuickMenuShown(int type) async {}
  void refreshQuickMenu() async {}
}

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static int hidTime = 0;

  static final ObserverList<QuickMenuTriggers> _listeners = ObserverList<QuickMenuTriggers>();
  static List<QuickMenuTriggers> get listeners => List<QuickMenuTriggers>.from(_listeners);

  static bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  static void addListener(QuickMenuTriggers listener) {
    _listeners.add(listener);
  }

  static void removeListener(QuickMenuTriggers listener) {
    _listeners.remove(listener);
  }

  static Future<void> toggleQuickMenu({int type = 0, bool? visible, bool center = false}) async {
    visible ??= !isQuickMenuVisible;
    isQuickMenuVisible = visible;
    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) return;
      await listener.onQuickMenuToggled(visible, type);
    }
    if (visible) {
      if (type == 3) {
        Globals.quickMenuPage = QuickMenuPage.quickActions;
      } else if (type == 2) {
        Globals.quickMenuPage = QuickMenuPage.quickRun;
      } else {
        Globals.quickMenuPage = QuickMenuPage.quickMenu;
      }
      if (DateTime.now().millisecondsSinceEpoch - hidTime > 150) {
        Future<void>.delayed(const Duration(milliseconds: 100), () async {
          if (center) {
            await Win32.setCenter(useMouse: true);
          } else {
            await Win32.setMainWindowToMousePos();
          }
          for (final QuickMenuTriggers listener in listeners) {
            if (!_listeners.contains(listener)) return;
            await listener.onQuickMenuShown(type);
          }
        });
      } else {
        visible = false;
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      if (!kReleaseMode) return;
      Win32.setPosition(const Offset(-99999, -99999));

      // Win32.setPosition(const Offset(0, 0));
      hidTime = DateTime.now().millisecondsSinceEpoch;
    }
  }
}

enum TrktivityType { mouse, keys, window, title, idle }

class TrkFilterInfo {
  String title;
  String exe;
  String result;
  bool hasFilters;
  TrkFilterInfo({
    required this.title,
    required this.exe,
    required this.result,
    required this.hasFilters,
  });
}

class TrktivitySave {
  int ts = 0;
  String t = "";
  String d = "";
  int get timestamp => ts;
  String get type => t;
  String get data => d;
  set timestamp(int e) => ts = e;
  set type(String e) => t = e;
  set data(String e) => d = e;
  TrktivitySave({
    this.ts = 0,
    this.t = "",
    this.d = "",
  });

  TrktivitySave copyWith({
    int? ts,
    String? t,
    String? d,
  }) {
    return TrktivitySave(
      ts: ts ?? this.ts,
      t: t ?? this.t,
      d: d ?? this.d,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'ts': ts,
      't': t,
      'd': d,
    };
  }

  factory TrktivitySave.fromMap(Map<String, dynamic> map) {
    return TrktivitySave(
      ts: (map['ts'] ?? 0) as int,
      t: (map['t'] ?? '') as String,
      d: (map['d'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivitySave.fromJson(String source) => TrktivitySave.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'TrktivitySave(ts: $ts, t: $t, d: $d)';

  @override
  bool operator ==(covariant TrktivitySave other) {
    if (identical(this, other)) return true;

    return other.ts == ts && other.t == t && other.d == d;
  }

  @override
  int get hashCode => ts.hashCode ^ t.hashCode ^ d.hashCode;
}

class TrktivityData {
  String t;
  String e;
  String tl;
  String get type => t;
  String get exe => e;
  String get title => tl;
  set type(String e) => t = e;
  set exe(String e) => e = e;
  set title(String e) => tl = e;
  TrktivityData({
    required this.t,
    required this.e,
    required this.tl,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      't': t,
      'e': e,
      'tl': tl,
    };
  }

  factory TrktivityData.fromMap(Map<String, dynamic> map) {
    return TrktivityData(
      t: (map['t'] ?? '') as String,
      e: (map['e'] ?? '') as String,
      tl: (map['tl'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivityData.fromJson(String source) => TrktivityData.fromMap(json.decode(source) as Map<String, dynamic>);

  TrktivityData copyWith({
    String? t,
    String? e,
    String? tl,
  }) {
    return TrktivityData(
      t: t ?? this.t,
      e: e ?? this.e,
      tl: tl ?? this.tl,
    );
  }

  @override
  String toString() => 'TrktivityData(t: $t, e: $e, tl: $tl)';

  @override
  bool operator ==(covariant TrktivityData other) {
    if (identical(this, other)) return true;

    return other.t == t && other.e == e && other.tl == tl;
  }

  @override
  int get hashCode => t.hashCode ^ e.hashCode ^ tl.hashCode;
}

class Trktivity {
  List<TrktivityFilter> _filters = <TrktivityFilter>[];
  List<TrktivitySave> saved = <TrktivitySave>[];
  String folder = "${WinUtils.getTabameSettingsFolder()}\\trktivity";
  set filters(List<TrktivityFilter> list) => _filters = list;
  List<TrktivityFilter> get filters => _filters.isEmpty
      ? _filters = Boxes.getSavedMap<TrktivityFilter>(TrktivityFilter.fromJson, "trktivityFilter",
          def: <TrktivityFilter>[TrktivityFilter(exe: "code", titleSearch: r"([\w\. ]+\w)[\W ]+([\w ]+) [\W ]+Visual", titleReplace: r"$2 - $1")])
      : _filters;

  void add(TrktivityType type, String value) {
    if (type == TrktivityType.idle) {
      final String data = TrktivityData(e: "idle.exe", t: "w", tl: "Idle").toJson();
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "w", d: data));
    } else if (type == TrktivityType.title || type == TrktivityType.window) {
      final TrkFilterInfo filterInfo = fitlerTitle(int.tryParse(value) ?? 0);
      String title = "";
      if (filterInfo.hasFilters) {
        title = filterInfo.result;
      } else if (globalSettings.trktivitySaveAllTitles) {
        title = filterInfo.title;
      } else if (type == TrktivityType.title) {
        return;
      }
      final String data = TrktivityData(e: filterInfo.exe, t: type == TrktivityType.window ? "w" : "t", tl: title).toJson();
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "w", d: data));
    } else if (type == TrktivityType.keys) {
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "k", d: value));
    } else if (type == TrktivityType.mouse) {
      if (saved.length > 2) {
        if (saved.last.type == "m") {
          saved.last.data = ((int.tryParse(saved.last.data) ?? 0) + 1).toString();
          return;
        }
      }
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "m", d: "1"));
    }
    if (saved.length > 10) {
      WinUtils.getTabameSettingsFolder();
      final String date = DateFormat("yyyy-MM-dd").format(DateTime.now());
      String output = "";
      for (TrktivitySave tr in saved) {
        output += "${tr.toJson()}\n";
      }
      File("$folder\\$date.json").writeAsStringSync(output, mode: FileMode.append);
      saved.clear();
    }
  }

  TrkFilterInfo fitlerTitle(int hWnd) {
    if (!Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd).isEmpty) {
      return TrkFilterInfo(exe: "", hasFilters: false, result: "", title: "");
    }
    String title = Win32.getTitle(hWnd);
    final String exe = Win32.getExe(Win32.getWindowExePath(hWnd));
    String newtitle = title;
    bool hasFilters = false;
    for (TrktivityFilter filter in filters) {
      if (filter.titleReplace.isEmpty || filter.titleSearch.isEmpty) continue;
      if (!RegExp(filter.exe, caseSensitive: false).hasMatch(exe)) continue;
      final RegExpMatch? match = RegExp(filter.titleSearch, caseSensitive: false).firstMatch(title);
      if (match != null) {
        String newString = filter.titleReplace;
        for (int i = 1; i < match.groupCount + 1; i++) {
          newString = newString.replaceAll("\$$i", match[i]!);
        }
        newtitle = newString;
        hasFilters = true;
        break;
      }
    }
    return TrkFilterInfo(exe: exe, title: title, result: newtitle, hasFilters: hasFilters);
  }
}

class PredefinedSizes {
  String name;
  int width;
  int height;
  int x;
  int y;
  PredefinedSizes({
    required this.name,
    required this.width,
    required this.height,
    required this.x,
    required this.y,
  });

  PredefinedSizes copyWith({
    String? name,
    int? width,
    int? height,
    int? x,
    int? y,
  }) {
    return PredefinedSizes(
      name: name ?? this.name,
      width: width ?? this.width,
      height: height ?? this.height,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'width': width,
      'height': height,
      'x': x,
      'y': y,
    };
  }

  factory PredefinedSizes.fromMap(Map<String, dynamic> map) {
    return PredefinedSizes(
      name: (map['name'] ?? '') as String,
      width: (map['width'] ?? 0) as int,
      height: (map['height'] ?? 0) as int,
      x: (map['x'] ?? 0) as int,
      y: (map['y'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory PredefinedSizes.fromJson(String source) => PredefinedSizes.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'PredefinedSizes(name: $name, width: $width, height: $height, x: $x, y: $y)';
  }

  @override
  bool operator ==(covariant PredefinedSizes other) {
    if (identical(this, other)) return true;

    return other.name == name && other.width == width && other.height == height && other.x == x && other.y == y;
  }

  @override
  int get hashCode {
    return name.hashCode ^ width.hashCode ^ height.hashCode ^ x.hashCode ^ y.hashCode;
  }
}

class QuickActions {
  String name;
  String type;
  String value;
  QuickActions({
    required this.name,
    required this.type,
    required this.value,
  });

  QuickActions copyWith({
    String? name,
    String? type,
    String? value,
  }) {
    return QuickActions(
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'type': type,
      'value': value,
    };
  }

  factory QuickActions.fromMap(Map<String, dynamic> map) {
    return QuickActions(
      name: (map['name'] ?? '') as String,
      type: (map['type'] ?? '') as String,
      value: (map['value'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory QuickActions.fromJson(String source) => QuickActions.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'QuickActions(name: $name, type: $type, value: $value)';

  @override
  bool operator ==(covariant QuickActions other) {
    if (identical(this, other)) return true;

    return other.name == name && other.type == type && other.value == value;
  }

  @override
  int get hashCode => name.hashCode ^ type.hashCode ^ value.hashCode;
}
