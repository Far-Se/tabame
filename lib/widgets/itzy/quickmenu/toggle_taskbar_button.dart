import 'package:flutter/material.dart';

import '../../../models/win32/win32.dart';

class ToggleTaskbarButton extends StatelessWidget {
  const ToggleTaskbarButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Toggle Taskbar", child: Icon(Icons.call_to_action_outlined)),
        onTap: () async {
          WinUtils.toggleTaskbar();
        },
      ),
    );
  }
}
