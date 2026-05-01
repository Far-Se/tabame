import 'package:flutter/material.dart';

import '../../../models/win32/win_utils.dart';
import '../../widgets/quick_actions_item.dart';

class ToggleWallpaperModeButton extends StatelessWidget {
  const ToggleWallpaperModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Toggle Wallpaper",
      icon: const Icon(Icons.wallpaper_rounded),
      onTap: () async {
        final DesktopBackgroundType state = WinUtils.getDesktopBackgroundType();

        if (state == DesktopBackgroundType.wallpaper) {
          await WinUtils.toggleDesktopWallpaper(false);
          return;
        }

        await WinUtils.toggleDesktopWallpaper(true);
      },
    );
  }
}
