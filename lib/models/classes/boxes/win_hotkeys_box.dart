import 'package:flutter/foundation.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../globals.dart';
import '../hotkeys.dart';
import '../boxes.dart';

// --------------------------------------------------------------------------
// WinHotkeys
// --------------------------------------------------------------------------

class WinHotkeys {
  static Future<void> update() async {
    final List<Map<String, dynamic>> allHotkeys = <Map<String, dynamic>>[];
    final List<Hotkeys> bindHotkeys = <Hotkeys>[...Boxes.remap];

    for (Hotkeys hotkeys in bindHotkeys) {
      hotkeys.keymaps.sort((KeyMap a, KeyMap b) {
        final int pos = a.boundToRegion == true ? -1 : 0;
        return pos == 0 ? 1 : pos;
      });

      for (KeyMap hotkey in hotkeys.keymaps) {
        if (!hotkey.enabled) continue;
        allHotkeys.add(<String, dynamic>{
          "name": hotkey.name,
          "hotkey": hotkeys.hotkey.toUpperCase(),
          "keyVK": Hotkeys.keyToVirtualKey(hotkeys.key) ?? -1,
          "modifisers": hotkeys.modifiers.isNotEmpty ? hotkeys.modifiers.join('+').toUpperCase() : "noModifiers",
          "listenToMovement":
              hotkeys.keymaps.any((KeyMap e) => e.triggerType == TriggerType.movement && e.triggerInfo[2] == -1),
          "matchWindowBy": hotkey.windowsInfo[0] == "any" ? "" : hotkey.windowsInfo[0],
          "matchWindowText": hotkey.windowsInfo[1],
          "activateWindowUnderCursor": hotkey.windowUnderMouse,
          "noopScreenBusy": hotkeys.noopScreenBusy,
          "prohibitedWindows": hotkeys.prohibited.join(";"),
          "regionasPercentage": hotkey.region.asPercentage,
          "regionOnScreen": hotkey.regionOnScreen,
          "regionX1": hotkey.region.x1,
          "regionX2": hotkey.region.x2,
          "regionY1": hotkey.region.y1,
          "regionY2": hotkey.region.y2,
          "anchorType": !hotkey.boundToRegion ? 0 : hotkey.region.anchorType.index + 1,
        });
      }
    }

    if (Globals.debugHooks || kReleaseMode) {
      NativeHooks.runHotkeys(allHotkeys);
    }
  }
}
