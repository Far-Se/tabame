import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/settings.dart';
import '../itzy/quickmenu/widget_time.dart';
import '../itzy/quickmenu/widget_usage.dart';
import '../itzy/quickmenu/widget_weather.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    Debug.add("QuickMenu: BottomBar");
    Globals.heights.infoBar = 30;
    if (!user.showSystemUsage && (user.showTrayBar || !user.showTrayBar)) {
      if (!user.showWeather) {
        return const TimeWidget(inline: true);
      } else {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: constraints.minWidth,
                  minHeight: constraints.minHeight,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                verticalDirection: VerticalDirection.down,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TimeWidget(inline: true),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: WeatherWidget(width: 80, showUnit: true),
                  ),
                ],
              )),
        );
      }
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: constraints.minWidth,
              minHeight: constraints.minHeight,
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            verticalDirection: VerticalDirection.down,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const TimeWidget(inline: true),
              if (!user.showSystemUsage) const SizedBox(width: 10),
              const WeatherWidget(width: 70, showUnit: true),
              if (user.showSystemUsage) const SizedBox(width: 10),
              if (user.showSystemUsage) const SizedBox(width: 45, child: SystemUsageWidget()),
            ],
          )),
    );
  }
}
