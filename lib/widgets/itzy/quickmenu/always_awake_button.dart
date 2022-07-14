import 'package:flutter/material.dart';

import '../../../models/globals.dart';

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
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: Tooltip(message: "Always awake", child: Icon(Icons.running_with_errors, color: Globals.alwaysAwake ? Colors.red : Theme.of(context).iconTheme.color)),
        onTap: () async {
          Globals.alwaysAwake = !Globals.alwaysAwake;
          Globals.alwaysAwakeRun(Globals.alwaysAwake);
          setState(() {});
        },
      ),
    );
  }
}
