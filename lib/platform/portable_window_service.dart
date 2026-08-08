import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Common window lifecycle for the portable launcher shell.
class PortableWindowService {
  PortableWindowService._();

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(860, 620),
      minimumSize: Size(620, 420),
      center: true,
      skipTaskbar: false,
      alwaysOnTop: false,
      title: 'Tabame',
    );
    unawaited(windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    }));
  }

  static Future<void> show() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static Future<void> hide() => windowManager.hide();

  static Future<void> close() => windowManager.destroy();
}
