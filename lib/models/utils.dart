// ignore_for_file: public_member_api_docs, sort_constructors_first
/// [flutter pub run build_runner build]
import 'package:hive/hive.dart';

part 'utils.g.dart';

extension Truncate on String {
  String truncate(int max, {suffix = ''}) => length < max ? this : replaceRange(max, null, suffix);
}

enum TaskBarAppsStyle { onlyActiveMonitor, activeMonitorFirst, orderByActivity }

enum VolumeOSDStyle { normal, media, visible, thin }

@HiveType(typeId: 0)
class Settings {
  @HiveField(0, defaultValue: true)
  bool runOnStartup = true;

  @HiveField(1, defaultValue: true)
  bool autoHideTaskbar = true;

  @HiveField(2, defaultValue: "activeMonitorFirst")
  String taskBarAppsStyle = "activeMonitorFirst";

  @HiveField(3, defaultValue: '')
  String taskbarRenames = "";

  @HiveField(4, defaultValue: false)
  bool fullScreenModeBlackWallpaper = false;

  @HiveField(5, defaultValue: false)
  bool fullScreenModeShowTaskbar = false;

  @HiveField(6, defaultValue: 'en')
  String language = 'en';

  @HiveField(7, defaultValue: "normal")
  String volumeOSDStyle = 'normal';
  TaskBarAppsStyle get taskBarStyle => TaskBarAppsStyle.values.firstWhere((e) => e.name == taskBarAppsStyle);
  set taskBarStyle(TaskBarAppsStyle value) => taskBarAppsStyle = value.name;
}

Settings globalSettings = Settings();

@HiveType(typeId: 1)
class Projects {
  @HiveField(0)
  String name;

  @HiveField(1)
  String execution;

  @HiveField(2)
  String icon;
  Projects({
    required this.name,
    required this.execution,
    required this.icon,
  });
}

@HiveType(typeId: 2)
class RemapKeys {
  @HiveField(0)
  String from;
  @HiveField(1)
  String to;
  RemapKeys({
    required this.from,
    required this.to,
  });
}

@HiveType(typeId: 3)
class Hotkeys {
  @HiveField(0)
  String name;
  @HiveField(1)
  String key;
  @HiveField(2)
  String action;
  @HiveField(3)
  String description;
  Hotkeys({
    required this.name,
    required this.key,
    required this.action,
    required this.description,
  });
}

@HiveType(typeId: 4)
class RunSettings {
  @HiveField(0)
  String type;
  @HiveField(1)
  String shortcut;
  RunSettings({
    required this.type,
    required this.shortcut,
  });
}

@HiveType(typeId: 5)
class RunShortcuts {
  @HiveField(0)
  String key;
  @HiveField(1)
  String shortcut;
  RunShortcuts({
    required this.key,
    required this.shortcut,
  });
}

@HiveType(typeId: 6)
class RunApi {
  @HiveField(0)
  String key;
  @HiveField(1)
  String api;
  RunApi({
    required this.key,
    required this.api,
  });
}

//? mixed classes

class MapStringInt {
  String? key;
  int? value;
}

class MapIntString {
  int? key;
  String? value;
}

class MapStringString {
  String? key;
  String? value;
}

class MapStringMapStringString {
  String? key;
  Map<String, dynamic>? value;
}
