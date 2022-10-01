// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:math_parser/math_parser.dart';
import 'package:units_converter/units_converter.dart';
import 'package:window_manager/window_manager.dart';

import 'package:http/http.dart' as http;
import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/keys.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';

class QuickRun extends StatefulWidget {
  const QuickRun({Key? key}) : super(key: key);

  @override
  QuickRunState createState() => QuickRunState();
}

class NextElement extends Intent {
  const NextElement();
}

class PreviousElement extends Intent {
  const PreviousElement();
}

class RunShortcuts {
  String name;
  List<String> shortcuts;
  String regex;
  RunShortcuts({
    required this.name,
    required this.shortcuts,
    required this.regex,
  });

  @override
  String toString() => 'Shortcuts(name: $name, shortcuts: $shortcuts, regex: $regex)';
}

class QuickRunState extends State<QuickRun> {
  final Parsers parser = Parsers();
  ParserResult result = ParserResult();
  FocusNode textFocusNode = FocusNode();
  FocusNode keyboardFocusNode = FocusNode();
  TextEditingController textController = TextEditingController();

  List<RunShortcuts> shortcuts = <RunShortcuts>[];
  String currentRun = "";

  int activeElement = -1;

  int copied = -1;

  @override
  void initState() {
    super.initState();
    final Map<String, String> map = globalSettings.run.toMap();
    for (MapEntry<String, String> x in map.entries) {
      final List<String> split = x.value.removeCharAtTheEnd(';').split(';');
      List<String> scuts = <String>[];
      String regex = "";
      // continue;
      if (split.length > 1 && !split.last.endsWith(' ')) {
        regex = split.last;
        split.removeLast();
      }
      scuts.addAll(split);

      shortcuts.add(RunShortcuts(name: x.key, shortcuts: scuts, regex: regex));
      result = ParserResult();
      for (RunShortcuts x in shortcuts) {
        result.results.add("${x.name}: ${x.shortcuts.join(',')} ${x.regex.isNotEmpty ? "[${x.regex}]" : ""}");
      }
    }
    textController.text = globalSettings.quickRunText;
    globalSettings.quickRunState = 2;
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => FocusScope.of(context).requestFocus(textFocusNode));
  }

  @override
  void dispose() {
    textController.dispose();
    textFocusNode.dispose();
    keyboardFocusNode.dispose();
    super.dispose();
  }

  int _currentFocus = 0;
  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Material(
        type: MaterialType.transparency,
        child: Shortcuts(
          shortcuts: <ShortcutActivator, Intent>{
            LogicalKeySet(LogicalKeyboardKey.arrowDown): const NextElement(),
            LogicalKeySet(LogicalKeyboardKey.arrowUp): const PreviousElement(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              NextElement: CallbackAction<NextElement>(
                onInvoke: (NextElement intent) => setState(() {
                  _currentFocus += 1;
                  if (_currentFocus > result.results.length) {
                    FocusScope.of(context).requestFocus(textFocusNode);
                    _currentFocus = -1;
                  } else {
                    FocusScope.of(context).nextFocus();
                  }
                }),
              ),
              PreviousElement: CallbackAction<PreviousElement>(
                onInvoke: (PreviousElement intent) => setState(() {
                  _currentFocus -= 1;
                  if (_currentFocus == -1) {
                    FocusScope.of(context).requestFocus(textFocusNode);
                    _currentFocus = 0;
                  } else {
                    FocusScope.of(context).previousFocus();
                  }
                }),
              ),
            },
            child: Focus(
              autofocus: true,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 25,
                        height: 35,
                        child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (DragStartDetails details) {
                              windowManager.startDragging();
                            },
                            child: const Icon(Icons.drag_indicator_sharp)),
                      ),
                      Expanded(
                        child: TextField(
                          autofocus: true,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10.0),
                          ),
                          focusNode: textFocusNode,
                          controller: textController,
                          onSubmitted: (String input) => onSubmitted(input),
                          onChanged: (String input) async {
                            input = input.trimLeft();
                            if (input.isEmpty) {
                              result = ParserResult();
                              for (RunShortcuts x in shortcuts) {
                                result.results.add("${x.name}: ${x.shortcuts.join(',')} ${x.regex.isNotEmpty ? "[${x.regex}]" : ""}");
                              }
                              setState(() {});
                              return;
                            }
                            String command = "";
                            List<String> x = getCommandFromString(input);
                            if (x.isEmpty) {
                              result = ParserResult();
                              for (RunShortcuts x in shortcuts) {
                                result.results.add("${x.name}: ${x.shortcuts.join(',')} ${x.regex.isNotEmpty ? "[${x.regex}]" : ""}");
                              }
                              setState(() {});
                              return;
                            }
                            command = x[0];
                            if (x.length == 2) input = input.replaceFirst(x[1], "");
                            if (currentRun != command) {
                              currentRun = command;
                            }
                            final Map<String, Function(String)> functions = <String, Function(String)>{
                              "calculator": parser.calculator,
                              "unit": parser.unit,
                              "color": parser.color,
                              "timer": parser.timer,
                              "currency": parser.currency,
                              "timezones": parser.timezones,
                              "memo": parser.memos,
                              "bookmarks": parser.bookmarks,
                              "shortcut": parser.shortcuts,
                              "regex": parser.regex,
                              "lorem": parser.loremIpsum,
                              "encoders": parser.encoders,
                              "setvar": parser.setVar,
                              "keys": parser.sendKeys,
                            };
                            if (functions.containsKey(currentRun)) {
                              result = await functions[currentRun]!(input.toLowerCase());
                            } else {
                              result = ParserResult();
                            }
                            setState(() {});
                          },
                        ),
                      )
                    ],
                  ),
                  if (result.results.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      // constraints: BoxConstraints.loose(const Size(280, 200)),
                      child: SingleChildScrollView(
                        // scrollDirection: Axis.vertical,
                        controller: ScrollController(),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            ...List<Widget>.generate(
                              result.results.length,
                              (int index) {
                                String item = result.results[index];
                                if (item.startsWith("custom:")) {
                                  item = item.replaceFirst("custom:", "");
                                  if (item.startsWith("color:")) {
                                    item = item.replaceFirst("color:", "");
                                    final Color color = Color(int.parse(item));
                                    return Row(
                                      children: <Widget>[
                                        Expanded(
                                            child: DecoratedBox(
                                          decoration: BoxDecoration(color: color),
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(horizontal: 10.0, vertical: 3),
                                            child: Text("  "),
                                          ),
                                        )),
                                      ],
                                    );
                                  }
                                  return Container();
                                }
                                return InkWell(
                                  onTap: () {
                                    if (result.type == ResultType.copy) {
                                      if (currentRun == "unit") {
                                        final RegExpMatch? match = RegExp(r'^([\d,\.]+)').firstMatch(item);
                                        if (match != null) {
                                          Clipboard.setData(ClipboardData(text: match[1]!.replaceAll(',', '.')));
                                        } else {
                                          Clipboard.setData(ClipboardData(text: item));
                                        }
                                      } else {
                                        Clipboard.setData(ClipboardData(text: result.actions.containsKey(item) ? result.actions[item] : item));
                                      }
                                      setState(() => copied = index);
                                      Future<void>.delayed(const Duration(seconds: 1), () {
                                        if (mounted) setState(() => copied = -1);
                                      });
                                    } else if (result.type == ResultType.open) {
                                      WinUtils.open(result.actions.containsKey(item) ? result.actions[item]! : item);
                                    } else if (result.type == ResultType.send) {
                                      WinKeys.send(result.actions.containsKey(item) ? result.actions[item]! : item);
                                    }
                                    WidgetsBinding.instance.addPostFrameCallback((_) => regainFocus());
                                  },
                                  onFocusChange: (bool f) {
                                    if (f) {
                                      activeElement = index;
                                    } else {
                                      activeElement = -1;
                                    }
                                  },
                                  onHover: (bool f) {
                                    if (f) {
                                      activeElement = index;
                                    } else {
                                      activeElement = -1;
                                    }
                                    setState(() {});
                                  },
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1))),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3),
                                            child: Stack(
                                              children: <Widget>[
                                                Text(item),
                                                Positioned(
                                                  right: 0,
                                                  top: 2.5,
                                                  child: SizedBox(
                                                    width: 15,
                                                    child: activeElement == index
                                                        ? Icon(
                                                            result.type == ResultType.copy
                                                                ? Icons.copy
                                                                : result.type == ResultType.open
                                                                    ? Icons.open_in_browser
                                                                    : Icons.extension,
                                                            size: 15,
                                                            color: copied == index ? Colors.cyan : Theme.of(context).iconTheme.color)
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (result.error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), child: Text(result.error)),
                  // const SizedBox(height: 5),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<String> getCommandFromString(String input) {
    for (RunShortcuts scuts in shortcuts) {
      for (String scut in scuts.shortcuts) {
        if (input.startsWith(scut)) {
          return <String>[scuts.name, scut];
        }
      }
    }
    for (RunShortcuts scuts in shortcuts) {
      if (scuts.regex.isEmpty) continue;
      if (RegExp(scuts.regex, caseSensitive: false).hasMatch(input)) {
        return <String>[scuts.name];
      }
    }
    return <String>[];
  }

  void regainFocus() {
    textController.selection = TextSelection.fromPosition(TextPosition(offset: textController.text.length));
    setState(() {});
    FocusScope.of(context).requestFocus(textFocusNode);
  }

  void onSubmitted(String input) {
    if (currentRun == "regex") {
      textController.text = globalSettings.run.regex.split(';')[0];
      regainFocus();
    } else if (currentRun == "shortcut") {
      if (input.contains(" add ") && parser.shortcutInput.isNotEmpty) {
        parser.runShortcuts.add(<String>[
          parser.shortcutInput.substring(0, parser.shortcutInput.indexOf(" ")),
          parser.shortcutInput.substring(parser.shortcutInput.indexOf(" ") + 1),
        ]);
        Boxes().runShortcuts = <List<String>>[...parser.runShortcuts];
        result.error = "Added ${parser.shortcutInput}";
        parser.shortcutInput = "";
      } else if (input.contains(" remove ") && parser.shortcutInput.isNotEmpty) {
        for (List<String> x in parser.runShortcuts) {
          if (x[0] == parser.shortcutInput) {
            parser.runShortcuts.remove(x);
            break;
          }
        }
        Boxes().runShortcuts = <List<String>>[...parser.runShortcuts];
        result.error = "Removed ${parser.shortcutInput}";
        parser.shortcutInput = "";
      } else {
        if (result.results.isNotEmpty) {
          WinUtils.open(RegExp(r'^.*?:(.*?)$').firstMatch(result.results[0])![1]!);
          QuickMenuFunctions.toggleQuickMenu(visible: false);
        }
      }
      regainFocus();
    } else if (currentRun == "memo") {
      if (input.contains(" add ") && parser.memoInput.isNotEmpty) {
        parser.runMemos.add(<String>[
          parser.memoInput.substring(0, parser.memoInput.indexOf(" ")),
          parser.memoInput.substring(parser.memoInput.indexOf(" ") + 1),
        ]);
        Boxes().runMemos = <List<String>>[...parser.runMemos];
        result.error = "Added ${parser.memoInput}";
        parser.memoInput = "";
        setState(() {});
      } else if (input.contains(" remove ") && parser.memoInput.isNotEmpty) {
        for (List<String> x in parser.runMemos) {
          if (x[0] == parser.memoInput) {
            parser.runMemos.remove(x);
            break;
          }
        }
        Boxes().runMemos = <List<String>>[...parser.runMemos];
        result.error = "Removed ${parser.memoInput}";
        parser.memoInput = "";
      }
      regainFocus();
    } else if (currentRun == "timer") {
      if (input.contains(" remove ")) {
        bool removed = false;
        int index = 0;
        for (QuickTimer quick in Boxes.quickTimers) {
          if (quick.name == parser.timerInfo[0]) {
            removed = true;
            quick.timer?.cancel();
            Boxes.quickTimers.removeAt(index);
            break;
          }
          index++;
        }
        if (removed) {
          result.results = <String>["Removed reminder ${parser.timerInfo[0]}"];
          parser.timerInfo = <dynamic>[];
          regainFocus();
        }
        return;
      }

      if (parser.timerInfo.isEmpty) return;
      Boxes().addQuickTimer(parser.timerInfo[0], parser.timerInfo[1], parser.timerInfo[2]);
      result.results = <String>[
        "${<String>["Audio", "Message", "Notification"][parser.timerInfo[2]]} Reminder ${parser.timerInfo[1]} minutes: ${parser.timerInfo[0]}"
      ];
      parser.timerInfo = <dynamic>[];
      regainFocus();
    } else if (currentRun == "setvar") {
      if (parser.varInfo.isEmpty) return;

      final String varName = parser.varInfo.substring(0, parser.varInfo.indexOf(" "));
      final String varValue = parser.varInfo.substring(parser.varInfo.indexOf(" ") + 1);
      Boxes.pref.setString("k_$varName", varValue).then((_) {
        result.results = <String>["Saved $varName as $varValue"];
        regainFocus();
      });
    } else if (currentRun == "keys") {
      if (parser.keysToSent.isEmpty) return;
      WinKeys.send(parser.keysToSent);
      regainFocus();
    } else if (currentRun == "bookmarks") {
      if (result.actions.isEmpty) return;
      regainFocus();
      WinUtils.open(result.actions.values.elementAt(0));
      QuickMenuFunctions.toggleQuickMenu(visible: false);
    }
  }
}

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
    final Map<String, num> mathVars = <String, num>{"x": 0, "y": 0, "z": 0, "a": 0, "b": 0, "c": 0, "d": 0, "e": 0, "f": 0};
    for (int i = 0; i < math.length; i++) {
      if (math[i].isEmpty) continue;
      num x = 0;
      try {
        x = MathNodeExpression.fromString(math[i], variableNames: <String>{"x", "y", "z", "a", "b", "c", "d", "e", "f"}).calc(MathVariableValues(mathVars));
      } catch (e) {
        result.error = e.toString();
      }
      mathVars[mathVars.keys.elementAt(i)] = x;
      result.results.add("${mathVars.keys.elementAt(i)} = ${x.formatNum()}");
    }
    return result;
  }

  T? getUnitType<T>(String from, List<Unit> units, Iterable<T> names) {
    T? matched;
    for (Unit e in units) {
      if (from == e.symbol?.toLowerCase()) {
        return (e.name as T);
      }
    }
    if (matched == null) {
      for (T type in names) {
        if (type.toString().toLowerCase().split(".").last == from) {
          return type;
        }
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
          return result..results.add("${format.format(number.convertFromTo(matched, matchedTo) ?? 0)} ${matchedTo.name} (${length.getUnit(matchedTo).symbol})");
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
      if (input.length == 8) {
        input = input.substring(input.length - 2) + input.substring(0, input.length - 2);
        color = Color(int.parse('0x$input'));
      }
      if (input.length == 3) {
        color = Color(int.parse('0xFF$input$input'));
      } else {
        while (input.length < 6) {
          input += "F";
        }
        try {
          color = Color(int.parse('0xFF$input'));
        } catch (__) {
          return result;
        }
      }
    } else if (input.startsWith("rgb") && RegExp(r'^rgba?\(([0-9 ]+),([0-9 ]+),([0-9 ]+)(?:,([0-9 ]+))?\)').hasMatch(input)) {
      final RegExpMatch col = RegExp(r'^rgba?\(([0-9 ]+),([0-9 ]+),([0-9 ]+)(?:,([0-9 ]+))?\)').firstMatch(input)!;
      color = Color.fromARGB(int.parse(col[4] ?? "255"), int.parse(col[1]!), int.parse(col[2]!), int.parse(col[3]!));
    } else if (input.startsWith("cmyk") && RegExp(r'^cmyk?\(([0-9 ]+),([0-9 ]+),([0-9 ]+),([0-9 ]+)\)').hasMatch(input)) {
      final RegExpMatch cmyk = RegExp(r'^cmyk?\(([0-9 ]+),([0-9 ]+),([0-9 ]+),([0-9 ]+)\)').firstMatch(input)!;
      final double r = (255 * (1 - int.parse(cmyk[1]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      final double g = (255 * (1 - int.parse(cmyk[2]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      final double b = (255 * (1 - int.parse(cmyk[3]!) / 100) * (1 - int.parse(cmyk[4]!) / 100));
      color = Color.fromARGB(255, (r).round(), (g).round(), (b).round());
    } else {
      return result..results.addAll(<String>["#ffffff", "rgba(255,255,255,255)", "cmyk(0,0,0)"]);
    }

    result.results.add("#${color.value.toRadixString(16)}");
    result.results.add("0x${color.value.toRadixString(16)}");
    result.results.add("rgba(${color.red}, ${color.green}, ${color.blue}, ${color.alpha})");
    result.results.add("argb(${color.alpha}, ${color.red}, ${color.green}, ${color.blue})");
    final HSLColor hslColor = HSLColor.fromColor(color);
    result.results.add("hsl(${hslColor.hue.toStringAsFixed(1)}, ${(hslColor.saturation * 100).toStringAsFixed(1)}%, ${(hslColor.lightness * 100).toStringAsFixed(1)}%)");
    result.results.add(
        "hsla(${hslColor.hue.toStringAsFixed(1)}, ${(hslColor.saturation * 100).toStringAsFixed(1)}%, ${(hslColor.lightness * 100).toStringAsFixed(1)}%, ${hslColor.alpha})");
    final HSVColor hsvColor = HSVColor.fromColor(color);
    result.results.add("hsv(${hsvColor.hue.toStringAsFixed(1)}, ${(hsvColor.saturation * 100).toStringAsFixed(1)}%, ${(hsvColor.value * 100).toStringAsFixed(1)}%)");

    if (color.red == 0 && color.green == 0 && color.blue == 0) {
    } else {
      final double r = 1 - (color.red / 255);
      final double g = 1 - (color.green / 255);
      final double b = 1 - (color.blue / 255);
      final num k = min(r, min(g, b));
      final num c = ((r - k) / (1 - k) * 100).round();
      final num m = ((g - k) / (1 - k) * 100).round();
      final num y = ((b - k) / (1 - k) * 100).round();
      result.results.add("cmyk($c, $m, $y, ${(k * 100).round()})");
    }
    result.results.add("custom:color:0x${color.value.toRadixString(16)}");
    return result;
  }

  Future<ParserResult> currency(String input) async {
    final ParserResult result = ParserResult();
    if (input.isEmpty) {
      return result..results.addAll(<String>["Format: NUMBER CODE to CODE", "Example: 100 USD to EUR", "github.com/fawazahmed0/currency-api/"]);
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
        return result..results.addAll(<String>["Format: NUMBER CODE to CODE", "Example: 100 USD to EUR", "github.com/fawazahmed0/currency-api/"]);
      }
    }
    final String url = "https://raw.githubusercontent.com/fawazahmed0/currency-api/1/latest/currencies/$from/$to.min.json";
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
          result.results.add("${DateFormat('hh:mm dd MMM').format(dstTime)} (without DST: ${DateFormat('hh:mm').format(dateTime)})\n${zone.join(', ')}");
        } else {
          result.results.add("${DateFormat('hh:mm dd MMM').format(dateTime)} (with DST: ${DateFormat('hh:mm').format(dstTime)})\n${zone.join(', ')}");
        }
      }
    }
    return result;
  }

  String regexText = "";
  Future<ParserResult> regex(String input) async {
    final ParserResult result = ParserResult()..error = regexText;
    result.type = ResultType.copy;
    if (regexText.isEmpty) regexText = Boxes.pref.getString("regexTest") ?? "test";
    if (input.startsWith("text ")) {
      regexText = input.replaceFirst("text ", "");

      if (regexText.isEmpty) return result;
      Boxes.updateSettings("regexTest", regexText);
    } else {
      if (input.isEmpty) return result;
      try {
        final Iterable<RegExpMatch> matches = RegExp(input, caseSensitive: false).allMatches(regexText);
        for (RegExpMatch match in matches) {
          result.results.add(match[0]!);
          for (int m = 1; m < match.groupCount + 1; m++) {
            result.results.add(match[m]!);
          }
        }
      } catch (e) {
        result.results.add(e.toString());
      }
    }
    // result.results.add(regexText);
    return result;
  }

  Future<ParserResult> loremIpsum(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.none;
    if (input.isEmpty) return result..error = "Format [nr or pharagraphs]\n[short, medium, long, verylong]\nOpt:[headers, plaintext, decorate, prude]";
    final RegExpMatch? reg = RegExp(r'^(\d+) (short|medium|long|verylong) ?((headers|plaintext|decorate|prude)|$)').firstMatch(input);
    if (reg != null) {
      final int nr = int.tryParse(reg[1]!) ?? 0;
      final String type = reg[2]!;
      String opt = "";
      if (reg.groupCount == 4) {
        if (reg[3]!.length > 1) {
          opt = reg[3]!;
        }
      }

      final String url = "https://loripsum.net/api/$nr/$type/$opt";
      final http.Response response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        Clipboard.setData(ClipboardData(text: response.body));
        result.results.addAll(<String>["Generated $nr $type $opt", "Copied to Clipboard!"]);
      } else {
        result.error = "Status code ${response.statusCode}";
      }
    } else {
      result.error = "Format [nr or pharagraphs]\n[short, medium, long, verylong]\nOpt:[headers,plaintext,decorate]";
    }
    return result;
  }

  //!reee
  Future<ParserResult> encoders(String input) async {
    final ParserResult result = ParserResult();
    // url, base, rot13, hex, bin , ascii, html;
    if (input.isEmpty) return result..error = "! to encode; @ to decode\nConversions:  [url, base, rot13, ascii]";
    RegExpMatch? reg = RegExp(r'\[([a-z1-9!@, ]+)\] (.*?)$').firstMatch(input);
    if (reg == null) {
      reg = RegExp(r'([a-z1-9!@]+) (.*?)$').firstMatch(input);
      if (reg == null) return result..error = "Unknown Format";
    }
    final List<String> conversions = reg[1]!.replaceAll(' ', '').split(',');
    String toConvert = reg[2]!;
    for (String conversion in conversions) {
      if (conversion.isEmpty) return result;
      bool encode = true;
      if (<String>['!', '@'].contains(conversion[0])) {
        encode = conversion[0] == '!' ? true : false;
        conversion = conversion.substring(1);
      }
      if (!<String>["url", "base", "rot13", "ascii"].contains(conversion)) return result..error = "Unknown $conversion";
      if (conversion == "url") {
        if (encode) {
          toConvert = Uri.encodeQueryComponent(toConvert);
        } else {
          toConvert = Uri.decodeQueryComponent(toConvert);
        }
      } else if (conversion == "base") {
        Codec<String, String> stringToBase64 = utf8.fuse(base64Url);
        if (encode) {
          toConvert = stringToBase64.encode(toConvert);
        } else {
          // final String str = base64.normalize(toConvert);
          // toConvert = stringToBase64.decode(str);
          result.error = "Base64 decode doens't work...";
        }
      } else if (conversion == "rot13") {
        const String a = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
        const String b = "nopqrstuvwxyzabcdefghijklmNOPQRSTUVWXYZABCDEFGHIJKLM";
        if (encode) {
          toConvert = toConvert.replaceAllMapped(RegExp('[a-zA-Z]'), (Match match) => b[a.indexOf(match[0]!)]);
        } else {
          toConvert = toConvert.replaceAllMapped(RegExp('[a-zA-Z]'), (Match match) => a[b.indexOf(match[0]!)]);
        }
      } else if (conversion == "ascii") {
        const AsciiCodec ascii = AsciiCodec(allowInvalid: true);
        if (encode) {
          toConvert = ascii.encode(toConvert).join(' ');
        } else {
          List<int> split = <int>[];
          final List<String> split2 = toConvert.split(" ");
          if (split2.isEmpty) continue;
          for (String i in split2) {
            if (i.isEmpty) continue;
            split.add(int.parse(i));
          }
          toConvert = ascii.decode(split, allowInvalid: true).toString();
        }
      }
    }
    result.results.add(toConvert);
    // result.error = "";
    return result;
  }

  final List<List<String>> runShortcuts = Boxes().runShortcuts;
  String shortcutInput = "";
  Future<ParserResult> shortcuts(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.open;
    if (input.isEmpty) {
      for (List<String> x in runShortcuts) {
        result.results.add("${x[0]}: ${x[1].truncate(20, suffix: '...')}");
      }
      return result;
    }
    if (input.startsWith("add ")) {
      input = input.replaceFirst("add ", "");
      final List<String> split = input.split(" ");
      if (split.length == 1) return result..error = "Format: name link/file";
      if (split[0].isEmpty || split[1].isEmpty) return result..error = "Format: name link/file";

      bool found = false;
      for (List<String> x in runShortcuts) {
        if (x[0] == split[0]) found = true;
      }
      if (!found) {
        shortcutInput = input;
      } else {
        shortcutInput = "";
        return result..error = "Already saved!";
      }
      result.error = "Press Enter to save";
    }
    if (input.startsWith("remove ")) {
      input = input.replaceFirst("remove ", "");
      if (input.isEmpty) return result..error = "Format: remove name";
      bool found = false;
      for (List<String> x in runShortcuts) {
        if (x[0] == input) found = true;
      }
      if (found) {
        shortcutInput = input;
      } else {
        return result..error = "Not found";
      }
      result.error = "Press Enter to delete";
    } else {
      final List<String> text = input.splitFirst(" ");
      for (List<String> x in runShortcuts) {
        if (x[0].contains(text[0])) {
          String url = x[1];
          if (text.length == 2) {
            url = url.replaceAll("{params}", Uri.encodeQueryComponent(text[1]));
          }
          result.results.add("${x[0]}:$url");
          result.actions["${x[0]}:$url"] = url;
        }
      }
    }
    return result;
  }

  final List<List<String>> runMemos = Boxes().runMemos;
  String memoInput = "";
  Future<ParserResult> memos(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.copy;
    if (input.isEmpty) {
      for (List<String> x in runMemos) {
        result.results.add("${x[0]}: ${x[1].truncate(20, suffix: '...')}");
      }
      return result;
    }
    if (input.startsWith("add ")) {
      input = input.replaceFirst("add ", "");
      final List<String> split = input.split(" ");
      if (split.length == 1) return result..error = "Format: name memo";
      if (split[0].isEmpty || split[1].isEmpty) return result..error = "Format: name memo";

      bool found = false;
      for (List<String> x in runMemos) {
        if (x[0] == split[0]) found = true;
      }
      if (!found) {
        memoInput = input;
      } else {
        memoInput = "";
        return result..error = "Already saved!";
      }
      result.error = "Press Enter to save";
    }
    if (input.startsWith("remove ")) {
      input = input.replaceFirst("remove ", "");
      if (input.isEmpty) return result..error = "Format: remove name";
      bool found = false;
      for (List<String> x in runMemos) {
        if (x[0] == input) found = true;
      }
      if (found) {
        memoInput = input;
      } else {
        return result..error = "Not found";
      }
      result.error = "Press Enter to delete";
    } else {
      for (List<String> x in runMemos) {
        if (x[0].contains(input)) {
          result.results.add("${x[0]}:${x[1]}");
          result.actions["${x[0]}:${x[1]}"] = x[1];
        }
      }
    }
    return result;
  }

  final List<BookmarkGroup> savedBookmarks = Boxes().bookmarks;
  Future<ParserResult> bookmarks(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.open;
    for (BookmarkGroup projectGroup in savedBookmarks) {
      for (BookmarkInfo project in projectGroup.bookmarks) {
        if (project.title.toLowerCase().contains(input) || projectGroup.title.toLowerCase().contains(input)) {
          result.results.add("${project.emoji} ${project.title} - ${projectGroup.emoji} ${projectGroup.title.truncate(20, suffix: "...")}");
          result.actions["${project.emoji} ${project.title} - ${projectGroup.emoji} ${projectGroup.title.truncate(20, suffix: "...")}"] = "${project.stringToExecute}";
        }
      }
    }
    return result;
  }

  List<dynamic> timerInfo = <dynamic>[];
  Future<ParserResult> timer(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.none;
    if (input.isEmpty) {
      result.results.addAll(<String>["Format: t [minutes] message", "Format: t [minutes] [a,n,m]:message"]);
      for (QuickTimer quick in Boxes.quickTimers) {
        result.results.add(quick.name);
      }
      return result;
    }
    if (input.startsWith("remove ")) {
      input = input.replaceFirst("remove ", "");
      if (input.isEmpty) return result;
      for (QuickTimer quick in Boxes.quickTimers) {
        if (quick.name.contains(input)) {
          result.results.add(quick.name);
        }
      }
      timerInfo = <String>[input];
      if (result.results.isEmpty) result.error = "No Timer Found!";
      return result;
    }
    final RegExpMatch? timeMessage = RegExp(r'^(\d+) (.*?)$').firstMatch(input);
    if (timeMessage == null) return result..results.addAll(<String>["Format: t [minutes] message", "Format: t [minutes] [a,n,m]:message"]);
    final int minutes = int.tryParse(timeMessage[1]!) ?? 0;
    input = timeMessage[2]!;
    final RegExpMatch? regExp = RegExp(r'^(\w):').firstMatch(input);
    int type = 0;
    if (regExp != null) {
      input = input.replaceFirst(regExp[0]!, "");
      if (regExp[1]! == "m") type = 1;
      if (regExp[1]! == "n") type = 2;
    }
    timerInfo = <dynamic>[input, minutes, type];
    result.results.add("Set Reminder $input in $minutes minutes");
    return result;
  }

  String varInfo = "";
  Future<ParserResult> setVar(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.none;
    if (input.isEmpty) result.error = "Format: varname value";
    final Set<String> keys = Boxes.pref.getKeys();
    for (String key in keys) {
      if (key.startsWith("k_$input")) result.results.add("$key: ${Boxes.pref.getString("$key")}");
    }
    varInfo = input;
    return result;
  }

  List<List<String>> runKeys = Boxes().runKeys;
  String keysToSent = "";
  Future<ParserResult> sendKeys(String input) async {
    final ParserResult result = ParserResult();
    result.type = ResultType.send;
    bool setted = false;
    for (List<String> key in runKeys) {
      if (key[0].contains(input)) {
        if (!setted) keysToSent = key[1];

        setted = true;
        result.results.add("${key[0]}: ${key[1]}");
        result.actions["${key[0]}: ${key[1]}"] = key[1];
      }
    }
    return result;
  }
}
