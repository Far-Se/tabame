import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../widgets/quick_actions_item.dart';

class DesktopFilesButton extends StatelessWidget {
  const DesktopFilesButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Desktop Files Search",
      icon: const Icon(Icons.desktop_windows_outlined),
      onTap: () {
        Globals.quickMenuPage = QuickMenuPage.launcher;
        Globals.clearQuickMenuSearchInput();
        Globals.queueQuickMenuSearchInput(';');
        QuickMenuFunctions.refreshQuickMenu();
      },
    );
  }
}
