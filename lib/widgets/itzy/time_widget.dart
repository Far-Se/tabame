// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/keys.dart';

class TimeWidget extends StatelessWidget {
  const TimeWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      initialData: {
        "time": DateFormat('hh:mm:ss').format(DateTime.now()),
        "date": DateFormat('dd MMM').format(DateTime.now()),
        "day": DateFormat('EE').format(DateTime.now()),
      },
      stream: Stream.periodic(Duration(milliseconds: 500), (timer) {
        final now = DateTime.now();
        return {
          "time": DateFormat('hh:mm:ss').format(now),
          "date": DateFormat('dd MMM').format(now),
          "day": DateFormat('EE').format(now),
        };
      }),
      builder: (context, snapshot) {
        return InkWell(
          onTap: () {
            WinKeys.send("{#LWIN}C");
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: 0, maxWidth: 140),
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    (snapshot.data as Map)["time"] as String,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    // textAlign: TextAlign,
                  ),
                ),
                SizedBox(
                  width: 30,
                  height: 15,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        top: -3,
                        child: Text(
                          (snapshot.data as Map)["day"] as String,
                          style: const TextStyle(color: Colors.white, fontSize: 10),
                        ),
                      ),
                      Positioned(
                        top: 7,
                        child: Text((snapshot.data as Map)["date"] as String, style: const TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                    ],
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
