import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../platform/screen_capture_service.dart';
import '../../widgets/quick_actions_item.dart';

class ScreenDrawButton extends StatelessWidget {
  const ScreenDrawButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ScreenCaptureService capture = ScreenCaptureService.instance;
    final bool available = capture.isAvailable;
    return QuickActionItem(
      message: available ? "Open Screen Draw" : "Screen Draw unavailable: ${capture.unavailableReason}",
      icon: Icon(Icons.draw_outlined, color: available ? null : Colors.white38),
      hoverColor: Design.accentHue(58, saturation: 0.92),
      onTap: available
          ? () {
              final int windowHwnd = Win32.findWindow("Tabame Screen Draw");
              if (windowHwnd != 0) {
                Win32.closeWindow(windowHwnd);
              } else {
                QuickMenuFunctions.hideQuickMenu();
                WinUtils.startTabame(closeCurrent: false, arguments: "-screenDraw");
              }
            }
          : null,
    );
  }
}
