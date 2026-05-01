import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ScreenDrawButton extends StatelessWidget {
  const ScreenDrawButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Open Screen Draw",
      icon: const Icon(Icons.draw_outlined),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Screen Draw");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: "-screenDraw");
        }
      },
    );
  }
}
