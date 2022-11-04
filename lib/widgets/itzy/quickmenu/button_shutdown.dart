import 'dart:ui';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/info_text.dart';

class ShutDownButton extends StatefulWidget {
  const ShutDownButton({Key? key}) : super(key: key);
  @override
  ShutDownButtonState createState() => ShutDownButtonState();
}

class ShutDownButtonState extends State<ShutDownButton> {
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
        child: const Tooltip(message: "Schedule Shutdown", child: Icon(Icons.power_settings_new_rounded)),
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
  bool isShutDownScheduled = false;
  int shutDownUnix = 0;
  String? selectedTimerType = "ShutDown in";
  final TextEditingController minutesController = TextEditingController(text: "00");
  final TextEditingController hoursController = TextEditingController(text: "00");
  @override
  void initState() {
    isShutDownScheduled = Boxes.pref.getBool("isShutDownScheduled") ?? false;
    shutDownUnix = Boxes.pref.getInt("shutDownUnix") ?? 0;
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
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
          child: SingleChildScrollView(
            controller: ScrollController(),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      height: 100,
                      width: 280,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            flex: 10,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Stack(
                                  children: <Widget>[
                                    const Positioned(right: 20, bottom: 2, child: InfoText("Hours")),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).backgroundColor.withOpacity(0.6),
                                        backgroundBlendMode: BlendMode.screen,
                                      ),
                                      margin: const EdgeInsets.only(right: 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                                      child: Focus(
                                        onFocusChange: (bool e) {
                                          if (!e) {
                                            hoursController.text = hoursController.text.padLeft(2, "0");
                                          }
                                        },
                                        child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                                          style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            hintText: "00",
                                            hintStyle:
                                                TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                            border: InputBorder.none,
                                            // counterText: "Minutes",
                                          ),
                                          controller: hoursController,
                                          onSubmitted: (String e) {
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Flexible(
                            fit: FlexFit.tight,
                            flex: 1,
                            child: Center(child: Text(":", style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 0.75))),
                          ),
                          Expanded(
                            flex: 10,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                Stack(
                                  children: <Widget>[
                                    const Positioned(right: 5, bottom: 2, child: InfoText("Minutes")),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).backgroundColor.withOpacity(0.6),
                                        backgroundBlendMode: BlendMode.screen,
                                      ),
                                      margin: const EdgeInsets.only(left: 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                                      child: Focus(
                                        onFocusChange: (bool e) {
                                          if (!e) {
                                            minutesController.text = minutesController.text.padLeft(2, "0");
                                          }
                                        },
                                        child: TextField(
                                          keyboardType: TextInputType.number,
                                          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
                                          style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            hintText: "00",
                                            hintStyle:
                                                TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                            border: InputBorder.none,
                                            // counterText: "Seconds",
                                          ),
                                          controller: minutesController,
                                          onChanged: (String e) {},
                                          onSubmitted: (String e) {
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                    isShutDownScheduled
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              const SizedBox(height: 10),
                              ElevatedButton.icon(
                                onPressed: () {
                                  isShutDownScheduled = false;
                                  Boxes.pref.setBool("isShutDownScheduled", isShutDownScheduled);
                                  Boxes.pref.setInt("shutDownUnix", 0);
                                  Boxes.shutDownTimer?.cancel();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear_sharp),
                                label: const Text("Cancel Shut Down Schedule", style: TextStyle(height: 1.1)),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: Text(
                                    "Shut Down at ${(DateTime.fromMillisecondsSinceEpoch(shutDownUnix).hour * 60 + DateTime.fromMillisecondsSinceEpoch(shutDownUnix).minute).formatTime()}",
                                    style: const TextStyle(fontSize: 22)),
                              )
                            ],
                          )
                        : Row(
                            children: <Widget>[
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton2<String>(
                                    isExpanded: false,
                                    hint: Text("Type", style: TextStyle(fontSize: 14, color: Theme.of(context).hintColor)),
                                    buttonPadding: const EdgeInsets.symmetric(horizontal: 5),
                                    dropdownPadding: const EdgeInsets.all(1),
                                    offset: const Offset(0, 30),
                                    isDense: true,
                                    style: const TextStyle(fontSize: 200),
                                    items: <String>["ShutDown in", "ShutDown at"]
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
                                        Boxes.shutDownTimer?.cancel();
                                        final int hour = int.tryParse(hoursController.text) ?? 0;
                                        final int minute = int.tryParse(minutesController.text) ?? 0;
                                        Duration duration = Duration(hours: hour, minutes: minute);

                                        if (selectedTimerType == "ShutDown in") {
                                          if (duration.inSeconds < 120) return;
                                          shutDownUnix = DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
                                        } else {
                                          DateTime now = DateTime.now();
                                          final int nowHour = now.hour;
                                          now = now.subtract(Duration(hours: now.hour, minutes: now.minute, seconds: now.second));
                                          if (nowHour < hour) {
                                            now = now.add(duration);
                                          } else {
                                            now = now.add(duration).add(const Duration(days: 1));
                                          }
                                          shutDownUnix = now.millisecondsSinceEpoch;
                                        }
                                        isShutDownScheduled = true;
                                        Boxes.pref.setBool("isShutDownScheduled", isShutDownScheduled);
                                        Boxes.pref.setInt("shutDownUnix", shutDownUnix);
                                        Boxes.shutDownScheduler();
                                        setState(() {});
                                      },
                                      icon: const Icon(Icons.schedule_rounded),
                                      label: const Text("Schedule", style: TextStyle(height: 1))))
                            ],
                          )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
