import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class QuickSnapStandalone extends StatelessWidget {
  const QuickSnapStandalone({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Open QuickSnap Standalone",
      icon: const Icon(Icons.view_quilt_rounded),
      onTap: () {
        final int hWnd = Win32.findWindow("Tabame QuickSnap");
        if (hWnd != 0) {
          Win32.closeWindow(hWnd);
        } else {
          QuickMenuFunctions.hideQuickMenu();
          WinUtils.startTabame(closeCurrent: false, arguments: "-quickSnap", admin: true);
        }
      },
    );
  }
}
