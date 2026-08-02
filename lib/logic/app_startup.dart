import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/classes/save_settings.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../services/browser_bridge_service.dart';
import 'error_handler.dart';

class AppStartup {
  static Future<void> initialize() async {
    Debug.register(clean: true);

    Debug.add("===");
    Debug.add("Started");
    // WidgetsFlutterBinding.ensureInitialized();
    Debug.add("Register WindowManager");
    await windowManager.ensureInitialized();
    if (kReleaseMode) {
      // FlutterError.onError = handleErrors;
      // PlatformDispatcher.instance.onError = handlePlatformErrors;
      //
      FlutterError.onError = (FlutterErrorDetails details) async {
        await ErrorLogger.log(
          'FlutterError',
          details.exceptionAsString(),
          details.stack,
        );
      };

      // Dart async/platform errors not caught by Flutter
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        ErrorLogger.log('PlatformDispatcher', error.toString(), stack);
        return true; // returning true = you handled it
      };
    }
  }

  static void parseArguments(List<String> arguments2) {
    List<String> arguments = <String>[...arguments2];
    if (arguments.isNotEmpty) {
      if (arguments[0].endsWith('"') && !arguments[0].startsWith('"')) arguments[0] = '"${arguments[0]}';
      String argString = arguments.join(" ");
      user.args = <String>[...arguments];
      final int launcherIndex = arguments.indexOf("-launcher");
      if (launcherIndex != -1) {
        Globals.isStandaloneLauncher = true;
        Globals.quickMenuPage = QuickMenuPage.launcher;
        user.launcherSearchText = launcherIndex + 1 < arguments.length ? arguments[launcherIndex + 1] : '';
      }
      if (argString.contains("interface")) {
        user.page = TPage.interface;
        // This process is the Interface: bump the reload marker on settings writes so the
        // running QuickMenu process live-reloads (see SavedStore + QuickMenu file watcher).
        SavedStore.signalOnWrite = true;
      }
    }
    Debug.add("Parsed arguments ${user.page}");
  }

  static Future<void> registerServices() async {
    if (Globals.isStandaloneLauncher) {
      await Boxes.registerBoxes(justLoad: true);
      await BrowserBridgeService.instance.initialize(asLauncherClient: true);
      Debug.add("Registered: Standalone launcher settings");
      return;
    }
    await registerAll();
    if (user.page == TPage.quickmenu) {
      await BrowserBridgeService.instance.initialize();
      Debug.add("Registered: Browser bridge");
    }
    if (File("${WinUtils.getTabameAppDataFolder()}\\enable_debug.txt").existsSync()) {
      Debug.methodDebug(clean: true);
    }
    Debug.add("Registered All");
  }

  static Future<bool> checkAdminAndRestart() async {
    if (Globals.isStandaloneLauncher) return false;
    if (kReleaseMode &&
        user.runAsAdministrator &&
        !WinUtils.isAdministrator() &&
        !user.args.join(' ').contains('-tryadmin')) {
      Debug.add("Trying Admin");
      user.args.add('-tryadmin');
      WinUtils.closeAllTabameExProcesses();
      Debug.add("Closed all tabame processed");
      WinUtils.runAsAdmin(Platform.resolvedExecutable, arguments: '"${user.args.join('" "')}"');
      Debug.add("Started New");
      Timer(const Duration(seconds: 1), () {
        Debug.add("Started Close Current");
        exit(0);
      });
      return true;
    }
    if (user.args.contains("-restarted")) {
      Future<void>.delayed(const Duration(seconds: 2), () => WinUtils.closeAllTabameExProcesses());
    }
    return false;
  }

  static void registerHooks() {
    if (Globals.isStandaloneLauncher) return;
    if (Globals.debugHooks || kReleaseMode) {
      Debug.add("Registering Hooks");
      if (user.args.contains("-interface") && Boxes.remap.isEmpty) {
        NativeHooks.registerCallHandler();
      } else {
        NativeHooks.registerCallHandler();
      }
    }
  }

  static Future<void> setupWindow(List<String> arguments) async {
    late WindowOptions windowOptions;
    if (Globals.isStandaloneLauncher) {
      windowOptions = WindowOptions(
        size: Size(Boxes.launcherSizeWidth, Globals.launcherSize.height),
        minimumSize: Size(Globals.quickMenuSize.width, 200),
        maximumSize: const Size(32000, 32000),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        alwaysOnTop: false,
        title: "Tabame - Launcher - ${user.launcherSearchText.addDots(9)}",
      );
    } else if (user.args.contains("-interface") || Boxes.remap.isEmpty) {
      late String title;
      if (user.args.contains("-wizardly")) {
        title = "Wizardly";
      } else if (user.args.contains("-fancyshot")) {
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
      if (!Globals.isStandaloneLauncher) await ClipboardHooks.start();
      Globals.fullLoaded.value = true;
      Debug.add("Set windowOptions");
    });
  }

  static Future<void> finalizeStartup() async {
    Debug.add("Setting transparency");
    await setWindowAsTransparent();
    if (Globals.isStandaloneLauncher) {
      Debug.add("Set transparency");
      return;
    }
    if (user.quickClickEnabled) {
      await QuickClick.registerQuickClick(user.quickClickConfig);
      await QuickClick.disableQuickClick();
    }
    Debug.add("Set transparency");
  }
}
