import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:window_manager/window_manager.dart';

import 'models/classes/boxes.dart';
import 'models/globals.dart';
import 'models/win32/win32.dart';
import 'models/win32/win_utils.dart';
import 'platform/windows/win32_api.dart';
import 'platform/windows/tabamewin32_api.dart';

class TimestampLogger {
  static Timer? _timer;
  static bool _writing = false;
  static bool _recovering = false;

  static String get filePath {
    // final localAppData = Platform.environment['LOCALAPPDATA'];

    // if (localAppData == null) {
    //   throw StateError('LOCALAPPDATA not found.');
    // }

    return '${WinUtils.getTabameAppDataFolder()}\\timestamp.log';
  }

  static Future<void> init() async {
    final File file = File(filePath);

    // Ensure the Tabame directory exists.
    await file.parent.create(recursive: true);

    // Preserve the last failure across a restart.
    await file.writeAsString('${DateTime.now().toIso8601String()} start pid=$pid\n', mode: FileMode.append);
    // Prevent duplicate timers.
    _timer?.cancel();

    // Start logging every minute.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _writeTimestamp(),
    );
  }

  static void setWindowFramed(int hwnd, bool framed) {
    int style = GetWindowLongPtr(hwnd, GWL_STYLE);

    if (framed) {
      style |= WS_CAPTION | WS_SYSMENU | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX;
    } else {
      style &= ~(WS_CAPTION | WS_THICKFRAME);
    }

    SetWindowLongPtr(hwnd, GWL_STYLE, style);

    SetWindowPos(
      hwnd,
      0,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED,
    );
  }

  static Future<void> _writeTimestamp() async {
    if (_writing) return;
    _writing = true;
    try {
      // The heartbeat must not depend on any window, frame, or recovery future.
      final File file = File(filePath);

      await file.writeAsString(
        '${DateTime.now().toIso8601String()}\n',
        mode: FileMode.append,
        flush: true,
      );
      final File reset = File('${WinUtils.getTabameAppDataFolder()}\\reset.log');
      if (!_recovering && await reset.exists()) {
        // Consume the request once; do not stack a new recovery every minute.
        await reset.delete();
        _recovering = true;
        unawaited(_recover());
      }
    } catch (e) {
      print('TimestampLogger error: $e');
    } finally {
      _writing = false;
    }
  }

  static Future<void> _recover() async {
    try {
      // Request a framework frame without depending on the stalled vsync.
      // This cannot repair a deadlocked raster thread or a lost GPU device.
      WidgetsBinding.instance.scheduleWarmUpFrame();
      await QuickMenuFunctions.toggleQuickMenu(
        type: QuickMenuPage.quickMenu,
        visible: true,
        forceReposition: true,
      );
      await QuickMenuFunctions.refreshQuickMenu();
      WinUtils.setWindowFullyOpaque(Win32.hWnd);
      await Win32.forceRedraw();
      final Size value = await windowManager.getSize();
      await windowManager.setSize(Size(value.width + 1, value.height + 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await windowManager.setSize(value);
      if (NativeHooks.isRegistered) {
        await NativeHooks.freeHotkeys();
        await NativeHooks.unHook();
        await NativeHooks.hook();
      }
    } catch (error, stack) {
      print('TimestampLogger recovery error: $error\n$stack');
    } finally {
      _recovering = false;
    }
  }

  static void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
