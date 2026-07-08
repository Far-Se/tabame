import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

/// Launches the Screen Ruler overlay (pixel measure + loupe) as its own
/// process; tapping again while it's open closes it.
class ScreenRulerButton extends StatelessWidget {
  const ScreenRulerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Screen Ruler",
      icon: const Icon(Icons.straighten_rounded),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Screen Ruler");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          QuickMenuFunctions.hideQuickMenu();
          WinUtils.startTabame(closeCurrent: false, arguments: "-screenRuler");
        }
      },
    );
  }
}
