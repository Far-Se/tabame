import 'package:hive_flutter/hive_flutter.dart';
import 'utils.dart';
import 'win32/win32.dart';

/// [flutter pub run build_runner build]

class Boxes {
  static late Box<Settings> settings;
  static late Box remapKeys;
  static late Box hotkeys;
  static late Box projects;
  static late Box runSettings;
  static late Box shortcuts;
  static late Box runApi;
  // static late Box traySettings;
  static late Box<Map<int, dynamic>> keyObject;

  static late Box<List> lists;

  static Future<void> registerBoxes() async {
    await Hive.initFlutter('./.tabame');
    Hive.registerAdapter(SettingsAdapter());

    await Hive.openBox<Settings>('settings');
    Boxes.settings = Hive.box<Settings>('settings');
    Boxes.settings.compact();

    await Hive.openBox<Map<int, dynamic>>('objects');
    Boxes.keyObject = Hive.box<Map<int, dynamic>>('objects');
    Boxes.keyObject.compact();

    await Hive.openBox<List<dynamic>>('lists');
    Boxes.lists = Hive.box<List<dynamic>>('lists');
    Boxes.lists.compact();

    await initiateData();
  }

  static Future initiateData() async {
    if (!Boxes.settings.containsKey('settings')) {
      await Boxes.settings.put('settings', globalSettings);
    }
    globalSettings = Boxes.settings.get('settings') ?? globalSettings;

    if (!Boxes.lists.containsKey('pinned')) {
      final pinnedApps = await WinUtils.getTaskbarPinnedApps();
      final taskbarLocation = WinUtils.getTaskManagerPath();
      if (taskbarLocation != "") pinnedApps.add(taskbarLocation);
      Boxes.lists.put("pinned", pinnedApps);
    }
  }
}
