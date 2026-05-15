import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import 'error_handler.dart';

class AppStartup {
  static Future<void> initialize() async {
    Debug.register(clean: true);
    if (File("${WinUtils.getTabameAppDataFolder()}\\enable_debug.txt").existsSync()) {
      Debug.register(clean: false);
    }
    if (File("${WinUtils.getTabameAppDataFolder()}\\disable_audio.txt").existsSync()) {
      Audio.alreadySet = true;
      Audio.canRunAudioModule = false;
    }

    Debug.add("===");
    Debug.add("Started");
    WidgetsFlutterBinding.ensureInitialized();
    Debug.add("Register WindowManager");
    await windowManager.ensureInitialized();
    if (kReleaseMode) {
      FlutterError.onError = handleErrors;
      PlatformDispatcher.instance.onError = handlePlatformErrors;
    }
  }

  static void parseArguments(List<String> arguments2) {
    List<String> arguments = <String>[...arguments2];
    if (arguments.isNotEmpty) {
      if (arguments[0].endsWith('"') && !arguments[0].startsWith('"')) arguments[0] = '"${arguments[0]}';
      String argString = arguments.join(" ");
      userSettings.args = <String>[...arguments];
      if (argString.contains("interface")) {
        userSettings.page = TPage.interface;
      }
    }
    Debug.add("Parsed arguments ${userSettings.page}");
  }

  static Future<void> registerServices() async {
    await registerAll();
    if (File("${WinUtils.getTabameAppDataFolder()}\\enable_debug.txt").existsSync()) {
      Debug.methodDebug(clean: true);
    }
    Debug.add("Registered All");
  }

  static Future<bool> checkAdminAndRestart() async {
    if (kReleaseMode &&
        userSettings.runAsAdministrator &&
        !WinUtils.isAdministrator() &&
        !userSettings.args.join(' ').contains('-tryadmin')) {
      Debug.add("Trying Admin");
      userSettings.args.add('-tryadmin');
      WinUtils.closeAllTabameExProcesses();
      Debug.add("Closed all tabame processed");
      WinUtils.runAsAdmin(Platform.resolvedExecutable, arguments: '"${userSettings.args.join('" "')}"');
      Debug.add("Started New");
      Timer(const Duration(seconds: 1), () {
        Debug.add("Started Close Current");
        exit(0);
      });
      return true;
    }
    if (userSettings.args.contains("-restarted")) {
      Future<void>.delayed(const Duration(seconds: 2), () => WinUtils.closeAllTabameExProcesses());
    }
    return false;
  }

  static void registerHooks() {
    if (Globals.debugHooks || kReleaseMode) {
      Debug.add("Registering Hooks");
      if (userSettings.args.contains("-interface") && Boxes.remap.isEmpty) {
        NativeHooks.registerCallHandler();
      } else {
        NativeHooks.registerCallHandler();
      }
    }
  }

  static Future<void> setupWindow(List<String> arguments) async {
    late WindowOptions windowOptions;
    if (userSettings.args.contains("-interface") || Boxes.remap.isEmpty) {
      late String title;
      if (userSettings.args.contains("-wizardly")) {
        title = "Wizardly";
      } else if (userSettings.args.contains("-fancyshot")) {
        title = "Fancyshot";
      } else {
        title = "Interface";
      }
      windowOptions = WindowOptions(
        size: const Size(980, 600),
        center: false,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        alwaysOnTop: false,
        title: "Tabame - $title",
      );
    } else {
      final double size = Boxes.quickMenuWidth;
      windowOptions = WindowOptions(
        size: Size(size, Globals.quickMenuSize.height),
        minimumSize: Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height),
        maximumSize: const Size(32000, 32000),
        center: false,
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        alwaysOnTop: true,
        title: kDebugMode ? "Tabame - Debug" : "Tabame",
      );
    }
    Debug.add("Setting windowOptions");
    windowManager.setMinimizable(false);
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await Win32.fetchMainWindowHandle();
      await ClipboardHooks.start();
      Globals.fullLoaded.value = true;
      Debug.add("Set windowOptions");
    });
  }

  static Future<void> finalizeStartup() async {
    Debug.add("Setting transparency");
    await setWindowAsTransparent();
    if (userSettings.quickClickEnabled) {
      await QuickClick.registerQuickClick(userSettings.quickClickConfig);
      await QuickClick.disableQuickClick();
    }
    Debug.add("Set transparency");
  }
}
