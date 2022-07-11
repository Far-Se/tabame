import 'package:flutter/material.dart';

import '../../models/keys.dart';

class SimulateKeyButton extends StatelessWidget {
  final IconData icon;
  final String simulateKeys;
  final String singleKey;
  final double iconSize;
  final String tooltip;
  const SimulateKeyButton({
    Key? key,
    required this.icon,

    /// [VK.KEY]
    this.simulateKeys = "",
    this.singleKey = "",
    this.iconSize = 0,
    this.tooltip = "",
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final double? size = iconSize != 0 ? iconSize : Theme.of(context).iconTheme.size;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size! + 5,
        child: IconButton(
          iconSize: size,
          padding: const EdgeInsets.all(0),
          splashRadius: size,
          icon: Tooltip(
            message: tooltip,
            child: Icon(icon),
          ),
          onPressed: () {
            if (simulateKeys.isNotEmpty) {
              WinKeys.send(simulateKeys);
            } else if (singleKey.isNotEmpty) {
              WinKeys.single(singleKey, KeySentMode.normal);
            }
          },
        ),
      ),
    );
  }
}
