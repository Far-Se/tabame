// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/keys.dart';

class TimeWidget extends StatefulWidget {
  const TimeWidget({Key? key}) : super(key: key);

  @override
  TimeWidgetState createState() => TimeWidgetState();
}

class DateMap {
  String time = "00:00:00";
  String date = "12 Jan";
  String day = "Day";
  @override
  String toString() => 'DateMap(time: $time, date: $date, day: $day)';
}

class TimeWidgetState extends State<TimeWidget> {
  DateMap date = DateMap();
  final timeFormat = DateFormat('hh:mm:ss');
  final dateFormat = DateFormat('dd MMM');
  final dayFormat = DateFormat('EE');
  late Timer mainTimer;
  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    init();
  }

  setDate() {
    final now = DateTime.now();
    date.time = timeFormat.format(now);
    date.date = dateFormat.format(now);
    date.day = dayFormat.format(now);
    // date.time = "xx";
    // date.date = "xx";
    // date.day = "xx";
  }

  Future<void> init() async {
    setDate();
    Timer.periodic(Duration(milliseconds: 500), (timer) {
      mainTimer = timer;
      setDate();
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    mainTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        WinKeys.send("{#LWIN}C");
      },
      child: Row(
        // direction: Axis.horizontal,
        // clipBehavior: Clip.none,
        // spacing: 0,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              date.time,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.justify,
            ),
          ),
          SizedBox(
            width: 30,
            height: 15,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: -5,
                  child: Text(
                    date.day,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
                Positioned(
                  top: 5,
                  child: Text(date.date, style: const TextStyle(color: Colors.white, fontSize: 10)),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
