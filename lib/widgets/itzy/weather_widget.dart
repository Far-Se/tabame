import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../models/boxes.dart';
import '../../models/utils.dart';
import '../../models/win32/win32.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({Key? key}) : super(key: key);

  Future<String> fetchWeather() async {
    final http.Response response = await http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=%c+%t"));
    if (response.statusCode == 200) {
      return response.body.replaceAll(RegExp(r'[\t ]+'), " ");
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: double.infinity,
      child: FutureBuilder<String>(
        future: fetchWeather(),
        initialData: globalSettings.weather,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            globalSettings.weather = snapshot.data as String;
            Boxes.settings.put('settings', globalSettings);
          }
          return Theme(
            data: Theme.of(context)
                .copyWith(tooltipTheme: Theme.of(context).tooltipTheme.copyWith(preferBelow: false, decoration: BoxDecoration(color: Theme.of(context).backgroundColor))),
            child: InkWell(
              onTap: () {
                WinUtils.open("https://www.accuweather.com/en/search-locations?query=${globalSettings.weatherCity}");
              },
              child: Tooltip(
                message: globalSettings.weatherCity.capitalize(),
                child: Align(
                  child: Text(
                    snapshot.data as String,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w100,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
