import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../widgets/info_text.dart';
import '../../widgets/info_widget.dart';

class TasksPageWatchers extends StatefulWidget {
  const TasksPageWatchers({Key? key}) : super(key: key);

  @override
  TasksPageWatchersState createState() => TasksPageWatchersState();
}

class TasksPageWatchersState extends State<TasksPageWatchers> {
  final Tasks tasks = Tasks();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        ListTile(
          minLeadingWidth: 20,
          leading: Container(height: double.infinity, child: const Icon(Icons.add)),
          trailing: InfoWidget("It reads HTML, on dynamic sites you need to match HTML.", onTap: () {}),
          style: ListTileStyle.drawer,
          title: const Text("Page Watchers", style: TextStyle(fontSize: 23)),
          onTap: () {
            Boxes.pageWatchers.add(PageWatcher(url: "", regex: "", lastMatch: "", enabled: false, checkPeriod: 60, voiceNotification: false));
            if (mounted) setState(() {});
          },
        ),
        ListView.builder(
          shrinkWrap: true,
          itemCount: Boxes.pageWatchers.length,
          controller: ScrollController(),
          itemBuilder: (BuildContext context, int index) {
            final PageWatcher pageWatcher = Boxes.pageWatchers[index];

            final TextEditingController urlTextController = TextEditingController(text: pageWatcher.url);
            final TextEditingController regexTextController = TextEditingController(text: pageWatcher.regex);
            final TextEditingController secondsTextController = TextEditingController(text: pageWatcher.checkPeriod.toString());
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      //!Left Buttons
                      Container(
                        height: 100,
                        width: 40,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(
                              child: Checkbox(
                                value: pageWatcher.enabled,
                                onChanged: (bool? value) async {
                                  pageWatcher.enabled = value ?? false;
                                  if (pageWatcher.enabled) {
                                    tasks.startPageWatchers(specificIndex: index);
                                  } else {
                                    pageWatcher.timer?.cancel();
                                  }
                                  await savePage(pageWatcher, urlTextController, regexTextController, secondsTextController, index);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                            Expanded(
                              child: Tooltip(
                                message: pageWatcher.voiceNotification ? "Voice Notification" : "Toast Notification",
                                child: InkWell(
                                    child: Icon(pageWatcher.voiceNotification ? Icons.record_voice_over : Icons.notification_important),
                                    onTap: () async {
                                      await savePage(pageWatcher, urlTextController, regexTextController, secondsTextController, index);
                                    }),
                              ),
                            )
                          ],
                        ),
                      ),
                      //! Text Fields
                      Expanded(
                        child: Column(
                          children: <Widget>[
                            TextField(
                              decoration: InputDecoration(
                                labelText: "Url to fetch:",
                                hintText: "Url to fetch:",
                                isDense: true,
                                border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                              ),
                              controller: urlTextController,
                              style: const TextStyle(fontSize: 14),
                            ),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  flex: 4,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: "Regex to Match",
                                      hintText: "Regex to Match",
                                      isDense: true,
                                      border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                    ),
                                    controller: regexTextController,
                                    style: const TextStyle(fontSize: 14),
                                    onSubmitted: (String value) async {
                                      await savePage(pageWatcher, urlTextController, regexTextController, secondsTextController, index);
                                    },
                                  ),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: TextField(
                                    decoration: InputDecoration(
                                      labelText: "Seconds",
                                      hintText: "Check Period",
                                      isDense: true,
                                      border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                    ),
                                    inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                                    controller: secondsTextController,
                                    style: const TextStyle(fontSize: 14),
                                    onSubmitted: (String value) async {
                                      await savePage(pageWatcher, urlTextController, regexTextController, secondsTextController, index);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      //! Right Buttons
                      Container(
                        height: 100,
                        width: 40,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Expanded(
                              child: Tooltip(
                                message: "Save",
                                preferBelow: false,
                                child: InkWell(
                                  child: const Icon(Icons.save),
                                  onTap: () async {
                                    await savePage(pageWatcher, urlTextController, regexTextController, secondsTextController, index);
                                  },
                                ),
                              ),
                            ),
                            Expanded(
                              child: Tooltip(
                                message: "Delete",
                                preferBelow: true,
                                child: InkWell(
                                  child: const Icon(Icons.delete),
                                  onTap: () async {
                                    Boxes.pageWatchers.removeAt(index);
                                    pageWatcher.timer?.cancel();
                                    await Boxes.updateSettings("pageWatchers", jsonEncode(Boxes.pageWatchers));
                                    if (mounted) if (mounted) setState(() {});
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  InfoText("Last Matched Text: ${pageWatcher.lastMatch}"),
                ],
              ),
            );
          },
        )
      ],
    );
  }

  Future<void> savePage(PageWatcher pageWatcher, TextEditingController urlTextController, TextEditingController regexTextController,
      TextEditingController secondsTextController, int index) async {
    pageWatcher.url = urlTextController.value.text;
    pageWatcher.regex = regexTextController.value.text;
    pageWatcher.checkPeriod = int.parse(secondsTextController.value.text);
    pageWatcher.lastMatch = await tasks.pageWatcherGetValue(pageWatcher.url, pageWatcher.regex);

    await Boxes.updateSettings("pageWatchers", jsonEncode(Boxes.pageWatchers));
    if (pageWatcher.enabled) {
      pageWatcher.timer?.cancel();
      tasks.startPageWatchers(specificIndex: index);
    }
    if (mounted) if (mounted) setState(() {});
  }
}
