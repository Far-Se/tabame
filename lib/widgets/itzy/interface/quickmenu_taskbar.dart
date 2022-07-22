import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/utils.dart';

class QuickmenuTaskbar extends StatefulWidget {
  const QuickmenuTaskbar({Key? key}) : super(key: key);

  @override
  State<QuickmenuTaskbar> createState() => _QuickmenuTaskbarState();
}

class _QuickmenuTaskbarState extends State<QuickmenuTaskbar> {
  Map<String, String> taskbarRewrites = Boxes().taskBarRewrites;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(padding: const EdgeInsets.only(left: 10), child: Text("TaskBar Settings:", style: Theme.of(context).textTheme.bodyMedium)),
                  CheckboxListTile(
                    title: const Text("Show QuickMenu at Taskbar Level"),
                    value: globalSettings.showQuickMenuAtTaskbarLevel,
                    onChanged: (bool? newValue) async {
                      globalSettings.showQuickMenuAtTaskbarLevel = newValue ?? false;
                      await Boxes.updateSettings("showQuickMenuAtTaskbarLevel", globalSettings.showQuickMenuAtTaskbarLevel);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                  CheckboxListTile(
                    title: const Text("Show Media Control for each App"),
                    value: globalSettings.showMediaControlForApp,
                    onChanged: (bool? newValue) async {
                      globalSettings.showMediaControlForApp = newValue ?? false;
                      await Boxes.updateSettings("showMediaControlForApp", globalSettings.showMediaControlForApp);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                  if (globalSettings.showMediaControlForApp)
                    ListTile(
                      title: TextField(
                        decoration: const InputDecoration(labelText: "Predefined apps (press Enter after edit)", hintText: "Predefined apps"),
                        controller: TextEditingController(text: Boxes.mediaControls.join(",")),
                        toolbarOptions: const ToolbarOptions(
                          paste: true,
                          cut: true,
                          copy: true,
                          selectAll: true,
                        ),
                        focusNode: FocusNode(),
                        style: const TextStyle(fontSize: 14),
                        enableInteractiveSelection: true,
                        onSubmitted: (String e) {
                          if (e == "") {
                            Boxes.mediaControls = <String>[];
                            Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                          } else {
                            Boxes.mediaControls = e.replaceAll(',,', ',').split(",");
                            for (int i = 0; i < Boxes.mediaControls.length; i++) {
                              Boxes.mediaControls[i] = Boxes.mediaControls[i].trim();
                            }
                            Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                          }
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: RadioTheme(
                data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(padding: const EdgeInsets.only(left: 10), child: Text("Task Bar Order:", style: Theme.of(context).textTheme.bodyMedium)),
                    RadioListTile<TaskBarAppsStyle>(
                      title: const Text('Active Monitor First'),
                      value: TaskBarAppsStyle.activeMonitorFirst,
                      groupValue: globalSettings.taskBarAppsStyle,
                      onChanged: (TaskBarAppsStyle? value) {
                        globalSettings.taskBarAppsStyle = value ?? TaskBarAppsStyle.activeMonitorFirst;
                        Boxes.updateSettings("taskBarAppsStyle", globalSettings.taskBarAppsStyle);
                        setState(() {});
                      },
                    ),
                    RadioListTile<TaskBarAppsStyle>(
                      title: const Text('Only Active Monitor'),
                      value: TaskBarAppsStyle.onlyActiveMonitor,
                      groupValue: globalSettings.taskBarAppsStyle,
                      onChanged: (TaskBarAppsStyle? value) {
                        globalSettings.taskBarAppsStyle = value ?? TaskBarAppsStyle.activeMonitorFirst;
                        Boxes.updateSettings("taskBarAppsStyle", globalSettings.taskBarAppsStyle);
                        setState(() {});
                      },
                    ),
                    RadioListTile<TaskBarAppsStyle>(
                      title: const Text('Order by Activity'),
                      value: TaskBarAppsStyle.orderByActivity,
                      groupValue: globalSettings.taskBarAppsStyle,
                      onChanged: (TaskBarAppsStyle? value) {
                        globalSettings.taskBarAppsStyle = value ?? TaskBarAppsStyle.activeMonitorFirst;
                        Boxes.updateSettings("taskBarAppsStyle", globalSettings.taskBarAppsStyle);
                        taskbarRewrites = Boxes().taskBarRewrites;
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        ListTile(
          title: const Text("Taskbar Rewrites"),
          trailing: IconButton(
            onPressed: () {
              taskbarRewrites["find"] = "replace";
              setState(() {});
            },
            icon: const Icon(Icons.add),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300, minHeight: 200),
          child: //generate a listview with taskBarRewrites
              ListView.builder(
            itemCount: taskbarRewrites.length,
            itemBuilder: (BuildContext context, int index) {
              String key = taskbarRewrites.keys.elementAt(index);
              String value = taskbarRewrites.values.elementAt(index);
              return ListTile(
                title: TextField(
                  decoration: const InputDecoration(labelText: "Search for (regex aware)", hintText: "Search for (regex aware)"),
                  controller: TextEditingController(text: key),
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: TextField(
                  decoration: const InputDecoration(labelText: "Replace with: (press Enter after edit)", hintText: "Replace with:"),
                  controller: TextEditingController(text: value),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (String e) async {
                    taskbarRewrites[key] = e;
                    await Boxes.updateSettings("taskBarRewrites", json.encode(taskbarRewrites));
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () {
                    taskbarRewrites.remove(key);
                    Boxes.updateSettings("taskBarRewrites", taskbarRewrites);
                    setState(() {});
                  },
                ),
              );
            },
          ),
        )
      ],
    );
  }
}
