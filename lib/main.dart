// ignore_for_file: unused_import, dead_code, unnecessary_import, prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import 'logic/app_startup.dart';
import 'logic/error_handler.dart';
import 'models/globals.dart';
import 'models/win32/win_utils.dart';
import 'pages/color_picker/color_picker.dart';
import 'pages/msgbox.dart';
import 'pages/photo_editor.dart';
import 'pages/root_app.dart';
import 'pages/screen_capture.dart';
import 'pages/screen_draw.dart';
import 'pages/screen_recording.dart';
import 'pages/spotlight.dart';
import 'pages/run.dart';
import 'widgets/widgets/focus_fix.dart';

Future<void> main(List<String> arguments) async {
  AppStartup.parseArguments(arguments);
  // return startSpotlight();
  // Test.

  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  // return startScreenCapture();
  // final File file = File("${WinUtils.getTabameAppDataFolder(settings: true)}\\settings.json");
  // if (file.existsSync()) file.deleteSync();
  if (arguments.contains("-spotlight")) return startSpotlight();
  if (arguments.contains("-editor")) return startPhotoEditor(arguments);
  if (arguments.contains("-screenCapture")) return startScreenCapture();
  if (arguments.contains("-screenRecording")) return startScreenRecordingPage();
  if (arguments.contains("-screenDraw")) return startScreenDraw();
  if (arguments.contains("-colorPicker")) return startColorPicker();
  if (arguments.contains("-msgbox")) return showMessage(arguments);
  if (arguments.contains("-run")) return showRunStatus(arguments);

  // PaintingBinding.instance.imageCache.maximumSize = 50;

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await AppStartup.registerServices();
      AppStartup.registerHooks();
      if (await AppStartup.checkAdminAndRestart()) return;
      await AppStartup.setupWindow(arguments);
      await AppStartup.finalizeStartup();
      PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
      await AppStartup.initialize();
      runApp(const Tabame());
    },
    (Object error, StackTrace stack) async {
      await ErrorLogger.log('ZoneError', error.toString(), stack);
    },
  );
  // runApp(FocusFix(child: Tabame()));
}
