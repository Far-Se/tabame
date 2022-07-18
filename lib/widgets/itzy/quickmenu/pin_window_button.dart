import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';

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
          Win32.setAlwaysOnTop(Globals.lastFocusedWinHWND);
        },
      ),
    );
  }
}
