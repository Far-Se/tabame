import 'package:flutter/material.dart';

import '../../models/utils.dart';
import '../itzy/interface/tasks_page_watchers.dart';
import '../itzy/interface/tasks_reminders.dart';
import '../widgets/info_text.dart';

class Tasks extends StatefulWidget {
  const Tasks({Key? key}) : super(key: key);

  @override
  TasksState createState() => TasksState();
}

class TasksState extends State<Tasks> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: TasksReminders(),
              ),
            ),
            const VerticalDivider(
              width: 10,
              thickness: 2,
              indent: 0,
              endIndent: 0,
              // color: Colors.white,
            ),
            const Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: TasksPageWatchers(),
              ),
            ),
          ],
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
          subtitle: const InfoText('It is possible that Native Toast Notification will not popup sometimes. If you miss some, toggle this.'),
        ),
      ],
    );
  }
}
