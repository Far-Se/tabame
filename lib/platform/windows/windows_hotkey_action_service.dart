import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/classes/text_snippet.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/win32/keys.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../models/window_watcher.dart';
import '../../pages/color_picker/win32_helper.dart';
import '../../pages/screen_capture.dart';
import '../audio_system_service.dart';
import '../hotkey_action_service.dart';
import '../input_service.dart';

import 'tabamewin32_api.dart' hide AudioDeviceType;
import 'win32_api.dart';

/// Windows adapter for configured hotkey action execution.
///
/// This is the compatibility home for window handles, shell-specific actions,
/// and Windows key injection. Shared models submit [PlatformHotkeyExecution]
/// requests and never see these native values.
class WindowsHotkeyActionService extends HotkeyActionService {
  const WindowsHotkeyActionService();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  String get unavailableReason => isAvailable ? '' : 'Windows hotkey actions are unavailable on this platform.';

  /// Installs the existing Windows action callbacks behind the neutral action
  /// registry used by the editor and dispatcher.
  static void registerCallbacks() {
    HotkeyActionRegistry.register(<String, Function>{
      'ToggleQuickMenu': () {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          final Offset position = Win32.getPosition();
          if (position.dx < -99) return QuickMenuFunctions.toggleQuickMenu(visible: true);
          QuickMenuFunctions.hideQuickMenu();
          if (GetForegroundWindow() == Win32.hWnd) WindowWatcher.focusFirstWindow();
          return <dynamic, dynamic>{};
        }
        return QuickMenuFunctions.toggleQuickMenu();
      },
      'ShowQuickMenuInCenter': () => QuickMenuFunctions.toggleQuickMenu(center: true),
      'OpenLauncher': () {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          if (Globals.quickMenuPage == QuickMenuPage.launcher) {
            QuickMenuFunctions.hideQuickMenu();
            Win32.activateWindow(Globals.lastFocusedWinHWND);
            return <dynamic, dynamic>{};
          }
        }
        return QuickMenuFunctions.toggleQuickMenu(type: QuickMenuPage.launcher, center: true, visible: true);
      },
      'ToggleTaskbar': () => WinUtils.toggleTaskbar(),
      'OpenColorPicker': () => WinUtils.startTabame(closeCurrent: false, arguments: '-colorPicker'),
      'OpenQuickSnapStandalone': () {
        final int windowHandle = Win32.findWindow('Tabame QuickSnap');
        if (windowHandle != 0) {
          Win32.closeWindow(windowHandle);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: '-quickSnap', admin: true);
        }
      },
      'OpenScreenDraw': () {
        final int windowHandle = Win32.findWindow('Tabame Screen Draw');
        if (windowHandle != 0) {
          Win32.closeWindow(windowHandle);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: '-screenDraw', admin: false);
        }
      },
      'OpenScreenRecording': () {
        final int windowHandle = Win32.findWindow('Tabame Screen Recording');
        if (windowHandle != 0) {
          Win32.closeWindow(windowHandle);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: '-screenRecording');
        }
      },
      'OpenSpotlight': () {
        final int windowHandle = Win32.findWindow('Tabame Spotlight');
        if (windowHandle != 0) {
          Win32.closeWindow(windowHandle);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: '-spotlight');
        }
      },
      'OpenLiveFancyShot': () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          WinUtils.startTabame(closeCurrent: false, arguments: '-screenCapture');
          return;
        }
        Globals.quickMenuPage = QuickMenuPage.fancyShotLive;
        QuickMenuFunctions.refreshQuickMenu();
      },
      'OpenFrozenFancyShot': () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          WinUtils.startTabame(closeCurrent: false, arguments: '-screenCapture -frozen');
          return;
        }
        Globals.quickMenuPage = QuickMenuPage.fancyShotFreeze;
        await FancyShotCaptureWidget.captureScreenshots();
        QuickMenuFunctions.refreshQuickMenu();
      },
      'OpenColorPickerInstant': () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          QuickMenuFunctions.hideQuickMenu();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await Win32Helper.instantColorPicker();
      },
      'OpenEmojiPicker': () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          QuickMenuFunctions.hideQuickMenu();
          await Future<void>.delayed(const Duration(milliseconds: 160));
        }
        if (Debug.enabled) {
          final CaretDebugInfo caretDebug = await getFocusedElementCaretRectDebug();
          Debug.add('OpenEmojiPicker caret debug: $caretDebug');
          print(caretDebug);
          Globals.focusedRect = caretDebug.best;
        } else {
          Globals.focusedRect = await getFocusedElementCaretRect();
        }
        await QuickMenuFunctions.toggleQuickMenu(
          visible: true,
          type: QuickMenuPage.emojiPicker,
          forcePop: true,
          forceReposition: false,
        );
      },
      'OpenQuickClick': () async {
        await Future<void>.delayed(const Duration(milliseconds: 160));
        if (Globals.quickMenuPage == QuickMenuPage.quickClick) {
          Win32.setPosition(const Offset(-99999, -99999));
          await QuickMenuFunctions.hideQuickMenu();
          return;
        }
        Win32.setWindowInvisible(true);
        if (QuickMenuFunctions.isQuickMenuVisible) {
          QuickMenuFunctions.hideQuickMenu();
          await Future<void>.delayed(const Duration(milliseconds: 160));
        }
        await QuickMenuFunctions.toggleQuickMenu(
          visible: true,
          type: QuickMenuPage.quickClick,
          forcePop: true,
          forceReposition: false,
        );
      },
      'BlockKeyboard': () async {
        await QuickMenuFunctions.openQuickMenuWithAction('BlockKeyboard', center: true);
        await Future<void>.delayed(const Duration(milliseconds: 300), () {
          QuickMenuFunctions.triggerQuickAction('StartBlockingKeyboard');
        });
      },
      'ShowStartMenu': () {
        int trayWindowHandle = FindWindow(TEXT('Shell_TrayWnd'), nullptr);
        if (trayWindowHandle == 0) return;
        final int monitorId = Monitor.getMonitorNumber(Monitor.getCursorMonitor());
        if (monitorId > 1) trayWindowHandle = FindWindow(TEXT('Shell_SecondaryTrayWnd'), nullptr);
        if (trayWindowHandle == 0) trayWindowHandle = FindWindow(TEXT('Shell_TrayWnd'), nullptr);
        final int startButtonHandle = FindWindowEx(trayWindowHandle, 0, TEXT('Start'), nullptr);
        if (startButtonHandle != 0) {
          SetForegroundWindow(startButtonHandle);
          WinKeys.send('{SPACE}');
        } else {
          SetForegroundWindow(trayWindowHandle);
          WinKeys.send('{#SHIFT}{TAB}{|}{#SHIFT}{TAB}{|}{SPACE}');
        }
      },
      'ShowLastActiveWindow': () {
        QuickMenuFunctions.hideQuickMenu();
        WindowWatcher.focusSecondWindow();
        Future<void>.delayed(const Duration(milliseconds: 320), () {
          QuickMenuFunctions.hideQuickMenu();
        });
      },
      'ShowSecondWindowUnderCursor': () {
        QuickMenuFunctions.hideQuickMenu();
        WindowWatcher.showSecondWindowUnderCursor();
        Future<void>.delayed(const Duration(milliseconds: 320), () {
          QuickMenuFunctions.hideQuickMenu();
        });
      },
      'ShowLastWindowUnderCursor': () {
        QuickMenuFunctions.hideQuickMenu();
        WindowWatcher.showLastWindowUnderCursor();
        Future<void>.delayed(const Duration(milliseconds: 320), () {
          QuickMenuFunctions.hideQuickMenu();
        });
      },
      'ToggleAlwaysOnTopForWindow': () => Win32.setAlwaysOnTop(GetForegroundWindow()),
      'ExpandSnippet': () => TextSnippetsManager.expand(),
      'ToggleHiddenFiles': () => WinUtils.toggleHiddenFiles(),
      'ToggleDesktopFiles': () => WinUtils.toggleDesktopFiles(),
      'SwitchAudioOutput': () => AudioSystemService.instance.switchDefaultDevice(
            AudioDeviceType.output,
            targeting: AudioDeviceTargeting(
              console: user.audioConsole,
              multimedia: user.audioMultimedia,
              communications: user.audioCommunications,
            ),
          ),
      'SwitchMicrophoneInput': () => AudioSystemService.instance.switchDefaultDevice(
            AudioDeviceType.input,
            targeting: AudioDeviceTargeting(
              console: user.audioConsole,
              multimedia: user.audioMultimedia,
              communications: user.audioCommunications,
            ),
          ),
      'ToggleMicrophone': () =>
          AudioOrchestrator(service: AudioSystemService.instance).toggleMute(AudioDeviceType.input),
      'SwitchDesktopToRight': () => WinUtils.moveDesktop(DesktopDirection.right),
      'SwitchDesktopToLeft': () => WinUtils.moveDesktop(DesktopDirection.left),
      'ToggleWallpaper': () async {
        final DesktopBackgroundType current = WinUtils.getDesktopBackgroundType();
        if (current == DesktopBackgroundType.wallpaper) {
          await WinUtils.toggleDesktopWallpaper(false);
          return;
        }
        await WinUtils.toggleDesktopWallpaper(true);
      },
    });
  }

  @override
  Future<void> execute(PlatformHotkeyExecution execution) async {
    if (!isAvailable) return;

    if (!_passesVariableCheck(execution.variableCheck)) return;

    int targetWindow = GetForegroundWindow();
    if (execution.windowUnderCursor) {
      final Pointer<POINT> cursor = calloc<POINT>();
      try {
        GetCursorPos(cursor);
        targetWindow = GetAncestor(WindowFromPoint(cursor.ref), 3);
      } finally {
        free(cursor);
      }
    }

    if (!_matchesWindow(targetWindow, execution.windowMatch)) return;

    if (execution.windowUnderCursor && GetForegroundWindow() != targetWindow) {
      Win32.activateWindow(targetWindow);
      int pollCount = 0;
      while (pollCount < 200 && GetForegroundWindow() != targetWindow) {
        pollCount++;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      if (GetForegroundWindow() != targetWindow) return;
    }

    for (final PlatformHotkeyAction action in execution.actions) {
      await _executeAction(action);
    }
  }

  bool _passesVariableCheck(List<String> variableCheck) {
    if (variableCheck.isEmpty || variableCheck[0].isEmpty) return true;
    final String stored = Boxes.pref.getString('k_${variableCheck[0]}') ?? '';
    if (stored.isNotEmpty) return stored == variableCheck[1];
    Boxes.pref.setString('k_${variableCheck[0]}', variableCheck[1]);
    return true;
  }

  bool _matchesWindow(int targetWindow, List<String> windowMatch) {
    if (windowMatch.isEmpty || windowMatch[0] == 'any') return true;
    String value = '';
    switch (windowMatch[0].toLowerCase()) {
      case 'exe':
        value = Win32.getWindowExePath(targetWindow);
      case 'class':
        value = Win32.getClass(targetWindow);
      case 'title':
        value = Win32.getTitle(targetWindow);
    }
    return RegExp(windowMatch.length > 1 ? windowMatch[1] : '', caseSensitive: false).hasMatch(value);
  }

  Future<void> _executeAction(PlatformHotkeyAction action) async {
    switch (action.type) {
      case 'hotkey':
        await _sendHotkey(action.value);
      case 'sendKeys':
        if (action.value == '{WIN}') {
          int trayWindowHandle = FindWindow(TEXT('Shell_TrayWnd'), nullptr);
          if (trayWindowHandle == 0) trayWindowHandle = GetDesktopWindow();
          SetForegroundWindow(trayWindowHandle);
        }
        await InputService.instance.injectKeySequence(action.value);
      case 'openQuickMenuPage':
        if (!HotKeyInfo.quickMenuPopups.contains(action.value)) return;
        if (action.value == 'Interface' || action.value == 'Launcher') {
          await QuickMenuFunctions.toggleQuickMenu(type: QuickMenuPage.launcher, center: true);
        } else {
          await QuickMenuFunctions.openQuickMenuWithAction(action.value, center: true);
        }
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: int.tryParse(action.value) ?? 0));
      case 'sendClick':
        await _sendClick(action.value);
      case 'tabameFunction':
        await HotkeyActionRegistry.invoke(action.value);
      case 'setVar':
        _setVariable(action.value);
      case 'openLauncherWithPrefix':
        if (action.value.isNotEmpty) {
          await QuickMenuFunctions.openQuickMenuWithAction(action.value, center: true, useSlash: false);
        }
    }
  }

  Future<void> _sendHotkey(String value) async {
    final String serialized = value.split('+').map((String part) => part.length > 1 ? '{#$part}' : part).join();
    await InputService.instance.injectKeySequence(serialized);
  }

  void _setVariable(String value) {
    try {
      final List<dynamic> assignment = jsonDecode(value) as List<dynamic>;
      if (assignment.length == 2) {
        Boxes.pref.setString('k_${assignment[0]}', assignment[1].toString());
      }
    } catch (error) {
      Debug.add('Hotkey: Error setting var $error');
    }
  }

  Future<void> _sendClick(String value) async {
    final Pointer<POINT> cursor = calloc<POINT>();
    final Pointer<RECT> windowRect = calloc<RECT>();
    try {
      GetCursorPos(cursor);
      int targetWindow = GetForegroundWindow();
      if (value.isEmpty) return;
      final ClickAction clickAction = ClickAction.fromJson(value);
      if (clickAction.currentWindow) targetWindow = GetAncestor(WindowFromPoint(cursor.ref), 2);
      if (GetWindowRect(targetWindow, windowRect) == 0) return;

      int clickX = windowRect.ref.left;
      int clickY = windowRect.ref.top;
      switch (clickAction.anchorType) {
        case AnchorType.topLeft:
          clickX += clickAction.x;
          clickY += clickAction.y;
        case AnchorType.topRight:
          clickX = windowRect.ref.right - clickAction.x;
          clickY += clickAction.y;
        case AnchorType.bottomLeft:
          clickX += clickAction.x;
          clickY = windowRect.ref.bottom - clickAction.y;
        case AnchorType.bottomRight:
          clickX = windowRect.ref.right - clickAction.x;
          clickY = windowRect.ref.bottom - clickAction.y;
      }
      await InputService.instance.setCursorPosition(Point<int>(clickX, clickY));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await InputService.instance.injectClick(position: Point<int>(clickX, clickY));
      await InputService.instance.setCursorPosition(Point<int>(cursor.ref.x, cursor.ref.y));
    } finally {
      free(cursor);
      free(windowRect);
    }
  }
}
