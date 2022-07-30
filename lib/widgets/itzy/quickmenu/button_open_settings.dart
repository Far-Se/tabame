import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../pages/quickmenu.dart';

class OpenSettingsButton extends StatelessWidget {
  const OpenSettingsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 25,
        child: IconButton(
          padding: const EdgeInsets.all(0),
          splashRadius: 25,
          icon: const Icon(
            Icons.settings,
          ),
          onPressed: () {
            if (kReleaseMode) {
              int hWnd = Win32.findWindow("Tabame - Interface");
              if (hWnd == 0) {
                WinUtils.startTabame(closeCurrent: false, arguments: "-interface");
              } else {
                Win32.activateWindow(hWnd);
                return;
              }
              bool settingsChanged = globalSettings.settingsChanged;
              Boxes().watchForSettingsChange();
              Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
                if (settingsChanged != globalSettings.settingsChanged) {
                  themeChangeNotifier.value = !themeChangeNotifier.value;
                  settingsChanged = globalSettings.settingsChanged;
                }
              });
              // themeChangeNotifier.value = !themeChangeNotifier.value;
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
        ),
      ),
    );
  }
}
