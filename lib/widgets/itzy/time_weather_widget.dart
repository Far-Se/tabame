import 'package:flutter/widgets.dart';

import 'time_widget.dart';
import 'weather_widget.dart';

class TimeWeatherWidget extends StatelessWidget {
  const TimeWeatherWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      constraints: BoxConstraints(minWidth: 0, maxWidth: 100),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        verticalDirection: VerticalDirection.down,
        children: [
          TimeWidget(),
          // Spacer(),
          WeatherWidget(),
        ],
      ),
    );
  }
}
