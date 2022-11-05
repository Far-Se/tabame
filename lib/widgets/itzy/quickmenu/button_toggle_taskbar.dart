import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';
import '../../widgets/quick_actions_item.dart';

class ToggleTaskbarButton extends StatelessWidget {
  const ToggleTaskbarButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Toggle Taskbar",
      icon: const Icon(Icons.call_to_action_outlined),
      onTap: () async {
        WinUtils.toggleTaskbar();
      },
    );
  }
}
