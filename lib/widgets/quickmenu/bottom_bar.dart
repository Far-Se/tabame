import 'package:flutter/material.dart';
import '../../models/globals.dart';
import '../itzy/quickmenu/time_weather_widget.dart';
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            verticalDirection: VerticalDirection.down,
            children: <Widget>[
              Expanded(
                // ! Align HERE
                child: Container(
                  width: 280 / 2,
                  child: const TimeWeatherWidget(),
                ),
              ),
              Expanded(
                // ! Align HERE
                child: Container(
                  width: 280 / 2,
                  child: const TrayBar(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
