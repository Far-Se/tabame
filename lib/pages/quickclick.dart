import 'dart:async';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';

class QuickClickOverlay extends StatefulWidget {
  const QuickClickOverlay({super.key});

  @override
  State<QuickClickOverlay> createState() => _QuickClickOverlayState();
}

class _QuickClickOverlayState extends State<QuickClickOverlay> with TabameListener {
  final FocusNode _focusNode = FocusNode();

  final List<String> rows = userSettings.quickClickConfig.verticalKeys.split('');

  final List<String> cols = userSettings.quickClickConfig.horizontalKeys.split('');

  late double screenWidth;
  late double screenHeight;

  int? selectedRow;
  int? selectedCol;

  int currentMonitor = -1;
  Square monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  @override
  void initState() {
    super.initState();
    NativeHooks.addListener(this);
    QuickClick.enableQuickClick();
    _enableDpiAwareness();

    currentMonitor = Monitor.getCursorMonitor();
    monitorData = Monitor.monitorSizes[currentMonitor]!;
    print(monitorData);
    WindowManager.instance.setPosition(Offset(monitorData.x.toDouble(), monitorData.y.toDouble()));
    WindowManager.instance.setSize(Size(monitorData.width.toDouble(), monitorData.height.toDouble()));
    WinUtils.makeWindowClickThrough(true);
    WinUtils.fixDrawBug();
    // WidgetsBinding.instance.addPostFrameCallback((_) async {
    //   WinUtils.makeWindowClickThrough(true);
    //   setState(() {});
    // });

    screenWidth = (monitorData.width).toDouble();
    screenHeight = (monitorData.height).toDouble();

    Timer(const Duration(milliseconds: 600), () {
      WinUtils.makeWindowClickThrough(true);
      _focusNode.requestFocus();
    });
  }

  @override
  void onQuickClickEvent(String eventName, Map<String, String> params) {
    print(eventName);
    switch (eventName) {
      case "dragStart":
        print("dragStart");
        break;
      case "dragEnd":
        print("dragEnd");
        break;
      case "scroll":
        print("scroll");
        break;
    }
  }

  @override
  void dispose() {
    NativeHooks.removeListener(this);
    QuickClick.disableQuickClick();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      autofocus: true,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          type: MaterialType.transparency,
          child: Stack(
            children: <Widget>[
              CustomPaint(
                size: Size.infinite,
                painter: GridPainter(
                  rows: rows,
                  cols: cols,
                ),
              ),
              _buildLabels(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabels() {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 40,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 40),
              ...List<Widget>.generate(cols.length, (int index) {
                return Expanded(
                  child: Center(
                    child: Text(
                      cols[index],
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 40,
                child: Column(
                  children: List<Widget>.generate(rows.length, (int index) {
                    return Expanded(
                      child: Center(
                        child: Text(
                          rows[index],
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyUpEvent && event is! KeyRepeatEvent) return;

    final LogicalKeyboardKey key = event.logicalKey;

    // Number selection
    for (int i = 0; i < cols.length; i++) {
      if (key.keyLabel == cols[i]) {
        selectedCol = i;
        _moveIfReady();
        return;
      }
    }

    // Letter selection
    for (int i = 0; i < rows.length; i++) {
      if (key.keyLabel.toUpperCase() == rows[i]) {
        selectedRow = i;
        _moveIfReady();
        return;
      }
    }

    // Movement keys
    if (key == LogicalKeyboardKey.comma || key == LogicalKeyboardKey.arrowLeft) {
      _relativeMove(-5, 0);
    }

    if (key == LogicalKeyboardKey.period || key == LogicalKeyboardKey.arrowDown) {
      _relativeMove(0, 5);
    }

    if (key == LogicalKeyboardKey.slash || key == LogicalKeyboardKey.arrowRight) {
      _relativeMove(5, 0);
    }

    if (key == LogicalKeyboardKey.semicolon || key == LogicalKeyboardKey.arrowUp) {
      _relativeMove(0, -5);
    }

    // Left click
    if (key == LogicalKeyboardKey.controlLeft || key == LogicalKeyboardKey.controlRight) {
      _leftClick();
    }

    // Right click
    if (key == LogicalKeyboardKey.altLeft || key == LogicalKeyboardKey.altRight) {
      _rightClick();
    }

    // Scroll
    if (key.keyLabel == '[') {
      _scroll(120);
    }

    if (key.keyLabel == ']') {
      _scroll(-120);
    }
  }

  void _moveIfReady() {
    if (selectedRow == null || selectedCol == null) return;

    final double cellWidth = screenWidth / cols.length;
    final double cellHeight = screenHeight / rows.length;

    final double x = (selectedCol! * cellWidth) + (cellWidth / 2);
    final double y = (selectedRow! * cellHeight) + (cellHeight / 2);

    _moveMouseAbsolute(x.toInt(), y.toInt());

    selectedRow = null;
    selectedCol = null;
  }

  void _moveMouseAbsolute(int x, int y) {
    final int absX = monitorData.x + x;
    final int absY = monitorData.y + y;

    SetCursorPos(absX, absY);
  }

  void _relativeMove(int dx, int dy) {
    final Pointer<POINT> point = calloc<POINT>();

    GetCursorPos(point);

    final int newX = point.ref.x + dx;
    final int newY = point.ref.y + dy;

    SetCursorPos(newX, newY);

    calloc.free(point);
  }

  void _leftClick() {
    final Pointer<INPUT> down = calloc<INPUT>();
    down.ref.type = INPUT_MOUSE;
    down.ref.mi.dwFlags = MOUSEEVENTF_LEFTDOWN;

    final Pointer<INPUT> up = calloc<INPUT>();
    up.ref.type = INPUT_MOUSE;
    up.ref.mi.dwFlags = MOUSEEVENTF_LEFTUP;

    SendInput(1, down, sizeOf<INPUT>());
    SendInput(1, up, sizeOf<INPUT>());

    calloc.free(down);
    calloc.free(up);
  }

  void _rightClick() {
    final Pointer<INPUT> down = calloc<INPUT>();
    down.ref.type = INPUT_MOUSE;
    down.ref.mi.dwFlags = MOUSEEVENTF_RIGHTDOWN;

    final Pointer<INPUT> up = calloc<INPUT>();
    up.ref.type = INPUT_MOUSE;
    up.ref.mi.dwFlags = MOUSEEVENTF_RIGHTUP;

    SendInput(1, down, sizeOf<INPUT>());
    SendInput(1, up, sizeOf<INPUT>());

    calloc.free(down);
    calloc.free(up);
  }

  void _scroll(int amount) {
    final Pointer<INPUT> input = calloc<INPUT>();

    input.ref.type = INPUT_MOUSE;
    input.ref.mi.dwFlags = MOUSEEVENTF_WHEEL;
    input.ref.mi.mouseData = amount;

    SendInput(1, input, sizeOf<INPUT>());

    calloc.free(input);
  }
}

class GridPainter extends CustomPainter {
  final List<String> rows;
  final List<String> cols;

  GridPainter({required this.rows, required this.cols});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;

    final double cellWidth = size.width / cols.length;
    final double cellHeight = size.height / rows.length;

    // Vertical lines
    for (int i = 0; i <= cols.length; i++) {
      final double x = i * cellWidth;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    // Horizontal lines
    for (int i = 0; i <= rows.length; i++) {
      final double y = i * cellHeight;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _enableDpiAwareness() {
  try {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  } catch (_) {}
}
