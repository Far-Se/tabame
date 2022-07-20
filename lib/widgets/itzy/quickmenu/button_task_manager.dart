import 'package:flutter/material.dart';

import 'button_simulate_key.dart';

class TaskManagerButton extends StatelessWidget {
  const TaskManagerButton({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SimulateKeyButton(
      icon: Icons.app_registration,
      simulateKeys: "{#CTRL}{#SHIFT}{ESC}",
      tooltip: "Open Task Manager",
    );
  }
  /* Widget build(BuildContext context) {
    final taskManagerPath = WinUtils().getTaskManagerPath();
    if (taskManagerPath == "") return const SizedBox();
    return WindowsAppButton(path: taskManagerPath);
  } */
}
