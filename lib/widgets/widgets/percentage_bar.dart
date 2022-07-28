import 'package:flutter/material.dart';

class PercentageBar extends StatelessWidget {
  const PercentageBar({
    Key? key,
    required this.percent,
    required this.barWidth,
  }) : super(key: key);

  final double percent;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    double percent2 = percent;
    if (percent2.isNaN || percent2.isNegative) percent2 = 0;
    double bar = percent / (100 / barWidth);
    if (bar.isNaN || bar.isNegative) bar = 0;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Tooltip(
        message: "${percent2.toStringAsFixed(2)}%",
        child: SizedBox(
            width: barWidth,
            height: 10,
            child: Stack(
              children: <Widget>[
                Container(width: barWidth, height: 30, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.2)),
                Positioned(top: 0, left: 0, child: Container(width: bar, height: 30, color: Theme.of(context).colorScheme.primary)),
              ],
            )),
      ),
    );
  }
}
