import 'package:flutter/widgets.dart';

import '../containers/two_sides.dart';
import 'time_widget.dart';
import 'weather_widget.dart';

class TimeWeatherWidget extends StatelessWidget {
  const TimeWeatherWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TwoSides(
      left: TimeWidget(),
      right: WeatherWidget(),
      leftWidth: 95,
      rightWidht: 30,
      mainAxisAlignment: MainAxisAlignment.start,
    );
  }
}
