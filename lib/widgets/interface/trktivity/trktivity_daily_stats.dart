import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/settings.dart';
import 'trktivity_models.dart';

class TrktivityDailyStats extends StatelessWidget {
  final Map<String, DMTRack> dailyStats;

  const TrktivityDailyStats({
    super.key,
    required this.dailyStats,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 20),
              Text("Daily Stats", style: Theme.of(context).textTheme.titleLarge),
              const Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text("Day")),
                  SizedBox(width: 80, child: Text("Active")),
                  SizedBox(width: 80, child: Text("Idle")),
                  SizedBox(width: 80, child: Text("Keys")),
                  SizedBox(width: 80, child: Text("Mouse")),
                ],
              ),
              InkWell(
                onTap: () {},
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: Text("Total", style: Theme.of(context).textTheme.labelLarge)),
                    SizedBox(
                        width: 80,
                        child: Text(timeFormat(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.time)),
                            style: Theme.of(context).textTheme.labelLarge)),
                    SizedBox(
                        width: 80,
                        child: Text(timeFormat(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.idleTime)),
                            style: Theme.of(context).textTheme.labelLarge)),
                    SizedBox(
                        width: 80,
                        child: Text(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.keyboard).formatInt(),
                            style: Theme.of(context).textTheme.labelLarge)),
                    SizedBox(
                        width: 80,
                        child: Text(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.mouse).formatInt(),
                            style: Theme.of(context).textTheme.labelLarge)),
                  ],
                ),
              ),
              ...List<Widget>.generate(dailyStats.keys.length, (int index) {
                return InkWell(
                  onTap: () {},
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                          child: Padding(
                        padding: const EdgeInsets.only(right: 5.0),
                        child: Text(DateFormat("EE, dd MMMM, yyyy").format(DateTime.parse(dailyStats.keys.elementAt(index))),
                            maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                      )),
                      SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).timeFormat)),
                      SizedBox(width: 80, child: Text(timeFormat(dailyStats.values.elementAt(index).idleTime))),
                      SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).keyboard.formatInt())),
                      SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).mouse.formatInt())),
                    ],
                  ),
                );
              })
            ],
          ),
        ),
        Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SizedBox(height: 20),
                Text("Daily Average", style: Theme.of(context).textTheme.titleLarge),
                Text("Active hours: ${timeFormat(dailyStats.values.map((DMTRack e) => e.time).average.toInt())}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 2)),
                Text("Idle hours: ${timeFormat(dailyStats.values.map((DMTRack e) => e.idleTime).average.toInt())}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 2)),
                Text("Key Strokes: ${dailyStats.values.map((DMTRack e) => e.keyboard).average.toInt().formatInt()}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 2)),
                Text("Mouse Pings: ${dailyStats.values.map((DMTRack e) => e.mouse).average.toInt().formatInt()}",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(height: 2)),
              ],
            ))
      ],
    );
  }
}
