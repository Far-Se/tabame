import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/win32/win32.dart';
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
          await toggleMonitorWallpaper(false);
          // await setWallpaperColor(0x00000000);
          return;
        }

        await toggleMonitorWallpaper(true);
      },
    );
  }
}
