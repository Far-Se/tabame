import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/quick_actions_item.dart';

class FancyShotButton extends StatelessWidget {
  final bool freeze;
  const FancyShotButton({super.key, this.freeze = false});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: freeze ? "Open Frozen Screen Capture" : "Open Screen Capture",
      icon: freeze ? const Icon(Icons.center_focus_strong) : const Icon(Icons.center_focus_strong_outlined),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Screen Capture");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          // WinUtils.startTabame(closeCurrent: false, arguments: freeze ? "-capture -freeze" : "-capture");
          Globals.quickMenuPage = freeze ? QuickMenuPage.fancyShotFreeze : QuickMenuPage.fancyShotLive;
          QuickMenuFunctions.refreshQuickMenu();
        }
      },
    );
  }
}
