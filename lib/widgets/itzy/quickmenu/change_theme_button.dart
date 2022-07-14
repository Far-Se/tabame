import 'package:flutter/material.dart';

import '../../../main.dart';

class ChangeThemeButton extends StatelessWidget {
  const ChangeThemeButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        onTap: () {
          darkThemeNotifier.value = !darkThemeNotifier.value;
        },
        child: const Tooltip(message: "Change Theme", child: Icon(Icons.theater_comedy_sharp)),
      ),
    );
  }
}
