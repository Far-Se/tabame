import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class PersistentRemindersWidget extends StatefulWidget {
  const PersistentRemindersWidget({super.key});
  @override
  PersistentRemindersWidgetState createState() => PersistentRemindersWidgetState();
}

class PersistentRemindersWidgetState extends State<PersistentRemindersWidget> {
  int lastPersistentRemindersLength = 0;
  @override
  void initState() {
    super.initState();
    //timer
    Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (globalSettings.persistentReminders.length != lastPersistentRemindersLength) {
        lastPersistentRemindersLength = globalSettings.persistentReminders.length;
        if (mounted) setState(() {});
      }
    });
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
        child: GestureDetector(
          onSecondaryTap: () {
            globalSettings.persistentReminders.clear();
            Boxes.pref.setStringList("persistentReminders", globalSettings.persistentReminders);
            for (final QuickMenuTriggers listener in QuickMenuFunctions.listeners) {
              if (!QuickMenuFunctions.listeners.contains(listener)) return;
              listener.refreshQuickMenu();
            }
            setState(() {});
          },
          child: Tooltip(
            message: "Reminders",
            child: globalSettings.persistentReminders.length > 1
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
                    child: Badge.count(
                      offset: const Offset(8, -5),
                      count: globalSettings.persistentReminders.length,
                      backgroundColor: Colors.transparent,
                      textStyle: const TextStyle(fontSize: 9),
                      textColor: Colors.white,
                      child: const Icon(Icons.warning_rounded, color: Colors.red),
                    ),
                  )
                : const Icon(Icons.warning_rounded, color: Colors.red),
          ),
        ),
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
  const TimersWidget({super.key});
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
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
          child: SingleChildScrollView(
            controller: ScrollController(),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: globalSettings.persistentReminders.isEmpty
                    ? const InkWell(child: Text("You have no reminders"))
                    : Column(mainAxisAlignment: MainAxisAlignment.start, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                        ...List<Widget>.generate(
                            globalSettings.persistentReminders.length,
                            (int index) => ListTile(
                                  onTap: () {
                                    globalSettings.persistentReminders.removeAt(index);
                                    Boxes.pref.setStringList("persistentReminders", globalSettings.persistentReminders);
                                    for (final QuickMenuTriggers listener in QuickMenuFunctions.listeners) {
                                      if (!QuickMenuFunctions.listeners.contains(listener)) return;
                                      listener.refreshQuickMenu();
                                    }
                                    setState(() {});
                                  },
                                  title: Text(" ${globalSettings.persistentReminders.elementAt(index)}", style: const TextStyle(fontSize: 16)),
                                  trailing: const Icon(Icons.delete),
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                                  minVerticalPadding: 0,
                                ))
                      ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
