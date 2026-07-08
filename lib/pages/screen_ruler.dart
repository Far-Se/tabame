import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/screen_utils.dart';

// ---------------------------------------------------------------------------
// Screen Ruler — PowerToys-style pixel measure overlay with a loupe.
//
// Spawned as its own process via `tabame.exe -screenRuler` (same pattern as
// -screenDraw / -colorPicker). Takes one frozen snapshot of the virtual
// desktop and measures on it:
//  - crosshair mode: walks the snapshot from the cursor in all four directions
//    until the color changes beyond the tolerance, drawing measured spans,
//  - drag mode: manual box measurement,
//  - loupe: magnified pixel view with coordinates and hex color.
//
// Keys: 1/2/3 measuring mode, L loupe, wheel tolerance, R re-snapshot,
// click/copy measurement, Esc quit.
// ---------------------------------------------------------------------------

Future<void> startScreenRuler() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();

  final int vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final int vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  final WindowOptions windowOptions = WindowOptions(
    size: Size(vWidth.toDouble(), vHeight.toDouble()),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: 'Tabame Screen Ruler',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
    Win32Window.hwnd = GetAncestor(GetActiveWindow(), 2);
  });

  runApp(const ScreenRulerApp());
}

// ---------------------------------------------------------------------------
// Snapshot of the whole virtual desktop (physical pixels)
// ---------------------------------------------------------------------------

class RulerSnapshot {
  RulerSnapshot({
    required this.rgba,
    required this.width,
    required this.height,
    required this.image,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final ui.Image image;

  int pixel(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    final int i = (y * width + x) * 4;
    return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
  }
}

Future<RulerSnapshot?> _captureVirtualDesktop() async {
  final int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  final int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  final int w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final int h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (w <= 0 || h <= 0) return null;

  final int screenDc = GetDC(NULL);
  final int memDc = CreateCompatibleDC(screenDc);
  final int bmp = CreateCompatibleBitmap(screenDc, w, h);
  SelectObject(memDc, bmp);

  BitBlt(memDc, 0, 0, w, h, screenDc, x, y, SRCCOPY | CAPTUREBLT);

  final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();
  bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
  bmi.ref.bmiHeader.biWidth = w;
  bmi.ref.bmiHeader.biHeight = -h;
  bmi.ref.bmiHeader.biPlanes = 1;
  bmi.ref.bmiHeader.biBitCount = 32;
  bmi.ref.bmiHeader.biCompression = BI_RGB;

  final Pointer<Uint8> bgra = calloc<Uint8>(w * h * 4);
  GetDIBits(memDc, bmp, 0, h, bgra.cast(), bmi, DIB_RGB_COLORS);

  final Uint8List rgba = Uint8List(w * h * 4);
  final Uint8List src = bgra.asTypedList(w * h * 4);
  for (int i = 0; i < src.length; i += 4) {
    rgba[i] = src[i + 2];
    rgba[i + 1] = src[i + 1];
    rgba[i + 2] = src[i];
    rgba[i + 3] = 255;
  }

  DeleteObject(bmp);
  DeleteDC(memDc);
  ReleaseDC(NULL, screenDc);
  calloc.free(bgra);
  calloc.free(bmi);

  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, w, h, ui.PixelFormat.rgba8888, completer.complete);
  final ui.Image image = await completer.future;

  return RulerSnapshot(rgba: rgba, width: w, height: h, image: image);
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class ScreenRulerApp extends StatelessWidget {
  const ScreenRulerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const ScreenRulerShell(),
    );
  }
}

enum RulerMode { cross, horizontal, vertical }

class ScreenRulerShell extends StatefulWidget {
  const ScreenRulerShell({super.key});

  @override
  State<ScreenRulerShell> createState() => _ScreenRulerShellState();
}

class _ScreenRulerShellState extends State<ScreenRulerShell> {
  RulerSnapshot? _snapshot;
  RulerMode _mode = RulerMode.cross;
  bool _loupeVisible = true;
  int _tolerance = 16;

  Offset? _cursorLocal; // logical (widget) coords
  Offset? _dragStartLocal;
  Offset? _dragEndLocal;
  Rect? _committedDragLocal; // finished drag box kept on screen

  String? _toast;
  Timer? _toastTimer;
  bool _hideChromeForCapture = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Win32Window.setupOverlay());
    unawaited(_refreshSnapshot(initial: true));
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshSnapshot({bool initial = false}) async {
    if (!initial) {
      // Hide everything we draw so the new snapshot doesn't contain our own
      // overlay (the window itself is transparent).
      setState(() => _hideChromeForCapture = true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final RulerSnapshot? snapshot = await _captureVirtualDesktop();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _hideChromeForCapture = false;
      _committedDragLocal = null;
    });
  }

  double get _dpr => MediaQuery.of(context).devicePixelRatio;

  Offset _toPhysical(Offset local) => local * _dpr;

  void _showToast(String text) {
    _toastTimer?.cancel();
    setState(() => _toast = text);
    _toastTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  // --- measurement ------------------------------------------------------------

  /// Walks from (px,py) in the snapshot until the color differs from the
  /// starting pixel by more than [_tolerance] on any channel.
  ({int left, int right, int up, int down}) _findEdges(int px, int py) {
    final RulerSnapshot snap = _snapshot!;
    final Uint8List d = snap.rgba;
    final int w = snap.width;
    final int h = snap.height;

    int baseIndex(int x, int y) => (y * w + x) * 4;
    final int bi = baseIndex(px.clamp(0, w - 1), py.clamp(0, h - 1));
    final int r0 = d[bi], g0 = d[bi + 1], b0 = d[bi + 2];

    bool similar(int x, int y) {
      final int i = baseIndex(x, y);
      return (d[i] - r0).abs() <= _tolerance &&
          (d[i + 1] - g0).abs() <= _tolerance &&
          (d[i + 2] - b0).abs() <= _tolerance;
    }

    int left = px;
    while (left > 0 && similar(left - 1, py)) {
      left--;
    }
    int right = px;
    while (right < w - 1 && similar(right + 1, py)) {
      right++;
    }
    int up = py;
    while (up > 0 && similar(px, up - 1)) {
      up--;
    }
    int down = py;
    while (down < h - 1 && similar(px, down + 1)) {
      down++;
    }
    return (left: left, right: right, up: up, down: down);
  }

  String? _currentMeasurementText() {
    if (_committedDragLocal != null || (_dragStartLocal != null && _dragEndLocal != null)) {
      final Rect local = _committedDragLocal ?? Rect.fromPoints(_dragStartLocal!, _dragEndLocal!);
      final Rect phys = Rect.fromPoints(_toPhysical(local.topLeft), _toPhysical(local.bottomRight));
      return "${phys.width.round()} x ${phys.height.round()}";
    }
    if (_cursorLocal == null || _snapshot == null) return null;
    final Offset p = _toPhysical(_cursorLocal!);
    final ({int down, int left, int right, int up}) edges = _findEdges(p.dx.round(), p.dy.round());
    final int spanW = edges.right - edges.left + 1;
    final int spanH = edges.down - edges.up + 1;
    switch (_mode) {
      case RulerMode.cross:
        return "$spanW x $spanH";
      case RulerMode.horizontal:
        return "$spanW";
      case RulerMode.vertical:
        return "$spanH";
    }
  }

  void _copyMeasurement() {
    final String? text = _currentMeasurementText();
    if (text == null) return;
    Clipboard.setData(ClipboardData(text: text));
    _showToast("Copied  $text");
  }

  // --- input ----------------------------------------------------------------------

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_committedDragLocal != null) {
        setState(() => _committedDragLocal = null);
      } else {
        unawaited(windowManager.close());
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyL) {
      setState(() => _loupeVisible = !_loupeVisible);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyR) {
      unawaited(_refreshSnapshot());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyC) {
      _copyMeasurement();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit1) {
      setState(() => _mode = RulerMode.cross);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit2) {
      setState(() => _mode = RulerMode.horizontal);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.digit3) {
      setState(() => _mode = RulerMode.vertical);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: Listener(
          onPointerSignal: (PointerSignalEvent event) {
            if (event is PointerScrollEvent) {
              setState(() => _tolerance = (_tolerance + (event.scrollDelta.dy > 0 ? -4 : 4)).clamp(4, 96));
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (PointerHoverEvent event) => setState(() => _cursorLocal = event.localPosition),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _copyMeasurement,
              onSecondaryTap: () => unawaited(windowManager.close()),
              onPanStart: (DragStartDetails details) => setState(() {
                _committedDragLocal = null;
                _dragStartLocal = details.localPosition;
                _dragEndLocal = details.localPosition;
              }),
              onPanUpdate: (DragUpdateDetails details) => setState(() {
                _dragEndLocal = details.localPosition;
                _cursorLocal = details.localPosition;
              }),
              onPanEnd: (DragEndDetails details) {
                final Offset? start = _dragStartLocal;
                final Offset? end = _dragEndLocal;
                setState(() {
                  if (start != null && end != null && (end - start).distance > 4) {
                    _committedDragLocal = Rect.fromPoints(start, end);
                  }
                  _dragStartLocal = null;
                  _dragEndLocal = null;
                });
                _copyMeasurement();
              },
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Nearly-invisible backdrop so the whole surface is hit-testable.
                  Container(color: const Color(0x01000000)),
                  if (!_hideChromeForCapture && _snapshot != null)
                    CustomPaint(
                      painter: _RulerPainter(
                        snapshot: _snapshot!,
                        dpr: _dpr,
                        cursorLocal: _cursorLocal,
                        mode: _mode,
                        tolerance: _tolerance,
                        findEdges: _findEdges,
                        dragLocal: _dragStartLocal != null && _dragEndLocal != null
                            ? Rect.fromPoints(_dragStartLocal!, _dragEndLocal!)
                            : _committedDragLocal,
                        loupeVisible: _loupeVisible,
                      ),
                    ),
                  if (!_hideChromeForCapture) _buildHintBar(),
                  if (!_hideChromeForCapture && _toast != null) _buildToast(),
                  if (_snapshot == null)
                    const Center(
                      child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHintBar() {
    final String modeName = switch (_mode) {
      RulerMode.cross => "CROSS",
      RulerMode.horizontal => "HORIZONTAL",
      RulerMode.vertical => "VERTICAL",
    };
    return Positioned(
      left: 0,
      right: 0,
      bottom: 18,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xE6161A20),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x33FFFFFF)),
          ),
          child: Text(
            "$modeName  ·  tolerance $_tolerance  ·  1/2/3 mode  ·  L loupe  ·  wheel tolerance  ·  "
            "drag box  ·  click copy  ·  R refresh  ·  ESC exit",
            style: const TextStyle(fontSize: 12, letterSpacing: 0.4, color: Color(0xCCFFFFFF)),
          ),
        ),
      ),
    );
  }

  Widget _buildToast() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 58,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xF0284B32),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0x5546D583)),
          ),
          child: Text(
            _toast!,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF9CE7B4)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.snapshot,
    required this.dpr,
    required this.cursorLocal,
    required this.mode,
    required this.tolerance,
    required this.findEdges,
    required this.dragLocal,
    required this.loupeVisible,
  });

  final RulerSnapshot snapshot;
  final double dpr;
  final Offset? cursorLocal;
  final RulerMode mode;
  final int tolerance;
  final ({int left, int right, int up, int down}) Function(int px, int py) findEdges;
  final Rect? dragLocal;
  final bool loupeVisible;

  static const Color _lineColor = Color(0xFFFF4A6A);
  static const Color _boxColor = Color(0xFF39B0FF);

  @override
  void paint(Canvas canvas, Size size) {
    if (dragLocal != null) {
      _paintDragBox(canvas, dragLocal!);
    } else if (cursorLocal != null) {
      _paintCross(canvas);
    }
    if (loupeVisible && cursorLocal != null) {
      _paintLoupe(canvas, size);
    }
  }

  void _paintCross(Canvas canvas) {
    final Offset phys = cursorLocal! * dpr;
    final int px = phys.dx.round().clamp(0, snapshot.width - 1);
    final int py = phys.dy.round().clamp(0, snapshot.height - 1);
    final ({int down, int left, int right, int up}) edges = findEdges(px, py);

    final Paint line = Paint()
      ..color = _lineColor
      ..strokeWidth = 1;

    final double y = py / dpr;
    final double x = px / dpr;

    if (mode == RulerMode.cross || mode == RulerMode.horizontal) {
      final double x1 = edges.left / dpr;
      final double x2 = (edges.right + 1) / dpr;
      canvas.drawLine(Offset(x1, y), Offset(x2, y), line);
      canvas.drawLine(Offset(x1, y - 5), Offset(x1, y + 5), line);
      canvas.drawLine(Offset(x2, y - 5), Offset(x2, y + 5), line);
    }
    if (mode == RulerMode.cross || mode == RulerMode.vertical) {
      final double y1 = edges.up / dpr;
      final double y2 = (edges.down + 1) / dpr;
      canvas.drawLine(Offset(x, y1), Offset(x, y2), line);
      canvas.drawLine(Offset(x - 5, y1), Offset(x + 5, y1), line);
      canvas.drawLine(Offset(x - 5, y2), Offset(x + 5, y2), line);
    }

    final int spanW = edges.right - edges.left + 1;
    final int spanH = edges.down - edges.up + 1;
    final String label = switch (mode) {
      RulerMode.cross => "$spanW × $spanH",
      RulerMode.horizontal => "$spanW px",
      RulerMode.vertical => "$spanH px",
    };
    _paintLabel(canvas, Offset(x + 14, y + 14), label, _lineColor);
  }

  void _paintDragBox(Canvas canvas, Rect rect) {
    final Paint stroke = Paint()
      ..color = _boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint fill = Paint()..color = _boxColor.withAlpha(24);
    canvas.drawRect(rect, fill);
    canvas.drawRect(rect, stroke);

    final Rect phys = Rect.fromPoints(rect.topLeft * dpr, rect.bottomRight * dpr);
    _paintLabel(
      canvas,
      rect.bottomRight + const Offset(10, 10),
      "${phys.width.round()} × ${phys.height.round()}",
      _boxColor,
    );
  }

  void _paintLabel(Canvas canvas, Offset at, String text, Color accent) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final Rect bg = Rect.fromLTWH(at.dx, at.dy, tp.width + 14, tp.height + 8);
    final RRect rr = RRect.fromRectAndRadius(bg, const Radius.circular(5));
    canvas.drawRRect(rr, Paint()..color = const Color(0xE6161A20));
    canvas.drawRRect(
      rr,
      Paint()
        ..color = accent.withAlpha(140)
        ..style = PaintingStyle.stroke,
    );
    tp.paint(canvas, at + const Offset(7, 4));
  }

  void _paintLoupe(Canvas canvas, Size size) {
    const double loupeSize = 132; // logical px, on-screen
    const int sourcePixels = 17; // odd → cursor pixel exactly centered

    final Offset phys = cursorLocal! * dpr;
    final int px = phys.dx.round().clamp(0, snapshot.width - 1);
    final int py = phys.dy.round().clamp(0, snapshot.height - 1);

    // Keep the loupe on-screen, flipping to the other side of the cursor near edges.
    double left = cursorLocal!.dx + 26;
    double top = cursorLocal!.dy + 26;
    if (left + loupeSize + 8 > size.width) left = cursorLocal!.dx - loupeSize - 26;
    if (top + loupeSize + 34 > size.height) top = cursorLocal!.dy - loupeSize - 26 - 20;
    left = left.clamp(4, math.max(4, size.width - loupeSize - 4));
    top = top.clamp(4, math.max(4, size.height - loupeSize - 24));

    final Rect dst = Rect.fromLTWH(left, top, loupeSize, loupeSize);
    final Rect src = Rect.fromLTWH(
      (px - sourcePixels ~/ 2).toDouble(),
      (py - sourcePixels ~/ 2).toDouble(),
      sourcePixels.toDouble(),
      sourcePixels.toDouble(),
    );

    canvas.drawRect(dst.inflate(1), Paint()..color = const Color(0xFF161A20));
    canvas.drawImageRect(
      snapshot.image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.none,
    );

    // Center pixel marker.
    const double cell = loupeSize / sourcePixels;
    final Rect center = Rect.fromLTWH(
      dst.left + (sourcePixels ~/ 2) * cell,
      dst.top + (sourcePixels ~/ 2) * cell,
      cell,
      cell,
    );
    canvas.drawRect(
      center,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawRect(
      dst,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke,
    );

    // Coordinates + hex color of the pixel under the cursor.
    final int rgb = snapshot.pixel(px, py);
    final String hex = "#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}";
    final TextPainter tp = TextPainter(
      text: TextSpan(
        children: <InlineSpan>[
          TextSpan(text: "$px, $py   ", style: const TextStyle(color: Color(0xCCFFFFFF))),
          TextSpan(text: hex, style: TextStyle(color: Color(0xFF000000 | rgb), fontWeight: FontWeight.w700)),
        ],
        style: const TextStyle(fontSize: 11.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect bar = Rect.fromLTWH(dst.left, dst.bottom + 3, dst.width, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bar, const Radius.circular(4)),
      Paint()..color = const Color(0xE6161A20),
    );
    tp.paint(canvas, Offset(bar.left + (bar.width - tp.width) / 2, bar.top + 3));
  }

  @override
  bool shouldRepaint(_RulerPainter oldDelegate) {
    return oldDelegate.cursorLocal != cursorLocal ||
        oldDelegate.mode != mode ||
        oldDelegate.tolerance != tolerance ||
        oldDelegate.dragLocal != dragLocal ||
        oldDelegate.loupeVisible != loupeVisible ||
        oldDelegate.snapshot != snapshot;
  }
}
