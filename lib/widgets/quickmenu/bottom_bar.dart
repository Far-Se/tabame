import 'package:flutter/material.dart';
import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../itzy/quickmenu/list_powershell.dart';
import '../itzy/quickmenu/widget_time.dart';
import '../itzy/quickmenu/widget_time_weather.dart';
import '../itzy/quickmenu/widget_usage.dart';
import '../itzy/quickmenu/widget_weather.dart';
import 'tray_bar.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({super.key});

  @override
  Widget build(BuildContext context) {
    Debug.add("QuickMenu: BottomBar");
    Globals.heights.traybar = 30;
    final bool showPowerShell = globalSettings.showPowerShell && Boxes().powerShellScripts.isNotEmpty;
    if (!showPowerShell &&
        !globalSettings.showSystemUsage &&
        ((globalSettings.showTrayBar && globalSettings.quickMenuPinnedWithTrayAtBottom) || !globalSettings.showTrayBar)) {
      if (!globalSettings.showWeather) {
        return const TimeWidget(inline: true);
      } else {
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
              constraints:
                  BoxConstraints(minWidth: constraints.minWidth, minHeight: constraints.minHeight, maxWidth: constraints.maxWidth, maxHeight: constraints.maxHeight),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                verticalDirection: VerticalDirection.down,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Expanded(child: TimeWidget(inline: true)),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: WeatherWidget(width: 80, showUnit: true)),
                ],
              )),
        );
      }
    }
    return Container(
      width: 280,
      height: 31,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context)
                .copyWith(tooltipTheme: Theme.of(context).tooltipTheme.copyWith(preferBelow: false, decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              verticalDirection: VerticalDirection.down,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(width: 100, child: TimeWeatherWidget()),
                if (globalSettings.showSystemUsage) const SizedBox(width: 45, child: SystemUsageWidget()),
                if (showPowerShell) const Expanded(flex: 3, child: PowershellList()),
                if (showPowerShell) const SizedBox(width: 5),
                if (!globalSettings.quickMenuPinnedWithTrayAtBottom)
                  ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 180 - (showPowerShell ? 65 : 0) - (globalSettings.showSystemUsage ? 40 : 0), minWidth: 50),
                      child: const TrayBar()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
