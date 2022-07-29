// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';

Future<String> fetchWeather() async {
  final http.Response response =
      await http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=${globalSettings.weatherFormat}&${globalSettings.weatherUnit}"));
  if (response.statusCode == 200) {
    return response.body.replaceAll(RegExp(r'[\t ]+'), " ");
  }
  return "-";
}

class WeatherWidget extends StatefulWidget {
  final double width;
  const WeatherWidget({
    Key? key,
    this.width = 30,
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
      // height: double.infinity,
      child: FutureBuilder<String>(
        future: fetchWeather(),
        initialData: globalSettings.weatherTemperature,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasData) {
              globalSettings.weatherTemperature = snapshot.data as String;
              Boxes.updateSettings("weather", globalSettings.weather);
            }
          }
          return Theme(
            data: Theme.of(context)
                .copyWith(tooltipTheme: Theme.of(context).tooltipTheme.copyWith(preferBelow: false, decoration: BoxDecoration(color: Theme.of(context).backgroundColor))),
            child: InkWell(
              onTap: () {
                WinUtils.open("https://www.accuweather.com/en/search-locations?query=${globalSettings.weatherCity}");
              },
              child: Tooltip(
                message: globalSettings.weatherCity.toUpperCaseEach(),
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
