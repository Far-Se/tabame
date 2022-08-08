import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/keys.dart';

class ToggleDesktopButton extends StatelessWidget {
  const ToggleDesktopButton({Key? key}) : super(key: key);

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
          icon: const Tooltip(
            message: "Show Desktop",
            child: Icon(Icons.desktop_windows),
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
