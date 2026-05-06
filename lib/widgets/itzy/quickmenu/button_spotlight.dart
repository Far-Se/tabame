import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class SpotlightButton extends StatelessWidget {
  const SpotlightButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Open Spotlight",
      icon: const Icon(Icons.no_flash),
      onTap: () {
        final int spotlightHwnd = Win32.findWindow("Tabame Spotlight");
        if (spotlightHwnd != 0) {
          Win32.closeWindow(spotlightHwnd);
        } else {
          WinUtils.startTabame(closeCurrent: false, arguments: "-spotlight");
        }
      },
    );
  }
}
