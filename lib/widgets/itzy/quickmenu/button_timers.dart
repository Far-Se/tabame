import 'dart:async';
import 'dart:ui';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class TimersButton extends StatefulWidget {
  const TimersButton({super.key});
  @override
  TimersButtonState createState() => TimersButtonState();
}

class TimersButtonState extends State<TimersButton> {
  @override
  void initState() {
    Boxes().loadLatestQuickTimers();
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Timers",
      icon: const Icon(Icons.timer_sharp),
      onTap: () async {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 280),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse) {
                      if (event.buttons == kSecondaryMouseButton) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: TimersWidget(),
                  ),
                ),
              ),
            );
          },
        );
        return;
      },
    );
  }
}

class TimersWidget extends StatefulWidget {
  const TimersWidget({super.key});
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  String? selectedTimerType = "Message";

  TextEditingController messageController = TextEditingController();
  TextEditingController durationController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    messageController.dispose();
    durationController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: double.infinity,
          width: 280,
          constraints: BoxConstraints(maxWidth: 280, maxHeight: 100 + Boxes.lastQuickTimers.length * 35),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              colors: <Color>[
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface.withAlpha(globalSettings.themeColors.gradientAlpha),
                Theme.of(context).colorScheme.surface,
              ],
              stops: <double>[0, 0.4, 1],
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
            ],
            color: Theme.of(context).colorScheme.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // const Text("Create Timer:", style: TextStyle(fontSize: 17)),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 2,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            hintText: "Minutes",
                            hintStyle: TextStyle(fontSize: 12),
                            border: UnderlineInputBorder(borderRadius: BorderRadius.zero)),
                        controller: durationController,
                        onChanged: (String e) {
                          // filters.watermark = e;
                          setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: TextField(
                        decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            hintText: "Message",
                            hintStyle: TextStyle(fontSize: 12),
                            border: UnderlineInputBorder(borderRadius: BorderRadius.zero)),
                        controller: messageController,
                        onChanged: (String e) {
                          // filters.watermark = e;
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton2<String>(
                          isExpanded: false,
                          hint: Text(
                            "Type",
                            style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor),
                          ),
                          buttonStyleData: const ButtonStyleData(padding: EdgeInsets.symmetric(horizontal: 5), height: 40, width: 200),
                          menuItemStyleData: const MenuItemStyleData(height: 30),
                          dropdownStyleData: const DropdownStyleData(padding: EdgeInsets.all(1), offset: Offset(0, 30), maxHeight: 200),
                          isDense: true,
                          style: const TextStyle(fontSize: 200),
                          items: <String>["Audio", "Message", "Notification"]
                              .map((String item) => DropdownMenuItem<String>(value: item, child: Text(item, style: const TextStyle(fontSize: 14))))
                              .toList(),
                          value: selectedTimerType,
                          onChanged: (String? value) {
                            selectedTimerType = value;
                            setState(() {});
                          },
                        ),
                      ),
                    ),
                    Expanded(
                        child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              shape: const StadiumBorder(),
                              side: const BorderSide(color: Colors.transparent),
                            ),
                            onPressed: () {
                              Boxes().addQuickTimer(
                                messageController.text.isEmpty ? "${durationController.text} Minute Timer" : messageController.text,
                                int.tryParse(durationController.text) ?? 1,
                                <String>["Audio", "Message", "Notification"].indexWhere((String el) => el == selectedTimerType),
                              );
                              if (messageController.text.isEmpty) {
                                context.findAncestorStateOfType<TimersButtonState>()?.setState(() {});
                                if (mounted) setState(() {});
                                return;
                              }
                              SavedQuickTimers timer = SavedQuickTimers();
                              timer.name = messageController.text;
                              timer.minutes = int.tryParse(durationController.text) ?? 1;
                              timer.type = <String>["Audio", "Message", "Notification"].indexWhere((String el) => el == selectedTimerType);
                              Boxes.lastQuickTimers.add(timer);
                              Boxes.lastQuickTimers.sort(((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes));
                              if (Boxes.lastQuickTimers.length > 20) {
                                Boxes.lastQuickTimers.removeRange(0, Boxes.lastQuickTimers.length - 20);
                              }
                              Boxes().saveLatestQuickTimers();
                              context.findAncestorStateOfType<TimersButtonState>()?.setState(() {});

                              setState(() {});
                            },
                            icon: const Icon(Icons.add),
                            label: const Text("Create", style: TextStyle(height: 1))))
                  ],
                ),
                // const Divider(height: 5, thickness: 1),
                Container(
                  height: 160 + Boxes.lastQuickTimers.length * 15, //175,
                  width: 280,
                  child: SingleChildScrollView(
                    controller: ScrollController(),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (Boxes.quickTimers.isNotEmpty) const ListTimersWidget(),
                          if (Boxes.lastQuickTimers.isNotEmpty)
                            ListLatestQuickTimers(onTriggered: () {
                              setState(() {});
                            }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ListLatestQuickTimers extends StatefulWidget {
  final Function onTriggered;
  const ListLatestQuickTimers({super.key, required this.onTriggered});
  @override
  ListLatestQuickTimersState createState() => ListLatestQuickTimersState();
}

class ListLatestQuickTimersState extends State<ListLatestQuickTimers> {
  //List<SavedQuickTimers> lastTimers = <SavedQuickTimers>[];
  @override
  void initState() {
    super.initState();

    //lastTimers = <SavedQuickTimers>[...Boxes.lastQuickTimers];
    Boxes.lastQuickTimers.sort(((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Divider(height: 6, thickness: 1),
        const Text(
          "Latest Timers:",
          style: TextStyle(
            fontSize: 19.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        ...List<Widget>.generate(
            Boxes.lastQuickTimers.length,
            (int index) => Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Boxes().addQuickTimer(Boxes.lastQuickTimers[index].name, Boxes.lastQuickTimers[index].minutes, Boxes.lastQuickTimers[index].type);
                          setState(() {});
                          Timer(const Duration(milliseconds: 200), () => context.findAncestorStateOfType<TimersButtonState>()?.setState(() {}));
                          widget.onTriggered();
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Text("${Boxes.lastQuickTimers[index].name}: ${Boxes.lastQuickTimers[index].minutes} minutes (${<String>[
                            "Audio",
                            "Message",
                            "Notification"
                          ][Boxes.lastQuickTimers[index].type]})"),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: InkWell(
                        onTap: () {
                          Boxes.lastQuickTimers.removeAt(index);
                          Boxes.lastQuickTimers.sort(((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes));
                          setState(() {});
                          Boxes().saveLatestQuickTimers();
                        },
                        child: const Icon(Icons.close_rounded),
                      ),
                    )
                  ],
                ))
      ],
    );
  }
}

class ListTimersWidget extends StatefulWidget {
  const ListTimersWidget({
    super.key,
  });

  @override
  State<ListTimersWidget> createState() => _ListTimersWidgetState();
}

class _ListTimersWidgetState extends State<ListTimersWidget> {
  Timer? leTimer;
  @override
  void initState() {
    super.initState();
    leTimer = Timer.periodic(const Duration(milliseconds: 500), (Timer timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    leTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List<Widget>.generate(
          Boxes.quickTimers.length,
          (int index) {
            final Duration diff = DateTime.now().difference(Boxes.quickTimers[index].endTime);
            final DateTime endTimer = Boxes.quickTimers[index].endTime;
            return Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                IconButton(
                  splashRadius: 16,
                  onPressed: () {
                    Boxes.quickTimers[index].timer?.cancel();
                    Boxes.quickTimers.removeAt(index);
                    setState(() {});
                  },
                  icon: const Icon(Icons.delete),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(width: 200, child: Text(Boxes.quickTimers[index].name, overflow: TextOverflow.fade, softWrap: false)),
                    Text("${diff.toString().replaceAll(RegExp(r'(\.\d+|-)'), '')}" " (${endTimer.hour.formatZeros()}:${endTimer.minute.formatZeros()})")
                  ],
                )
              ],
            );
          },
        ));
  }
}
