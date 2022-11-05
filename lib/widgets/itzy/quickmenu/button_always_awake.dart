import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/quick_actions_item.dart';

class AlwaysAwakeButton extends StatefulWidget {
  const AlwaysAwakeButton({
    Key? key,
  }) : super(key: key);

  @override
  State<AlwaysAwakeButton> createState() => _AlwaysAwakeButtonState();
}

class _AlwaysAwakeButtonState extends State<AlwaysAwakeButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Always awake",
      icon: Icon(Icons.running_with_errors, color: Globals.alwaysAwake ? Colors.red : Theme.of(context).iconTheme.color),
      onTap: () async {
        Globals.alwaysAwake = !Globals.alwaysAwake;
        WinUtils.alwaysAwakeRun(Globals.alwaysAwake);
        setState(() {});
      },
    );
  }
}
