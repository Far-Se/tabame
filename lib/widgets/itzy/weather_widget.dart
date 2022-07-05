import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/boxes.dart';

import '../../models/utils.dart';

class WeatherWidget extends StatefulWidget {
  const WeatherWidget({Key? key}) : super(key: key);

  @override
  WeatherWidgetState createState() => WeatherWidgetState();
}

class WeatherWidgetState extends State<WeatherWidget> {
  String weather = globalSettings.weather;
  Future<String> fetchWeather() async {
    final response = await http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=%c+%t"));
    if (response.statusCode == 200) {
      return response.body.replaceAll(RegExp(r'[\t ]+'), " ");
    }
    return "";
  }

  void init() async {
    globalSettings = await Boxes.settings.getAt(0);
    weather = await fetchWeather();
    globalSettings.weather = weather;
    Boxes.settings.putAt(0, globalSettings);
    if (!mounted) return;
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    init();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      // height: 30,
      child: Text(weather,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w100,
            color: Colors.white,
          )),
    );
  }
}
