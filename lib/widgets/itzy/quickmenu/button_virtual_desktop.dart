import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';

class VirtualDesktopButton extends StatelessWidget {
  const VirtualDesktopButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () async {
              await QuickMenuFunctions.toggleQuickMenu(visible: false);
              Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.left));
            },
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.display_settings_outlined)),
                  SizedBox(width: 5),
                  Text("Move Desktop to Left")
                ],
              ),
            ),
          ),
          InkWell(
            onTap: () async {
              await QuickMenuFunctions.toggleQuickMenu(visible: false);
              Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.right));
            },
            child: const SizedBox(
              height: 25,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(width: 5),
                  SizedBox(width: 20, child: Icon(Icons.display_settings_outlined)),
                  SizedBox(width: 5),
                  Text("Move Desktop to Right")
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
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {},
          child: GestureDetector(
            onTap: () async {
              await QuickMenuFunctions.toggleQuickMenu(visible: false);
              Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.right));
            },
            onSecondaryTap: () async {
              await QuickMenuFunctions.toggleQuickMenu(visible: false);
              Future<void>.delayed(const Duration(milliseconds: 200), () => WinUtils.moveDesktop(DesktopDirection.left));
            },
            child: const Tooltip(message: "Move Desktop", child: Icon(Icons.display_settings_outlined)),
          ),
        ),
      ),
    );
  }
}
