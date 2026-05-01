import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:math_parser/math_parser.dart';
import 'package:units_converter/units_converter.dart';

import 'settings.dart';
import 'win32/mixed.dart';

enum ResultType { copy, open, send, none }

class ParserResult {
  List<String> results = <String>[];
  Map<String, String> actions = <String, String>{};
  ResultType type = ResultType.copy;
  String error = "";
}

class Parsers {
  Future<ParserResult> calculator(String input) async {
    input = input.replaceAll('%', "/100");
    final ParserResult result = ParserResult();
    final List<String> math = input.split('|');
    final Map<String, num> mathVars = <String, num>{
      "x": 0,
      "y": 0,
      "z": 0,
      "a": 0,
      "b": 0,
      "c": 0,
      "d": 0,
      "e": 0,
      "f": 0
    };
    for (int i = 0; i < math.length; i++) {
      if (math[i].isEmpty) continue;
      num x = 0;
      try {
        x = MathNodeExpression.fromString(math[i], variableNames: <String>{"x", "y", "z", "a", "b", "c", "d", "e", "f"})
            .calc(MathVariableValues(mathVars));
      } catch (e) {
        result.error = e.toString();
      }
      mathVars[mathVars.keys.elementAt(i)] = x;
      result.results.add("${mathVars.keys.elementAt(i)} = ${x.formatNum()}");
    }
    return result;
  }

  T? getUnitType<T>(String from, List<Unit> units, Iterable<T> names) {
    for (Unit e in units) {
      if (from == e.symbol?.toLowerCase()) {
        return (e.name as T);
      }
    }
    for (T type in names) {
      if (type.toString().toLowerCase().split(".").last == from) {
        return type;
      }
    }
    return null;
  }

  final NumberFormat format = NumberFormat("#,##0.00", "en_US");

  Future<ParserResult> unit(String input) async {
    Map<String, String> convertFormats = <String, String>{
      "Type a number to see results:": "",
      "ex: 1 power": "",
      "length": "m",
      "mass": "g",
      "temperature": "fahrenheit",
      "volume": "l",
      "speed": "m/s",
      "digital": "b",
      "area": "acres",
      "energy": "j",
      "force": "n",
      "fuel": "km/l",
      "power": "watt",
      "pressure": "pa",
      "shoe": "ukindiachild",
      "time": "s",
      "torque": "n·m",
    };
    final ParserResult result = ParserResult();
    final RegExp reg = RegExp(r'^([\d\.]+) ([\w\\/]+)');
    if (!reg.hasMatch(input)) {
      result.results.addAll(convertFormats.keys);
      return result..error = "Format: NUMBER unit to unit";
    }
    final RegExpMatch matches = reg.firstMatch(input)!;
    final double number = double.tryParse(matches[1]!) ?? 0;
    String from = matches[2]!;
    String to = "";
    if (from == "f") from = "fahrenheit";
    if (from == "c") from = "celsius";
    if (input.contains(' to ')) {
      to = input.replaceFirst("${matches[0]!} to ", "");
      to = to.trim();
    }
    if (convertFormats.keys.contains(from)) from = convertFormats[from]!;

    if (true) {
      final Length length = Length();
      final LENGTH? matched = getUnitType<LENGTH>(from, length.getAll(), LENGTH.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as LENGTH).name} (${i.symbol})");
          }
          return result;
        }
        final LENGTH? matchedTo = getUnitType<LENGTH>(to, length.getAll(), LENGTH.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Area length = Area();
      final AREA? matched = getUnitType<AREA>(from, length.getAll(), AREA.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as AREA).name} (${i.symbol})");
          }
          return result;
        }
        final AREA? matchedTo = getUnitType<AREA>(to, length.getAll(), AREA.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final DigitalData length = DigitalData();
      final DIGITAL_DATA? matched = getUnitType<DIGITAL_DATA>(from, length.getAll(), DIGITAL_DATA.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as DIGITAL_DATA).name} (${i.symbol})");
          }
          return result;
        }
        final DIGITAL_DATA? matchedTo = getUnitType<DIGITAL_DATA>(to, length.getAll(), DIGITAL_DATA.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Energy length = Energy();
      final ENERGY? matched = getUnitType<ENERGY>(from, length.getAll(), ENERGY.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as ENERGY).name} (${i.symbol})");
          }
          return result;
        }
        final ENERGY? matchedTo = getUnitType<ENERGY>(to, length.getAll(), ENERGY.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Force length = Force();
      final FORCE? matched = getUnitType<FORCE>(from, length.getAll(), FORCE.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as FORCE).name} (${i.symbol})");
          }
          return result;
        }
        final FORCE? matchedTo = getUnitType<FORCE>(to, length.getAll(), FORCE.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final FuelConsumption length = FuelConsumption();
      final FUEL_CONSUMPTION? matched = getUnitType<FUEL_CONSUMPTION>(from, length.getAll(), FUEL_CONSUMPTION.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as FUEL_CONSUMPTION).name} (${i.symbol})");
          }
          return result;
        }
        final FUEL_CONSUMPTION? matchedTo = getUnitType<FUEL_CONSUMPTION>(to, length.getAll(), FUEL_CONSUMPTION.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Mass length = Mass();
      final MASS? matched = getUnitType<MASS>(from, length.getAll(), MASS.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as MASS).name} (${i.symbol})");
          }
          return result;
        }
        final MASS? matchedTo = getUnitType<MASS>(to, length.getAll(), MASS.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Power length = Power();
      final POWER? matched = getUnitType<POWER>(from, length.getAll(), POWER.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as POWER).name} (${i.symbol})");
          }
          return result;
        }
        final POWER? matchedTo = getUnitType<POWER>(to, length.getAll(), POWER.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Pressure length = Pressure();
      final PRESSURE? matched = getUnitType<PRESSURE>(from, length.getAll(), PRESSURE.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as PRESSURE).name} (${i.symbol})");
          }
          return result;
        }
        final PRESSURE? matchedTo = getUnitType<PRESSURE>(to, length.getAll(), PRESSURE.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final ShoeSize length = ShoeSize();
      final SHOE_SIZE? matched = getUnitType<SHOE_SIZE>(from, length.getAll(), SHOE_SIZE.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as SHOE_SIZE).name} (${i.symbol})");
          }
          return result;
        }
        final SHOE_SIZE? matchedTo = getUnitType<SHOE_SIZE>(to, length.getAll(), SHOE_SIZE.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Speed length = Speed();
      final SPEED? matched = getUnitType<SPEED>(from, length.getAll(), SPEED.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as SPEED).name} (${i.symbol})");
          }
          return result;
        }
        final SPEED? matchedTo = getUnitType<SPEED>(to, length.getAll(), SPEED.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Temperature length = Temperature();
      final TEMPERATURE? matched = getUnitType<TEMPERATURE>(from, length.getAll(), TEMPERATURE.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as TEMPERATURE).name} (${i.symbol})");
          }
          return result;
        }
        final TEMPERATURE? matchedTo = getUnitType<TEMPERATURE>(to, length.getAll(), TEMPERATURE.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Time length = Time();
      final TIME? matched = getUnitType<TIME>(from, length.getAll(), TIME.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as TIME).name} (${i.symbol})");
          }
          return result;
        }
        final TIME? matchedTo = getUnitType<TIME>(to, length.getAll(), TIME.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Torque length = Torque();
      final TORQUE? matched = getUnitType<TORQUE>(from, length.getAll(), TORQUE.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as TORQUE).name} (${i.symbol})");
          }
          return result;
        }
        final TORQUE? matchedTo = getUnitType<TORQUE>(to, length.getAll(), TORQUE.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }
    if (true) {
      final Volume length = Volume();
      final VOLUME? matched = getUnitType<VOLUME>(from, length.getAll(), VOLUME.values);
      if (matched != null) {
        if (to == "") {
          length.convert(matched, number);
          final List<Unit> x = length.getAll();
          for (Unit i in x) {
            result.results.add("${format.format(i.value)} ${(i.name as VOLUME).name} (${i.symbol})");
          }
          return result;
        }
        final VOLUME? matchedTo = getUnitType<VOLUME>(to, length.getAll(), VOLUME.values);
        if (matchedTo != null) {
          return result
            ..results.add(
                "${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
        }
      }
    }

    return result;
  }

  Future<ParserResult> color(String input) async {
    final ParserResult result = ParserResult();
    late Color color;
    if (input.startsWith("#") || input.startsWith("0x")) {
      input = input.replaceAll("#", "").replaceAll("0x", "");
      if (input.isEmpty) return result;
      if (input.length > 8) return result;
      try {
        if (input.length == 8) {
          input = input.substring(input.length - 2) + input.substring(0, input.length - 2);
          color = Color(int.parse('0x$input'));
        } else if (input.length == 3) {
          final String expanded = input.split('').map((String char) => '$char$char').join();
          color = Color(int.parse('0xFF$expanded'));
        } else {
          while (input.length < 6) {
            input += "F";
          }
          color = Color(int.parse('0xFF$input'));
        }
      } catch (__) {
        return result;
      }
    } else if (input.startsWith("rgb") &&
        RegExp(r'^rgba?\(([0-9 ]+),([0-9 ]+),([0-9 ]+)(?:,([0-9 ]+))?\)').hasMatch(input)) {
      final RegExpMatch col = RegExp(r'^rgba?\(([0-9 ]+),([0-9 ]+),([0-9 ]+)(?:,([0-9 ]+))?\)').firstMatch(input)!;
      color = Color.fromARGB(int.parse(col[4] ?? "255"), int.parse(col[1]!), int.parse(col[2]!), int.parse(col[3]!));
    } else if (input.startsWith("cmyk") &&
        RegExp(r'^cmyk?\(([0-9 ]+),([0-9 ]+),([0-9 ]+),([0-9 ]+)\)').hasMatch(input)) {
      final RegExpMatch cmyk = RegExp(r'^cmyk?\(([0-9 ]+),([0-9 ]+),([0-9 ]+),([0-9 ]+)\)').firstMatch(input)!;
      final double r = (255 * (1 - int.parse(cmyk[1]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      final double g = (255 * (1 - int.parse(cmyk[2]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      final double b = (255 * (1 - int.parse(cmyk[3]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      color = Color.fromARGB(255, (r).round(), (g).round(), (b).round());
    } else {
      return result..results.addAll(<String>["#ffffff", "rgba(255,255,255,255)", "cmyk(0,0,0,0)"]);
    }

    result.results.add("#${color.value32bit.toRadixString(16)}");
    result.results.add("0x${color.value32bit.toRadixString(16)}");
    result.results.add("rgba(${color.red8bit}, ${color.green8bit}, ${color.blue8bit}, ${color.alpha8bit})");
    result.results.add("argb(${color.alpha8bit}, ${color.red8bit}, ${color.green8bit}, ${color.blue8bit})");
    final HSLColor hslColor = HSLColor.fromColor(color);
    result.results.add(
        "hsl(${hslColor.hue.toStringAsFixed(1)}, ${(hslColor.saturation * 100).toStringAsFixed(1)}%, ${(hslColor.lightness * 100).toStringAsFixed(1)}%)");
    result.results.add(
        "hsla(${hslColor.hue.toStringAsFixed(1)}, ${(hslColor.saturation * 100).toStringAsFixed(1)}%, ${(hslColor.lightness * 100).toStringAsFixed(1)}%, ${hslColor.alpha})");
    final HSVColor hsvColor = HSVColor.fromColor(color);
    result.results.add(
        "hsv(${hsvColor.hue.toStringAsFixed(1)}, ${(hsvColor.saturation * 100).toStringAsFixed(1)}%, ${(hsvColor.value * 100).toStringAsFixed(1)}%)");

    if (color.red8bit == 0 && color.green8bit == 0 && color.blue8bit == 0) {
    } else {
      final double r = 1 - (color.red8bit / 255);
      final double g = 1 - (color.green8bit / 255);
      final double b = 1 - (color.blue8bit / 255);
      final num k = min(r, min(g, b));
      final num c = ((r - k) / (1 - k) * 100).round();
      final num m = ((g - k) / (1 - k) * 100).round();
      final num y = ((b - k) / (1 - k) * 100).round();
      result.results.add("cmyk($c, $m, $y, ${(k * 100).round()})");
    }
    result.results.add("custom:color:0x${color.value32bit.toRadixString(16)}");
    return result;
  }

  Future<ParserResult> currency(String input) async {
    final ParserResult result = ParserResult();
    if (input.isEmpty) {
      return result
        ..results.addAll(
            <String>["Format: NUMBER CODE to CODE", "Example: 100 USD to EUR", "github.com/fawazahmed0/currency-api/"]);
    }
    input = input.replaceAll("\$", " USD ").replaceAll(RegExp(r' +'), ' ').toLowerCase();
    double amount = 0;
    String from = "";
    String to = "";
    final RegExpMatch? reg = RegExp(r'((?:[\d\.\,]+\d)|\d+) (\w{3,4}) to (\w{3,4})').firstMatch(input);
    if (reg != null) {
      String amountReg = reg[1]!;
      amountReg = amountReg.replaceFirstMapped(RegExp(r',(\d{2})$'), (Match match) => "p${match[1]}");
      amountReg = amountReg.replaceFirstMapped(RegExp(r'\.(\d{2})$'), (Match match) => "p${match[1]}");
      amountReg = amountReg.replaceAll(',', '').replaceAll('.', '').replaceAll('p', '.');
      amount = double.parse(amountReg);
      from = reg[2]!;
      to = reg[3]!;
    } else {
      final RegExpMatch? reg = RegExp(r'(\w{3,4}) ([\d\.\,]+) to (\w{3,4})').firstMatch(input);
      if (reg != null) {
        amount = double.tryParse(reg[2]!) ?? 0;
        from = reg[1]!;
        to = reg[3]!;
      } else {
        return result
          ..results.addAll(<String>[
            "Format: NUMBER CODE to CODE",
            "Example: 100 USD to EUR",
            "github.com/fawazahmed0/currency-api/"
          ]);
      }
    }
    final String url = "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/$from/$to.min.json";
    print(url);
    final http.Response response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final Map<String, dynamic> json = jsonDecode(response.body);
      if (json.containsKey(to)) {
        final double rate = double.parse(json[to].toString());
        result.results.add("${format.format(rate * amount)} ${to.toUpperCase()}");
        result.results.add("1 $from = $rate $to".toUpperCase());
      } else {
        result.error = "Could not find currency in result..";
      }
    } else {
      return result..error = "Could not find the currencies";
    }
    return result;
  }

  final TimeZones timeZone = TimeZones();
  Future<ParserResult> timezones(String input) async {
    final ParserResult result = ParserResult();
    DateTime dateTime = DateTime.now().toUtc();

    int jan = DateTime(dateTime.year, 0, 1).timeZoneOffset.inMinutes;
    int jul = DateTime(dateTime.year, 6, 1).timeZoneOffset.inMinutes;
    bool dst = max(jan, jul) != dateTime.timeZoneOffset.inMinutes;
    String timezone = "";
    int hour = 0;
    if (RegExp(r'^[0-9:]+ ').hasMatch(input)) {
      final List<String> oInput = input.splitFirst(' ');
      final String time = oInput[0];
      if (time.contains(':')) {
        final List<String> tSplit = time.split(':');
        hour = int.tryParse(tSplit[0]) ?? 0;
      } else {
        hour = int.tryParse(time) ?? 0;
      }
      timezone = oInput[1];
    } else {
      timezone = input;
    }
    final List<List<String>> timeZones = timeZone.getTime(timezone);
    if (timeZones.isNotEmpty) {
      for (List<String> zone in timeZones) {
        final List<String> offset = zone.removeAt(0).split(':');
        final String type = offset[0][0];
        final int hours = int.parse(offset[0].substring(1));
        final int minutes = int.parse(offset[1]);
        final int offsetTime = hours * 60 + minutes;
        if (hour != 0) {
          if (hour > dateTime.hour) {
            dateTime = dateTime.add(Duration(hours: dateTime.hour - hour));
          } else {
            dateTime = dateTime.subtract(Duration(hours: dateTime.hour - hour));
          }
        }
        if (type == "+") {
          dateTime = dateTime.add(Duration(minutes: offsetTime));
        } else {
          dateTime = dateTime.subtract(Duration(minutes: offsetTime));
        }
        late DateTime dstTime;
        dstTime = dateTime.add(const Duration(hours: 1));
        if (dst) {
          result.results.add(
              "${DateFormat('hh:mm dd MMM').format(dstTime)} (without DST: ${DateFormat('hh:mm').format(dateTime)})\n${zone.join(', ')}");
        } else {
          result.results.add(
              "${DateFormat('hh:mm dd MMM').format(dateTime)} (with DST: ${DateFormat('hh:mm').format(dstTime)})\n${zone.join(', ')}");
        }
      }
    }
    return result;
  }
}
