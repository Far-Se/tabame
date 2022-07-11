import 'package:flutter/widgets.dart';
import 'tray_bar.dart';

import '../containers/two_sides.dart';
import '../itzy/time_weather_widget.dart';

class BottomBar extends StatelessWidget {
  const BottomBar({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const TwoSides(left: TimeWeatherWidget(), right: TrayBar());
  }
}
