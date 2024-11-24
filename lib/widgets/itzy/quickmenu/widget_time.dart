// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/win32/keys.dart';
import '../../../models/settings.dart';

class TimeWidget extends StatefulWidget {
  final bool? inline;
  const TimeWidget({
    super.key,
    this.inline,
  });

  @override
  State<TimeWidget> createState() => _TimeWidgetState();
}

class _TimeWidgetState extends State<TimeWidget> {
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
    final bool inline2 = widget.inline ?? false;
    return StreamBuilder<Map<String, String>>(
      initialData: <String, String>{
        "time": DateFormat('hh:mm:ss').format(DateTime.now()),
        "date": DateFormat('dd MMM').format(DateTime.now()),
        "day": DateFormat('EE').format(DateTime.now()),
      },
      stream: Stream<Map<String, String>>.periodic(const Duration(milliseconds: 500), (int timer) {
        final DateTime now = DateTime.now();
        return <String, String>{
          "time": DateFormat('hh:mm:ss').format(now),
          "date": DateFormat('dd MMM').format(now),
          "day": DateFormat('EE').format(now),
        };
      }),
      builder: (BuildContext context, AsyncSnapshot<Map<dynamic, dynamic>> snapshot) {
        if (inline2) {
          return InkWell(
            onTap: () {
              globalSettings.noopKeyListener = true;
              WinKeys.send("{#LWIN}C");
              Future<void>.delayed(const Duration(milliseconds: 500), () => globalSettings.noopKeyListener = false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text((snapshot.data as Map<String, String>)["time"] as String,
                      style: TextStyle(fontSize: 14, fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400)),
                  Text("${snapshot.data!["day"]} ${snapshot.data!["date"]}",
                      style: TextStyle(fontSize: 14, fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400))
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Container(
            width: 60,
            child: InkWell(
              onTap: () {
                globalSettings.noopKeyListener = true;
                WinKeys.send("{#LWIN}C");
                Future<void>.delayed(const Duration(milliseconds: 500), () => globalSettings.noopKeyListener = false);
              },
              child: Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 0, maxWidth: 100),
                  child: Column(
                    children: <Widget>[
                      Flexible(
                          fit: FlexFit.tight,
                          child: Text((snapshot.data as Map<String, String>)["time"] as String,
                              style: TextStyle(fontSize: 14, fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400))),
                      Flexible(
                          fit: FlexFit.tight,
                          child: Text("${snapshot.data!["day"]} ${snapshot.data!["date"]}",
                              style: TextStyle(fontSize: 10, fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400)))
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
