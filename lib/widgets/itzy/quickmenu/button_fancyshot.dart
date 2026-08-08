import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../pages/screen_capture.dart';
import '../../../platform/screen_capture_service.dart';
import '../../widgets/quick_actions_item.dart';

class PhotoEditorButton extends StatelessWidget {
  const PhotoEditorButton({super.key});

  @override
  Widget build(BuildContext context) {
    final ScreenCaptureService capture = ScreenCaptureService.instance;
    final bool available = capture.isAvailable;
    return QuickActionItem(
      message: available ? "Open Photo Editor" : "Photo Editor unavailable: ${capture.unavailableReason}",
      hoverColor: Design.accentHue(58, saturation: 0.92),
      icon: Icon(Icons.photo_camera_back_outlined, color: available ? null : Colors.white38),
      onTap: available
          ? () async {
              if (QuickMenuFunctions.isQuickMenuVisible) {
                QuickMenuFunctions.hideQuickMenu();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              WinUtils.startTabame(arguments: "-editor");
            }
          : null,
    );
  }
}

class FancyShotButton extends StatelessWidget {
  final bool freeze;
  const FancyShotButton({super.key, this.freeze = false});

  @override
  Widget build(BuildContext context) {
    final ScreenCaptureService capture = ScreenCaptureService.instance;
    final bool available = capture.isAvailable;
    return QuickActionItem(
      message: available
          ? (freeze ? "Open Frozen Fancyshot" : "Open Live Fancyshot")
          : "FancyShot unavailable: ${capture.unavailableReason}",
      hoverColor: Design.accentHue(58, saturation: 0.92),
      icon: Icon(
        freeze ? Icons.center_focus_strong : Icons.center_focus_strong_outlined,
        color: available ? null : Colors.white38,
      ),
      onTap: available
          ? () async {
              if (QuickMenuFunctions.isQuickMenuVisible) {
                QuickMenuFunctions.hideQuickMenu();
                await Future<void>.delayed(const Duration(milliseconds: 50));
              }
              await FancyShotCaptureWidget.captureScreenshots();
              // WinUtils.startTabame(closeCurrent: false, arguments: freeze ? "-capture -freeze" : "-capture");
              Globals.quickMenuPage = freeze ? QuickMenuPage.fancyShotFreeze : QuickMenuPage.fancyShotLive;
              QuickMenuFunctions.refreshQuickMenu();
            }
          : null,
    );
  }
}
