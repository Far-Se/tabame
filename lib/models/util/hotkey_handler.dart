import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../classes/boxes.dart';
import '../classes/hotkeys.dart';
import '../globals.dart';
import '../settings.dart';
import '../win32/keys.dart';

class HotkeyHandler {
  Point<int> mouseSteps = const Point<int>(0, 0);
  int startMouseDir = 0;
  Map<String, int> hotkeyDoublePress = <String, int>{};
  Map<String, int> hotkeyMovement = <String, int>{};
  int currentVK = -1;
  void handle(HotkeyEvent hotkeyInfo) {
    if (!kReleaseMode && !Globals.debugHotkeys) return;
    final List<Hotkeys> hk = <Hotkeys>[...Boxes.remap.where((Hotkeys element) => element.hotkey == hotkeyInfo.hotkey).toList()];
    if (hk.isEmpty) return;
    final Hotkeys hotkey = hk[0];

    //* Keyboard listen to release
    if (hotkeyInfo.action == "pressedKbd") {
      //
      final int key = keyMap.containsKey("VK_${hotkey.key.toUpperCase()}") ? keyMap["VK_${hotkey.key.toUpperCase()}"]! : -1;
      if (key == -1) return;
      currentVK = key;

      if (hotkey.hasMouseMovementTriggers) {
        mouseSteps = hotkeyInfo.mouse.start;
      }
    }
    if (hotkeyInfo.action == "releaseKbd") {
      // NativeHotkey.free();
      if (hotkeyInfo.vk == currentVK) {
        currentVK = -1;
        NativeHooks.freeHotkeys();
        hotkeyInfo.action = "released";
        for (final TabameListener listener in NativeHooks.listeners) {
          if (!NativeHooks.listenersObv.contains(listener)) return;
          listener.onHotKeyEvent(hotkeyInfo);
        }
        return;
      }
    }

    ///
    if (hotkeyInfo.action == "pressed") {
      if (hotkey.hasMouseMovementTriggers) {
        mouseSteps = hotkeyInfo.mouse.start;
      }
    }
    if (hotkeyInfo.action == "moved") {
      if (hotkey.hasMouseMovementTriggers && startMouseDir == 0) {
        Point<int> diffAux = hotkeyInfo.mouse.end - mouseSteps;
        Point<int> diff = Point<int>(diffAux.x.abs(), diffAux.y.abs());
        if (diff.x + diff.y > 40) startMouseDir = diff.x > diff.y ? 1 : 2;
      }

      if (startMouseDir != 0) {
        final List<KeyMap> list = hotkey.getHotkeysWithMovementTriggers;
        if (list.isNotEmpty) {
          for (KeyMap key in list) {
            if (!key.isMouseInRegion) continue;
            Point<int> diffAux = hotkeyInfo.mouse.end - mouseSteps;
            if ((startMouseDir == 1 && key.triggerInfo[0] == 0 && diffAux.x < 0 && diffAux.x.abs() > key.triggerInfo[1]) ||
                ((startMouseDir == 1 && key.triggerInfo[0] == 1 && diffAux.x > 0 && diffAux.x.abs() > key.triggerInfo[1])) ||
                ((startMouseDir == 2 && key.triggerInfo[0] == 2 && diffAux.y < 0 && diffAux.y.abs() > key.triggerInfo[1])) ||
                ((startMouseDir == 2 && key.triggerInfo[0] == 3 && diffAux.y > 0 && diffAux.y.abs() > key.triggerInfo[1]))) {
              mouseSteps = hotkeyInfo.mouse.end;
              hotkeyMovement[hotkeyInfo.hotkey] = 1;
              key.applyActions();
            }
          }
        }
      }
    }

    if (hotkeyInfo.action == "released") {
      if (hotkeyMovement.containsKey(hotkeyInfo.hotkey)) {
        hotkeyMovement.remove(hotkeyInfo.hotkey);
        return;
      }
      startMouseDir = 0;
      final List<KeyMap> mouseDir = hotkey.getHotkeysWithMovement;
      mouseDir.sort((KeyMap a, KeyMap b) => a.boundToRegion
          ? -1
          : b.boundToRegion
              ? -1
              : 1);
      // ? Direction
      if (mouseDir.isNotEmpty) {
        final Point<int> diff = hotkeyInfo.mouse.diff;
        final int diffX = diff.x.abs();
        final int diffY = diff.y.abs();
        for (KeyMap key in mouseDir) {
          if (!key.isMouseInRegion) continue;
          // left right up down
          if ((key.triggerInfo[0] == 0 && diff.x < 0 && diffX.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2])) ||
              ((key.triggerInfo[0] == 1 && diff.x > 0 && diffX.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2]))) ||
              ((key.triggerInfo[0] == 2 && diff.y < 0 && diffY.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2]))) ||
              ((key.triggerInfo[0] == 3 && diff.y > 0 && diffY.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2])))) {
            key.applyActions();
            return;
          }
        }
      }
      // ? Duration
      List<KeyMap> keys = hotkey.getDurationKeys;
      mouseDir.sort((KeyMap a, KeyMap b) => a.boundToRegion
          ? -1
          : b.boundToRegion
              ? -1
              : 1);
      if (keys.isNotEmpty) {
        final int diff = hotkeyInfo.time.duration;
        for (KeyMap key in keys) {
          if (!key.isMouseInRegion) continue;
          if (diff.isBetweenEqual(key.triggerInfo[0], key.triggerInfo[1])) {
            key.applyActions();
            return;
          }
        }
      }
      // ?Region
      if (hotkeyDoublePress.containsKey(hotkey.hotkey) && hotkeyInfo.name.isNotEmpty) {
        keys = hotkey.keymaps.where((KeyMap element) => element.boundToRegion && element.triggerType == TriggerType.doublePress).toList();
        for (KeyMap key in keys) {
          if (key.isMouseInRegion) {
            if (hotkeyInfo.time.end - hotkeyDoublePress[hotkey.hotkey]! < 300) {
              key.applyActions();
              hotkeyDoublePress.remove(hotkey.hotkey);
              return;
            } else {
              hotkeyDoublePress.remove(hotkey.hotkey);
            }
          }
        }
      }
      keys = hotkey.keymaps.where((KeyMap element) => element.boundToRegion && element.triggerType == TriggerType.press).toList();
      if (hotkeyInfo.name.isNotEmpty) {
        for (KeyMap key in keys) {
          if (key.isMouseInRegion) {
            if (hotkey.hasDoublePress) {
              hotkeyDoublePress[hotkey.hotkey] = hotkeyInfo.time.end;
            }
            key.applyActions();
            return;
          }
        }
      }

      // ?Double press
      if (hotkeyDoublePress.containsKey(hotkey.hotkey)) {
        keys = hotkey.getDoublePress;
        for (KeyMap key in keys) {
          if (!key.isMouseInRegion) continue;
          if (hotkeyInfo.time.end - hotkeyDoublePress[hotkey.hotkey]! < 300) {
            key.applyActions();
            hotkeyDoublePress.remove(hotkey.hotkey);
            return;
          }
        }
        hotkeyDoublePress.remove(hotkey.hotkey);
      }
      // ?Normal
      keys = hotkey.getPress;
      for (KeyMap key in keys) {
        if (!key.isMouseInRegion) continue;
        if (hotkeyInfo.name.isNotEmpty && key.name != hotkeyInfo.name) continue;
        if (hotkey.hasDoublePress) {
          hotkeyDoublePress[hotkey.hotkey] = hotkeyInfo.time.end;
        }
        key.applyActions();
      }
    }
  }
}
