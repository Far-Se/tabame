// ignore_for_file: public_member_api_docs, sort_constructors_first
/// [flutter pub run build_runner build]
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'globals.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

extension Truncate on String {
  String truncate(int max, {String suffix = ''}) => length < max ? this : replaceRange(max, null, suffix);
}

extension StringExtension on String {
  String capitalize() {
    if (length < 2) return this;
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}

enum TaskBarAppsStyle { onlyActiveMonitor, activeMonitorFirst, orderByActivity }

enum VolumeOSDStyle { normal, media, visible, thin }

@HiveType(typeId: 0)
class Settings {
  bool runOnStartup = true;
  bool autoHideTaskbar = true;
  TaskBarAppsStyle taskBarAppsStyle = TaskBarAppsStyle.activeMonitorFirst;
  String language = 'en';
  String weather = '10 C';
  String weatherCity = 'Iasi';
  bool showQuickMenuAtTaskbarLevel = true;
  VolumeOSDStyle volumeOSD = VolumeOSDStyle.normal;
}

Settings globalSettings = Settings();

late Timer monitorChecker;
Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Main Handle
  Monitor.fetchMonitor();
  monitorChecker = Timer.periodic(const Duration(seconds: 5), (Timer timer) => Monitor.fetchMonitor());
  await Boxes.registerBoxes();
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
      await setStartOnSystemStartup(true);
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
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await prefs.setStringList("pinnedApps", pinnedApps2);
    }
    if (kReleaseMode) {
      if (globalSettings.autoHideTaskbar) {
        WinUtils.toggleTaskbar(visible: true);
      }
    }
    globalSettings.volumeOSD = VolumeOSDStyle.media;
    if (globalSettings.volumeOSD != VolumeOSDStyle.normal) {
      WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSD, applyStyle: true);
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
