// ignore_for_file: unused_import, dead_code, unnecessary_import, prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'logic/app_startup.dart';
import 'logic/error_handler.dart';
import 'models/classes/save_settings.dart';
import 'platform/app_paths.dart';
import 'platform/distribution_profile.dart';
import 'platform/platform_bootstrap.dart';
import 'platform/portable_application.dart';
import 'pages/color_picker/color_picker.dart';
import 'pages/msgbox.dart';
import 'pages/photo_editor.dart';
import 'pages/present_mode.dart';
import 'pages/keystrokes_overlay.dart';
import 'platform/windows/windows_quicksnap_standalone.dart';
import 'pages/root_app.dart';
import 'pages/screen_capture.dart';
import 'pages/screen_draw.dart';
import 'pages/screen_recording.dart';
import 'pages/screen_ruler.dart';
import 'pages/spotlight.dart';
import 'pages/run.dart';

Future<void> main(List<String> arguments) async {
  DistributionProfileConfig.validate();
  WidgetsFlutterBinding.ensureInitialized();
  await PlatformBootstrap.initialize();
  await AppPaths.initialize();
  AppStartup.parseArguments(arguments);

  if (!PlatformBootstrap.isWindows) return startPortableApplication(arguments);
  // return startScreenCapture();
  // final File file = File(AppPaths.settingsPath('settings.json'));
  // if (file.existsSync()) file.deleteSync();
  if (arguments.contains("-spotlight")) return startSpotlight();
  if (arguments.contains("-editor")) return startPhotoEditor(arguments);
  if (arguments.contains("-screenCapture")) return startScreenCapture();
  if (arguments.contains("-screenRecording")) return startScreenRecordingPage();
  if (arguments.contains("-screenDraw")) return startScreenDraw();
  if (arguments.contains("-screenRuler")) return startScreenRuler();
  if (arguments.contains("-colorPicker")) return startColorPicker();
  if (arguments.contains("-quickSnap")) return startQuickSnap();
  if (arguments.contains("-present")) return startPresentMode();
  if (arguments.contains("-keystrokes")) return startKeystrokes();
  if (arguments.contains("-msgbox")) return showMessage(arguments);
  if (arguments.contains("-run")) return showRunStatus(arguments);

  // PaintingBinding.instance.imageCache.maximumSize = 50;

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      SaveSettings.suppressWrites = !AppPaths.hasSettingsFile;
      if (await AppStartup.registerServices()) exit(0);
      AppStartup.registerHooks();
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
