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
      if (argString.contains("interface")) {
        user.page = TPage.interface;
      }
    }
    Debug.add("Parsed arguments ${user.page}");
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
    if (user.args.contains("-interface") || Boxes.remap.isEmpty) {
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
      await ClipboardHooks.start();
      Globals.fullLoaded.value = true;
      Debug.add("Set windowOptions");
    });
  }

  static Future<void> finalizeStartup() async {
    Debug.add("Setting transparency");
    await setWindowAsTransparent();
    if (user.quickClickEnabled) {
      await QuickClick.registerQuickClick(user.quickClickConfig);
      await QuickClick.disableQuickClick();
    }
    Debug.add("Set transparency");
  }
}

