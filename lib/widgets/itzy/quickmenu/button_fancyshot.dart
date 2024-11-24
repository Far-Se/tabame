import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import '../../../pages/quickmenu.dart';
import '../../widgets/quick_actions_item.dart';

class FancyShotButton extends StatelessWidget {
  const FancyShotButton({super.key});
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "FancyShot",
      icon: const Icon(Icons.center_focus_strong_rounded),
      onTap: () async {
        QuickMenuFunctions.toggleQuickMenu(visible: false);
        await WinUtils.screenCapture();

        if (kReleaseMode) {
          WinUtils.startTabame(closeCurrent: false, arguments: "-interface -fancyshot");
          return;
        }
        final QuickMenuState? x = context.findAncestorStateOfType<QuickMenuState>();
        Globals.changingPages = true;
        //ignore: invalid_use_of_protected_member
        x?.setState(() {});
        mainPageViewController.jumpToPage(Pages.interface.index);
        Globals.changingPages = true;
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        return;
      },
    );
  }
}
