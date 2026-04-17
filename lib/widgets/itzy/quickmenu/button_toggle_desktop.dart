import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/win32/keys.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class ToggleDesktopButton extends StatelessWidget {
  const ToggleDesktopButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 21,
        child: IconButton(
          iconSize: 16,
          padding: const EdgeInsets.all(0),
          splashRadius: 16,
          icon: const CustomTooltip(
            message: "Show Desktop",
            child: Icon(Icons.desktop_windows_rounded),
          ),
          onPressed: () {
            FocusScope.of(context).unfocus();
            SetFocus(GetDesktopWindow());
            Future<void>.delayed(const Duration(milliseconds: 200), () {
              WinKeys.send("{#WIN}D");
            });
          },
        ),
      ),
    );
  }
}
