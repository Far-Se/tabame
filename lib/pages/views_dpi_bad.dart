//dpi
// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/imports.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';

class ViewsScreen extends StatefulWidget {
  const ViewsScreen({super.key});
  @override
  ViewsScreenState createState() => ViewsScreenState();
}

Future<bool> interfaceWindowSetup() async {
  Monitor.fetchMonitor();
  Globals.currentPage = Pages.interface;
  final Square monitor = Monitor.monitorSizes[Win32.getCursorMonitor()]!;
  await WindowManager.instance.setMinimumSize(const Size(700, 600));
  await WindowManager.instance.setSkipTaskbar(true);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(true);
  await WindowManager.instance.setSize(Size(Monitor.dpiAdjust(monitor.width.toDouble()), Monitor.dpiAdjust(monitor.height.toDouble())));
  await WindowManager.instance.setPosition(const Offset(-9999, -9999));
  final int exstyle = GetWindowLong(Win32.hWnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
  SetWindowLongPtr(
      Win32.hWnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE, exstyle | WINDOW_EX_STYLE.WS_EX_TRANSPARENT | WINDOW_EX_STYLE.WS_EX_LAYERED | WINDOW_EX_STYLE.WS_EX_TOOLWINDOW);
  return true;
}

class Space {
  bool selected;
  bool hovered;
  int gridX;
  int gridY;
  double x;
  double y;
  Space({
    this.selected = false,
    this.hovered = false,
    required this.gridX,
    required this.gridY,
    required this.x,
    required this.y,
  });

  @override
  String toString() {
    return 'Space(enabled: $selected, hovered: $hovered, gridX: $gridX, gridY: $gridY, x: $x, y: $y)';
  }

  Space copyWith({
    bool? selected,
    bool? hovered,
    int? gridX,
    int? gridY,
    double? x,
    double? y,
  }) {
    return Space(
      selected: selected ?? this.selected,
      hovered: hovered ?? this.hovered,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }
}

class ViewsSettings {
  int minW = 10;
  int maxW = 10;
  int minH = 30;
  int maxH = 30;
  int scaleW = 15;
  int scaleH = 15;
  int scrollStepW = 5;
  int scrollStepH = 5;
  ViewsSettings();
  Future<void> load() async {
    final String file = "${WinUtils.getTabameSettingsFolder()}\\views.json";
    if (!File(file).existsSync()) File(file).createSync();
    String fileData = File(file).readAsStringSync();
    if (fileData.isEmpty) {
      File(file).writeAsStringSync(toJson());
      fileData = File(file).readAsStringSync();
    }
    final Map<String, dynamic> map = json.decode(fileData);
    minW = (map['minW'] ?? 10) as int;
    maxW = (map['maxW'] ?? 10) as int;
    minH = (map['minH'] ?? 30) as int;
    maxH = (map['maxH'] ?? 30) as int;
    scaleW = (map['scaleW'] ?? 15) as int;
    scaleH = (map['scaleH'] ?? 15) as int;
    scrollStepW = (map['scrollStepW'] ?? 5) as int;
    scrollStepH = (map['scrollStepH'] ?? 5) as int;
  }

  Future<void> save() async {
    final String file = "${WinUtils.getTabameSettingsFolder()}\\views.json";
    if (!File(file).existsSync()) File(file).createSync();
    File(file).writeAsStringSync(toJson());
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'minW': minW,
      'maxW': maxW,
      'minH': minH,
      'maxH': maxH,
      'scaleW': scaleW,
      'scaleH': scaleH,
      'scrollStepW': scrollStepW,
      'scrollStepH': scrollStepH,
    };
  }

  String toJson() => json.encode(toMap());
}

class ViewsScreenState extends State<ViewsScreen> with TabameListener {
  final ViewsSettings settings = ViewsSettings();
  final Future<bool> interfaceWindow = interfaceWindowSetup();
  Timer? timer;
  int currentMonitor = -1;
  bool processing = false;

  Square monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  final List<Space> matrix = <Space>[];
  ViewsAction action = ViewsAction.open;
  int hWnd = 0;
  // ? checker
  int lastX = 0;
  int lastY = 0;
  bool selecting = false;
  bool visible = false;
  Space spaceHovered = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  Space spaceStarted = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  Space spaceEnded = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  //? saved Data
  final Map<int, Space> winsSavedPos = <int, Space>{};
  final Space nowPos = Space(gridX: 0, gridY: 0, x: 0, y: 0);

  final Color bgColor = const Color(0xff202020);
  late Color borderColor;
  @override
  void initState() {
    super.initState();
    NativeHooks.hook();
    NativeHooks.addListener(this);
    int monitor = Monitor.getCursorMonitor();
    currentMonitor = monitor;
    monitorData = Monitor.monitorSizes[monitor]!;
    setMatrix();
    borderColor = Color.fromRGBO(255 - bgColor.red, 255 - bgColor.green, 255 - bgColor.blue, 0.2);
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) async {
      WindowManager.instance.setPosition(const Offset(-99999, -99999));
    });
  }

  void setMatrix() {
    matrix.clear();
    final double width = monitorData.width / settings.scaleW;
    final double height = monitorData.height / settings.scaleH;
    for (int h = 0; h < settings.scaleH; h++) {
      for (int w = 0; w < settings.scaleW; w++) {
        matrix.add(Space(x: w * width, y: h * height, gridX: w, gridY: h));
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
  }

  void checker() async {
    if (!visible) return;
    if (processing == true) return;
    processing = true;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final PointXY cpos = PointXY(X: lpPoint.ref.x, Y: lpPoint.ref.y);
    free(lpPoint);
    final int monitor = Monitor.getCursorMonitor();

    int mX = cpos.X;
    int mY = cpos.Y;

    if (monitor != currentMonitor) {
      currentMonitor = monitor;
      monitorData = Monitor.monitorSizes[monitor]!;
      await WindowManager.instance.setPosition(Offset(Monitor.dpiAdjust(monitorData.x.toDouble()), Monitor.dpiAdjust(monitorData.y.toDouble())));
      await WindowManager.instance.setSize(Size(Monitor.dpiAdjust(monitorData.width.toDouble()), Monitor.dpiAdjust(monitorData.height.toDouble())));
    }
    if (mX != lastX && mY != lastY && mX.isBetweenEqual(monitorData.x, monitorData.length) && mY.isBetweenEqual(monitorData.y, monitorData.wide)) {
      lastX = mX;
      lastY = mY;
      mX = mX - monitorData.x;
      mY = mY - monitorData.y;
      final double width = monitorData.width / settings.scaleW;
      final double height = monitorData.height / settings.scaleH;
      for (Space space in matrix) {
        if (mX.isBetweenEqual(space.x, space.x + width) && mY.isBetweenEqual(space.y, space.y + height)) {
          if (spaceHovered != space) {
            for (Space e in matrix) {
              e.hovered = false;
              e.selected = false;
            }
            space.hovered = true;
            spaceHovered = space;
            if (selecting) {
              int minX = 0;
              int maxX = 0;
              int minY = 0;
              int maxY = 0;
              if (spaceStarted.gridX < spaceHovered.gridX) {
                minX = spaceStarted.gridX;
                maxX = spaceHovered.gridX;
              } else {
                minX = spaceHovered.gridX;
                maxX = spaceStarted.gridX;
              }
              if (spaceStarted.gridY < spaceHovered.gridY) {
                minY = spaceStarted.gridY;
                maxY = spaceHovered.gridY;
              } else {
                minY = spaceHovered.gridY;
                maxY = spaceStarted.gridY;
              }
              for (Space e in matrix) {
                if (e.gridX.isBetweenEqual(minX, maxX) && e.gridY.isBetweenEqual(minY, maxY)) {
                  e.selected = true;
                }
              }
            }
            if (mounted) setState(() {});
          }
          //
        }
      }
    }

    processing = false;
  }

  bool fixedWindowsBug = false;
  @override
  void onViewsEvent(ViewsAction action, int hWnd) async {
    if (action == ViewsAction.open) {
      visible = true;
      final Square monitor = Monitor.monitorSizes[Win32.getCursorMonitor()]!;
      currentMonitor = Win32.getCursorMonitor();
      monitorData = monitor;
      // Future<void>.delayed(const Duration(milliseconds: 300), () => WindowManager.instance.setPosition(Offset(monitor.x.toDouble(), monitor.y.toDouble())));
      WindowManager.instance.setPosition(Offset(Monitor.dpiAdjust(monitor.x.toDouble()), Monitor.dpiAdjust(monitor.y.toDouble())));
      winsSavedPos[this.hWnd] = nowPos.copyWith();
      timer = Timer.periodic(const Duration(milliseconds: 50), (Timer timer) {
        if (!visible) timer.cancel();
        checker();
      });
    }
    if (action == ViewsAction.selecting) {
      selecting = true;
      spaceStarted = spaceHovered;
    } else if (action == ViewsAction.selected) {
      spaceEnded = spaceHovered;
      selecting = false;
    } else if (action == ViewsAction.moveStart) {
      if (!fixedWindowsBug) WindowManager.instance.setPosition(const Offset(-99998, -9998));
      fixedWindowsBug = true;
      this.hWnd = hWnd;
      final Pointer<RECT> lpRect = calloc<RECT>();
      GetWindowRect(this.hWnd, lpRect);
      nowPos
        ..gridX = lpRect.ref.right - lpRect.ref.left
        ..gridY = lpRect.ref.bottom - lpRect.ref.top
        ..x = lpRect.ref.left.toDouble()
        ..y = lpRect.ref.top.toDouble();
      free(lpRect);
      //
    } else if (action == ViewsAction.moveEnd) {
      if (!visible) {
        if (winsSavedPos.containsKey(hWnd)) {
          SetWindowPos(
              this.hWnd, NULL, NULL, NULL, winsSavedPos[hWnd]!.gridX, winsSavedPos[hWnd]!.gridY, SET_WINDOW_POS_FLAGS.SWP_NOMOVE | SET_WINDOW_POS_FLAGS.SWP_NOZORDER);
          winsSavedPos.remove(hWnd);
        }
        this.hWnd = -1;

        return;
      }
      timer?.cancel();
      spaceEnded = spaceHovered;
      selecting = false;
      final List<Space> spaces = matrix.where((Space element) => element.selected).toList();
      if (spaces.length < 2) {
        visible = false;
        Win32.setPosition(const Offset(-99999, -99999));
        return;
      }
      final double width = monitorData.width / settings.scaleW;
      final double height = monitorData.height / settings.scaleH;
      final double windowWidth = spaces.last.x - spaces.first.x + width;
      final double windowHeight = spaces.last.y - spaces.first.y + height;
      final Square monitor = Monitor.monitorSizes[Win32.getCursorMonitor()]!;
      const int diffX = 7;
      const int diffY = 2;
      final int x = (monitor.x + spaces.first.x.floor() / 1).toInt();
      final int y = (monitor.y + spaces.first.y.floor() / 1).toInt();
      final int sizeX = windowWidth.toInt();
      final int sizeY = windowHeight.toInt();
      SetWindowPos(this.hWnd, NULL, x - diffX, y - diffY, sizeX + (diffX * 2), sizeY + (diffY * 2), SET_WINDOW_POS_FLAGS.SWP_NOZORDER);
      for (Space e in matrix) {
        e.selected = false;
        e.hovered = false;
      }
      setState(() {});
      // WindowManager.instance.minimize();
      WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => Win32.setPosition(const Offset(-99999, -99999)));

      visible = false;
    } else if (action == ViewsAction.switchUp || action == ViewsAction.switchDown) {
      settings.scaleW = action == ViewsAction.switchDown ? (settings.scaleW - settings.scrollStepW) : (settings.scaleW + settings.scrollStepW);
      settings.scaleH = action == ViewsAction.switchDown ? (settings.scaleH - settings.scrollStepH) : (settings.scaleH + settings.scrollStepH);
      settings.scaleW = settings.scaleW.clamp(settings.minH, settings.maxH);
      settings.scaleH = settings.scaleH.clamp(settings.minW, settings.maxH);
      setMatrix();
      lastX = 0;
      lastY = 0;
      selecting = false;
      spaceHovered = Space(gridX: 0, gridY: 0, x: 0, y: 0);
      spaceStarted = Space(gridX: 0, gridY: 0, x: 0, y: 0);
      spaceEnded = Space(gridX: 0, gridY: 0, x: 0, y: 0);
      checker();
      setState(() {});
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor.withOpacity(0.7),
      body: FutureBuilder<bool>(
        future: interfaceWindow,
        builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
          if (!snapshot.hasData) return Container();
          return Stack(
            children: <Widget>[
              Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List<Widget>.generate(
                  settings.scaleH,
                  (int colIndex) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List<Widget>.generate(
                        settings.scaleH,
                        (int rowIndex) {
                          final int spaceIndex = matrix.indexWhere((Space element) => element.gridX == rowIndex && element.gridY == colIndex);
                          if (spaceIndex == -1) return Container();
                          final Space space = matrix.elementAt(spaceIndex);
                          Color color = Colors.transparent;
                          if (space.hovered) {
                            color = borderColor.withOpacity(0.2);
                          }
                          if (space.selected) {
                            color = borderColor.withOpacity(0.2);
                          }
                          return Container(
                              width: MediaQuery.of(context).size.width / settings.scaleW,
                              height: MediaQuery.of(context).size.height / settings.scaleH,
                              decoration: BoxDecoration(
                                border: !space.selected ? Border.all(color: borderColor.withOpacity(0.4), style: BorderStyle.solid, width: 0.5) : null,
                                color: color,
                              )
                              // child: Center(child: Text("$colIndex/$rowIndex")),
                              );
                        },
                      ),
                    );
                  },
                ),
              ),
              if (matrix.where((Space element) => element.selected).length > 2)
                ...List<Widget>.generate(1, (int index) {
                  final double left = matrix.firstWhere((Space element) => element.selected).x;
                  final double top = matrix.firstWhere((Space element) => element.selected).y;
                  final double width = matrix.lastWhere((Space element) => element.selected).x + (MediaQuery.of(context).size.width / settings.scaleW) - left;
                  final double height = matrix.lastWhere((Space element) => element.selected).y + (MediaQuery.of(context).size.height / settings.scaleH) - top;
                  return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: height,
                      child: Center(
                        child: Text("${width.toInt()}:${height.toInt()}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 25)),
                      ));
                }),
            ],
          );
        },
      ),
    );
  }
}
