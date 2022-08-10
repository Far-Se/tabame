// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';

Future<String> fetchWeather() async {
  bool failed = false;
  // final http.Response response =
  // await http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=${globalSettings.weatherFormat}&${globalSettings.weatherUnit}"));
  try {
    final Future<http.Response> responseA =
        http.get(Uri.parse("https://wttr.in/${globalSettings.weatherCity}?format=${globalSettings.weatherFormat}&${globalSettings.weatherUnit}")).catchError((_) {
      failed = true;
    });

    final http.Response response = await responseA;
    if (failed) return "";
    if (response.statusCode == 200) {
      return response.body.replaceAll(RegExp(r'[\t ]+'), " ");
    }
  } catch (_) {
    return "";
  }
  return "";
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
      height: 30,
      // height: double.infinity,
      child: FutureBuilder<String>(
        future: fetchWeather(),
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
              WinUtils.open("https://www.accuweather.com/en/search-locations?query=${globalSettings.weatherCity}");
            },
            child: Tooltip(
              message: globalSettings.weatherCity.toUpperCaseEach(),
              child: Align(
                child: Text(
                  snapshot.data as String,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: globalSettings.quickMenuPinnedWithTrayAtBottom ? 13 : 10,
                    fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w200,
                    height: 1.3,
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
