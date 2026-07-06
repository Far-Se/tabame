import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/win32/mixed.dart';

/// Presentation Toolkit overlay.
///
/// A single always-on-top, click-through overlay that follows the cursor's
/// monitor and offers three teaching/screencast tools, switched via global
/// hotkeys (the window is click-through + no-activate, so it never steals input
/// from the app being demoed — controls therefore go through [NativeHooks]):
///
///  * Spotlight  — dim everything except a soft circle around the cursor.
///  * Magnifier  — a live magnified lens under the cursor (samples a WGC frame).
///  * Ruler      — a crosshair + pixel readout; drop an anchor to measure.
///
/// Reuses the monitor-capture + click-through scaffolding proven in
/// `spotlight.dart`.
const Duration _pollInterval = Duration(milliseconds: 33);
const double _minSpotRadius = 60.0;
const double _maxSpotRadius = 500.0;
const double _minZoom = 1.5;
const double _maxZoom = 6.0;

enum PresentTool { off, spotlight, magnifier, ruler }

Future<void> startPresentMode() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();
  await windowManager.ensureInitialized();
  await Boxes.registerBoxes(justLoad: true);

  const WindowOptions windowOptions = WindowOptions(
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: "Tabame Present Mode",
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.maximize();
    await windowManager.setHasShadow(false);
    await windowManager.show();
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.platformDispatcher.onMetricsChanged?.call();
  });
  runApp(const PresentModeApp());
}

class PresentModeApp extends StatelessWidget {
  const PresentModeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: PresentOverlay(),
    );
  }
}

class PresentOverlay extends StatefulWidget {
  const PresentOverlay({super.key});

  @override
  State<PresentOverlay> createState() => _PresentOverlayState();
}

class _PresentOverlayState extends State<PresentOverlay> with TabameListener {
  Timer? _timer;
  Timer? _captureTimer;

  int _overlayHwnd = 0;
  int _currentMonitor = 0;
  bool _resizeInProgress = false;
  bool _snapshotInProgress = false;

  Square _monitorData = Square(x: 0, y: 0, width: 0, height: 0);

  Offset _cursor = Offset.zero; // monitor-local
  PresentTool _tool = PresentTool.spotlight;

  double _spotRadius = 160.0;
  double _zoom = 2.5;

  Offset? _anchor; // monitor-local, for ruler measuring

  ui.Image? _monitorImage;
  int _monitorImageW = 0;
  int _monitorImageH = 0;

  @override
  void initState() {
    super.initState();
    _spotRadius = Boxes.pref.getDouble('presentSpotRadius') ?? 160.0;
    _zoom = Boxes.pref.getDouble('presentZoom') ?? 2.5;

    Monitor.fetchMonitors();
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkResize(force: true);
      _setupOverlayWindow();
      _enableClickThrough();
      await _registerHotkeys();
      await _captureMonitorSnapshot();
    });

    _timer = Timer.periodic(_pollInterval, (_) => _tick());
    _captureTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (_tool == PresentTool.magnifier) unawaited(_captureMonitorSnapshot());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _captureTimer?.cancel();
    NativeHooks.removeListener(this);
    unawaited(NativeHooks.unHook());
    if (_overlayHwnd != 0) unawaited(includeWindowFromCapture(_overlayHwnd));
    _monitorImage?.dispose();
    super.dispose();
  }

  // ---- Cursor + monitor tracking ------------------------------------------
  void _tick() {
    _checkResize();
    final Pointer<POINT> lpPoint = calloc<POINT>();
    try {
      GetCursorPos(lpPoint);
      final Offset local = Offset(
        (lpPoint.ref.x - _monitorData.x).toDouble(),
        (lpPoint.ref.y - _monitorData.y).toDouble(),
      );
      if (local != _cursor && mounted) setState(() => _cursor = local);
    } finally {
      calloc.free(lpPoint);
    }
  }

  Future<void> _checkResize({bool force = false}) async {
    if (_resizeInProgress) return;
    _resizeInProgress = true;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    try {
      GetCursorPos(lpPoint);
      final int monitor = MonitorFromPoint(lpPoint.ref, MONITOR_DEFAULTTONEAREST);
      if (!force && monitor == _currentMonitor) return;
      _currentMonitor = monitor;
      final Square? next = Monitor.monitorSizes[monitor];
      if (next == null) return;
      _monitorData = next;
      await WindowManager.instance.setPosition(Offset(next.x.toDouble(), next.y.toDouble()));
      await WindowManager.instance.setSize(Size(next.width.toDouble(), next.height.toDouble()));
      _setupOverlayWindow();
      _enableClickThrough();
      await _captureMonitorSnapshot();
    } finally {
      calloc.free(lpPoint);
      _resizeInProgress = false;
    }
  }

  // ---- Global hotkeys ------------------------------------------------------
  Future<void> _registerHotkeys() async {
    List<Map<String, dynamic>> hk(String name, int vk, String keyLabel) {
      final List<String> mods = Hotkeys.normalizeModifiers(<String>['CTRL', 'ALT']);
      return <Map<String, dynamic>>[
        <String, dynamic>{
          "name": name,
          "hotkey": "${mods.join('+')}+$keyLabel".toUpperCase(),
          "keyVK": vk,
          "modifisers": mods.join('+'),
          "listenToMovement": false,
          "matchWindowBy": "",
          "matchWindowText": "",
          "activateWindowUnderCursor": false,
          "noopScreenBusy": false,
          "prohibitedWindows": "",
          "regionasPercentage": false,
          "regionOnScreen": false,
          "regionX1": 0,
          "regionX2": 0,
          "regionY1": 0,
          "regionY2": 0,
          "anchorType": 0,
        }
      ];
    }

    final List<Map<String, dynamic>> hotkeys = <Map<String, dynamic>>[
      ...hk('present_spotlight', 0x53, 'S'), // Ctrl+Alt+S
      ...hk('present_magnifier', 0x5A, 'Z'), // Ctrl+Alt+Z
      ...hk('present_ruler', 0x52, 'R'), // Ctrl+Alt+R
      ...hk('present_anchor', 0x41, 'A'), // Ctrl+Alt+A
      ...hk('present_increase', 0xBB, 'OEM_PLUS'), // Ctrl+Alt+Plus
      ...hk('present_decrease', 0xBD, 'OEM_MINUS'), // Ctrl+Alt+Minus
      ...hk('present_quit', 0x51, 'Q'), // Ctrl+Alt+Q
    ];
    await NativeHooks.runHotkeys(hotkeys);
  }

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    if (hotkeyInfo.action != "releaseKbd") return;
    switch (hotkeyInfo.name) {
      case 'present_spotlight':
        setState(() => _tool = _tool == PresentTool.spotlight ? PresentTool.off : PresentTool.spotlight);
      case 'present_magnifier':
        setState(() => _tool = _tool == PresentTool.magnifier ? PresentTool.off : PresentTool.magnifier);
        if (_tool == PresentTool.magnifier) unawaited(_captureMonitorSnapshot());
      case 'present_ruler':
        setState(() {
          _tool = _tool == PresentTool.ruler ? PresentTool.off : PresentTool.ruler;
          _anchor = null;
        });
      case 'present_anchor':
        if (_tool == PresentTool.ruler) {
          setState(() => _anchor = _anchor == null ? _cursor : null);
        }
      case 'present_increase':
        _adjust(1);
      case 'present_decrease':
        _adjust(-1);
      case 'present_quit':
        unawaited(windowManager.close());
    }
  }

  void _adjust(int dir) {
    setState(() {
      if (_tool == PresentTool.magnifier) {
        _zoom = (_zoom + dir * 0.25).clamp(_minZoom, _maxZoom);
        Boxes.pref.setDouble('presentZoom', _zoom);
      } else {
        _spotRadius = (_spotRadius + dir * 20).clamp(_minSpotRadius, _maxSpotRadius);
        Boxes.pref.setDouble('presentSpotRadius', _spotRadius);
      }
    });
  }

  // ---- Monitor snapshot (for the magnifier lens) --------------------------
  Future<void> _captureMonitorSnapshot() async {
    if (_snapshotInProgress || _overlayHwnd == 0) return;
    _snapshotInProgress = true;
    try {
      final int monitorIndex = (Monitor.monitorIds[_currentMonitor] ?? 1) - 1;
      final MonitorCapture? capture = await captureMonitor(monitorIndex: monitorIndex);
      if (capture == null) return;
      final ui.Image image = await _decodeRgbaImage(_bgraToRgba(capture.pixels), capture.width, capture.height);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _monitorImage?.dispose();
        _monitorImage = image;
        _monitorImageW = capture.width;
        _monitorImageH = capture.height;
      });
    } finally {
      _enableClickThrough();
      _snapshotInProgress = false;
    }
  }

  Future<ui.Image> _decodeRgbaImage(Uint8List bytes, int width, int height) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  Uint8List _bgraToRgba(Uint8List bgra) {
    final Uint8List rgba = Uint8List(bgra.length);
    for (int i = 0; i < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2];
      rgba[i + 1] = bgra[i + 1];
      rgba[i + 2] = bgra[i];
      rgba[i + 3] = 255;
    }
    return rgba;
  }

  // ---- Native window styling (click-through, no-activate, topmost) ---------
  void _setupOverlayWindow() {
    _overlayHwnd = GetAncestor(GetActiveWindow(), GA_ROOT);
    if (_overlayHwnd == 0) return;
    final int style = GetWindowLongPtr(_overlayHwnd, GWL_STYLE);
    SetWindowLongPtr(
      _overlayHwnd,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );
    final int exStyle = GetWindowLongPtr(_overlayHwnd, GWL_EXSTYLE);
    SetWindowLongPtr(
      _overlayHwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
    );
    SetLayeredWindowAttributes(_overlayHwnd, 0, 255, LWA_ALPHA);
    unawaited(excludeWindowFromCapture(_overlayHwnd));
    SetWindowPos(_overlayHwnd, HWND_TOPMOST, _monitorData.x, _monitorData.y, _monitorData.width, _monitorData.height,
        SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }

  void _enableClickThrough() {
    if (_overlayHwnd == 0) return;
    final int exStyle = GetWindowLongPtr(_overlayHwnd, GWL_EXSTYLE);
    SetWindowLongPtr(_overlayHwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
    SetLayeredWindowAttributes(_overlayHwnd, 0, 255, LWA_ALPHA);
    SetWindowPos(_overlayHwnd, HWND_TOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: <Widget>[
            CustomPaint(
              painter: _PresentPainter(
                tool: _tool,
                cursor: _cursor,
                spotRadius: _spotRadius,
                zoom: _zoom,
                anchor: _anchor,
                bgImage: _monitorImage,
                bgImageW: _monitorImageW,
                bgImageH: _monitorImageH,
              ),
              child: const SizedBox.expand(),
            ),
            const _PresentHud(),
          ],
        ),
      ),
    );
  }
}

/// Small always-visible hint of the active hotkeys, top-left.
class _PresentHud extends StatelessWidget {
  const _PresentHud();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      top: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: const Text(
          "Ctrl+Alt · S spotlight · Z magnifier · R ruler (A anchor) · +/- size · Q quit",
          style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _PresentPainter extends CustomPainter {
  final PresentTool tool;
  final Offset cursor;
  final double spotRadius;
  final double zoom;
  final Offset? anchor;
  final ui.Image? bgImage;
  final int bgImageW;
  final int bgImageH;

  const _PresentPainter({
    required this.tool,
    required this.cursor,
    required this.spotRadius,
    required this.zoom,
    required this.anchor,
    required this.bgImage,
    required this.bgImageW,
    required this.bgImageH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (tool) {
      case PresentTool.off:
        return;
      case PresentTool.spotlight:
        _paintSpotlight(canvas, size);
      case PresentTool.magnifier:
        _paintMagnifier(canvas, size);
      case PresentTool.ruler:
        _paintRuler(canvas, size);
    }
  }

  void _paintSpotlight(Canvas canvas, Size size) {
    final Rect full = Offset.zero & size;
    final Path outside = Path()
      ..addRect(full)
      ..addOval(Rect.fromCircle(center: cursor, radius: spotRadius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.55));
    // Soft ring around the lit circle.
    canvas.drawCircle(
      cursor,
      spotRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _paintMagnifier(Canvas canvas, Size size) {
    if (bgImage == null || bgImageW == 0) return;
    final double lensR = spotRadius * 0.9;
    // Scale from monitor-local logical pixels to captured-image pixels.
    final double sx = bgImageW / size.width;
    final double sy = bgImageH / size.height;
    final double srcR = lensR / zoom;
    final Rect src = Rect.fromCircle(
      center: Offset(cursor.dx * sx, cursor.dy * sy),
      radius: srcR * math.max(sx, sy),
    );
    final Rect dst = Rect.fromCircle(center: cursor, radius: lensR);
    canvas.save();
    canvas.clipPath(Path()..addOval(dst));
    canvas.drawImageRect(bgImage!, src, dst, Paint()..filterQuality = FilterQuality.high);
    canvas.restore();
    canvas.drawCircle(
      cursor,
      lensR,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  void _paintRuler(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..strokeWidth = 1;
    // Full-screen crosshair through the cursor.
    canvas.drawLine(Offset(0, cursor.dy), Offset(size.width, cursor.dy), line);
    canvas.drawLine(Offset(cursor.dx, 0), Offset(cursor.dx, size.height), line);

    String label = "${cursor.dx.toInt()}, ${cursor.dy.toInt()} px";
    final Offset? a = anchor;
    if (a != null) {
      final Paint measure = Paint()
        ..color = const Color(0xFFFFD54F)
        ..strokeWidth = 2;
      canvas.drawLine(a, cursor, measure);
      canvas.drawCircle(a, 4, Paint()..color = const Color(0xFFFFD54F));
      final double dist = (cursor - a).distance;
      final double angle = math.atan2(cursor.dy - a.dy, cursor.dx - a.dx) * 180 / math.pi;
      label = "${dist.toStringAsFixed(1)} px  ·  ${angle.toStringAsFixed(1)}°  ·  "
          "Δ${(cursor.dx - a.dx).toInt()},${(cursor.dy - a.dy).toInt()}";
    }
    _paintLabel(canvas, label, cursor + const Offset(14, 14));
  }

  void _paintLabel(Canvas canvas, String text, Offset at) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final Rect bg = Rect.fromLTWH(at.dx - 5, at.dy - 3, tp.width + 10, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bg, const Radius.circular(4)),
      Paint()..color = Colors.black.withValues(alpha: 0.75),
    );
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_PresentPainter old) {
    return old.tool != tool ||
        old.cursor != cursor ||
        old.spotRadius != spotRadius ||
        old.zoom != zoom ||
        old.anchor != anchor ||
        old.bgImage != bgImage;
  }
}
