// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';

import 'logic/app_startup.dart';
import 'pages/color_picker/color_picker.dart';
import 'pages/msgbox.dart';
import 'pages/root_app.dart';
import 'widgets/widgets/focus_fix.dart';

Future<void> main(List<String> arguments) async {
  await AppStartup.initialize();
  AppStartup.parseArguments(arguments);

  if (arguments.contains("-colorPicker")) return startColorPicker();
  if (arguments.contains("-msgbox")) return showMessage(arguments);

  await AppStartup.registerServices();

  if (await AppStartup.checkAdminAndRestart()) return;

  AppStartup.registerHooks();
  await AppStartup.setupWindow(arguments);
  await AppStartup.finalizeStartup();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
  PaintingBinding.instance.imageCache.maximumSize = 50;

  runApp(FocusFix(child: Tabame()));
}
