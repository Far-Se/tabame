// ignore_for_file: public_member_api_docs, sort_constructors_first
/// [flutter pub run build_runner build]
import 'package:hive/hive.dart';

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
