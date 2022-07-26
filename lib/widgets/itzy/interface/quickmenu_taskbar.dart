import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/utils.dart';
import '../../../models/window_watcher.dart';

class QuickmenuTaskbar extends StatefulWidget {
  const QuickmenuTaskbar({Key? key}) : super(key: key);

  @override
  State<QuickmenuTaskbar> createState() => _QuickmenuTaskbarState();
}

class _QuickmenuTaskbarState extends State<QuickmenuTaskbar> {
  List<MapEntry<String, String>> taskbarRewrites = Boxes().taskBarRewrites.entries.toList();
  final List<TextEditingController> reWriteRegexController = <TextEditingController>[];
  @override
  void initState() {
    super.initState();
    taskbarRewrites = Boxes().taskBarRewrites.entries.toList();
    for (MapEntry<String, String> item in taskbarRewrites) {
      reWriteRegexController.add(TextEditingController(text: item.key));
    }
  }

  @override
  void dispose() {
    for (TextEditingController item in reWriteRegexController) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: Theme.of(context).listTileTheme.copyWith(
            dense: true,
            style: ListTileStyle.drawer,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            minVerticalPadding: 0,
            visualDensity: VisualDensity.compact,
            horizontalTitleGap: 0,
          ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              //! Settings and Order
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ListTile(title: Text("TaskBar Settings:", style: Theme.of(context).textTheme.bodyMedium)),
                    CheckboxListTile(
                      controlAffinity: ListTileControlAffinity.leading,
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
                      controlAffinity: ListTileControlAffinity.leading,
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
                          decoration: const InputDecoration(
                            labelText: "Predefined apps (press Enter to save)",
                            hintText: "Predefined apps",
                            border: InputBorder.none,
                            isDense: false,
                          ),
                          controller: TextEditingController(text: Boxes.mediaControls.join(", ")),
                          toolbarOptions: const ToolbarOptions(
                            paste: true,
                            cut: true,
                            copy: true,
                            selectAll: true,
                          ),
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
                                if (Boxes.mediaControls[i] == "") {
                                  Boxes.mediaControls.removeAt(i);
                                  i--;
                                }
                              }
                              Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                            }
                            if (!mounted) return;
                            setState(() {});
                          },
                        ),
                      ),
                    RadioTheme(
                      data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          ListTile(title: Text("Task Bar Order:", style: Theme.of(context).textTheme.bodyMedium)),
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
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              //! Rewrites
              Expanded(
                flex: 2,
                child: Column(
                  children: <Widget>[
                    ListTile(
                      title: const Text("Taskbar Rewrites"),
                      trailing: IconButton(
                        onPressed: () {
                          taskbarRewrites.insert(0, const MapEntry<String, String>("find", "replace"));
                          reWriteRegexController.insert(0, TextEditingController(text: "find"));
                          setState(() {});
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250, minHeight: 100),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: ListView.builder(
                          itemCount: taskbarRewrites.length,
                          controller: ScrollController(),
                          itemBuilder: (BuildContext context, int index) {
                            String value = taskbarRewrites.elementAt(index).value;
                            return Column(
                              children: <Widget>[
                                ListTile(
                                  dense: true,
                                  style: ListTileStyle.drawer,
                                  contentPadding: const EdgeInsets.only(left: 10),
                                  minVerticalPadding: 0,
                                  visualDensity: VisualDensity.compact,
                                  horizontalTitleGap: 0,
                                  title: TextField(
                                    decoration: const InputDecoration(
                                      labelText: "Search for (regex aware)",
                                      hintText: "Search for (regex aware)",
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    controller: reWriteRegexController[index],
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  subtitle: TextField(
                                    decoration: const InputDecoration(
                                      labelText: "Replace with (press Enter here to save)",
                                      hintText: "Replace with:",
                                      contentPadding: EdgeInsets.zero,
                                      isDense: true,
                                      border: InputBorder.none,
                                    ),
                                    controller: TextEditingController(text: value),
                                    scrollPadding: EdgeInsets.zero,
                                    style: const TextStyle(fontSize: 14),
                                    onSubmitted: (String e) async {
                                      if (e == "") e = " ";
                                      taskbarRewrites[index] = MapEntry<String, String>(reWriteRegexController[index].value.text.toString(), e);
                                      Map<String, String> reWrites = <String, String>{};
                                      for (int i = 0; i < taskbarRewrites.length; i++) {
                                        reWrites[taskbarRewrites.elementAt(i).key] = taskbarRewrites.elementAt(i).value;
                                      }
                                      await Boxes.updateSettings("taskBarRewrites", jsonEncode(reWrites));
                                      WindowWatcher.taskBarRewrites = reWrites;
                                      if (!mounted) return;
                                      setState(() {});
                                    },
                                  ),
                                  trailing: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () async {
                                        taskbarRewrites.removeAt(index);
                                        reWriteRegexController.removeAt(index);
                                        Map<String, String> reWrites = <String, String>{};
                                        for (int i = 0; i < taskbarRewrites.length; i++) {
                                          reWrites[taskbarRewrites.elementAt(i).key] = taskbarRewrites.elementAt(i).value;
                                        }
                                        await Boxes.updateSettings("taskBarRewrites", reWrites);
                                        WindowWatcher.taskBarRewrites = reWrites;
                                        if (!mounted) return;
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ),
                                if (index < taskbarRewrites.length - 1)
                                  const Divider(
                                    thickness: 2,
                                    height: 20,
                                    indent: 10,
                                    endIndent: 10,
                                    color: Colors.transparent,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
