import 'package:flutter/widgets.dart';

import 'widget_time.dart';
import 'widget_weather.dart';

class TimeWeatherWidget extends StatelessWidget {
  const TimeWeatherWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      verticalDirection: VerticalDirection.up,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        TimeWidget(),
        WeatherWidget(),
      ],
    );
  }
}
