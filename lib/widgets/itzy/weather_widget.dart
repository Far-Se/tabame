import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/boxes.dart';

import '../../models/utils.dart';
import '../../models/win32/win32.dart';

class WeatherWidget extends StatelessWidget {
  const WeatherWidget({Key? key}) : super(key: key);

  Future<String> fetchWeather() async {
    final response = await http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=%c+%t"));
    if (response.statusCode == 200) {
      return response.body.replaceAll(RegExp(r'[\t ]+'), " ");
    }
    return "";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      child: FutureBuilder(
        future: fetchWeather(),
        initialData: globalSettings.weather,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            globalSettings = Boxes.settings.getAt(0);
            globalSettings.weather = snapshot.data as String;
            Boxes.settings.putAt(0, globalSettings);
          }
          return InkWell(
            onTap: () {
              WinUtils.open("https://www.accuweather.com/en/search-locations?query=${globalSettings.weatherCity}");
            },
            child: Text(
              snapshot.data as String,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w100,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }
}
