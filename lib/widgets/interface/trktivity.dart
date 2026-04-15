// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_widget.dart';

import 'trktivity/trktivity_activity_chart.dart';
import 'trktivity/trktivity_daily_stats.dart';
import 'trktivity/trktivity_filter_set.dart';
import 'trktivity/trktivity_focus_tables.dart';
import 'trktivity/trktivity_heat_map.dart';
import 'trktivity/trktivity_models.dart';
import 'trktivity/trktivity_timeline.dart';

class TrktivityPage extends StatefulWidget {
  const TrktivityPage({super.key});
  @override
  TrktivityPageState createState() => TrktivityPageState();
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
    allDates.addAll(Directory(trk.folder)
        .listSync()
        .where((FileSystemEntity e) => e.path.contains("-"))
        .map((FileSystemEntity e) => e.path.substring(e.path.lastIndexOf('\\') + 1).replaceAll(".json", "")));

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
    wTimeTrack.clear();
    wTrackList.clear();
    wTimeTrackList.clear();

    tTrack.clear();
    tTimeTrack.clear();
    tTrackList.clear();
    tTimeTrackList.clear();

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              flex: 4,
              child: Column(
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
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    secondary: InfoWidget("Press to open folder with saved data", onTap: () {
                      WinUtils.open("${WinUtils.getTabameAppDataFolder()}\\trktivity");
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
                            // Modern Filter Toolbar
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                children: <Widget>[
                                  InkWell(
                                    onTap: () => setState(() => showFilters = !showFilters),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(
                                            showFilters ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                            size: 20,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Filters & Privacy",
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  CheckBoxWidget(
                                    onChanged: (bool e) {
                                      globalSettings.trktivitySaveAllTitles = e;
                                      Boxes.updateSettings("trktivitySaveAllTitles", e);
                                      setState(() {});
                                    },
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    value: globalSettings.trktivitySaveAllTitles,
                                    text: "Save All Window Titles",
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      trk.filters.add(TrktivityFilter(
                                        exe: "exe",
                                        titleSearch: r"",
                                        titleReplace: r"",
                                      ));
                                      Boxes.updateSettings("trktivityFilter", jsonEncode(trk.filters));
                                      setState(() => showFilters = true);
                                    },
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text("Add Rule", style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                            if (showFilters)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: List<Widget>.generate(
                                      trk.filters.length,
                                      (int index) => TrktivityFilterSet(
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
                                ),
                              ),
                            const SizedBox(height: 8),
                            TrktivityHeatMap(
                              allDates: allDates,
                              folder: trk.folder,
                            ),
                          ],
                        ),
                  if (allDates.isEmpty)
                    const Text("  There is no file to analyze. Close Interface, do some activity and come back to see it saved!")
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                // Day Selector
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.today, size: 18, color: Theme.of(context).colorScheme.primary),
                                      const SizedBox(width: 8),
                                      DropdownButtonHideUnderline(
                                        child: DropdownButton2<String>(
                                          isDense: true,
                                          buttonStyleData: const ButtonStyleData(
                                            padding: EdgeInsets.zero,
                                            height: 35,
                                            width: 120,
                                          ),
                                          menuItemStyleData: const MenuItemStyleData(height: 35),
                                          dropdownStyleData: DropdownStyleData(
                                            padding: const EdgeInsets.all(4),
                                            offset: const Offset(0, -4),
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            maxHeight: 250,
                                          ),
                                          value: selectedDay,
                                          items: allDates
                                              .take(30)
                                              .map<DropdownMenuItem<String>>((String e) => DropdownMenuItem<String>(
                                                    value: e,
                                                    child: Text(e, style: const TextStyle(fontSize: 13)),
                                                  ))
                                              .toList(),
                                          onMenuStateChange: (bool e) {
                                            if (!e) return;
                                            dataAnalyzed = false;
                                            setState(() {});
                                          },
                                          onChanged: (String? e) {
                                            dataAnalyzed = false;
                                            selectedDay = e ?? allDates.first;
                                            pickText = "Pick Range";
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
                                VerticalDivider(
                                  width: 1,
                                  indent: 8,
                                  endIndent: 8,
                                  color: Theme.of(context).colorScheme.outlineVariant,
                                ),
                                // Range Selector
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime.parse(allDates.last),
                                        lastDate: DateTime.parse(allDates.first),
                                      ).then((DateTimeRange? value) {
                                        if (value == null) return;
                                        dataAnalyzed = false;
                                        startDate = DateFormat('yyyy-MM-dd').format(value.start);
                                        endDate = DateFormat('yyyy-MM-dd').format(value.end);
                                        pickText = startDate == endDate ? startDate : "$startDate → $endDate";
                                        showReport();
                                        setState(() {});
                                      });
                                    },
                                    icon: Icon(Icons.date_range, size: 18, color: Theme.of(context).colorScheme.primary),
                                    label: Text(
                                      pickText == "Pick Dates" ? "Pick Range" : pickText,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text("Total Keys pressed: ${uTrack.values.fold(0, (int previousValue, MTrack element) => element.keyboard + previousValue).formatInt()}"),
                const SizedBox(height: 20),
                TrktivityActivityChart(
                  uTrack: uTrack,
                  uTrackMaxValue: uTrackMaxValue,
                ),
                const SizedBox(height: 10),
                Text("Focus time", style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 10),
                TrktivityFocusTables(
                  wTrack: wTrack,
                  wTrackList: wTrackList,
                  tTrack: tTrack,
                  tTrackList: tTrackList,
                ),
                if ((startDate.isEmpty && selectedDay.isNotEmpty) || (startDate.isNotEmpty && startDate == endDate))
                  TrktivityTimeline(
                    wTimeTrackList: wTimeTrackList,
                    tTimeTrackList: tTimeTrackList,
                  ),
                if (startDate.isNotEmpty && dailyStats.isNotEmpty && startDate != endDate)
                  TrktivityDailyStats(
                    dailyStats: dailyStats,
                  )
              ],
            ),
          ),
        const SizedBox(height: 50)
      ],
    );
  }
}
