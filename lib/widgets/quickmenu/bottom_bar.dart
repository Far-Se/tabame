import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/globals.dart';
import '../../models/utils.dart';
import '../itzy/quickmenu/list_powershell.dart';
import '../itzy/quickmenu/widget_time_weather.dart';
import '../itzy/quickmenu/widget_usage.dart';
import 'tray_bar.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Globals.heights.traybar = 30;
    return Container(
      width: 280,
      height: 30,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context)
                .copyWith(tooltipTheme: Theme.of(context).tooltipTheme.copyWith(preferBelow: false, decoration: BoxDecoration(color: Theme.of(context).backgroundColor))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              verticalDirection: VerticalDirection.down,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(width: 100, child: TimeWeatherWidget()),
                if (kReleaseMode && globalSettings.showSystemUsage) const SizedBox(width: 45, child: SystemUsageWidget()), //! System Info
                if (Boxes().getPowerShellScripts().isNotEmpty) const Expanded(flex: 3, child: PowershellList()),
                if (Boxes().getPowerShellScripts().isNotEmpty) const SizedBox(width: 5),
                ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: 200 - (Boxes().getPowerShellScripts().isNotEmpty ? 65 : 0) - (kReleaseMode && globalSettings.showSystemUsage ? 40 : 0), minWidth: 50),
                    child: const TrayBar()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
