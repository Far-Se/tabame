// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/info_text.dart';
import '../../widgets/mouse_scroll_widget.dart';

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
                voiceVolume: 100,
              ),
            );
            await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 5),
        ListView.builder(
          shrinkWrap: true,
          itemCount: Boxes.reminders.length,
          controller: ScrollController(),
          reverse: true,
          itemBuilder: (BuildContext context, int index) {
            final Reminder reminder = Boxes.reminders[index];
            final TextEditingController messageTextController = TextEditingController(text: reminder.message.replaceFirst("p:", ""));
            final TextEditingController intervalDaysController = TextEditingController(text: reminder.interval[1].toString());
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
                          await updateReminders();
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
                            // reminder.message = messageTextController.text;
                            if (reminder.message.startsWith("p:")) {
                              reminder.message = "p:${messageTextController.text}";
                            } else {
                              reminder.message = messageTextController.text;
                            }
                            await updateReminders();
                            setState(() {});
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
                            if (reminder.message.startsWith("p:")) {
                              reminder.message = "p:$value";
                            } else {
                              reminder.message = value;
                            }
                            // reminder.message = value;
                            await updateReminders();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    ),
                    Row(
                      children: <Widget>[
                        IconButton(
                            onPressed: () async {
                              if (!reminder.message.startsWith("p:")) {
                                reminder.message = "p:${reminder.message}";
                              } else {
                                reminder.message = reminder.message.replaceFirst("p:", "");
                              }

                              messageTextController.text = reminder.message.replaceFirst("p:", "");
                              await updateReminders();
                              if (mounted) setState(() {});
                            },
                            splashRadius: 20,
                            tooltip: "Persistent",
                            icon: reminder.message.startsWith("p:") ? const Icon(Icons.warning_rounded, color: Colors.red) : const Icon(Icons.warning_rounded)),
                        IconButton(
                            tooltip: "Delete",
                            onPressed: () async {
                              Boxes.reminders.removeAt(index);
                              await updateReminders();
                              if (mounted) setState(() {});
                            },
                            splashRadius: 20,
                            icon: const Icon(Icons.delete_outline)),
                      ],
                    )
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
                              width: 30,
                              height: 30,
                              child: Tooltip(
                                message: reminder.voiceNotification ? "Voice Notification" : "Toast Notification",
                                child: InkWell(
                                    child: Icon(reminder.voiceNotification ? Icons.record_voice_over : Icons.notification_important, size: 16),
                                    onTap: () async {
                                      reminder.voiceNotification = !reminder.voiceNotification;
                                      await updateReminders();
                                      if (mounted) setState(() {});
                                    }),
                              ),
                            ),
                            Expanded(
                              // fit: FlexFit.loose,
                              child: reminder.interval[0] >= 0
                                  ? MouseScrollWidget(
                                      scrollDirection: Axis.horizontal,
                                      // controller: ScrollController(),
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
                                          await updateReminders();
                                          if (mounted) setState(() {});
                                        },
                                        isSelected: reminder.weekDays,
                                      ),
                                    )
                                  : MouseScrollWidget(
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: <Widget>[
                                          const Text("Repeat each "),
                                          SizedBox(
                                            width: 30,
                                            child: Focus(
                                              onFocusChange: (bool value) async {
                                                if (value == false) {
                                                  reminder.interval[1] = int.tryParse(intervalDaysController.text) ?? 1;
                                                  if (reminder.interval[1] <= 0) reminder.interval[1] = 1;
                                                  intervalDaysController.text = reminder.interval[1].toString();
                                                  reminder.interval[0] = -DateTime.now().millisecondsSinceEpoch;
                                                  await updateReminders();
                                                  setState(() {});
                                                }
                                              },
                                              child: TextField(
                                                controller: intervalDaysController,
                                                textAlign: TextAlign.center,
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const Text(" days since today"),
                                        ],
                                      ),
                                    ),
                            ),
                            if (!reminder.repetitive)
                              SizedBox(
                                width: 30,
                                height: 30,
                                child: Tooltip(
                                  message: reminder.interval[0] != -1 ? "Per day" : "Periodic",
                                  child: InkWell(
                                      child: Icon(reminder.interval[0] != -1 ? Icons.calendar_month_outlined : Icons.schedule_outlined, size: 16),
                                      onTap: () async {
                                        // reminder.voiceNotification = !reminder.voiceNotification;
                                        if (reminder.interval[0] < 0) {
                                          reminder.interval[0] = 0;
                                          reminder.interval[1] = 0;
                                        } else {
                                          reminder.interval[0] = -DateTime.now().day;
                                          reminder.interval[1] = 0;
                                        }
                                        await updateReminders();
                                        if (mounted) setState(() {});
                                      }),
                                ),
                              )
                          ],
                        ),
                      ),
                      if (reminder.voiceNotification)
                        Tooltip(
                          message: "Volume",
                          preferBelow: false,
                          verticalOffset: 10,
                          child: Focus(
                              child: SliderTheme(
                            data: Theme.of(context).sliderTheme.copyWith(
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                                  overlayShape: SliderComponentShape.noOverlay,
                                ),
                            child: Slider(
                              min: 0,
                              max: 100,
                              value: reminder.voiceVolume.toDouble(),
                              onChanged: (double v) => setState(() => reminder.voiceVolume = v.round()),
                              onChangeEnd: (double v) async {
                                await updateReminders();
                              },
                            ),
                          )),
                        ),
                      CheckboxListTile(
                        value: reminder.repetitive,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.all(0),
                        onChanged: (bool? newValue) async {
                          reminder.repetitive = newValue ?? false;
                          if (reminder.repetitive) {
                            reminder.time = 60;
                            reminder.interval = <int>[8 * 60, 20 * 60];
                          } else {
                            reminder.time = 12 * 60;
                          }
                          await updateReminders();
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
                          await updateReminders();
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
                                const Text("Starts at"),
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
                                    await updateReminders();
                                    if (mounted) setState(() {});
                                  },
                                ),
                                const Text("and it ends at"),
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
                                    await updateReminders();
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
        const InfoText("Tip: Add x[number] at the end of the string to repeat it if voice notification is enabled. Ex: Workout x3"),
        const InfoText("When Persistent is activated, a warning message will appear in QuickActions QuickMenu."),
      ],
    );
  }

  Future<void> updateReminders() async {
    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
    Tasks().startReminders();
  }
}
