import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/win32/win32.dart';

class VirtualDesktopButton extends StatelessWidget {
  const VirtualDesktopButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () {},
          child: GestureDetector(
            onTap: () {
              WinUtils.moveDesktop(DesktopDirection.right);
            },
            onSecondaryTap: () {
              WinUtils.moveDesktop(DesktopDirection.left);
            },
            child: const Tooltip(message: "Move Desktop", child: Icon(Icons.display_settings_outlined)),
          ),
        ),
      ),
    );
  }
}
