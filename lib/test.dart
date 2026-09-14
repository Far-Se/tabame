import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:window_manager/window_manager.dart';

import 'logic/ui_health.dart';
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
    UiHealth.start();

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
      UiHealth.record('heartbeat', <String, Object?>{
        'quickMenuVisible': QuickMenuFunctions.isQuickMenuVisible,
        'quickMenuPage': Globals.quickMenuPage.name,
        'recoveryPending': _recovering,
      });
      await UiHealth.probeNative();
      final File reset = File('${WinUtils.getTabameAppDataFolder()}\\reset.log');
      if (!_recovering && await reset.exists()) {
        // Consume the request once; do not stack a new recovery every minute.
        await reset.delete();
        _recovering = true;
        unawaited(_recover());
      }
    } catch (e, stack) {
      UiHealth.record('heartbeat.error', <String, Object?>{'error': '$e', 'stack': '$stack'});
      print('TimestampLogger error: $e');
    } finally {
      _writing = false;
    }
  }

  static Future<void> _recover() async {
    UiHealth.record('reset.before');
    try {
      if (!await UiHealth.probeNative()) {
        UiHealth.record('reset.aborted.nativeUnresponsive');
        return;
      }
      // Request a framework frame without depending on the stalled vsync.
      // This cannot repair a deadlocked raster thread or a lost GPU device.
      WidgetsBinding.instance.scheduleWarmUpFrame();
      await UiHealth.waitForFrame('reset.warmUp');
      await UiHealth.step(
          'reset.show',
          () => QuickMenuFunctions.toggleQuickMenu(
                type: QuickMenuPage.quickMenu,
                visible: true,
                forceReposition: true,
              ));
      await UiHealth.step('reset.refresh', QuickMenuFunctions.refreshQuickMenu);
      WinUtils.setWindowFullyOpaque(Win32.hWnd);
      await UiHealth.step('reset.redraw', Win32.forceRedraw);
      final Size value = await UiHealth.step('reset.getSize', windowManager.getSize);
      await UiHealth.step('reset.resize', () => windowManager.setSize(Size(value.width + 1, value.height + 1)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await UiHealth.step('reset.restoreSize', () => windowManager.setSize(value));
      if (NativeHooks.isRegistered) {
        await UiHealth.step('reset.freeHotkeys', NativeHooks.freeHotkeys);
        await UiHealth.step('reset.unhook', NativeHooks.unHook);
        await UiHealth.step('reset.hook', NativeHooks.hook);
      }
      final bool frameCompleted = await UiHealth.waitForFrame('reset.after');
      UiHealth.record('reset.after', <String, Object?>{'frameworkFrameCompleted': frameCompleted});
    } catch (error, stack) {
      UiHealth.record('reset.error', <String, Object?>{'error': '$error', 'stack': '$stack'});
    } finally {
      _recovering = false;
    }
  }

  static void dispose() {
    _timer?.cancel();
    _timer = null;
    UiHealth.stop();
  }
}
