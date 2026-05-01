import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../widgets/quick_actions_item.dart';

class LauncherButton extends StatelessWidget {
  const LauncherButton({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isLauncher = Globals.quickMenuPage == QuickMenuPage.launcher;
    return QuickActionItem(
      message: isLauncher ? "Back to Menu" : "Launcher",
      icon: Icon(isLauncher ? Icons.arrow_back_rounded : Icons.search_rounded),
      onTap: () {
        if (isLauncher) {
          QuickMenuFunctions.triggerQuickAction("page:quickMenu");
        } else {
          QuickMenuFunctions.triggerQuickAction("page:launcher");
        }
      },
    );
  }
}
