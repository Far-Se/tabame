import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/win32/keys.dart';
import '../../widgets/quick_actions_item.dart';

class ToggleDesktopButton extends StatelessWidget {
  const ToggleDesktopButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Show Desktop",
      icon: const Icon(Icons.desktop_windows_rounded),
      onTap: () {
        FocusScope.of(context).unfocus();
        SetFocus(GetDesktopWindow());
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          WinKeys.send("{#WIN}D");
        });
      },
    );
  }
}
