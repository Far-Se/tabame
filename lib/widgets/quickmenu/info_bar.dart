import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

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
        return const DragToMoveArea(child: TimeWidget(inline: true));
      } else {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: constraints.minWidth,
                  minHeight: constraints.minHeight,
                  maxWidth: constraints.maxWidth,
                  maxHeight: constraints.maxHeight),
              child: const DragToMoveArea(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  verticalDirection: VerticalDirection.down,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TimeWidget(inline: true),
                    FractionalTranslation(
                      translation: Offset(0, -1 / 30),
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: WeatherWidget(width: 80, showUnit: true),
                      ),
                    ),
                  ],
                ),
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
          child: DragToMoveArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              verticalDirection: VerticalDirection.down,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const TimeWidget(inline: true),
                if (!user.showSystemUsage) const SizedBox(width: 10),
                const FractionalTranslation(
                  translation: Offset(0, -1 / 30),
                  child: WeatherWidget(width: 70, showUnit: true),
                ),
                if (user.showSystemUsage) const SizedBox(width: 10),
                if (user.showSystemUsage) const SizedBox(width: 45, child: SystemUsageWidget()),
              ],
            ),
          )),
    );
  }
}
