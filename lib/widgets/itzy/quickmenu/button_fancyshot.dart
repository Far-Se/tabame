import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../pages/screen_capture.dart';
import '../../widgets/quick_actions_item.dart';

class PhotoEditorButton extends StatelessWidget {
  const PhotoEditorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Open Photo Editor",
      hoverColor: Design.accentHue(58, saturation: 0.92),
      icon: const Icon(Icons.photo_camera_back_outlined),
      onTap: () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          QuickMenuFunctions.hideQuickMenu();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        WinUtils.startTabame(arguments: "-editor");
      },
    );
  }
}

class FancyShotButton extends StatelessWidget {
  final bool freeze;
  const FancyShotButton({super.key, this.freeze = false});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: freeze ? "Open Frozen Fancyshot" : "Open Live Fancyshot",
      hoverColor: Design.accentHue(58, saturation: 0.92),
      icon: freeze ? const Icon(Icons.center_focus_strong) : const Icon(Icons.center_focus_strong_outlined),
      onTap: () async {
        if (QuickMenuFunctions.isQuickMenuVisible) {
          QuickMenuFunctions.hideQuickMenu();
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await FancyShotCaptureWidget.captureScreenshots();
        // WinUtils.startTabame(closeCurrent: false, arguments: freeze ? "-capture -freeze" : "-capture");
        Globals.quickMenuPage = freeze ? QuickMenuPage.fancyShotFreeze : QuickMenuPage.fancyShotLive;
        QuickMenuFunctions.refreshQuickMenu();
      },
    );
  }
}
