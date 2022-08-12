// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:collection/collection.dart';
import 'package:fl_chart/fl_chart.dart';
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

String timeFormat(int time) {
  final Duration dur = Duration(seconds: time);
  return "${dur.inHours.toString().numberFormat()}:${dur.inMinutes.remainder(60).toString().numberFormat()}:${dur.inSeconds.remainder(60).toString().numberFormat()}";
}

class MTrack {
  int mouse;
  int keyboard;
  int time;
  String get timeFormat {
    final Duration dur = Duration(seconds: time);
    return "${dur.inHours.toString().numberFormat()}:${dur.inMinutes.remainder(60).toString().numberFormat()}:${dur.inSeconds.remainder(60).toString().numberFormat()}";
  }

  MTrack({required this.mouse, required this.keyboard, this.time = 0});

  @override
  String toString() => '\nMTrack(mouse: $mouse, keyboard: $keyboard, time: ${time.formatTime()})';
}

class DMTRack extends MTrack {
  int idleTime;
  DMTRack({
    required int mouse,
    required int keyboard,
    required int time,
    required this.idleTime,
  }) : super(keyboard: keyboard, mouse: mouse, time: time);
}

class TTrack {
  int from;
  int to;
  int get diff => to - from;
  TTrack({
    required this.from,
    required this.to,
  });

  @override
  String toString() => '\nTTrack(from: $from, to: $to)';
}

class TrktivityPageState extends State<TrktivityPage> {
  final Trktivity trk = Trktivity();
  final List<String> allDates = <String>[];
  String selectedDay = "";
  String startDate = "";
  String endDate = "";
  bool showFilters = false;
  String pickText = "Pick Dates";
  bool dataAnalyzed = false;

  double uTrackMaxValue = 0.0;
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
  Map<String, List<TTrack>> wTimeTrack = <String, List<TTrack>>{};
  List<MapEntry<String, MTrack>> wTrackList = <MapEntry<String, MTrack>>[];
  List<MapEntry<String, List<TTrack>>> wTimeTrackList = <MapEntry<String, List<TTrack>>>[];

  final Map<String, MTrack> tTrack = <String, MTrack>{};
  Map<String, List<TTrack>> tTimeTrack = <String, List<TTrack>>{};
  List<MapEntry<String, MTrack>> tTrackList = <MapEntry<String, MTrack>>[];
  List<MapEntry<String, List<TTrack>>> tTimeTrackList = <MapEntry<String, List<TTrack>>>[];

  Map<String, DMTRack> dailyStats = <String, DMTRack>{};

  void showReport() {
    dataAnalyzed = false;
    uTrack.clear();
    wTrack.clear();
    tTrack.clear();
    dailyStats.clear();
    if (startDate.isEmpty && selectedDay.isNotEmpty) {
      parseTrkFile(selectedDay);
    } else if (startDate.isNotEmpty) {
      final int first = allDates.indexWhere((String element) => element == endDate);
      final int last = allDates.indexWhere((String element) => element == startDate);
      if (first > -1 && last > -1) {
        for (int x = first; x <= last; x++) {
          parseTrkFile(allDates[x]);
        }
      }
    }
    uTrackMaxValue = uTrack.values.fold(0, (double previousValue, MTrack element) {
      final double bigel = (element.keyboard < element.mouse ? element.mouse : element.keyboard).toDouble();
      return previousValue < bigel ? bigel : previousValue;
    });
    wTrackList.clear();

    wTrackList.addAll(wTrack.entries.toList());
    wTrackList.sort((MapEntry<String, MTrack> a, MapEntry<String, MTrack> b) => a.value.time > b.value.time ? -1 : 1);
    wTrackList = wTrackList.take(40).toList();

    tTrackList.clear();
    tTrackList.addAll(tTrack.entries.toList());
    if (tTrack.containsKey("Idle")) tTrack.remove("Idle");
    tTrackList.sort((MapEntry<String, MTrack> a, MapEntry<String, MTrack> b) => a.value.time > b.value.time ? -1 : 1);
    tTrackList = tTrackList.take(40).toList();

    wTimeTrackList.clear();

    if (wTimeTrack.containsKey("idle.exe")) {
      wTimeTrack["Idle"] = wTimeTrack["idle.exe"]!;
      wTimeTrack.remove("idle.exe");
    }
    wTimeTrackList.addAll(wTimeTrack.entries.toList());
    wTimeTrackList.sort((MapEntry<String, List<TTrack>> a, MapEntry<String, List<TTrack>> b) =>
        (a.value.fold(0, (num previousValue, TTrack element) => previousValue + element.diff) >
                b.value.fold(0, (num previousValue, TTrack element) => previousValue + element.diff))
            ? -1
            : 1);
    wTimeTrackList = wTimeTrackList.take(5).toList();

    if (tTimeTrack.containsKey("Idle")) tTimeTrack.remove("Idle");
    tTimeTrackList.clear();
    tTimeTrackList.addAll(tTimeTrack.entries.toList());
    tTimeTrackList.sort((MapEntry<String, List<TTrack>> a, MapEntry<String, List<TTrack>> b) =>
        (a.value.fold(0, (num previousValue, TTrack element) => previousValue + element.diff) >
                b.value.fold(0, (num previousValue, TTrack element) => previousValue + element.diff))
            ? -1
            : 1);
    tTimeTrackList = tTimeTrackList.take(5).toList();
    dataAnalyzed = true;
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
    dailyStats[file] = DMTRack(idleTime: 0, keyboard: 0, mouse: 0, time: 0);
    for (String line in lines) {
      final Map<String, dynamic> info = jsonDecode(line);
      final DateTime time = DateTime.fromMillisecondsSinceEpoch(info["ts"]);
      final int minute = (time.hour * 60) + (time.minute < 30 ? 0 : 30);
      //? Add Track info to minute which is half an hour.
      if (uTrack.containsKey(minute)) {
        if (info["t"] == "m") uTrack[minute]!.mouse += int.parse(info["d"]);
        if (info["t"] == "k") uTrack[minute]!.keyboard += int.parse(info["d"]);
      } else {
        uTrack[minute] = MTrack(
          mouse: info["t"] == "m" ? int.parse(info["d"]) : 0,
          keyboard: info["t"] == "k" ? int.parse(info["d"]) : 0,
        );
      }
      //? Add Track info to dailyStats
      if (info["t"] == "m") dailyStats[file]!.mouse += int.parse(info["d"]);
      if (info["t"] == "k") dailyStats[file]!.keyboard += int.parse(info["d"]);

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
          //?
          if (_lastExe.isEmpty) {
            _lastExe = wInfo["e"];
            _startWTime = info["ts"];
          }
          //? Add dailyStats Time.
          if (_lastExe == "idle.exe") {
            dailyStats[file]!.idleTime += time.difference(DateTime.fromMillisecondsSinceEpoch(_startWTime)).inSeconds;
          } else {
            dailyStats[file]!.time += time.difference(DateTime.fromMillisecondsSinceEpoch(_startWTime)).inSeconds;
          }
          //?
          if (!wTrack.containsKey(_lastExe)) {
            wTrack[_lastExe] = MTrack(mouse: 0, keyboard: 0);
            wTimeTrack[_lastExe] = <TTrack>[];
          }
          wTrack[_lastExe]!.keyboard += _wTrack.keyboard;
          wTrack[_lastExe]!.mouse += _wTrack.mouse;
          wTrack[_lastExe]!.time += time.difference(DateTime.fromMillisecondsSinceEpoch(_startWTime)).inSeconds;

          wTimeTrack[_lastExe]!.add(TTrack(from: _startWTime, to: info['ts']));
          _wTrack
            ..keyboard = 0
            ..mouse = 0
            ..time = 0;
          _lastExe = wInfo["e"];
          _startWTime = info["ts"];
        }

        if (wInfo["tl"].isNotEmpty) {
          wInfo["tl"] = wInfo["tl"].trim();
          if (_lastTitle != wInfo["tl"]) {
            if (_lastTitle.isEmpty) {
              _lastTitle = wInfo["tl"];
              _startTTime = info["ts"];
            }
            if (!tTrack.containsKey(_lastTitle)) {
              tTrack[_lastTitle] = MTrack(mouse: 0, keyboard: 0);
              tTimeTrack[_lastTitle] = <TTrack>[];
            }
            tTrack[_lastTitle]!.keyboard += _tTrack.keyboard;
            tTrack[_lastTitle]!.mouse += _tTrack.mouse;
            tTrack[_lastTitle]!.time += time.difference(DateTime.fromMillisecondsSinceEpoch(_startTTime)).inSeconds;

            tTimeTrack[_lastTitle]!.add(TTrack(from: _startTTime, to: info['ts']));

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
    wTrackList.fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "idle.exe" ? element.value.time : 0));
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
                  ListTile(
                    onTap: () {
                      setState(() => showFilters = !showFilters);
                    },
                    title: const Text("Filters"),
                    leading: Icon(showFilters ? Icons.expand_less : Icons.expand_more),
                  ),
                  if (showFilters)
                    Column(
                      children: <Widget>[
                        CheckBoxWidget(
                          onChanged: (bool e) {},
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                          value: globalSettings.trktivitySaveAllTitles,
                          text: "Save all All Window titles",
                        ),
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
                                      children: <Widget>[
                                        const Text("Add Title Filter"),
                                        const SizedBox(width: 10),
                                        InfoWidget("To remove leave exe empty", onTap: () {})
                                      ],
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
                ],
              ),
        if (allDates.isEmpty)
          const Text("There is no file to analyze.")
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
                                  dataAnalyzed = false;
                                  setState(() {});
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
                                  dataAnalyzed = false;
                                  setState(() {});
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
          ),
        if (dataAnalyzed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  startDate.isEmpty
                      ? "Stats for ${DateFormat("d MMMM, yyyy").format(DateTime.parse(selectedDay))}"
                      : "Stats from ${DateFormat("d MMM, yyyy").format(DateTime.parse(startDate))} to ${DateFormat("d MMM, yyyy").format(DateTime.parse(endDate))}"
                          "",
                  style: Theme.of(context).textTheme.headline6,
                ),
                Text("Total Keys pressed: ${uTrack.values.fold(0, (int previousValue, MTrack element) => element.keyboard + previousValue).formatInt()}"),
                const SizedBox(height: 20),
                Container(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: uTrackMaxValue,
                      barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: Theme.of(context).backgroundColor,
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        getTooltipItem: (BarChartGroupData a, int b, BarChartRodData c, int d) {
                          if (a.barRods.isEmpty) return BarTooltipItem("", Theme.of(context).textTheme.labelMedium!);
                          final String kb = a.barRods.elementAt(0).rodStackItems.elementAt(0).toY.toInt().formatInt();
                          final String mouse = a.barRods.elementAt(0).rodStackItems.elementAt(1).toY.toInt().formatInt();
                          return BarTooltipItem("${a.x.formatTime()}\n$kb keys pressed\n$mouse mouse pings", Theme.of(context).textTheme.button!);
                        },
                      )),
                      barGroups: List<BarChartGroupData>.generate(
                        48,
                        (int indx) {
                          int i = 0;
                          if (indx % 2 == 0) {
                            i = indx ~/ 2 * 60;
                          } else {
                            i = indx ~/ 2 * 60 + 30;
                          }
                          if (uTrack.containsKey(i)) {
                            return BarChartGroupData(
                              x: i,
                              // showingTooltipIndicators: <int>[uTrack[i]!.keyboard, uTrack[i]!.mouse],
                              barRods: <BarChartRodData>[
                                BarChartRodData(
                                    toY: uTrackMaxValue,
                                    rodStackItems: <BarChartRodStackItem>[
                                      BarChartRodStackItem(0, uTrack[i]!.keyboard.toDouble(), Colors.red),
                                      BarChartRodStackItem(0, uTrack[i]!.mouse.toDouble(), Colors.green),
                                    ],
                                    color: Colors.transparent),
                              ],
                            );
                          }
                          return BarChartGroupData(x: i);
                        },
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              if (value / 60 % 1 == 0) {
                                return SideTitleWidget(
                                  axisSide: meta.axisSide,
                                  space: 16,
                                  child: Text(
                                    (value.toInt() ~/ 60).toString(),
                                    style: const TextStyle(
                                      color: Color(0xff7589a2),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              }
                              return SideTitleWidget(
                                axisSide: meta.axisSide,
                                space: 0,
                                child: Container(),
                              );
                            },
                            reservedSize: 42,
                          ),
                        ),
                        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text("Focus time", style: Theme.of(context).textTheme.headline6),
                const SizedBox(height: 10),
                IntrinsicHeight(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Container(
                          height: 200,
                          child: MouseScrollWidget(
                            scrollDirection: Axis.vertical,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(child: Text("App", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 80, child: Text("Time", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 60, child: Text("Keys", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 60, child: Text("Mouse", style: Theme.of(context).textTheme.button)),
                                  ],
                                ),
                                InkWell(
                                  onTap: () {},
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                          child: Text(wTrack.containsKey("idle.exe") ? "Idle: ${wTrack["idle.exe"]!.timeFormat}" : "Total",
                                              style: Theme.of(context).textTheme.button)),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          timeFormat(
                                              wTrackList.fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "idle.exe" ? element.value.time : 0))),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          wTrackList
                                              .fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "idle.exe" ? element.value.keyboard : 0))
                                              .formatInt(),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          wTrackList
                                              .fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "idle.exe" ? element.value.mouse : 0))
                                              .formatInt(),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                ...List<Widget>.generate(
                                  wTrackList.length,
                                  (int index) {
                                    final MapEntry<String, MTrack> track = wTrackList.elementAt(index);
                                    if (track.key == "idle.exe") return Container();
                                    return InkWell(
                                      onTap: () {},
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Expanded(child: Text(track.key, maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
                                          SizedBox(width: 80, child: Text(track.value.timeFormat)),
                                          SizedBox(width: 60, child: Text(track.value.keyboard.formatInt())),
                                          SizedBox(width: 60, child: Text(track.value.mouse.formatInt())),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 20, thickness: 1),
                      Expanded(
                        child: Container(
                          height: 200,
                          child: MouseScrollWidget(
                            scrollDirection: Axis.vertical,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(child: Text("Title", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 80, child: Text("Time", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 60, child: Text("Keys", style: Theme.of(context).textTheme.button)),
                                    SizedBox(width: 60, child: Text("Mouse", style: Theme.of(context).textTheme.button)),
                                  ],
                                ),
                                InkWell(
                                  onTap: () {},
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(child: Text("Total", style: Theme.of(context).textTheme.button)),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          timeFormat(
                                              tTrackList.fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "Idle" ? element.value.time : 0))),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          tTrackList
                                              .fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "Idle" ? element.value.keyboard : 0))
                                              .formatInt(),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 60,
                                        child: Text(
                                          tTrackList
                                              .fold(0, (int p, MapEntry<String, MTrack> element) => p + (element.key != "Idle" ? element.value.mouse : 0))
                                              .formatInt(),
                                          style: Theme.of(context).textTheme.button,
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                ...List<Widget>.generate(
                                  tTrackList.length,
                                  (int index) {
                                    final MapEntry<String, MTrack> track = tTrackList.elementAt(index);
                                    if (track.key == "Idle") return Container();
                                    return InkWell(
                                      onTap: () {},
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.start,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Expanded(child: Text(track.key, maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
                                          SizedBox(width: 80, child: Text(track.value.timeFormat)),
                                          SizedBox(width: 60, child: Text(track.value.keyboard.formatInt())),
                                          SizedBox(width: 60, child: Text(track.value.mouse.formatInt())),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              ],
                            ),
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                if (startDate.isEmpty && selectedDay.isNotEmpty)
                  LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Divider(height: 20, thickness: 1),
                          Text("Timeline by App", style: Theme.of(context).textTheme.headline6),
                          const SizedBox(height: 11),
                          Container(
                            height: 20,
                            child: Stack(
                              children: List<Widget>.generate(
                                24,
                                (int index) {
                                  final double startpercentage = (index * 60 * 60) / (24 * 60 * 60);
                                  return Positioned(
                                    left: startpercentage * constraints.maxWidth,
                                    child: Text("$index"),
                                  );
                                },
                              ),
                            ),
                          ),
                          Container(
                            height: 220,
                            child: SingleChildScrollView(
                              controller: ScrollController(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List<Widget>.generate(
                                  wTimeTrackList.length,
                                  (int index) => Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(wTimeTrackList[index].key),
                                      Container(
                                        height: 20,
                                        width: constraints.maxWidth,
                                        child: Stack(
                                          children: List<Widget>.generate(wTimeTrackList[index].value.length, (int i) {
                                            final DateTime startDate = DateTime.fromMillisecondsSinceEpoch(wTimeTrackList[index].value[i].from);
                                            final DateTime endDate = DateTime.fromMillisecondsSinceEpoch(wTimeTrackList[index].value[i].to);
                                            final int startseconds = startDate.hour * 60 * 60 + startDate.minute * 60 + startDate.second;
                                            final int endseconds = endDate.hour * 60 * 60 + endDate.minute * 60 + endDate.second;
                                            const int secondsInADay = 24 * 60 * 60;

                                            final double startpercentage = startseconds / secondsInADay;
                                            final double diffPercentage = (endseconds - startseconds) / secondsInADay;

                                            return Positioned(
                                              left: startpercentage * constraints.maxWidth,
                                              width: diffPercentage * constraints.maxWidth,
                                              child: Container(height: 20, color: Theme.of(context).colorScheme.primary),
                                            );
                                          }),
                                        ),
                                      ),
                                      const Divider(height: 5, thickness: 1),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text("Timeline by Title", style: Theme.of(context).textTheme.headline6),
                          const SizedBox(height: 10),
                          Container(
                            height: 220,
                            child: SingleChildScrollView(
                              controller: ScrollController(),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: List<Widget>.generate(
                                  tTimeTrackList.length,
                                  (int index) => Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(tTimeTrackList[index].key),
                                      Container(
                                        height: 20,
                                        width: constraints.maxWidth,
                                        child: Stack(
                                          children: List<Widget>.generate(tTimeTrackList[index].value.length, (int i) {
                                            final DateTime startDate = DateTime.fromMillisecondsSinceEpoch(tTimeTrackList[index].value[i].from);
                                            final DateTime endDate = DateTime.fromMillisecondsSinceEpoch(tTimeTrackList[index].value[i].to);
                                            final int startseconds = startDate.hour * 60 * 60 + startDate.minute * 60 + startDate.second;
                                            final int endseconds = endDate.hour * 60 * 60 + endDate.minute * 60 + endDate.second;
                                            const int secondsInADay = 24 * 60 * 60;

                                            final double startpercentage = startseconds / secondsInADay;
                                            final double diffPercentage = (endseconds - startseconds) / secondsInADay;

                                            return Positioned(
                                              left: startpercentage * constraints.maxWidth,
                                              width: diffPercentage * constraints.maxWidth,
                                              child: Container(height: 20, color: Theme.of(context).colorScheme.primary),
                                            );
                                          }),
                                        ),
                                      ),
                                      const Divider(height: 5, thickness: 1),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                if (startDate.isNotEmpty && dailyStats.isNotEmpty)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const SizedBox(height: 20),
                            Text("Daily Stats", style: Theme.of(context).textTheme.headline6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Expanded(child: Text("Day")),
                                const SizedBox(width: 80, child: Text("Active")),
                                const SizedBox(width: 80, child: Text("Idle")),
                                const SizedBox(width: 80, child: Text("Keys")),
                                const SizedBox(width: 80, child: Text("Mouse")),
                              ],
                            ),
                            InkWell(
                              onTap: () {},
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Expanded(child: Text("Total", style: Theme.of(context).textTheme.button)),
                                  SizedBox(
                                      width: 80,
                                      child: Text(timeFormat(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.time)),
                                          style: Theme.of(context).textTheme.button)),
                                  SizedBox(
                                      width: 80,
                                      child: Text(timeFormat(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.idleTime)),
                                          style: Theme.of(context).textTheme.button)),
                                  SizedBox(
                                      width: 80,
                                      child: Text(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.keyboard).formatInt(),
                                          style: Theme.of(context).textTheme.button)),
                                  SizedBox(
                                      width: 80,
                                      child: Text(dailyStats.values.fold(0, (int previousValue, DMTRack element) => previousValue + element.mouse).formatInt(),
                                          style: Theme.of(context).textTheme.button)),
                                ],
                              ),
                            ),
                            ...List<Widget>.generate(dailyStats.keys.length, (int index) {
                              return InkWell(
                                onTap: () {},
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Expanded(child: Text(DateFormat("EE, dd MMMM, yyyy").format(DateTime.parse(dailyStats.keys.elementAt(index))))),
                                    SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).timeFormat)),
                                    SizedBox(width: 80, child: Text(timeFormat(dailyStats.values.elementAt(index).idleTime))),
                                    SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).keyboard.formatInt())),
                                    SizedBox(width: 80, child: Text(dailyStats.values.elementAt(index).mouse.formatInt())),
                                  ],
                                ),
                              );
                            })
                          ],
                        ),
                      ),
                      Expanded(
                          flex: 1,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const SizedBox(height: 20),
                              Text("Daily Average", style: Theme.of(context).textTheme.headline6),
                              Text("Active hours: ${timeFormat(dailyStats.values.map((DMTRack e) => e.time).average.toInt())}",
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text("Idle hours: ${timeFormat(dailyStats.values.map((DMTRack e) => e.idleTime).average.toInt())}",
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text("Key Strokes: ${dailyStats.values.map((DMTRack e) => e.keyboard).average.toInt().formatInt()}",
                                  style: Theme.of(context).textTheme.titleMedium),
                              Text("Mouse Pings: ${dailyStats.values.map((DMTRack e) => e.mouse).average.toInt().formatInt()}",
                                  style: Theme.of(context).textTheme.titleMedium),
                            ],
                          ))
                    ],
                  )
              ],
            ),
          ),
        const SizedBox(height: 50)
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
