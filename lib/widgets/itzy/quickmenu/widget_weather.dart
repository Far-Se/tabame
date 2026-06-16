// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';

int _weatherLastFetchDate = 0;
Future<String> fetchWeather([bool showUnit = false]) async {
  // Check if we have already fetched the weather in the last 15 minutes
  if (_weatherLastFetchDate + 900000 > DateTime.now().millisecondsSinceEpoch && user.weatherTemperature.isNotEmpty) {
    return user.weatherTemperature;
  }
  _weatherLastFetchDate = DateTime.now().millisecondsSinceEpoch;
  bool failed = false;
  final List<String> latLong = user.weatherLatLong.split(',');
  if (latLong.length < 2) return "Bad Format.";

  try {
    final Future<http.Response> responseA = http
        .get(Uri.parse(
            "https://api.open-meteo.com/v1/forecast?latitude=${latLong[0].trim()}&longitude=${latLong[1].trim()}&current_weather=true${user.weatherUnit == "u" ? "&temperature_unit=fahrenheit" : ""}"))
        .catchError((_) {
      failed = true;
      return http.Response("", 500);
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
        if (weatherEmoji.containsKey(data["current_weather"]["weathercode"])) {
          weather = weatherEmoji[data["current_weather"]["weathercode"]].toString();
        }
        weather += " ${double.parse(data["current_weather"]["temperature"].toString()).toInt().toString()}°";
        if (showUnit) weather += " ${user.weatherUnit == "u" ? "F" : "C"}";
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
    super.key,
    this.width = 30,
    this.showUnit = false,
  });

  @override
  State<WeatherWidget> createState() => _WeatherWidgetState();
}

class _WeatherWidgetState extends State<WeatherWidget> {
  late Timer _refreshTimer;

  /// The cached future — only replaced when the 30-minute timer fires.
  late Future<String> _weatherFuture;

  /// Last known display text, used while a new fetch is in-flight or on error.
  String _cachedWeather = "";

  @override
  void initState() {
    super.initState();
    // Seed cache from persisted settings so we show something immediately.
    _cachedWeather = user.weatherTemperature;

    // Kick off the very first fetch.
    _triggerFetch();

    // Every 30 minutes, replace the cached future and rebuild.
    _refreshTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!mounted) return;
      setState(_triggerFetch);
    });
  }

  void _triggerFetch() {
    _weatherFuture = fetchWeather(widget.showUnit);
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!user.showWeather) {
      return Container(width: widget.width, height: 30, color: Colors.red);
    }

    return Container(
      width: widget.width,
      height: 30,
      child: FutureBuilder<String>(
        // Re-using the same future instance means no extra network calls on
        // parent setState — Flutter just delivers the already-resolved value.
        future: _weatherFuture,
        initialData: _cachedWeather,
        builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final String result = snapshot.data as String? ?? "";
            if (result.isNotEmpty) {
              // Persist the fresh result.
              _cachedWeather = result;
              user.weatherTemperature = result;
              Boxes.updateSettings("weather", user.weather);
            }
          }

          // Decide what text to show.
          final String display;
          if (snapshot.connectionState == ConnectionState.done) {
            final String result = snapshot.data as String? ?? "";
            display = result.isNotEmpty ? result : (_cachedWeather.isNotEmpty ? _cachedWeather : "No Data");
          } else {
            // Still loading — show the last known value (or nothing while
            // the very first fetch is in-flight).
            display = _cachedWeather.isNotEmpty ? _cachedWeather : "";
          }

          return InkWell(
            onTap: () {
              WinUtils.open("https://www.accuweather.com/en/search-locations?query=${user.weatherLatLong}");
            },
            child: Align(
              child: Text(
                display,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: FontWeight(Design.uiFontWeight),
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
