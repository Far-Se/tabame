import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class KeystrokesButton extends StatelessWidget {
  const KeystrokesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Input Visualizer",
      icon: const Icon(Icons.keyboard_alt_outlined),
      hoverColor: Design.accentHue(58, saturation: 0.92),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Keystrokes");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          QuickMenuFunctions.hideQuickMenu();
          WinUtils.startTabame(closeCurrent: false, arguments: "-keystrokes");
        }
      },
    );
  }
}
