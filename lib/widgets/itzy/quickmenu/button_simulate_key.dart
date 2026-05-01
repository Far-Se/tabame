import 'package:flutter/material.dart';

import '../../../models/win32/keys.dart';
import '../../widgets/quick_actions_item.dart';

class SimulateKeyButton extends StatelessWidget {
  final IconData icon;
  final String simulateKeys;
  final String singleKey;
  final double iconSize;
  final String tooltip;
  const SimulateKeyButton({
    super.key,
    required this.icon,

    /// [VK.KEY]
    this.simulateKeys = "",
    this.singleKey = "",
    this.iconSize = 0,
    this.tooltip = "",
  });

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: tooltip,
      icon: Icon(icon),
      onTap: () {
        if (simulateKeys.isNotEmpty) {
          WinKeys.send(simulateKeys);
        } else if (singleKey.isNotEmpty) {
          WinKeys.single(singleKey, KeySentMode.normal);
        }
      },
    );
  }
}
