import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ScreenRecordingButton extends StatelessWidget {
  const ScreenRecordingButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Open Screen Recording",
      icon: const Icon(Icons.camera),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Screen Recording");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          QuickMenuFunctions.hideQuickMenu();
          WinUtils.startTabame(closeCurrent: false, arguments: "-screenRecording");
        }
      },
    );
  }
}
