import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';

class HideDesktopFilesButton extends StatelessWidget {
  const HideDesktopFilesButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    //return QuickActionItem(message: "Toggle Desktop Files", icon: const Icon(Icons.hide_image_outlined), onTap: () => WinUtils.toggleDesktopFiles());
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        onTap: () async => WinUtils.toggleDesktopFiles(),
        child: GestureDetector(
          onSecondaryTap: () => WinUtils.toggleDesktopFiles(visible: false),
          onTertiaryTapUp: (TapUpDetails details) => WinUtils.toggleDesktopFiles(visible: true),
          child: const Tooltip(message: "Toggle Desktop Files", child: Icon(Icons.hide_image)),
        ),
      ),
    );
  }
}
