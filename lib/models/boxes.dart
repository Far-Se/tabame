import 'package:shared_preferences/shared_preferences.dart';
import 'utils.dart';
import 'win32/win32.dart';

/// [flutter pub run build_runner build]

class Boxes {
  static List<String> pinnedApps = <String>[];
  static Future<void> registerBoxes() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    //? Settings
    if (prefs.getString("language") == null) {
      await prefs.setBool("runOnStartup", true);
      await prefs.setBool("autoHideTaskbar", false);
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
      ..volumeOSD = VolumeOSDStyle.values[prefs.getInt("volumeOSD") ?? 0];

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
