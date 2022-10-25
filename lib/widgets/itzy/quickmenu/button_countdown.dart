// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class CountdownButton extends StatefulWidget {
  const CountdownButton({Key? key}) : super(key: key);
  @override
  CountdownButtonState createState() => CountdownButtonState();
}

class CountdownButtonState extends State<CountdownButton> {
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
        child: const Tooltip(message: "Countdown", child: Icon(Icons.hourglass_bottom_outlined)),
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

class CountDown {
  int minutes = 0;
  int seconds = 0;
  CountDown({
    required this.minutes,
    required this.seconds,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'minute': minutes,
      'second': seconds,
    };
  }

  factory CountDown.fromMap(Map<String, dynamic> map) {
    return CountDown(
      minutes: (map['minute'] ?? 0) as int,
      seconds: (map['second'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory CountDown.fromJson(String source) => CountDown.fromMap(json.decode(source) as Map<String, dynamic>);

  CountDown copyWith({
    int? minutes,
    int? seconds,
  }) {
    return CountDown(
      minutes: minutes ?? this.minutes,
      seconds: seconds ?? this.seconds,
    );
  }

  @override
  String toString() => '\nCountDown(minutes: $minutes, seconds: $seconds)';
}

class TimersWidgetState extends State<TimersWidget> {
  List<CountDown> timers = Boxes.getSavedMap<CountDown>(CountDown.fromJson, "countdowns");

  final TextEditingController secondsController = TextEditingController(text: "00");
  final TextEditingController minutesController = TextEditingController(text: "00");
  final CountDown currentCountdown = CountDown(minutes: 0, seconds: 0);
  final CountDown initialCountdown = CountDown(minutes: 0, seconds: 0);
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    secondsController.dispose();
    minutesController.dispose();
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
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Expanded(child: Center(child: Text("Minutes", style: TextStyle(height: 1)))),
                    const SizedBox(width: 20),
                    const Expanded(child: Center(child: Text("Seconds", style: TextStyle(height: 1)))),
                  ],
                ),
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
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).backgroundColor.withOpacity(0.6),
                                backgroundBlendMode: BlendMode.screen,
                              ),
                              margin: const EdgeInsets.only(right: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                              child: TextField(
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  hintText: "00",
                                  hintStyle: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                  border: InputBorder.none,
                                  // counterText: "Minutes",
                                ),
                                controller: minutesController,
                                onSubmitted: (String e) {
                                  setState(() {});
                                },
                              ),
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
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).backgroundColor.withOpacity(0.6),
                                backgroundBlendMode: BlendMode.screen,
                              ),
                              margin: const EdgeInsets.only(left: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                              child: TextField(
                                keyboardType: TextInputType.number,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(2),
                                ],
                                style: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                  hintText: "00",
                                  hintStyle: TextStyle(fontSize: 50, fontWeight: FontWeight.bold, height: 1, color: Theme.of(context).textTheme.bodyLarge!.color),
                                  border: InputBorder.none,
                                  // counterText: "Seconds",
                                ),
                                controller: secondsController,
                                onChanged: (String e) {},
                                onSubmitted: (String e) {
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
                const Divider(height: 5, thickness: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextButton.icon(
                        onPressed: () {
                          final int minutes = int.tryParse(minutesController.text) ?? 0;
                          final int seconds = int.tryParse(secondsController.text) ?? 0;
                          if (minutes == 0 && seconds == 0) return;
                          if (countDownTimer != null) return;

                          final int index = timers.indexWhere((CountDown element) => element.minutes == minutes && element.seconds == seconds);
                          if (index > -1) timers.removeAt(index);
                          timers.insert(0, CountDown(minutes: minutes, seconds: seconds));
                          if (timers.length > 5) {
                            timers.removeRange(5, timers.length);
                          }

                          currentCountdown.minutes = minutes;
                          currentCountdown.seconds = seconds;
                          initialCountdown.minutes = minutes;
                          initialCountdown.seconds = seconds;
                          Boxes.updateSettings("countdowns", jsonEncode(timers));
                          currentCountdown.seconds++;
                          countDownTicker();
                          countDownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) => countDownTicker());
                        },
                        icon: const Icon(Icons.timer_outlined),
                        label: const Text("Start")),
                    TextButton.icon(
                      onPressed: () {
                        countDownTimer?.cancel();
                        countDownTimer = null;
                        setState(() {});
                      },
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text("Stop"),
                    ),
                    TextButton.icon(
                        onPressed: () {
                          minutesController.text = initialCountdown.minutes.toString();
                          secondsController.text = initialCountdown.seconds.toString();
                          countDownTimer?.cancel();
                          countDownTimer = null;
                          setState(() {});
                        },
                        icon: const Icon(Icons.restore),
                        label: const Text("Reset")),
                  ],
                ),
                const Divider(height: 5, thickness: 1),
                if (timers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: List<Widget>.generate(
                          timers.length,
                          (int index) => InkWell(
                            onTap: () {
                              minutesController.text = timers[index].minutes.toString().padLeft(2, '0');
                              secondsController.text = timers[index].seconds.toString().padLeft(2, '0');
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 5),
                              child: Text(
                                " ${timers[index].minutes} minutes and ${timers[index].seconds} seconds",
                                style: const TextStyle(fontSize: 15, height: 1),
                              ),
                            ),
                          ),
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

  Timer? countDownTimer;
  countDownTicker() {
    if (!mounted) {
      countDownTimer?.cancel();
      countDownTimer = null;
      return;
    }
    currentCountdown.seconds--;
    if (currentCountdown.seconds <= 0 && currentCountdown.minutes != 0) {
      currentCountdown.seconds = 59;
      currentCountdown.minutes -= 1;
    }
    minutesController.text = currentCountdown.minutes.toString().padLeft(2, '0');
    secondsController.text = currentCountdown.seconds.toString().padLeft(2, '0');
    if (currentCountdown.seconds <= 0 && currentCountdown.minutes <= 0) {
      currentCountdown.seconds = 0;
      currentCountdown.minutes = 0;
      countDownTimer?.cancel();
      countDownTimer = null;
      setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        Beep(100, 200);
        Beep(500, 200);
        Beep(1000, 200);
        Beep(500, 200);
      });
      return;
    }
    setState(() {});
  }
}
