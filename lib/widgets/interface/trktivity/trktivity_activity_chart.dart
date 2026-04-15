import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import 'trktivity_models.dart';

class TrktivityActivityChart extends StatelessWidget {
  final Map<int, MTrack> uTrack;
  final double uTrackMaxValue;

  const TrktivityActivityChart({
    super.key,
    required this.uTrack,
    required this.uTrackMaxValue,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: uTrackMaxValue,
          barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            getTooltipItem: (BarChartGroupData a, int b, BarChartRodData c, int d) {
              if (a.barRods.isEmpty) return BarTooltipItem("", Theme.of(context).textTheme.labelMedium!);
              final String kb = a.barRods.elementAt(0).rodStackItems.elementAt(0).toY.toInt().formatInt();
              final String mouse = a.barRods.elementAt(0).rodStackItems.elementAt(1).toY.toInt().formatInt();
              return BarTooltipItem("${a.x.formatTime()}\n$kb keys pressed\n$mouse mouse pings", Theme.of(context).textTheme.labelLarge!);
            },
          )),
          barGroups: List<BarChartGroupData>.generate(
            48,
            (int indx) {
              int i = 0;
              if (indx % 2 == 0) {
                i = indx ~/ 2 * 60;
              } else {
                i = indx ~/ 2 * 60 + 30;
              }
              if (uTrack.containsKey(i)) {
                return BarChartGroupData(
                  x: i,
                  barRods: <BarChartRodData>[
                    BarChartRodData(
                        toY: uTrackMaxValue,
                        rodStackItems: <BarChartRodStackItem>[
                          BarChartRodStackItem(0, uTrack[i]!.keyboard.toDouble(), Colors.red),
                          BarChartRodStackItem(0, uTrack[i]!.mouse.toDouble(), Colors.green),
                        ],
                        color: Colors.transparent),
                  ],
                );
              }
              return BarChartGroupData(x: i);
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value / 60 % 1 == 0) {
                    return SideTitleWidget(
                      meta: meta,
                      space: 16,
                      child: Text(
                        (value.toInt() ~/ 60).toString(),
                        style: const TextStyle(
                          color: Color(0xff7589a2),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 0,
                    child: Container(),
                  );
                },
                reservedSize: 42,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
        ),
      ),
    );
  }
}
