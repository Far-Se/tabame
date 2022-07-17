import 'package:flutter/widgets.dart';

import 'time_widget.dart';
import 'weather_widget.dart';

class TimeWeatherWidget extends StatelessWidget {
  const TimeWeatherWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      verticalDirection: VerticalDirection.up,
      mainAxisSize: MainAxisSize.max,
      children: <Widget>[
        const TimeWidget(),
        const WeatherWidget(),
      ],
    );
  }
}