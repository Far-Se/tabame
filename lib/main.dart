// ignore_for_file: unused_import, dead_code, unnecessary_import, prefer_const_constructors

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'logic/app_startup.dart';
import 'pages/color_picker/color_picker.dart';
import 'pages/msgbox.dart';
import 'pages/root_app.dart';
import 'pages/screen_capture.dart';
import 'pages/screen_draw.dart';
import 'pages/spotlight.dart';
import 'widgets/widgets/focus_fix.dart';

Future<void> main(List<String> arguments) async {
  await AppStartup.initialize();
  AppStartup.parseArguments(arguments);
  final bool wantsScreenCapture = arguments.contains("-capture") || arguments.contains("-screenCapture");
  final bool freezeScreenCapture = arguments.contains("-freeze");
  // if (kDebugMode && true && arguments.isEmpty) return startScreenCapture();
  if (arguments.contains("-spotlight")) return startSpotlight();
  if (wantsScreenCapture) return startScreenCapture(freezeMode: freezeScreenCapture);
  if (arguments.contains("-screenDraw")) return startScreenDraw();
  if (arguments.contains("-colorPicker")) return startColorPicker();
  if (arguments.contains("-msgbox")) return showMessage(arguments);

  await AppStartup.registerServices();

  if (await AppStartup.checkAdminAndRestart()) return;

  AppStartup.registerHooks();
  await AppStartup.setupWindow(arguments);
  await AppStartup.finalizeStartup();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
  // PaintingBinding.instance.imageCache.maximumSize = 50;

  runApp(Tabame());
  // runApp(FocusFix(child: Tabame()));
}
