// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_widget.dart';
import '../widgets/mouse_scroll_widget.dart';

class TrktivityPage extends StatefulWidget {
  const TrktivityPage({Key? key}) : super(key: key);
  @override
  TrktivityPageState createState() => TrktivityPageState();
}

class MTrack {
  int mouse;
  int keyboard;
  int time;
  String get timeFormat {
    final int minute = (time ~/ 60);
    final int second = (time % 60);
    return "${minute.toString().numberFormat()}:${second.toString().numberFormat()}";
  }

  MTrack({required this.mouse, required this.keyboard, this.time = 0});

  @override
  String toString() => 'MTrack(mouse: $mouse, keyboard: $keyboard, time: ${time.formatTime()})\n';
}

class TrktivityPageState extends State<TrktivityPage> {
  final Trktivity trk = Trktivity();
  final List<String> allDates = <String>[];
  String selectedDay = "";
  String startDate = "";
  String endDate = "";
  bool showFilters = false;
  String pickText = "Pick Dates";
  @override
  void initState() {
    super.initState();
    allDates.addAll(Directory(trk.folder).listSync().map((FileSystemEntity e) => e.path.substring(e.path.lastIndexOf('\\') + 1).replaceAll(".json", "")));

    if (allDates.isNotEmpty) {
      allDates.sort((String a, String b) => DateTime.parse(a).isBefore(DateTime.parse(b)) ? 1 : -1);
      selectedDay = allDates.first;
      showReport();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  final Map<int, MTrack> uTrack = <int, MTrack>{};
  final Map<String, MTrack> wTrack = <String, MTrack>{};
  final Map<String, MTrack> tTrack = <String, MTrack>{};
  void showReport() {
    uTrack.clear();
    wTrack.clear();
    tTrack.clear();
    if (startDate.isEmpty && selectedDay.isNotEmpty) {
      parseTrkFile(selectedDay);

      // print(uTrack);
      // print(wTrack);
      print(tTrack);
    } else if (startDate.isNotEmpty) {
      final int first = allDates.indexWhere((String element) => element == endDate);
      final int last = allDates.indexWhere((String element) => element == startDate);

      if (first > -1 && last > -1) {
        for (int x = first; x <= last; x++) {}
      }
    }
  }

  final MTrack _wTrack = MTrack(mouse: 0, keyboard: 0);
  final MTrack _tTrack = MTrack(mouse: 0, keyboard: 0);
  String _lastExe = "";
  int _startWTime = 0;
  String _lastTitle = "";
  int _startTTime = 0;
  void parseTrkFile(String file) {
    final File f = File("${trk.folder}\\$file.json");
    if (!f.existsSync()) return;
    final List<String> lines = f.readAsLinesSync();
    for (String line in lines) {
      final Map<String, dynamic> info = jsonDecode(line);
      final DateTime time = DateTime.fromMillisecondsSinceEpoch(info["ts"]);
      final int minute = (time.hour * 60) + time.minute;
      if (uTrack.containsKey(minute)) {
        if (info["t"] == "m") uTrack[minute]!.mouse += int.parse(info["d"]);
        if (info["t"] == "k") uTrack[minute]!.keyboard += int.parse(info["d"]);
      } else {
        uTrack[minute] = MTrack(
          mouse: info["t"] == "m" ? int.parse(info["d"]) : 0,
          keyboard: info["t"] == "k" ? int.parse(info["d"]) : 0,
        );
      }
      if (info["t"] == "m") {
        _wTrack.mouse += int.parse(info["d"]);
        _tTrack.mouse += int.parse(info["d"]);
      }
      if (info["t"] == "k") {
        _wTrack.keyboard += int.parse(info["d"]);
        _tTrack.keyboard += int.parse(info["d"]);
      }
      if (info["t"] == "w") {
        final Map<String, dynamic> wInfo = jsonDecode(info["d"]);
        if (_lastExe != wInfo["e"]) {
          if (_lastExe.isEmpty) {
            _lastExe = wInfo["e"];
            _startWTime = info["ts"];
          }
          if (!wTrack.containsKey(_lastExe)) {
            wTrack[_lastExe] = MTrack(mouse: 0, keyboard: 0);
          }
          wTrack[_lastExe]!.keyboard += _wTrack.keyboard;
          wTrack[_lastExe]!.mouse += _wTrack.mouse;
          wTrack[_lastExe]!.time += time.difference(DateTime.fromMillisecondsSinceEpoch(_startWTime)).inSeconds;
          _wTrack
            ..keyboard = 0
            ..mouse = 0
            ..time = 0;
          _lastExe = wInfo["e"];
          _startWTime = info["ts"];
        }
        if (wInfo["tl"].isNotEmpty) {
          if (_lastTitle != wInfo["tl"]) {
            if (_lastTitle.isEmpty) {
              _lastTitle = wInfo["tl"];
              _startTTime = info["ts"];
            }
            if (!tTrack.containsKey(_lastTitle)) {
              tTrack[_lastTitle] = MTrack(mouse: 0, keyboard: 0);
            }
            tTrack[_lastTitle]!.keyboard += _tTrack.keyboard;
            tTrack[_lastTitle]!.mouse += _tTrack.mouse;
            tTrack[_lastTitle]!.time += time.difference(DateTime.fromMillisecondsSinceEpoch(_startTTime)).inSeconds;
            _tTrack
              ..keyboard = 0
              ..mouse = 0
              ..time = 0;
            _lastTitle = wInfo["tl"];
            _startTTime = info["ts"];
          }
        } else {
          _lastTitle = "";
          _startTTime = info["ts"];
        }
      }
    }
    if (_lastExe.isNotEmpty) {
      if (!wTrack.containsKey(_lastExe)) {
        wTrack[_lastExe] = MTrack(mouse: 0, keyboard: 0);
      }
      wTrack[_lastExe]!.keyboard += _wTrack.keyboard;
      wTrack[_lastExe]!.mouse += _wTrack.mouse;
      _wTrack
        ..keyboard = 0
        ..mouse = 0
        ..time = 0;
    }
    _lastExe = "";
    _startWTime = 0;

    if (_lastTitle.isNotEmpty) {
      if (!tTrack.containsKey(_lastTitle)) {
        tTrack[_lastTitle] = MTrack(mouse: 0, keyboard: 0);
      }
      tTrack[_lastTitle]!.keyboard += _tTrack.keyboard;
      tTrack[_lastTitle]!.mouse += _tTrack.mouse;
      _tTrack
        ..keyboard = 0
        ..mouse = 0
        ..time = 0;
    }
    _lastTitle = "";
    _startTTime = 0;
    print("empty: ${_lastTitle.isEmpty}");
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          onChanged: (bool? e) => setState(() {
            globalSettings.trktivityEnabled = !globalSettings.trktivityEnabled;
            Boxes.updateSettings("trktivityEnabled", globalSettings.trktivityEnabled);
            enableTrcktivity(globalSettings.trktivityEnabled);
          }),
          controlAffinity: ListTileControlAffinity.leading,
          value: globalSettings.trktivityEnabled,
          title: Text(
            "Trktivity",
            style: Theme.of(context).textTheme.headline5,
          ),
          secondary: InfoWidget("Press to open folder with saved data", onTap: () {
            WinUtils.open("${WinUtils.getTabameSettingsFolder()}\\trktivity");
          }),
        ),
        !globalSettings.trktivityEnabled
            ? const Markdown(
                shrinkWrap: true,
                data: '''
With Trktivity you can track your activity per minute/hour/day/week. 

It records keystrokes, mouse movement and active Window.
''',
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  CheckBoxWidget(
                    onChanged: (bool e) {},
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                    value: globalSettings.trktivitySaveAllTitles,
                    text: "Save all All Window titles",
                  ),
                  ListTile(
                    onTap: () {
                      setState(() => showFilters = !showFilters);
                    },
                    title: const Text("Filters"),
                    leading: Icon(showFilters ? Icons.expand_less : Icons.expand_more),
                  ),
                  if (showFilters)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              ListTile(
                                leading: const Icon(Icons.add),
                                minLeadingWidth: 20,
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[const Text("Add Title Filter"), const SizedBox(width: 10), InfoWidget("To remove leave exe empty", onTap: () {})],
                                ),
                                onTap: () {
                                  trk.filters.add(TrktivityFilter(
                                    exe: "exe",
                                    titleSearch: r"",
                                    titleReplace: r"",
                                  ));
                                  Boxes.updateSettings("trktivityFilter", jsonEncode(trk.filters));
                                  setState(() {});
                                },
                              ),
                              SizedBox(
                                height: 200,
                                child: MouseScrollWidget(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: List<Widget>.generate(
                                        trk.filters.length,
                                        (int index) => Container(
                                          width: 200,
                                          child: TrktivityFilterSet(
                                            key: UniqueKey(),
                                            filter: trk.filters[index],
                                            onSaved: (TrktivityFilter filter) {
                                              if (filter.exe.isEmpty) {
                                                trk.filters.removeAt(index);
                                                Boxes.updateSettings("trktivityFilter", jsonEncode(trk.filters));
                                                setState(() {});
                                                return;
                                              }
                                              trk.filters[index] = filter;
                                              Boxes.updateSettings("trktivityFilter", jsonEncode(trk.filters));
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ),
                                    )),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
        if (allDates.isEmpty)
          const Text("There is no file to annalize.")
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (allDates.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            const Flexible(child: Text("Pick a date: ")),
                            Flexible(
                              // width: 130,
                              child: DropdownButton<String>(
                                alignment: Alignment.center,
                                isDense: true,
                                value: selectedDay,
                                items: allDates
                                    .map<DropdownMenuItem<String>>(
                                        (String e) => DropdownMenuItem<String>(value: e, child: Center(child: Text(e)), alignment: Alignment.center))
                                    .toList(),
                                onChanged: (String? e) {
                                  selectedDay = e ?? allDates.first;
                                  pickText = "Pick Dates";
                                  startDate = "";
                                  endDate = "";
                                  showReport();
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: <Widget>[
                            const Flexible(child: Text("Pick a Date Range: ")),
                            OutlinedButton(
                              onPressed: () {
                                showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime.parse(allDates.last),
                                  lastDate: DateTime.parse(allDates.first),
                                ).then((DateTimeRange? value) {
                                  if (value == null) return;
                                  startDate = DateFormat('yyyy-MM-dd').format(value.start);
                                  endDate = DateFormat('yyyy-MM-dd').format(value.end);
                                  pickText = "$startDate\n$endDate";
                                  showReport();
                                  setState(() {});
                                });
                              },
                              child: Text(pickText),
                            )
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          )
      ],
    );
  }
}

class TrktivityFilterSet extends StatefulWidget {
  final TrktivityFilter filter;
  final Function(TrktivityFilter filter) onSaved;
  const TrktivityFilterSet({
    Key? key,
    required this.filter,
    required this.onSaved,
  }) : super(key: key);
  @override
  TrktivityFilterSetState createState() => TrktivityFilterSetState();
}

class TrktivityFilterSetState extends State<TrktivityFilterSet> {
  final TextEditingController exeController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final TextEditingController replaceController = TextEditingController();
  late TrktivityFilter filter;
  @override
  void initState() {
    super.initState();
    filter = widget.filter.copyWith();
    exeController.text = filter.exe;
    searchController.text = filter.titleSearch;
    replaceController.text = filter.titleReplace;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
      child: Focus(
        onFocusChange: (bool f) {
          if (!f) {
            filter.exe = exeController.text;
            filter.titleSearch = searchController.text;
            filter.titleReplace = replaceController.text;
            widget.onSaved(filter);
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              decoration: const InputDecoration(labelText: "Match exe (regex):"),
              controller: exeController,
            ),
            TextField(
              decoration: const InputDecoration(labelText: "Search for (regex):"),
              controller: searchController,
            ),
            TextField(
              decoration: const InputDecoration(labelText: "Replace with:"),
              controller: replaceController,
            ),
          ],
        ),
      ),
    );
  }
}
