import 'package:flutter/material.dart';

import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ToggleWindowsThemeButton extends StatelessWidget {
  const ToggleWindowsThemeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Toggle Windows Theme",
      icon: const Icon(Icons.desktop_mac),
      onTap: () {
        final int theme = WinUtils.getWindowsTheme();
        WinUtils.setWindowsTheme(theme == 1 ? 0 : 1);
      },
    );
  }
}
