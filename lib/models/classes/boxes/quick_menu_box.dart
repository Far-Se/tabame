import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../globals.dart';
import '../../win32/win32.dart';

// --------------------------------------------------------------------------
// QuickMenu
// --------------------------------------------------------------------------

mixin class QuickMenuTriggers {
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {}
  Future<void> onQuickMenuShown(QuickMenuPage type) async {}
  void refreshQuickMenu() async {}
  void onVerticalArrow(bool up) {}
  void onEnter() {}
  void onQuickActionExecute(String actionName) {}
}

class QuickMenuFunctions {
  static bool isQuickMenuVisible = true;
  static bool keepOpen = false;
  static int hidTime = 0;

  static int taskBarSelectedIdx = -1;

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

  static final ObserverList<QuickMenuTriggers> _listeners = ObserverList<QuickMenuTriggers>();
  static List<QuickMenuTriggers> get listeners => List<QuickMenuTriggers>.from(_listeners);

  static bool get hasListeners => _listeners.isNotEmpty;

  static void addListener(QuickMenuTriggers listener) => _listeners.add(listener);
  static void removeListener(QuickMenuTriggers listener) => _listeners.remove(listener);

  static Future<void> toggleQuickMenu(
      {QuickMenuPage type = QuickMenuPage.quickMenu, bool? visible, bool center = false}) async {
    if (visible != null) {
      if (visible == false && QuickMenuFunctions.keepOpen) {
        return;
      }
    }
    visible ??= !isQuickMenuVisible;
    isQuickMenuVisible = visible;

    for (final QuickMenuTriggers listener in listeners) {
      if (!_listeners.contains(listener)) return;
      await listener.onQuickMenuToggled(visible, type);
    }

    if (visible) {
      Globals.quickMenuPage = type;

      if (DateTime.now().millisecondsSinceEpoch - hidTime > 150) {
        Future<void>.delayed(const Duration(milliseconds: 100), () async {
          if (center) {
            Win32.setCenter(useMouse: true);
          } else {
            await Win32.setMainWindowToMousePos();
          }
          for (final QuickMenuTriggers listener in listeners) {
            if (!_listeners.contains(listener)) return;
            await listener.onQuickMenuShown(type);
          }
        });
      } else {
        visible = false;
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      if (!kReleaseMode) return;
      Win32.setPosition(const Offset(-99999, -99999));
      hidTime = DateTime.now().millisecondsSinceEpoch;
    }
  }
}
