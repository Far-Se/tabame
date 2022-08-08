import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import 'hotkeys.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../../main.dart';
import '../settings.dart';
import 'save_settings.dart';
import 'saved_maps.dart';
import 'package:http/http.dart' as http;

import '../win32/win32.dart';

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

    // await pref.remove("projects");
    // pref = await SaveSettings.getInstance();
    //? Settings
    if (pref.getString("language") == null) {
      await pref.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await pref.setInt("volumeOSDStyle", VolumeOSDStyle.normal.index);

      await pref.setInt("themeType", ThemeType.system.index);
      await pref.setString("lightTheme", globalSettings.lightTheme.toJson());
      await pref.setString("darkTheme", globalSettings.darkTheme.toJson());

      await pref.setString("language", Platform.localeName.substring(0, 2));

      String city = await WinUtils.getCountryCityFromIP("berlin, germany");
      await pref.setStringList("weather", <String>["10 C", city, "m", "%c+%t"]);
      await pref.setBool("hideTaskbarOnStartup", false);
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setBool("showMediaControlForApp", true);
      await pref.setBool("showTrayBar", true);
      await pref.setBool("showWeather", true);
      await pref.setBool("showPowerShell", true);
      await pref.setBool("showSystemUsage", false);
      await pref.setBool("runAsAdministrator", false);
      await pref.setBool("hideTabameOnUnfocus", true);
      final Reminder demoReminder = Reminder(
          enabled: false,
          interval: <int>[540, 1200],
          message: "Stretch",
          repetitive: true,
          time: 60,
          voiceNotification: true,
          weekDays: <bool>[true, true, true, true, true, false, false],
          voiceVolume: 100);
      await pref.setString("reminders", jsonEncode(<Reminder>[demoReminder]));
      await setStartOnSystemStartup(true);
      pref = await SaveSettings.getInstance();
    }
    globalSettings
      ..hideTaskbarOnStartup = pref.getBool("hideTaskbarOnStartup") ?? false
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..themeScheduleMin = pref.getInt("themeScheduleMin") ?? globalSettings.themeScheduleMin
      ..themeScheduleMax = pref.getInt("themeScheduleMax") ?? globalSettings.themeScheduleMax
      ..themeType = ThemeType.values[pref.getInt("themeType") ?? 0] // * always after schedule
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
      ..usePowerShellAsToastNotification = pref.getBool("usePowerShellAsToastNotification") ?? false
      ..showSystemUsage = pref.getBool("showSystemUsage") ?? false
      ..hideTabameOnUnfocus = pref.getBool("hideTabameOnUnfocus") ?? globalSettings.hideTabameOnUnfocus
      ..trktivityEnabled = pref.getBool("trktivityEnabled") ?? globalSettings.trktivityEnabled;

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

    //? Pinned Apps
    if (pref.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await pref.setStringList("pinnedApps", pinnedApps2);
    }

    //?PowerShell
    if (pref.getString("powerShellScripts") == null) {
      final List<String> powerShellScripts = <String>[
        PowerShellScript(name: "🏠Show IP", command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content", showTerminal: true).toJson()
      ];
      await pref.setString("powerShellScripts", jsonEncode(powerShellScripts));
    }

    //? Media Controls
    mediaControls = pref.getStringList("mediaControls") ?? <String>["Spotify.exe", "chrome.exe", "firefox.exe", "Music.UI.exe"];
    //? Run Shortcuts
    globalSettings.run.fetch();
    //! Startup
    //? Taskbar
    //if (kReleaseMode) {
    if (globalSettings.page == TPage.quickmenu) {
      if (globalSettings.hideTaskbarOnStartup) {
        WinUtils.toggleTaskbar(visible: false);
      }

      //? Volume
      globalSettings.volumeOSDStyle = VolumeOSDStyle.media;
      if (globalSettings.volumeOSDStyle != VolumeOSDStyle.normal) {
        WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
      }
    }
    if (globalSettings.page == TPage.quickmenu) {
      if (pageWatchers.where((PageWatcher element) => element.enabled).isNotEmpty) Tasks().startPageWatchers();
      if (reminders.where((Reminder element) => element.enabled).isNotEmpty) Tasks().startReminders();
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
      throw ("No asociated type $value");
    }
    pref = await SaveSettings.getInstance();
  }

  static List<T> getSavedMap<T>(T Function(String json) fromJson, String key) {
    final String savedString = pref.getString(key) ?? "";
    if (savedString.isEmpty) return <T>[];
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
    if (prefString.isEmpty) return _runShortcuts;
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
    if (prefString.isEmpty) {
      return <List<String>>[
        <String>["g", "https://github.com/search?q={params}"]
      ];
    }
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
    List<String> defaultWidgets = <String>[
      "TaskManagerButton",
      "VirtualDesktopButton",
      "ToggleTaskbarButton",
      "PinWindowButton",
      "MicMuteButton",
      "AlwaysAwakeButton",
      "SpotifyButton",
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
    return topBarWidgets;
  }

  List<String> get pinnedApps => pref.getStringList("pinnedApps") ?? <String>[];
  List<PowerShellScript> get powerShellScripts => getSavedMap<PowerShellScript>(PowerShellScript.fromJson, "powerShellScripts");
  List<ProjectGroup> get projects => getSavedMap<ProjectGroup>(ProjectGroup.fromJson, "projects");

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

  void watchForSettingsChange() {
    globalSettings.previewTheme = true;
    String savedFileText = File(Boxes.pref.fileName).readAsStringSync();
    bool updating = false;
    Timer.periodic(const Duration(milliseconds: 100), (Timer timer) async {
      if (updating) return;
      final String x = File(Boxes.pref.fileName).readAsStringSync();
      if (savedFileText != x) {
        updating = true;
        savedFileText = x;
        await Boxes.registerBoxes(reload: true);
        updating = false;
        final String prevThemeLight = Boxes.pref.getString("previewThemeLight") ?? "";
        if (prevThemeLight.isNotEmpty) {
          globalSettings.lightTheme = ThemeColors.fromJson(prevThemeLight);
        }
        final String prevThemeDark = Boxes.pref.getString("previewThemeDark") ?? "";
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
    });
    quickTimers.add(quick);
  }
}

class QuickTimer {
  String name = "";
  Timer? timer;
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
    if (now.isBetweenEqual(reminder.interval[0], reminder.interval[1]) && reminder.weekDays[DateTime.now().weekday - 1]) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech('${reminder.message}', repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: ${reminder.message}", onClick: () {});
      }
    }
    reminder.timer = Timer(Duration(minutes: reminder.time), () => reminderPeriodic(reminder));
  }

  reminderDaily(Reminder reminder) {
    if (!reminder.enabled) return;
    if (reminder.weekDays[DateTime.now().weekday - 1]) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech('${reminder.message}', repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: ${reminder.message}", onClick: () {});
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
    NativeHotkey.run(allHotkeys);
  }
}

abstract class QuickMenuTriggers {
  void onQuickMenuToggled(bool visible, int type) {}
}

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static int hidTime = 0;

  static final ObserverList<QuickMenuTriggers> _listeners = ObserverList<QuickMenuTriggers>();
  static List<QuickMenuTriggers> get listeners => List<QuickMenuTriggers>.from(_listeners);

  static bool get hasListeners {
    return _listeners.isNotEmpty;
  }

  /// Add EventListener to the list of listeners.
  static void addListener(QuickMenuTriggers listener) {
    _listeners.add(listener);
  }

  static void removeListener(QuickMenuTriggers listener) {
    _listeners.remove(listener);
  }

  static Future<void> toggleQuickMenu({int type = 0, bool? visible, bool center = false}) async {
    visible ??= !isQuickMenuVisible;
    if (visible) {
      if (DateTime.now().millisecondsSinceEpoch - hidTime > 150) {
        if (center) {
          await Win32.setCenter(useMouse: true);
        } else {
          await Win32.setMainWindowToMousePos();
        }
      } else {
        visible = false;
      }
    } else {
      Win32.setPosition(const Offset(-99999, -99999));
      hidTime = DateTime.now().millisecondsSinceEpoch;
    }
    isQuickMenuVisible = visible;
    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) return;
      listener.onQuickMenuToggled(visible, type);
    }
  }
}
