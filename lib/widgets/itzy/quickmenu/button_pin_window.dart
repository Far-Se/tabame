import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/quick_actions_item.dart';

class PinWindowButton extends StatelessWidget {
  const PinWindowButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Pin window",
      icon: const Icon(Icons.pin_end),
      onTap: () async {
        if (Globals.lastFocusedWinHWND == 0) return;
        Win32.setAlwaysOnTop(Globals.lastFocusedWinHWND);
      },
    );
  }
}
