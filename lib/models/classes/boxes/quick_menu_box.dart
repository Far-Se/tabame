import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../globals.dart';
import '../../settings.dart';
import '../../win32/win32.dart';
import '../saved_maps.dart';
import 'boxes_base.dart';

// --------------------------------------------------------------------------
// QuickMenu
// --------------------------------------------------------------------------

mixin class QuickMenuTriggers {
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {}
  Future<void> onQuickMenuMaybePop() async {}
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) async {}
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {}
  void refreshQuickMenu() async {}
  void onVerticalArrow(bool up) {}
  void onEnter() {}
  void onQuickActionExecute(String actionName) {}
  void requestQuickMenuFocus() {}
}

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static bool keepOpen = false;
  static int hidTime = 0;

  static int taskBarSelectedIdx = -1;

  static void randomizeBackdrop() {
    final ThemeColors currentTheme = globalSettings.themeColors;
    if (currentTheme.backdropType == '') {
      globalSettings.activeBackdropPath = '';
      return;
    }
    if (currentTheme.backdropType == 'builtIn') {
      final int random = Random().nextInt(10);
      globalSettings.activeBackdropPath = 'resources/gradient/gradient$random.jpg';
    } else {
      if (currentTheme.backdropImages.isNotEmpty) {
        final int random = Random().nextInt(currentTheme.backdropImages.length);
        globalSettings.activeBackdropPath = currentTheme.backdropImages[random];
      } else {
        final int random = Random().nextInt(10);
        globalSettings.activeBackdropPath = 'resources/gradient/gradient$random.jpg';
      }
    }
  }

  static void resetKeyboardSelection() {
    taskBarSelectedIdx = -1;
  }

  static void onVerticalArrow(bool up) {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onVerticalArrow(up);
    }
  }

  static void onEnter() {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onEnter();
    }
  }

  static void triggerQuickAction(String actionName) {
    for (final QuickMenuTriggers listener in _listeners) {
      listener.onQuickActionExecute(actionName);
    }
  }

  static void requestQuickMenuFocus() {
    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) return;
      listener.requestQuickMenuFocus();
    }
  }

  static void refreshQuickMenu() {
    for (final QuickMenuTriggers listener in _listeners) {
      if (!_listeners.contains(listener)) return;
      listener.refreshQuickMenu();
    }
  }

  static final ObserverList<QuickMenuTriggers> _listeners = ObserverList<QuickMenuTriggers>();
  static List<QuickMenuTriggers> get listeners => List<QuickMenuTriggers>.from(_listeners);

  static bool get hasListeners => _listeners.isNotEmpty;

  static void addListener(QuickMenuTriggers listener) => _listeners.add(listener);
  static void removeListener(QuickMenuTriggers listener) => _listeners.remove(listener);

  static Future<void> toggleQuickMenu(
      {QuickMenuPage type = QuickMenuPage.quickMenu, bool? visible, bool center = false, bool forcePop = false}) async {
    if (visible == false && kDebugMode) return;
    if (visible != null) {
      if (visible == false && QuickMenuFunctions.keepOpen) {
        return;
      }
    }
    visible ??= !isQuickMenuVisible;
    isQuickMenuVisible = visible;
    if (Globals.quickMenuPage != type) {
      for (final QuickMenuTriggers listener in _listeners) {
        if (!_listeners.contains(listener)) return;
        await listener.onQuickMenuSwitchedPage(type, Globals.quickMenuPage, visible);
      }
    }

    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) return;
      await listener.onQuickMenuToggled(visible, type);
      if (forcePop) await listener.onQuickMenuMaybePop();
    }

    if (visible) {
      Globals.quickMenuPage = type;

      if (DateTime.now().millisecondsSinceEpoch - hidTime > 150) {
        Future<void>.delayed(const Duration(milliseconds: 110), () async {
          if (center) {
            Win32.setCenter(useMouse: true);
          } else {
            await Win32.setMainWindowToMousePos();
          }
          for (final QuickMenuTriggers listener in listeners) {
            if (!_listeners.contains(listener)) return;
            await listener.onQuickMenuVisible(type, center);
          }
          Win32.setWindowInvisiblity(false);
        });
      } else {
        visible = false;
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      await WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
      if (!kReleaseMode) return;
      Win32.setPosition(const Offset(-99999, -99999));
      hidTime = DateTime.now().millisecondsSinceEpoch;
    }
  }

  static Future<void> openQuickMenuWithAction(String actionName, {bool center = false}) async {
    await toggleQuickMenu(visible: true, center: center, type: QuickMenuPage.launcher, forcePop: true);

    Globals.setLauncherQuickAction(actionName);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Globals.clearQuickMenuSearchInput();
  }
}
