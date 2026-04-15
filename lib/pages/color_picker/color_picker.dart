import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'color_picker_window.dart';

Future<void> startColorPicker() async {
  const WindowOptions windowOptions = WindowOptions(
    // Window adds a transparent 34 px cursor buffer around the painted picker.
    size: Size(171, 227),
    minimumSize: Size(171, 227),
    maximumSize: Size(171, 227),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: 'Color Picker',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const ColorPickerApp());
}
