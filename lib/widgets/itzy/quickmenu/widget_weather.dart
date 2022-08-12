// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';

Future<String> fetchWeather([bool showUnit = false]) async {
  bool failed = false;
  final List<String> latLong = globalSettings.weatherLatLong.split(',');
  if (latLong.length < 2) return "Bad Format.";

  try {
    final Future<http.Response> responseA = http
        .get(Uri.parse(
            "https://api.open-meteo.com/v1/forecast?latitude=${latLong[0].trim()}&longitude=${latLong[1].trim()}&current_weather=true${globalSettings.weatherUnit == "u" ? "&temperature_unit=fahrenheit" : ""}"))
        .catchError((_) {
      failed = true;
    });

    final http.Response response = await responseA;
    if (failed) return "";
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      if (data.containsKey("current_weather")) {
        final Map<int, String> weatherEmoji = <int, String>{
          0: "☀",
          1: "🌤",
          2: "🌤",
          3: "🌤",
          45: "🌥",
          48: "🌥",
          51: "🌦",
          53: "🌦",
          55: "🌦",
          56: "☁",
          57: "☁",
          61: "🌧",
          63: "🌧",
          65: "🌧",
          66: "🌨",
          67: "🌨",
          71: "🌨",
          73: "🌨",
          75: "🌨",
          77: "❄",
          80: "⛈",
          81: "⛈",
          82: "⛈",
          85: "☃",
          86: "☃",
          95: "🌩",
          96: "🌩",
          99: "🌩",
        };
        String weather = "";
        if (weatherEmoji.containsKey(data["current_weather"]["weathercode"])) weather = weatherEmoji[data["current_weather"]["weathercode"]].toString();
        weather += " ${double.parse(data["current_weather"]["temperature"].toString()).toInt().toString()}°";
        if (showUnit) weather += " ${globalSettings.weatherUnit == "u" ? "F" : "C"}";
        return weather;
      }
    }
  } catch (_) {
    return "";
  }
  return "";
}

class WeatherWidget extends StatefulWidget {
  final double width;
  final bool showUnit;
  const WeatherWidget({
    Key? key,
    this.width = 30,
    this.showUnit = false,
  }) : super(key: key);

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  late Timer refreshWeather;
  @override
  void initState() {
    super.initState();
    refreshWeather = Timer.periodic(const Duration(minutes: 30), (Timer timer) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    refreshWeather.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!globalSettings.showWeather) return const SizedBox();
    return Container(
      width: widget.width,
      height: 30,
      // height: double.infinity,
      child: FutureBuilder<String>(
        future: fetchWeather(widget.showUnit),
        initialData: globalSettings.weatherTemperature,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              if ((snapshot.data as String).isNotEmpty) {
                globalSettings.weatherTemperature = snapshot.data as String;
                Boxes.updateSettings("weather", globalSettings.weather);
              }
            }
          }
          return InkWell(
            onTap: () {
              WinUtils.open("https://www.accuweather.com/en/search-locations?query=${globalSettings.weatherLatLong}");
            },
            child: Align(
              child: Text(
                snapshot.data as String,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w200,
                  height: 1.1,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
