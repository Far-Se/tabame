// ignore_for_file: public_member_api_docs, sort_constructors_first, dead_code
import 'dart:convert';

import 'package:animated_button_bar/animated_button_bar.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/info_text.dart';
import '../../widgets/mouse_scroll_widget.dart';

class TasksReminders extends StatefulWidget {
  const TasksReminders({super.key});

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
                multipleTimes: <int>[],
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
        ...List<Widget>.generate(Boxes.reminders.length, (int index) {
          final int i = Boxes.reminders.length - index - 1;
          final Reminder reminder = Boxes.reminders[i];
          return ListTile(
            minLeadingWidth: 20,
            leading: SizedBox(
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
            style: ListTileStyle.drawer,
            title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
              reminder.message.contains('p:')
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[const Icon(Icons.warning_rounded, color: Colors.red, size: 18), Text(reminder.message.replaceFirst("p:", ""))])
                  : Text(Boxes.reminders[i].message.replaceFirst('p:', ''), style: const TextStyle(fontSize: 18)),
              const Icon(Icons.edit, color: Colors.grey, size: 18)
            ]),
            subtitle: Text(
                reminder.repetitive
                    ? "Repetitive each ${reminder.time.formatTime()} within ${reminder.interval[0].formatTime()} - ${reminder.interval[1].formatTime()}"
                    : "At ${reminder.time.formatTime()}${reminder.multipleTimes.isNotEmpty ? ", ${reminder.multipleTimes.map<String>((int e) => e.formatTime()).join(", ")}" : ""}",
                style: const TextStyle(fontSize: 12)),
            onTap: () {
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      shadowColor: Colors.grey,
                      content: Container(
                        height: 600,
                        width: 800,
                        foregroundDecoration: BoxDecoration(border: Border.all(color: Colors.black.withOpacity(0.5))),
                        child: SingleChildScrollView(
                            controller: ScrollController(),
                            child: ReminderEditor(
                              key: UniqueKey(),
                              remindersIndex: i,
                              onDeleted: () async {
                                Boxes.reminders.removeAt(i);
                                await updateReminders();
                                Navigator.pop(context);
                                if (mounted) setState(() {});
                              },
                              onSaved: (Reminder reminder) async {
                                print(reminder);
                                Boxes.reminders[i] = reminder.copyWith();
                                await updateReminders();
                                Navigator.pop(context);
                                if (mounted) setState(() {});
                              },
                            )),
                      ),
                    );
                  });
            },
          );
        }),
        const Divider(),
        const InfoText("Tip: Add x[number] at the end of the string to repeat it if voice notification is enabled. Ex: Workout x3"),
        const InfoText("When Persistent is activated, a warning message will appear in QuickActions QuickMenu."),
        const Divider(),
      ],
    );
  }

  Future<void> updateReminders() async {
    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
    Tasks().startReminders();
  }
}

class ReminderEditor extends StatefulWidget {
  final int remindersIndex;
  final void Function(Reminder reminder) onSaved;
  final void Function() onDeleted;
  //make functions optional

  const ReminderEditor({super.key, required this.remindersIndex, required this.onSaved, required this.onDeleted});
  @override
  ReminderEditorState createState() => ReminderEditorState();
}

class ReminderEditorState extends State<ReminderEditor> {
  late Reminder reminder;
  late TextEditingController messageTextController;
  final TextEditingController intervalDaysController = TextEditingController();
  bool persistent = false;

  final AnimatedButtonController perDayType = AnimatedButtonController();
  final AnimatedButtonController repetitiveController = AnimatedButtonController();
  final AnimatedButtonController typeNotification = AnimatedButtonController();
  @override
  void initState() {
    reminder = Boxes.reminders[widget.remindersIndex].copyWith();
    messageTextController = TextEditingController(text: reminder.message.replaceFirst("p:", ""));
    intervalDaysController.text = reminder.interval[1].toString();
    if (reminder.message.contains("p:")) persistent = true;
    if (reminder.interval[0] <= -1) perDayType.index = 1;
    if (reminder.voiceNotification) typeNotification.index = 1;
    if (!reminder.repetitive) repetitiveController.index = 1;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
                tooltip: "Delete",
                onPressed: () async {
                  widget.onDeleted();
                  if (mounted) setState(() {});
                },
                splashRadius: 20,
                icon: const Icon(Icons.delete_outline)),
            Text(reminder.message.replaceFirst("p:", "")),
            IconButton(
                tooltip: "Save",
                onPressed: () async {
                  if (persistent) {
                    reminder.message = "p:${messageTextController.value.text}";
                  } else {
                    reminder.message = messageTextController.value.text;
                  }
                  widget.onSaved(reminder);
                },
                splashRadius: 20,
                icon: const Icon(Icons.save)),
          ],
        ),
        const Divider(height: 30, thickness: 1),
        TextField(
          controller: messageTextController,
          decoration: InputDecoration(
            labelText: "Message",
            hintText: "Message",
            isDense: true,
            border: UnderlineInputBorder(borderSide: BorderSide(width: 1, color: Colors.black.withOpacity(0.5))),
          ),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          title: const Text("Persistent"),
          controlAffinity: ListTileControlAffinity.leading,
          value: persistent,
          onChanged: (bool? value) async {
            persistent = value ?? false;
            setState(() {});
          },
        ),
        const Text("Notification Type:"),
        AnimatedButtonBar(
          foregroundColor: Theme.of(context).colorScheme.primary,
          radius: 0.0,
          curve: Curves.easeOutCirc,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5.0),
          controller: typeNotification,
          invertedSelection: true,
          children: <ButtonBarEntry>[
            ButtonBarEntry(
                child: const Text("Toast Notification"),
                onTap: () async {
                  reminder.voiceNotification = false;
                  if (mounted) setState(() {});
                }),
            ButtonBarEntry(
                child: const Text("Voice Notification"),
                onTap: () async {
                  reminder.voiceNotification = true;
                  if (mounted) setState(() {});
                }),
          ],
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
                onChangeEnd: (double v) async {},
              ),
            )),
          ),
        const Divider(),
        // const Text("Reminder Type:"),
        /* AnimatedButtonBar(
          foregroundColor: Theme.of(context).colorScheme.primary,
          radius: 0.0,
          curve: Curves.easeOutCirc,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5.0),
          controller: perDayType,
          invertedSelection: true,
          children: <ButtonBarEntry>[
            ButtonBarEntry(
                child: const Text("Days Active"),
                onTap: () async {
                  reminder.interval[0] = 0;
                  reminder.interval[1] = 0;
                  if (mounted) setState(() {});
                }),
            ButtonBarEntry(
                child: const Text("Repeat Each X days"),
                onTap: () async {
                  reminder.interval[0] = -1;
                  reminder.interval[1] = -1;
                  if (mounted) setState(() {});
                }),
          ],
        ), */
        const Text("Remind on:"),
        reminder.interval[0] >= 0
            ? Center(
                child: MouseScrollWidget(
                  scrollDirection: Axis.horizontal,
                  // controller: ScrollController(),
                  child: ToggleButtons(
                    constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
                    children: <Widget>[
                      const Tooltip(message: "Monday", child: Text("  Monday  ")),
                      const Tooltip(message: "Tueday", child: Text("  Tueday  ")),
                      const Tooltip(message: "Wednesday", child: Text("  Wednesday  ")),
                      const Tooltip(message: "Thursday", child: Text("  Thursday  ")),
                      const Tooltip(message: "Friday", child: Text("  Friday  ")),
                      const Tooltip(message: "Saturday", child: Text("  Saturday  ")),
                      const Tooltip(message: "Sunday", child: Text("  Sunday  ")),
                    ],
                    onPressed: (int index) async {
                      reminder.weekDays[index] = !reminder.weekDays[index];
                      if (mounted) setState(() {});
                    },
                    isSelected: reminder.weekDays,
                  ),
                ),
              )
            : Center(
                child: MouseScrollWidget(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
        const Divider(),
        AnimatedButtonBar(
          foregroundColor: Theme.of(context).colorScheme.primary,
          radius: 0.0,
          curve: Curves.easeOutCirc,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5.0),
          controller: repetitiveController,
          invertedSelection: true,
          children: <ButtonBarEntry>[
            ButtonBarEntry(
                child: const Text("Repetitive"),
                onTap: () async {
                  reminder.repetitive = true;
                  if (mounted) setState(() {});
                }),
            ButtonBarEntry(
                child: const Text("Daily"),
                onTap: () async {
                  reminder.repetitive = false;
                  if (mounted) setState(() {});
                }),
          ],
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
            if (mounted) setState(() {});
          },
          title: Text(reminder.repetitive ? "Reminder each ${reminder.time} minute${reminder.time == 1 ? "" : "s"}" : "Reminder at ${reminder.timeFormat}"),
          leading: const Icon(Icons.edit),
          minLeadingWidth: 20,
          contentPadding: const EdgeInsets.only(left: 5),
        ),
        if (!reminder.repetitive && reminder.multipleTimes.isNotEmpty)
          ...List<Widget>.generate(reminder.multipleTimes.length, (int index) {
            return ListTile(
              onTap: () async {
                final int hour = (reminder.multipleTimes[index] ~/ 60);
                final int minute = (reminder.multipleTimes[index] % 60);
                final TimeOfDay? timePicker = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: hour, minute: minute),
                  initialEntryMode: TimePickerEntryMode.input,
                  builder: (BuildContext context, Widget? child) {
                    return MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
                  },
                );
                if (timePicker == null) return;
                reminder.multipleTimes[index] = (timePicker.hour) * 60 + (timePicker.minute);
                if (mounted) setState(() {});
              },
              title: Text("Reminder at ${reminder.multipleTimes[index].formatTime()}"),
              leading: const Icon(Icons.edit),
              minLeadingWidth: 20,
              contentPadding: const EdgeInsets.only(left: 5),
              trailing: IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  reminder.multipleTimes.removeAt(index);
                  if (mounted) setState(() {});
                },
                splashRadius: 20,
              ),
            );
          }),

        if (!reminder.repetitive)
          ListTile(
            onTap: () async {
              reminder.multipleTimes.add(DateTime.now().hour * 60 + DateTime.now().minute);
              if (mounted) setState(() {});
            },
            title: const Text("Add multiple times"),
            leading: const Icon(Icons.add),
            minLeadingWidth: 20,
            contentPadding: const EdgeInsets.only(left: 5),
            subtitle: const Text("Tap to add multiple times"),
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
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
