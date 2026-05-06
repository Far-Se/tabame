import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ScreenCaptureButton extends StatelessWidget {
  final bool freeze;
  const ScreenCaptureButton({super.key, this.freeze = false});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: freeze ? "Open Frozen Screen Capture" : "Open Screen Capture",
      icon: freeze ? const Icon(Icons.dvr_outlined) : const Icon(Icons.featured_video_rounded),
      onTap: () {
        final int windowHwnd = Win32.findWindow("Tabame Screen Capture");
        if (windowHwnd != 0) {
          Win32.closeWindow(windowHwnd);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: freeze ? "-capture -freeze" : "-capture");
        }
      },
    );
  }
}
