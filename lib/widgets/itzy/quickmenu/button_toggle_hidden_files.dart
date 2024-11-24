import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';

class ToggleHiddenFilesButton extends StatelessWidget {
  const ToggleHiddenFilesButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => WinUtils.toggleHiddenFiles(visible: false),
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.folder_off_outlined)),
                  SizedBox(width: 5),
                  Text("Hide Hidden Files")
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () => WinUtils.toggleHiddenFiles(visible: true),
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.folder_outlined)),
                  SizedBox(width: 5),
                  Text("Show Hidden Files")
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
      child: GestureDetector(
        onSecondaryTap: () => WinUtils.toggleHiddenFiles(visible: false),
        onTertiaryTapUp: (TapUpDetails details) => WinUtils.toggleHiddenFiles(visible: true),
        child: InkWell(
          child: const Tooltip(message: "Toggle Hidden Files", child: Icon(Icons.folder_off_outlined)),
          onTap: () async {
            WinUtils.toggleHiddenFiles();
          },
        ),
      ),
    );
  }
}
