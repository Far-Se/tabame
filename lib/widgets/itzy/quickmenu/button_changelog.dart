
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import '../../../pages/quickmenu.dart';

class CheckChangelogButton extends StatefulWidget {
  const CheckChangelogButton({super.key});
  @override
  CheckChangelogButtonState createState() => CheckChangelogButtonState();
}

class CheckChangelogButtonState extends State<CheckChangelogButton> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Tooltip(
        message: "See what's new!",
        child: SizedBox(
          width: 20,
          child: IconButton(
            padding: const EdgeInsets.all(0),
            splashRadius: 25,
            icon: const Icon(
              Icons.newspaper,
            ),
            onPressed: () {
              if (kReleaseMode) {
                QuickMenuFunctions.toggleQuickMenu(visible: false);
                int hWnd = Win32.findWindow("Tabame - Interface");
                if (hWnd == 0) {
                  WinUtils.startTabame(closeCurrent: false, arguments: "-interface -changelog");
                } else {
                  Win32.activateWindow(hWnd);
                  return;
                }
                return;
              }
              final QuickMenuState? x = context.findAncestorStateOfType<QuickMenuState>();
              Globals.changingPages = true;
              x?.setState(() {});
              mainPageViewController.jumpToPage(Pages.interface.index);
              Globals.changingPages = true;
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              return;
            },
          ),
        ),
      ),
    );
  }
}
