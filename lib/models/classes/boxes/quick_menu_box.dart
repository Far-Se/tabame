import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../globals.dart';
import '../../settings.dart';
import '../../win32/win32.dart';
import '../../win32/win_utils.dart';
import '../saved_maps.dart';
import 'boxes_base.dart';

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static bool keepOpen = false;
  static int hiddenTime = 0;
  static int shownTime = 0;
  static int _visibilityRequest = 0;

  static int taskBarSelectedIdx = -1;

  static final ObserverList<QuickMenuTriggers> _listeners = ObserverList<QuickMenuTriggers>();

  static bool get hasListeners => _listeners.isNotEmpty;

  static List<QuickMenuTriggers> get listeners => List<QuickMenuTriggers>.from(_listeners);

  static void addListener(QuickMenuTriggers listener) => _listeners.add(listener);

  static void onEnter() {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onEnter();
    }
  }

  static void onVerticalArrow(bool up) {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onVerticalArrow(up);
    }
  }

  static Future<void> openQuickMenuWithAction(String actionName, {bool center = false, bool useSlash = true}) async {
    await toggleQuickMenu(visible: true, center: center, type: QuickMenuPage.launcher, forcePop: true);
    if (useSlash) {
      Globals.setLauncherQuickAction(actionName, replaceExisting: true);
    } else {
      Globals.setLauncherPretext(actionName, replaceExisting: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Globals.clearQuickMenuSearchInput();
  }

  static const String defaultBackdropPath = 'resources/gradient/gradient0.jpg';

  static void syncSelectedBackdrop({String? selectedPath}) {
    final ThemeColors currentTheme = user.themeColors;
    if (currentTheme.backdropType == '') {
      user.activeBackdropPath = '';
      currentTheme.backdropPath = '';
      return;
    }

    String nextPath = selectedPath ?? currentTheme.backdropPath;
    if (currentTheme.backdropType == 'builtIn') {
      if (!nextPath.startsWith('resources/gradient/')) nextPath = defaultBackdropPath;
    } else if (currentTheme.backdropType == 'custom') {
      if (!currentTheme.backdropImages.contains(nextPath)) {
        nextPath = currentTheme.backdropImages.isEmpty ? '' : currentTheme.backdropImages.first;
      }
    } else {
      nextPath = '';
    }

    user.activeBackdropPath = nextPath;
    currentTheme.backdropPath = nextPath;
  }

  static Future<void> refreshQuickMenu() async {
    for (final QuickMenuTriggers listener in _listeners) {
      if (!_listeners.contains(listener)) continue;
      await listener.refreshQuickMenu();
    }
    return;
  }

  static void removeListener(QuickMenuTriggers listener) => _listeners.remove(listener);

  static void requestQuickMenuFocus() {
    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) continue;
      listener.requestQuickMenuFocus();
    }
  }

  static void resetKeyboardSelection() {
    taskBarSelectedIdx = -1;
  }

  static Future<void> hideQuickMenu({bool launcherActivateLastWin = true}) async {
    if (Globals.isStandaloneLauncher) {
      await windowManager.close();
      return;
    }
    if (launcherActivateLastWin && Globals.quickMenuPage == QuickMenuPage.launcher) {
      Future<void>.delayed(const Duration(milliseconds: 50), () => Win32.activateWindow(Globals.lastFocusedWinHWND));
    }
    await toggleQuickMenu(visible: false);
  }

  static Future<void> toggleQuickMenu(
      {QuickMenuPage type = QuickMenuPage.quickMenu,
      bool? visible,
      bool center = false,
      bool forceReposition = true,
      bool forcePop = false}) async {
    final bool show = visible ?? !isQuickMenuVisible;
    if (!show && keepOpen) return;
    // Reject rapid reopens before listeners or opacity change anything.
    if (show && DateTime.now().millisecondsSinceEpoch - hiddenTime <= 150) return;
    final int request = ++_visibilityRequest;
    void restoreOpacity() {
      if (request == _visibilityRequest && isQuickMenuVisible) {
        WinUtils.setWindowFullyOpaque(Win32.hWnd);
      }
    }

    // A native/listener future can also stall. This timer is independent of
    // Flutter frames and prevents an async wait from leaving alpha at zero.
    final Timer? revealFallback = show
        ? Timer(const Duration(seconds: 3), () {
            if (request != _visibilityRequest || !isQuickMenuVisible) return;
            restoreOpacity();
          })
        : null;
    try {
      await _toggleQuickMenu(
        request: request,
        type: type,
        visible: show,
        center: center,
        forceReposition: forceReposition,
        forcePop: forcePop,
      );
    } finally {
      revealFallback?.cancel();
      restoreOpacity();
    }
  }

  static Future<void> _toggleQuickMenu(
      {required int request,
      required bool visible,
      QuickMenuPage type = QuickMenuPage.quickMenu,
      bool center = false,
      bool forceReposition = true,
      bool forcePop = false}) async {
    isQuickMenuVisible = visible;
    if (visible) {
      // Keep the on-screen window invisible while Flutter rebuilds and the
      // draw workaround runs. It is revealed only after the new frame is ready.
      WinUtils.setWindowFullyTransparent(Win32.hWnd);
    }
    if (!visible && !(kDebugMode && !Globals.debugHotkeys)) {
      Win32.setPosition(const Offset(-99999, -99999));
    }
    if (Globals.quickMenuPage != type) {
      for (final QuickMenuTriggers listener in listeners) {
        if (!_listeners.contains(listener)) continue;
        await listener.onQuickMenuSwitchedPage(type, Globals.quickMenuPage, visible);
        if (request != _visibilityRequest) return;
      }
    }

    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) continue;
      await listener.onQuickMenuToggled(visible, type);
      if (request != _visibilityRequest) return;
      if (forcePop) await listener.onQuickMenuMaybePop();
    }

    if (visible) {
      Globals.quickMenuPage = type;

      if (DateTime.now().millisecondsSinceEpoch - hiddenTime > 150) {
        if (type == QuickMenuPage.quickMenu) {
          triggerQuickAction("action:refreshTaskbar");
        }
        final Size value = await windowManager.getSize();
        await windowManager.setSize(Size(value.width + 2, value.height + 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await windowManager.setSize(value);

        if (forceReposition) {
          if (center) {
            Win32.setCenter(useMouse: true);
          } else {
            await Win32.setMainWindowToMousePos();
          }
        }
        for (final QuickMenuTriggers listener in listeners) {
          if (!_listeners.contains(listener)) continue;
          await listener.onQuickMenuVisible(type, center);
        }

        await Win32.forceRedraw();
        if (request != _visibilityRequest || !isQuickMenuVisible) return;
        Win32.setWindowInvisible(false);
        shownTime = DateTime.now().millisecondsSinceEpoch;
      } else {
        visible = false;
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      await WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
      if (kDebugMode && !Globals.debugHotkeys) return;
      Win32.setPosition(const Offset(-99999, -99999));
      // ShowWindow(Win32.hWnd, SW_HIDE);
      hiddenTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  static void triggerQuickAction(String actionName) {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onQuickActionExecute(actionName);
    }
  }
}

// --------------------------------------------------------------------------
// QuickMenu
// --------------------------------------------------------------------------

mixin class QuickMenuTriggers {
  void onEnter() {}
  void onQuickActionExecute(String actionName) {}
  Future<void> onQuickMenuMaybePop() async {}
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) async {}
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {}
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {}
  void onVerticalArrow(bool up) {}
  Future<void> refreshQuickMenu() async {}
  void requestQuickMenuFocus() {}
}
