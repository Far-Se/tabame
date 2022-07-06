// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

import '../../models/keys.dart';

class SimulateKeyButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String simulateKeys;
  final String singleKey;
  const SimulateKeyButton({
    Key? key,
    required this.icon,
    this.simulateKeys = "",
    required this.color,
    this.singleKey = "",
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: 25,
          child: IconButton(
            // constraints: BoxConstraints.loose(Size(13?, 13?)),
            iconSize: 18,
            padding: EdgeInsets.all(0),
            splashRadius: 18,
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
        ));
  }
}
