import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/settings.dart';
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
      hoverColor: Design.accentHue(58, saturation: 0.92),
      onTap: () {
        final int spotlightHwnd = Win32.findWindow("Tabame Spotlight");
        if (spotlightHwnd != 0) {
          Win32.closeWindow(spotlightHwnd);
        } else {
          QuickMenuFunctions.hideQuickMenu();
          WinUtils.startTabame(closeCurrent: false, arguments: "-spotlight");
        }
      },
    );
  }
}
