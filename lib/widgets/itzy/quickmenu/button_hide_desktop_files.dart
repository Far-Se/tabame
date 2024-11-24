import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';

class HideDesktopFilesButton extends StatelessWidget {
  const HideDesktopFilesButton({super.key});

  @override
  Widget build(BuildContext context) {
    // return QuickActionItem(message: "Toggle Desktop Files", icon: const Icon(Icons.hide_image_outlined), onTap: () => WinUtils.toggleDesktopFiles());
    if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 25,
            child: InkWell(
              onTap: () => WinUtils.toggleDesktopFiles(visible: false),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.hide_image_outlined)),
                  SizedBox(width: 5),
                  Text("Hide Desktop Files")
                ],
              ),
            ),
          ),
          SizedBox(
            height: 25,
            child: InkWell(
              onTap: () => WinUtils.toggleDesktopFiles(visible: true),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.image_outlined)),
                  SizedBox(width: 5),
                  Text("Show Desktop Files")
                ],
              ),
            ),
          )
        ],
      );
    }
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        onTap: () async => WinUtils.toggleDesktopFiles(),
        child: GestureDetector(
          onSecondaryTap: () => WinUtils.toggleDesktopFiles(visible: false),
          onTertiaryTapUp: (TapUpDetails details) => WinUtils.toggleDesktopFiles(visible: true),
          child: const Tooltip(message: "Toggle Desktop Files", child: Icon(Icons.hide_image_outlined)),
        ),
      ),
    );
  }
}
