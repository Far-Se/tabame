import 'package:flutter/material.dart';

import 'button_simulate_key.dart';

class TaskManagerButton extends StatelessWidget {
  const TaskManagerButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // ignore: prefer_const_constructors
    return SimulateKeyButton(
      icon: Icons.app_registration,
      simulateKeys: "{#CTRL}{#SHIFT}{ESC}",
      tooltip: "Open Task Manager",
    );
  }
}
