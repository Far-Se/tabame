import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/keys.dart';

class TimeWidget extends StatelessWidget {
  const TimeWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map>(
      initialData: {
        "time": DateFormat('hh:mm:ss').format(DateTime.now()),
        "date": DateFormat('dd MMM').format(DateTime.now()),
        "day": DateFormat('EE').format(DateTime.now()),
      },
      stream: Stream.periodic(const Duration(milliseconds: 500), (timer) {
        final now = DateTime.now();
        return {
          "time": DateFormat('hh:mm:ss').format(now),
          "date": DateFormat('dd MMM').format(now),
          "day": DateFormat('EE').format(now),
        };
      }),
      builder: (context, snapshot) {
        return Container(
          width: 70,
          child: InkWell(
            onTap: () {
              WinKeys.send("{#LWIN}C");
            },
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 0, maxWidth: 100),
                child: Column(
                  // mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  // mainAxisSize: MainAxisSize.max,
                  // crossAxisAlignment: CrossAxisAlignment.center,
                  // verticalDirection: VerticalDirection.down,
                  children: [
                    Flexible(
                      fit: FlexFit.loose,
                      child: SizedBox(
                        width: 100,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Text(
                            (snapshot.data as Map)["time"] as String,
                            style: const TextStyle(
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      fit: FlexFit.tight,
                      child: Text("${snapshot.data!["day"]} ${snapshot.data!["date"]}", style: const TextStyle(fontSize: 10)),
                    )
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
