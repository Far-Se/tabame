import 'package:hive_flutter/hive_flutter.dart';
import 'utils.dart';

class Boxes {
  static late Box settings;
  static late Box remapKeys;
  static late Box hotkeys;
  static late Box runSettings;
  static late Box shortcuts;
  static late Box runApi;

  static Future<void> registerBoxes() async {
    await Hive.initFlutter('./.tabame');
    Hive.registerAdapter(SettingsAdapter());
    Hive.registerAdapter(RemapKeysAdapter());
    Hive.registerAdapter(ProjectsAdapter());
    Hive.registerAdapter(HotkeysAdapter());
    Hive.registerAdapter(RunSettingsAdapter());
    Hive.registerAdapter(RunShortcutsAdapter());
    Hive.registerAdapter(RunApiAdapter());
    Boxes.settings = await Hive.openBox('settings');
    Boxes.settings.get('settings') ?? Boxes.settings.put('settings', Settings());

    Boxes.remapKeys = await Hive.openBox('remapKeys');
    Boxes.hotkeys = await Hive.openBox('hotkeys');
    Boxes.runSettings = await Hive.openBox('runSettings');
    Boxes.shortcuts = await Hive.openBox('shortcuts');
    Boxes.runApi = await Hive.openBox('runApi');
  }
}
