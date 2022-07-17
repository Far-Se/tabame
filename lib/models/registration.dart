import 'dart:async';
import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'boxes.dart';
import 'globals.dart';
import 'utils.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

late Timer monitorChecker;
Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Main Handle
  Monitor.fetchMonitor();
  monitorChecker = Timer.periodic(const Duration(seconds: 5), (Timer timer) => Monitor.fetchMonitor());
  await Boxes.registerBoxes();

  globalSettings.volumeOSD = VolumeOSDStyle.media;
  if (globalSettings.volumeOSD != VolumeOSDStyle.normal) {
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSD, applyStyle: true);
  }
  if (!Directory(Globals.iconCachePath).existsSync()) Directory(Globals.iconCachePath).createSync(recursive: true);
}

unregisterAll() {
  monitorChecker.cancel();
}

class Boxes {
  static List<String> pinnedApps = <String>[];
  static Future<void> registerBoxes() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    //? Settings
    if (prefs.getString("language") == null) {
      await prefs.setBool("runOnStartup", true);
      await prefs.setBool("autoHideTaskbar", false);
      await prefs.setBool("showQuickMenuAtTaskbarLevel", true);
      await prefs.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await prefs.setString("language", "en");
      await prefs.setString("weather", "10 C");
      await prefs.setString("weatherCity", "berlin");
      await prefs.setInt("volumeOSD", VolumeOSDStyle.normal.index);
    }
    globalSettings
      ..runOnStartup = prefs.getBool("runOnStartup") ?? true
      ..autoHideTaskbar = prefs.getBool("autoHideTaskbar") ?? false
      ..taskBarAppsStyle = TaskBarAppsStyle.values[prefs.getInt("taskBarAppsStyle") ?? 0]
      ..language = prefs.getString("language") ?? "en"
      ..weather = prefs.getString("weather") ?? "10 C"
      ..weatherCity = prefs.getString("weatherCity") ?? "berlin"
      ..volumeOSD = VolumeOSDStyle.values[prefs.getInt("volumeOSD") ?? 0]
      ..showQuickMenuAtTaskbarLevel = prefs.getBool("showQuickMenuAtTaskbarLevel") ?? true;

    //? Pinned Apps
    if (prefs.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskbarLocation = WinUtils.getTaskManagerPath();
      if (taskbarLocation != "") pinnedApps2.add(taskbarLocation);
      prefs.setStringList("pinnedApps", pinnedApps2);
    }
    pinnedApps = prefs.getStringList("pinnedApps") ?? <String>[];
  }

  static Future<void> updateSettings(String key, dynamic value, PTYPE type) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (type == PTYPE.boolT) await prefs.setBool(key, value);
    if (type == PTYPE.intT) await prefs.setInt(key, value);
    if (type == PTYPE.stringT) await prefs.setString(key, value);
    if (type == PTYPE.stringListT) await prefs.setStringList(key, value);
  }
}

enum PTYPE { boolT, intT, stringT, stringListT }
