// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../models/keys.dart';

class SimulateKeyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String simulateKeys;
  final String singleKey;
  final double iconSize;
  const SimulateKeyButton({
    Key? key,
    required this.icon,

    /// [VK.KEY]
    this.simulateKeys = "",
    this.singleKey = "",
    this.color = Colors.white,
    this.iconSize = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = iconSize != 0 ? iconSize : Theme.of(context).iconTheme.size;
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size! + 5,
        child: IconButton(
          // constraints: BoxConstraints.loose(Size(13?, 13?)),
          iconSize: size,
          padding: EdgeInsets.all(0),
          splashRadius: size,
          icon: Icon(
            icon,
            color: color,
            // size: 15,
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
