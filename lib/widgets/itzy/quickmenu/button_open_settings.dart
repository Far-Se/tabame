import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../../pages/quickmenu.dart';
import '../../widgets/custom_tooltip.dart';
import 'system_power_panel.dart';

class OpenSettingsButton extends StatelessWidget {
  const OpenSettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 25,
        child: GestureDetector(
          onSecondaryTap: () {
            showQuickMenuModal(
              context: context,
              child: const SystemPowerWidget(),
            );
          },
          child: CustomTooltip(
            message: user.autoCheckForUpdates && Globals.version != user.newVersion
                ? "New Version Available\nRight-click for power"
                : "Settings\nRight-click for power",
            child: IconButton(
              padding: const EdgeInsets.all(0),
              splashRadius: 25,
              icon: user.autoCheckForUpdates && Globals.version != user.newVersion
                  ? const Icon(Icons.new_releases)
                  : const Icon(Icons.settings),
              onPressed: () {
                // if (Boxes.quickTimers.isNotEmpty) {
                //   WinUtils.msgBox("You Have Running Timers", "You Have Running Timers and you can not open Settings because you will loose them.");
                //   return;
                // }
                if (kReleaseMode) {
                  QuickMenuFunctions.hideQuickMenu();
                  int hWnd = Win32.findWindow("Tabame - Interface");
                  if (hWnd == 0) {
                    WinUtils.startTabame(closeCurrent: false, arguments: "-interface");
                  } else {
                    Win32.activateWindow(hWnd);
                    return;
                  }
                  // bool settingsChanged = userSettings.settingsChanged;
                  // Boxes().watchForSettingsChange();
                  // Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
                  //   if (settingsChanged != userSettings.settingsChanged) {
                  //     Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                  //     settingsChanged = userSettings.settingsChanged;
                  //   }
                  // });
                  // Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                  return;
                }
                final QuickMenuState? x = context.findAncestorStateOfType<QuickMenuState>();
                Globals.changingPages = true;
                //ignore: invalid_use_of_protected_member
                x?.setState(() {});
                Globals.mainPageViewController.jumpToPage(Pages.interface.index);
                Globals.changingPages = true;
                return;
              },
            ),
          ),
        ),
      ),
    );
  }
}
