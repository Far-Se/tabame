import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/globals.dart';
import '../../../models/win32/imports.dart';

class PinWindowButton extends StatelessWidget {
  const PinWindowButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Pin window", child: Icon(Icons.pin_end)),
        onTap: () async {
          if (Globals.lastFocusedWinHWND == 0) return;
          final int exstyle = GetWindowLong(Globals.lastFocusedWinHWND, GWL_EXSTYLE);
          final int topmostOrNot = (exstyle & WS_EX_TOPMOST) != 0 ? HWND_NOTOPMOST : HWND_TOPMOST;
          SetWindowPos(Globals.lastFocusedWinHWND, topmostOrNot, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        },
      ),
    );
  }
}
