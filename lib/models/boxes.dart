import 'package:hive_flutter/hive_flutter.dart';
import 'utils.dart';

class Boxes {
  static late Box settings;
  static late Box remapKeys;
  static late Box hotkeys;
  static late Box projects;
  static late Box runSettings;
  static late Box shortcuts;
  static late Box runApi;
  static late Box traySettings;

  static Future<void> registerBoxes() async {
    await Hive.initFlutter('./.tabame');
    Hive.registerAdapter(SettingsAdapter());
    Hive.registerAdapter(RemapKeysAdapter());
    Hive.registerAdapter(HotkeysAdapter());
    Hive.registerAdapter(ProjectsAdapter());
    Hive.registerAdapter(RunSettingsAdapter());
    Hive.registerAdapter(RunShortcutsAdapter());
    Hive.registerAdapter(RunApiAdapter());
    Hive.registerAdapter(TraySettingsAdapter());

    await Hive.openBox('settings');
    Boxes.settings = Hive.box('settings');

    await Hive.openBox('remapKeys');
    Boxes.remapKeys = Hive.box('remapKeys');

    await Hive.openBox('hotkeys');
    Boxes.hotkeys = Hive.box('hotkeys');

    await Hive.openBox('projects');
    Boxes.projects = Hive.box('projects');

    await Hive.openBox('runSettings');
    Boxes.runSettings = Hive.box('runSettings');

    await Hive.openBox('shortcuts');
    Boxes.shortcuts = Hive.box('shortcuts');

    await Hive.openBox('runApi');
    Boxes.runApi = Hive.box('runApi');

    await Hive.openBox('traySettings');
    Boxes.traySettings = Hive.box('traySettings');
  }
}
