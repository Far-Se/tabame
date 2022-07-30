import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      String city = "berlin, germany";
      // ? Get city from IP
      final http.Response ip = await http.get(Uri.parse("http://ifconfig.me/ip"));
      if (ip.statusCode == 200) {
        final http.Response response = await http.get(Uri.parse("http://ip-api.com/json/${ip.body}"));
        if (response.statusCode == 200) {
          final Map<String, dynamic> data = json.decode(response.body);
          if (data.containsKey("city") && data.containsKey("country")) {
            city = "${data["city"]}, ${data["country"]}";
          }
        }
      }
      await pref.setStringList("weather", <String>["10 C", city, "m", "%c+%t"]);
      await pref.setBool("hideTaskbarOnStartup", false);
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setBool("showMediaControlForApp", true);
      await pref.setBool("showTrayBar", true);
      await pref.setBool("showWeather", true);
      await pref.setBool("showPowerShell", true);
      await pref.setBool("showSystemUsage", false);
      await pref.setBool("runAsAdministrator", false);
      final Reminder demoReminder = Reminder(
          enabled: false,
          interval: <int>[540, 1200],
          message: "Strech",
          repetitive: true,
          time: 60,
          voiceNotification: true,
          weekDays: <bool>[true, true, true, true, true, false, false]);
      await pref.setString("reminders", jsonEncode(<Reminder>[demoReminder]));
      await setStartOnSystemStartup(true);
      pref = await SaveSettings.getInstance();
    }
    globalSettings
      ..hideTaskbarOnStartup = pref.getBool("hideTaskbarOnStartup") ?? false
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..themeScheduleMin = pref.getInt("themeScheduleMin") ?? 0
      ..themeScheduleMax = pref.getInt("themeScheduleMax") ?? 0
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
      ..showSystemUsage = pref.getBool("showSystemUsage") ?? false;

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

    //! Startup
    //? Taskbar
    //if (kReleaseMode) {
    if (globalSettings.args.isEmpty) {
      if (globalSettings.hideTaskbarOnStartup) {
        WinUtils.toggleTaskbar(visible: false);
      }

      //? Volume
      globalSettings.volumeOSDStyle = VolumeOSDStyle.media;
      if (globalSettings.volumeOSDStyle != VolumeOSDStyle.normal) {
        WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
      }
    }
    if (globalSettings.args.isEmpty || globalSettings.args.contains("-restarted")) {
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
    if (rewrites == "") return <String, String>{"DevTools.*?\\.(.*?)\\..*?\$": "⚠DevTools: \$1 "};
    final Map<String, String> rewritesMap = Map<String, String>.from(json.decode(rewrites));
    return rewritesMap;
  }

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
        <String>["p", "{MEDIA_PREVIOUS_TRACK}"]
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
          File(r"E:\l.txt").writeAsString("changed prev theme for light", mode: FileMode.append);
        }
        final String prevThemeDark = Boxes.pref.getString("previewThemeDark") ?? "";
        if (prevThemeDark.isNotEmpty) {
          globalSettings.darkTheme = ThemeColors.fromJson(prevThemeDark);
          File(r"E:\l.txt").writeAsString("changed prev theme for dark", mode: FileMode.append);
        }
        globalSettings.settingsChanged = !globalSettings.settingsChanged;
      }
    });
  }
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
      if (!exp.hasMatch(response.body)) return "";

      final RegExpMatch match = exp.firstMatch(response.body)!;
      return match.group(0)!;
    }
    return "";
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
    if (now.isBetweenEqual(reminder.interval[0], reminder.interval[1]) && reminder.weekDays[DateTime.now().weekday]) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech('${reminder.message}', repeat: -1);
      } else {
        WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: ${reminder.message}", onClick: () {});
      }
    }
    reminder.timer = Timer(Duration(minutes: reminder.time), () => reminderPeriodic(reminder));
  }

  reminderDaily(Reminder reminder) {
    if (!reminder.enabled) return;
    if (reminder.voiceNotification) {
      WinUtils.textToSpeech('${reminder.message}', repeat: -1);
    } else {
      WinUtils.showWindowsNotification(title: "Tabame Reminder", body: "Reminder: ${reminder.message}", onClick: () {});
    }
    reminder.timer = Timer(const Duration(days: 1), () => reminderDaily(reminder));
  }
}