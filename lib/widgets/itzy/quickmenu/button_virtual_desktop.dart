import 'package:flutter/material.dart';
import '../../../platform/windows/tabamewin32_api.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class VirtualDesktopButton extends StatelessWidget {
  const VirtualDesktopButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Move Desktop",
      icon: const Icon(Icons.display_settings_outlined),
      onTap: () async {
        await QuickMenuFunctions.hideQuickMenu();
        Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.right));
      },
      onSecondaryTap: () async {
        await QuickMenuFunctions.hideQuickMenu();
        Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.left));
      },
    );
  }
}
