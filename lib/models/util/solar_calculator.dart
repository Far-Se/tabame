import 'dart:convert';

import 'package:http/http.dart' as http;

import '../classes/boxes.dart';
import '../settings.dart';

class SolarCalculator {
  static Future<void> updateSolarData({bool force = false}) async {
    final int nowUnix = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // Refresh only if 12h passed or forced
    if (!force && (nowUnix - userSettings.lightSwitchLastFetch < 12 * 3600)) {
      return;
    }

    final List<String> latLong = userSettings.weatherLatLong.split(',');
    if (latLong.length < 2) return;

    final String lat = latLong[0].trim();
    final String lon = latLong[1].trim();

    try {
      final Uri url = Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=sunrise,sunset&timezone=auto");
      final http.Response response = await http.get(url);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.containsKey("daily")) {
          final String sunriseStr = data["daily"]["sunrise"][0]; // Format: 2026-04-18T06:12
          final String sunsetStr = data["daily"]["sunset"][0];

          final DateTime sunrise = DateTime.parse(sunriseStr);
          final DateTime sunset = DateTime.parse(sunsetStr);

          userSettings.lightSwitchSunrise = sunrise.hour * 60 + sunrise.minute;
          userSettings.lightSwitchSunset = sunset.hour * 60 + sunset.minute;
          userSettings.lightSwitchLastFetch = nowUnix;

          await Boxes.updateSettings("lightSwitchSunrise", userSettings.lightSwitchSunrise);
          await Boxes.updateSettings("lightSwitchSunset", userSettings.lightSwitchSunset);
          await Boxes.updateSettings("lightSwitchLastFetch", userSettings.lightSwitchLastFetch);
        }
      }
    } catch (e) {
      // Silently fail, we'll try again later
    }
  }
}
