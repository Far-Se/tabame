import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../globals.dart';
import '../../settings.dart';
import '../../win32/win32.dart';
import '../saved_maps.dart';
import 'boxes_base.dart';

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static bool keepOpen = false;
  static int hidTime = 0;
  static int shownTime = 0;

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
      Globals.setLauncherQuickAction(actionName);
    } else {
      Globals.setLauncherPretext(actionName);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    Globals.clearQuickMenuSearchInput();
  }

  static void randomizeBackdrop() {
    final ThemeColors currentTheme = userSettings.themeColors;
    if (currentTheme.backdropType == '') {
      userSettings.activeBackdropPath = '';
      return;
    }
    if (currentTheme.backdropType == 'builtIn') {
      final int random = Random().nextInt(10);
      userSettings.activeBackdropPath = 'resources/gradient/gradient$random.jpg';
    } else {
      if (currentTheme.backdropImages.isNotEmpty) {
        final int random = Random().nextInt(currentTheme.backdropImages.length);
        userSettings.activeBackdropPath = currentTheme.backdropImages[random];
      } else {
        final int random = Random().nextInt(10);
        userSettings.activeBackdropPath = 'resources/gradient/gradient$random.jpg';
      }
    }
  }

  static void refreshQuickMenu() {
    for (final QuickMenuTriggers listener in _listeners) {
      if (!_listeners.contains(listener)) continue;
      listener.refreshQuickMenu();
    }
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

  static Future<void> hideQuickMenu() async => await toggleQuickMenu(visible: false);

  static Future<void> toggleQuickMenu(
      {QuickMenuPage type = QuickMenuPage.quickMenu,
      bool? visible,
      bool center = false,
      bool forceReposition = true,
      bool forcePop = false}) async {
    // if (visible == false /* && (kDebugMode && !Globals.debugHotkeys) */) return;
    if (visible != null) {
      if (visible == false && QuickMenuFunctions.keepOpen) {
        return;
      }
    }
    visible ??= !isQuickMenuVisible;
    isQuickMenuVisible = visible;
    if (Globals.quickMenuPage != type) {
      for (final QuickMenuTriggers listener in _listeners) {
        if (!_listeners.contains(listener)) continue;
        await listener.onQuickMenuSwitchedPage(type, Globals.quickMenuPage, visible);
      }
    }

    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) continue;
      await listener.onQuickMenuToggled(visible, type);
      if (forcePop) await listener.onQuickMenuMaybePop();
    }

    if (visible) {
      Globals.quickMenuPage = type;

      if (DateTime.now().millisecondsSinceEpoch - hidTime > 150) {
        if (type == QuickMenuPage.quickMenu) {
          triggerQuickAction("action:refreshTaskbar");
        }
        Future<void>.delayed(const Duration(milliseconds: 110), () async {
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
          Win32.setWindowInvisible(false);
          shownTime = DateTime.now().millisecondsSinceEpoch;
        });
      } else {
        visible = false;
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      await WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
      if (kDebugMode && !Globals.debugHotkeys) return;
      Win32.setPosition(const Offset(-99999, -99999));
      hidTime = DateTime.now().millisecondsSinceEpoch;
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
  void refreshQuickMenu() async {}
  void requestQuickMenuFocus() {}
}
