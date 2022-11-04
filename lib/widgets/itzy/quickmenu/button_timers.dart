import 'dart:async';
import 'dart:ui';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class TimersButton extends StatefulWidget {
  const TimersButton({Key? key}) : super(key: key);
  @override
  TimersButtonState createState() => TimersButtonState();
}

class TimersButtonState extends State<TimersButton> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: double.maxFinite,
      child: InkWell(
        child: const Tooltip(message: "Timers", child: Icon(Icons.timer_sharp)),
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
      ),
    );
  }
}

class TimersWidget extends StatefulWidget {
  const TimersWidget({Key? key}) : super(key: key);
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  String? selectedTimerType = "Audio";

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
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            gradient: LinearGradient(
              colors: <Color>[
                Theme.of(context).backgroundColor,
                Theme.of(context).backgroundColor.withAlpha(globalSettings.themeColors.gradientAlpha),
                Theme.of(context).backgroundColor,
              ],
              stops: <double>[0, 0.4, 1],
              end: Alignment.bottomRight,
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
            ],
            color: Theme.of(context).backgroundColor,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("Create Timer:", style: TextStyle(fontSize: 17)),
                Row(
                  children: <Widget>[
                    Expanded(
                      flex: 1,
                      child: TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          hintText: "Minutes",
                          hintStyle: const TextStyle(fontSize: 12),
                          border: UnderlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        controller: durationController,
                        onChanged: (String e) {
                          // filters.watermark = e;
                          setState(() {});
                        },
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          hintText: "Message",
                          hintStyle: const TextStyle(fontSize: 12),
                          border: UnderlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
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
                          buttonPadding: const EdgeInsets.symmetric(horizontal: 5),
                          dropdownPadding: const EdgeInsets.all(1),
                          offset: const Offset(0, 30),
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
                          buttonHeight: 40,
                          buttonWidth: 200,
                          itemHeight: 30,
                          dropdownMaxHeight: 200,
                        ),
                      ),
                    ),
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: () {
                              Boxes().addQuickTimer(
                                messageController.text,
                                int.tryParse(durationController.text) ?? 1,
                                <String>["Audio", "Message", "Notification"].indexWhere((String el) => el == selectedTimerType),
                              );
                              setState(() {});
                            },
                            icon: const Icon(Icons.add),
                            label: const Text("Create", style: TextStyle(height: 1))))
                  ],
                ),
                const Divider(height: 5, thickness: 1),
                Boxes.quickTimers.isEmpty ? const Text("No Active Timers") : const ListTimersWidget(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ListTimersWidget extends StatefulWidget {
  const ListTimersWidget({
    Key? key,
  }) : super(key: key);

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
    return Container(
      height: 175,
      width: 280,
      child: SingleChildScrollView(
        controller: ScrollController(),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List<Widget>.generate(
                Boxes.quickTimers.length,
                (int index) {
                  final Duration diff = DateTime.now().difference(Boxes.quickTimers[index].endTime);
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
                          Text("${diff.toString().replaceAll(RegExp(r'(\.\d+|-)'), '')}")
                        ],
                      )
                    ],
                  );
                },
              )),
        ),
      ),
    );
  }
}
