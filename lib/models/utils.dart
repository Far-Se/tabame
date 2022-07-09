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

  @HiveField(6, defaultValue: 'en')
  String language = 'en';

  @HiveField(7)
  final maps = <String, dynamic>{};

  @HiveField(8, defaultValue: "normal")
  String weather = '10 C';

  @HiveField(9, defaultValue: "berlin")
  String weatherCity = '10 C';

  TaskBarAppsStyle get taskBarStyle => TaskBarAppsStyle.values.firstWhere((e) => e.name == taskBarAppsStyle);
  set taskBarStyle(TaskBarAppsStyle value) => taskBarAppsStyle = value.name;

  VolumeOSDStyle get volumeOSD => VolumeOSDStyle.values.firstWhere((e) => e.index == (maps["volumeOSD"] ?? 0));
  set volumeOSD(VolumeOSDStyle value) => maps["volumeOSD"] = value.index;
}

Settings globalSettings = Settings();
