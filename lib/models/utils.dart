// ignore_for_file: public_member_api_docs, sort_constructors_first
/// [flutter pub run build_runner build]
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tabamewin32/tabamewin32.dart';

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

num darkerColor(int color, {int darkenBy = 0x10, int floor = 0x0}) {
  final num darkerHex = (max((color >> 16) - darkenBy, floor) << 16) + (max(((color & 0xff00) >> 8) - darkenBy, floor) << 8) + max(((color & 0xff) - darkenBy), floor);
  return darkerHex;
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
  // static List<String> pinnedApps = <String>[];
  static late SharedPreferences pref;
  static List<String> mediaControls = <String>[];
  Boxes();
  static Future<void> registerBoxes() async {
    pref = await SharedPreferences.getInstance();
    //? Settings
    if (pref.getString("language") == null) {
      await pref.setBool("runOnStartup", true);
      await pref.setBool("autoHideTaskbar", false);
      await pref.setBool("showQuickMenuAtTaskbarLevel", true);
      await pref.setInt("taskBarAppsStyle", TaskBarAppsStyle.activeMonitorFirst.index);
      await pref.setString("language", "en");
      await pref.setString("weather", "10 C");
      await pref.setString("weatherCity", "berlin, germany");
      await pref.setInt("volumeOSD", VolumeOSDStyle.normal.index);
      await setStartOnSystemStartup(true);
    }
    globalSettings
      ..runOnStartup = pref.getBool("runOnStartup") ?? true
      ..autoHideTaskbar = pref.getBool("autoHideTaskbar") ?? false
      ..taskBarAppsStyle = TaskBarAppsStyle.values[pref.getInt("taskBarAppsStyle") ?? 0]
      ..language = pref.getString("language") ?? "en"
      ..weather = pref.getString("weather") ?? "10 C"
      ..weatherCity = pref.getString("weatherCity") ?? "berlin"
      ..volumeOSD = VolumeOSDStyle.values[pref.getInt("volumeOSD") ?? 0]
      ..showQuickMenuAtTaskbarLevel = pref.getBool("showQuickMenuAtTaskbarLevel") ?? true;

    //? Pinned Apps
    if (pref.getStringList("pinnedApps") == null) {
      final List<String> pinnedApps2 = await WinUtils.getTaskbarPinnedApps();
      final String taskManagerPath = WinUtils.getTaskManagerPath();
      if (taskManagerPath != "") pinnedApps2.add(taskManagerPath);
      await pref.setStringList("pinnedApps", pinnedApps2);
    }
    if (pref.getStringList("powerShellScripts") == null) {
      final List<String> powerShellScripts = <String>[
        PowerShellScript(name: "Show IP", command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content", showTerminal: true).toJson()
      ];
      await pref.setStringList("powerShellScripts", powerShellScripts);
    }
    //? Taskbar
    if (kReleaseMode) {
      if (globalSettings.autoHideTaskbar) {
        WinUtils.toggleTaskbar(visible: true);
      }
    }
    //? Volume
    globalSettings.volumeOSD = VolumeOSDStyle.media;
    if (globalSettings.volumeOSD != VolumeOSDStyle.normal) {
      WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSD, applyStyle: true);
    }
    //? Media Controls
    mediaControls = pref.getStringList("mediaControls") ?? <String>["Spotify.exe", "chrome.exe", "firefox.exe", "Music.UI.exe"];
  }

  List<String> getPinnedApps() {
    return pref.getStringList("pinnedApps") ?? <String>[];
  }

  /*
  PowerShellScript(name: "Open AI", command: "Import-Module \"E:\\Playground\\Scripts\\openai.ps1\"", showTerminal: true).toJson(),
  PowerShellScript(name: "Show IP", command: "(Invoke-WebRequest -uri \"http://ifconfig.me/ip\").Content", showTerminal: true).toJson(),
  PowerShellScript(name: "Clear Temp", command: "E:\\Playground\\Scripts\\tempRemove.ps1", showTerminal: false, disabled: true).toJson(),
  */
  List<PowerShellScript> getPowerShellScripts() {
    final List<String> scriptsString = pref.getStringList("powerShellScripts") ?? <String>[];
    if (scriptsString.isEmpty) return <PowerShellScript>[];
    final List<PowerShellScript> scripts = <PowerShellScript>[];
    for (String script in scriptsString) {
      scripts.add(PowerShellScript.fromJson(script));
    }
    return scripts;
  }

  static Future<void> updateSettings(String key, dynamic value, PTYPE type) async {
    if (type == PTYPE.boolT) await pref.setBool(key, value);
    if (type == PTYPE.intT) await pref.setInt(key, value);
    if (type == PTYPE.stringT) await pref.setString(key, value);
    if (type == PTYPE.stringListT) await pref.setStringList(key, value);
    pref = await SharedPreferences.getInstance();
  }
}

class PowerShellScript {
  String command;
  String name;
  bool showTerminal;
  bool disabled = false;
  PowerShellScript({
    required this.command,
    required this.name,
    required this.showTerminal,
    this.disabled = false,
  });

  PowerShellScript copyWith({
    String? command,
    String? name,
    bool? showTerminal,
    bool? disabled,
  }) {
    return PowerShellScript(
      command: command ?? this.command,
      name: name ?? this.name,
      showTerminal: showTerminal ?? this.showTerminal,
      disabled: disabled ?? this.disabled,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'command': command,
      'name': name,
      'showTerminal': showTerminal,
      'disabled': disabled,
    };
  }

  factory PowerShellScript.fromMap(Map<String, dynamic> map) {
    return PowerShellScript(
      command: map['command'] as String,
      name: map['name'] as String,
      showTerminal: map['showTerminal'] as bool,
      disabled: map['disabled'] as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory PowerShellScript.fromJson(String source) => PowerShellScript.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'PowerShellScript(command: $command, name: $name, showTerminal: $showTerminal, disabled: $disabled)';
  }

  @override
  bool operator ==(covariant PowerShellScript other) {
    if (identical(this, other)) return true;

    return other.command == command && other.name == name && other.showTerminal == showTerminal && other.disabled == disabled;
  }

  @override
  int get hashCode {
    return command.hashCode ^ name.hashCode ^ showTerminal.hashCode ^ disabled.hashCode;
  }
}

enum PTYPE { boolT, intT, stringT, stringListT }
