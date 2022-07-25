// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/utils.dart';
import '../../widgets/info_text.dart';

class TasksReminders extends StatefulWidget {
  const TasksReminders({Key? key}) : super(key: key);

  @override
  TasksRemindersState createState() => TasksRemindersState();
}

class TasksRemindersState extends State<TasksReminders> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: <Widget>[
        ListTile(
          minLeadingWidth: 20,
          leading: Container(height: double.infinity, child: const Icon(Icons.add)),
          style: ListTileStyle.drawer,
          title: const Text("Reminders", style: TextStyle(fontSize: 22)),
          onTap: () async {
            Boxes.reminders.add(
              Reminder(
                enabled: true,
                weekDays: <bool>[true, true, true, true, true, true, true],
                time: 60,
                repetitive: true,
                interval: <int>[8 * 60, 20 * 60],
                message: "Reminder",
                voiceNotification: false,
              ),
            );
            await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
            if (mounted) setState(() {});
          },
        ),
        const InfoText("Tip: Add x[number] at the end of the string to repeat it if voice notification is enabled. Ex: Workout x3"),
        const SizedBox(height: 5),
        ListView.builder(
          shrinkWrap: true,
          itemCount: Boxes.reminders.length,
          controller: ScrollController(),
          itemBuilder: (BuildContext context, int index) {
            final Reminder reminder = Boxes.reminders[index];
            final TextEditingController messageTextController = TextEditingController(text: reminder.message);
            return Column(
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 25,
                      height: 50,
                      child: Checkbox(
                        onChanged: (bool? value) async {
                          reminder.enabled = value ?? false;
                          Boxes.reminders = Boxes.reminders;
                          await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                          Boxes().startReminders();
                          if (mounted) setState(() {});
                        },
                        value: reminder.enabled,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Focus(
                        onFocusChange: (bool value) async {
                          if (value == false) {
                            reminder.message = messageTextController.text;
                            await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                            Boxes().startReminders();
                          }
                        },
                        child: TextField(
                          controller: messageTextController,
                          decoration: InputDecoration(
                            labelText: "Message",
                            hintText: "Message",
                            isDense: true,
                            border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                          ),
                          onSubmitted: (String value) async {
                            reminder.message = value;
                            await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                            Boxes().startReminders();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ),
                    IconButton(
                        onPressed: () async {
                          Boxes.reminders.removeAt(index);
                          await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                          Boxes().startReminders();
                          if (mounted) setState(() {});
                        },
                        icon: const Icon(Icons.delete))
                  ],
                ),
                if (reminder.enabled)
                  Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 40,
                              child: Tooltip(
                                message: reminder.voiceNotification ? "Voice Notification" : "Toast Notification",
                                child: InkWell(
                                    child: Icon(reminder.voiceNotification ? Icons.record_voice_over : Icons.notification_important, size: 16),
                                    onTap: () async {
                                      reminder.voiceNotification = !reminder.voiceNotification;
                                      await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                                      Boxes().startReminders();
                                      if (mounted) setState(() {});
                                    }),
                              ),
                            ),
                            Flexible(
                              fit: FlexFit.loose,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                controller: ScrollController(),
                                child: ToggleButtons(
                                  constraints: const BoxConstraints(minHeight: 25, minWidth: 25),
                                  children: <Widget>[
                                    const Tooltip(message: "Monday", child: Text("  Mon  ")),
                                    const Tooltip(message: "Tueday", child: Text("  Tue  ")),
                                    const Tooltip(message: "Wednesday", child: Text("  Wed  ")),
                                    const Tooltip(message: "Thursday", child: Text("  Thu  ")),
                                    const Tooltip(message: "Friday", child: Text("  Fri  ")),
                                    const Tooltip(message: "Saturday", child: Text("  Sat  ")),
                                    const Tooltip(message: "Sunday", child: Text("  Sun  ")),
                                  ],
                                  onPressed: (int index) async {
                                    reminder.weekDays[index] = !reminder.weekDays[index];
                                    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                                    Boxes().startReminders();
                                    if (mounted) setState(() {});
                                  },
                                  isSelected: reminder.weekDays,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      CheckboxListTile(
                        value: reminder.repetitive,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.all(0),
                        onChanged: (bool? newValue) async {
                          reminder.repetitive = newValue ?? false;
                          if (reminder.repetitive) {
                            reminder.time = 60;
                          } else {
                            reminder.time = 12 * 60;
                          }
                          await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                          Boxes().startReminders();
                          if (mounted) setState(() {});
                        },
                        title: const Text("Repetitive"),
                      ),
                      ListTile(
                        onTap: () async {
                          final int hour = (reminder.time ~/ 60);
                          final int minute = (reminder.time % 60);
                          final TimeOfDay? timePicker = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(hour: hour, minute: minute),
                            initialEntryMode: TimePickerEntryMode.input,
                            builder: (BuildContext context, Widget? child) {
                              return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                            },
                          );
                          if (timePicker == null) return;
                          reminder.time = (timePicker.hour) * 60 + (timePicker.minute);
                          await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                          Boxes().startReminders();
                          if (mounted) setState(() {});
                        },
                        title: Text(reminder.repetitive ? "Reminder each ${reminder.time} minute${reminder.time == 1 ? "" : "s"}" : "Reminder at ${reminder.timeFormat}"),
                        leading: const Icon(Icons.edit),
                        minLeadingWidth: 20,
                        contentPadding: const EdgeInsets.only(left: 5),
                      ),
                      if (reminder.repetitive)
                        SingleChildScrollView(
                          controller: ScrollController(),
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: <Widget>[
                                const Text("Start the reminder at"),
                                InkWell(
                                  child: Text(" ✏${reminder.interval[0].formatTime()} ", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16)),
                                  onTap: () async {
                                    final int hour = (reminder.interval[0] ~/ 60);
                                    final int minute = (reminder.interval[0] % 60);
                                    final TimeOfDay? timePicker = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay(hour: hour, minute: minute),
                                      initialEntryMode: TimePickerEntryMode.dial,
                                      builder: (BuildContext context, Widget? child) {
                                        return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                                      },
                                    );
                                    if (timePicker == null) return;
                                    int timeinMinutes = (timePicker.hour) * 60 + (timePicker.minute);
                                    if (timeinMinutes + reminder.time > reminder.interval[1]) reminder.interval[1] = timeinMinutes + reminder.time;
                                    reminder.interval[0] = timeinMinutes;
                                    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                                    Boxes().startReminders();
                                    if (mounted) setState(() {});
                                  },
                                ),
                                const Text("and end it at"),
                                InkWell(
                                  child: Text(" ✏${reminder.interval[1].formatTime()} ", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16)),
                                  onTap: () async {
                                    final int hour = (reminder.interval[1] ~/ 60);
                                    final int minute = (reminder.interval[1] % 60);
                                    final TimeOfDay? timePicker = await showTimePicker(
                                      context: context,
                                      initialTime: TimeOfDay(hour: hour, minute: minute),
                                      initialEntryMode: TimePickerEntryMode.dial,
                                      builder: (BuildContext context, Widget? child) {
                                        return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                                      },
                                    );
                                    if (timePicker == null) return;
                                    int timeinMinutes = (timePicker.hour) * 60 + (timePicker.minute);
                                    if (reminder.interval[0] >= timeinMinutes - reminder.time) return;
                                    reminder.interval[1] = timeinMinutes;
                                    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
                                    Boxes().startReminders();
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                const Divider(height: 30, thickness: 1),
              ],
            );
          },
        ),
      ],
    );
  }
}
