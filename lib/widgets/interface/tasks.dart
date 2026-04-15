import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import 'reminders.dart';
import '../widgets/info_text.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  TasksPageState createState() => TasksPageState();
}

class TasksPageState extends State<TasksPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: TasksReminders(),
                ),
              ),
            ],
          ),
        ),
        CheckboxListTile(
          value: globalSettings.usePowerShellAsToastNotification,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (bool? newval) async {
            globalSettings.usePowerShellAsToastNotification = newval ?? false;
            await Boxes.updateSettings("usePowerShellAsToastNotification", newval);
            setState(() {});
          },
          title: const Text('Use PowerShell as toast notification'),
          subtitle: const InfoText('If you do not receive notifications, enable this. (less likely)'),
        ),
      ],
    );
  }
}
