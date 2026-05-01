import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/screen_draw_hotkeys.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';

// Adjust this import to your project.

const double outsideBlurSigma = 3.0;
const double outsideDimOpacity = 0.48;
const Duration pollInterval = Duration(milliseconds: 50);
const bool showCapturedMonitorImage = false;

Future<void> startSpotlight() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await Boxes.registerBoxes(justLoad: true);

  const WindowOptions windowOptions = WindowOptions(
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: "Tabame Spotlight",
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
  runApp(const PrivacySpotlightApp());
}

class PrivacySpotlightApp extends StatelessWidget {
  const PrivacySpotlightApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: SpotlightOverlay(),
    );
  }
}

class SpotlightOverlay extends StatefulWidget {
  const SpotlightOverlay({super.key});

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> with TabameListener {
  Timer? _timer;

  int _overlayHwnd = 0;
  int _targetHwnd = 0;

  bool _enabled = true;
  bool _snapshotInProgress = false;
  bool _resizeInProgress = false;

  Rect? _spotlightRect;
  ui.Image? _monitorImage;

  int _monitorImageW = 0;
  int _monitorImageH = 0;

  int currentMonitor = 0;

  Square monitorData = Square(
    x: 0,
    y: 0,
    width: 0,
    height: 0,
  );

  final bool _shouldResize = true;
  double _blurSigma = outsideBlurSigma;
  double _dimOpacity = outsideDimOpacity;

  @override
  void initState() {
    super.initState();
    _blurSigma = Boxes.pref.getDouble('spotlightBlurSigma') ?? outsideBlurSigma;
    _dimOpacity = Boxes.pref.getDouble('spotlightDimOpacity') ?? outsideDimOpacity;

    Monitor.fetchMonitors();
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await checkResize(forceCapture: true);
      _setupOverlayWindow();
      _enableClickThrough();
      await _registerSpotlightHotkeys();
      await _captureMonitorSnapshot(force: true);
      _moveToForegroundWindow();
    });

    Future<void>.delayed(const Duration(milliseconds: 300)).then((_) => _initializeWindowSize());
    _timer = Timer.periodic(pollInterval, (_) => _tick());
  }

  void _initializeWindowSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // await Future<void>.delayed(const Duration(milliseconds: 40));
      if (!mounted) return;
      WidgetsBinding.instance.platformDispatcher.onMetricsChanged?.call();
      final ui.Size size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width + 1, size.height + 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await windowManager.setSize(size);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    NativeHooks.removeListener(this);
    unawaited(NativeHooks.unHook());
    if (_overlayHwnd != 0) {
      unawaited(includeWindowFromCapture(_overlayHwnd));
    }
    _monitorImage?.dispose();
    super.dispose();
  }

  Future<void> checkResize({bool forceCapture = false}) async {
    // return;
    // ignore: dead_code
    if (!_shouldResize || _resizeInProgress) return;

    _resizeInProgress = true;

    final Pointer<POINT> lpPoint = calloc<POINT>();

    try {
      // GetCursorPos(lpPoint);
      final ui.Offset square = Win32.getPosition(hwnd: _targetHwnd);
      lpPoint.ref.x = square.dx.toInt();
      lpPoint.ref.y = square.dy.toInt();

      final int monitor = MonitorFromPoint(
        lpPoint.ref,
        MONITOR_DEFAULTTONEAREST,
      );

      if (forceCapture || monitor != currentMonitor) {
        currentMonitor = monitor;

        final Square? nextMonitorData = Monitor.monitorSizes[monitor];
        if (nextMonitorData == null) return;

        monitorData = nextMonitorData;

        await WindowManager.instance.setPosition(
          Offset(
            monitorData.x.toDouble(),
            monitorData.y.toDouble(),
          ),
        );

        await WindowManager.instance.setSize(
          Size(
            monitorData.width.toDouble(),
            monitorData.height.toDouble(),
          ),
        );

        _setupOverlayWindow();
        _enableClickThrough();

        if (_enabled) {
          await _captureMonitorSnapshot(force: true);
        }
      }
    } finally {
      calloc.free(lpPoint);
      _resizeInProgress = false;
    }
  }

  int skip = 0;
  final double _stepsSkipped = (20 / pollInterval.inMilliseconds);
  void _tick() {
    checkResize();
    if (!_enabled || _targetHwnd == 0) return;
    skip++;
    if (skip >= _stepsSkipped) {
      skip = 0;
      _captureMonitorSnapshot(force: true);
    }

    final Rect? screenRect = _getWindowRect(_targetHwnd);
    if (screenRect == null) return;

    final Rect localRect = _screenRectToMonitorLocal(screenRect);

    if (_spotlightRect != localRect && mounted) {
      setState(() => _spotlightRect = localRect);
    }
  }

  Rect _screenRectToMonitorLocal(Rect screenRect) {
    return screenRect.shift(
      Offset(
        -monitorData.x.toDouble(),
        -monitorData.y.toDouble(),
      ),
    );
  }

  Future<void> _toggleEnabled() async {
    _initializeWindowSize();
    if (_enabled) {
      setState(() {
        _enabled = false;
        _spotlightRect = null;
      });
      return;
    }

    setState(() => _enabled = true);

    await _captureMonitorSnapshot(force: true);
    _moveToForegroundWindow();
  }

  Future<void> _setActiveWindowFromHotkey() async {
    _enabled = true;
    _initializeWindowSize();
    await _captureMonitorSnapshot(force: true);
    _moveToForegroundWindow();
  }

  void _adjustBlurSigma(double delta) {
    _blurSigma = (_blurSigma + delta).clamp(0.0, 80.0);
    Boxes.pref.setDouble('spotlightBlurSigma', _blurSigma);
    setState(() {});
  }

  void _adjustDimOpacity(double delta) {
    _dimOpacity = (_dimOpacity + delta).clamp(0.0, 0.90);
    Boxes.pref.setDouble('spotlightDimOpacity', _dimOpacity);
    setState(() {});
  }

  Future<void> _registerSpotlightHotkeys() async {
    final List<Map<String, dynamic>> hotkeys = <Map<String, dynamic>>[];
    for (final ScreenDrawHotkeyBinding binding in Boxes.screenDrawHotkeys) {
      if (!binding.enabled || !binding.isSpotlight) continue;
      final int? keyVk = keyMap["VK_${binding.key.toUpperCase()}"];
      if (keyVk == null) continue;
      hotkeys.add(<String, dynamic>{
        "name": binding.actionId,
        "hotkey": binding.hotkey.toUpperCase(),
        "keyVK": keyVk,
        "modifisers":
            binding.modifiers.isNotEmpty ? Hotkeys.normalizeModifiers(binding.modifiers).join('+') : "noModifiers",
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
      });
    }
    await NativeHooks.runHotkeys(hotkeys);
  }

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    if (hotkeyInfo.action != "releaseKbd") return;
    final ScreenDrawHotkeyBinding? binding = Boxes.screenDrawHotkeys.cast<ScreenDrawHotkeyBinding?>().firstWhere(
          (ScreenDrawHotkeyBinding? item) => item != null && item.isSpotlight && item.hotkey == hotkeyInfo.hotkey,
          orElse: () => null,
        );
    switch (binding?.action) {
      case ScreenDrawHotkeyAction.spotlightEnable:
        unawaited(_toggleEnabled());
      case ScreenDrawHotkeyAction.spotlightSetActiveWindow:
        unawaited(_setActiveWindowFromHotkey());
      case ScreenDrawHotkeyAction.spotlightRaiseBlurSigma:
        _adjustBlurSigma(1.3);
      case ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma:
        _adjustBlurSigma(-1.3);
      case ScreenDrawHotkeyAction.spotlightRaiseDimOpacity:
        _adjustDimOpacity(0.03);
      case ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity:
        _adjustDimOpacity(-0.03);
      case ScreenDrawHotkeyAction.spotlightClose:
        unawaited(windowManager.close());
      case ScreenDrawHotkeyAction.closeScreenDraw:
      case ScreenDrawHotkeyAction.toggleDrawing:
      case ScreenDrawHotkeyAction.toggleVisibility:
      case null:
        return;
    }
  }

  void _moveToForegroundWindow() {
    final int foreground = GetForegroundWindow();

    if (foreground == 0) return;
    if (foreground == _overlayHwnd) return;

    _targetHwnd = foreground;

    final Rect? screenRect = _getWindowRect(_targetHwnd);
    if (screenRect == null) return;

    final Rect localRect = _screenRectToMonitorLocal(screenRect);

    if (mounted) {
      setState(() {
        _enabled = true;
        _spotlightRect = localRect;
      });
    }
  }

  Rect? _getWindowRect(int hwnd) {
    if (hwnd == 0) return null;
    if (IsWindow(hwnd) == 0) return null;
    if (IsIconic(hwnd) != 0) return null;

    final Pointer<RECT> rect = calloc<RECT>();

    try {
      if (GetWindowRect(hwnd, rect) == 0) return null;
      final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(hwnd);

      return Rect.fromLTRB(
        (rect.ref.left + border.left).toDouble(),
        (rect.ref.top + border.top).toDouble(),
        (rect.ref.right - border.right).toDouble(),
        (rect.ref.bottom - border.bottom).toDouble(),
      );
    } finally {
      calloc.free(rect);
    }
  }

  Future<void> _captureMonitorSnapshot({bool force = false}) async {
    if (_snapshotInProgress) return;
    if (!_enabled && !force) return;
    if (_overlayHwnd == 0) return;

    _snapshotInProgress = true;

    try {
      final int monitorIndex = (Monitor.monitorIds[currentMonitor] ?? 1) - 1;
      final MonitorCapture? capture = await captureMonitor(monitorIndex: monitorIndex);
      final Uint8List? bytes = capture == null ? null : _bgraToRgba(capture.pixels);

      if (bytes == null) return;

      final ui.Image image = await _decodeRgbaImage(
        bytes,
        capture!.width,
        capture.height,
      );

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

  Future<ui.Image> _decodeRgbaImage(
    Uint8List bytes,
    int width,
    int height,
  ) {
    final Completer<ui.Image> completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

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

    SetWindowPos(
      _overlayHwnd,
      HWND_TOPMOST,
      monitorData.x,
      monitorData.y,
      monitorData.width,
      monitorData.height,
      SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  void _enableClickThrough() {
    if (_overlayHwnd == 0) return;

    final int exStyle = GetWindowLongPtr(_overlayHwnd, GWL_EXSTYLE);

    SetWindowLongPtr(
      _overlayHwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
    );

    SetLayeredWindowAttributes(_overlayHwnd, 0, 255, LWA_ALPHA);

    SetWindowPos(
      _overlayHwnd,
      HWND_TOPMOST,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: true,
      child: Material(
        color: Colors.transparent,
        child: showCapturedMonitorImage
            ? RawImage(
                image: _monitorImage,
                fit: BoxFit.fill,
                width: double.infinity,
                height: double.infinity,
              )
            : CustomPaint(
                painter: _PrivacySpotlightPainter(
                  enabled: _enabled,
                  bgImage: _monitorImage,
                  bgImageW: _monitorImageW,
                  bgImageH: _monitorImageH,
                  spotlightRect: _spotlightRect,
                  blurSigma: _blurSigma,
                  dimOpacity: _dimOpacity,
                ),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _PrivacySpotlightPainter extends CustomPainter {
  final bool enabled;
  final ui.Image? bgImage;
  final int bgImageW;
  final int bgImageH;
  final Rect? spotlightRect;
  final double blurSigma;
  final double dimOpacity;

  const _PrivacySpotlightPainter({
    required this.enabled,
    required this.bgImage,
    required this.bgImageW,
    required this.bgImageH,
    required this.spotlightRect,
    required this.blurSigma,
    required this.dimOpacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled) return;

    final Rect? spotRect = spotlightRect;
    if (spotRect == null) return;

    final Rect full = Offset.zero & size;

    final Path outside = Path()
      ..addRect(full)
      ..addRect(spotRect)
      ..fillType = PathFillType.evenOdd;

    if (bgImage != null) {
      final Rect src = Rect.fromLTWH(
        0,
        0,
        bgImageW.toDouble(),
        bgImageH.toDouble(),
      );

      canvas.save();
      canvas.clipPath(outside);

      canvas.saveLayer(
        full,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: blurSigma,
            sigmaY: blurSigma + (blurSigma * 0.06),
            tileMode: TileMode.clamp,
          ),
      );

      canvas.drawImageRect(
        bgImage!,
        src,
        full,
        Paint()..filterQuality = FilterQuality.high,
      );

      canvas.restore();

      canvas.drawPath(
        outside,
        Paint()..color = Colors.black.withValues(alpha: dimOpacity),
      );

      canvas.restore();
    } else {
      canvas.drawPath(
        outside,
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
    }

    canvas.drawRect(
      spotRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PrivacySpotlightPainter old) {
    return old.enabled != enabled ||
        old.bgImage != bgImage ||
        old.bgImageW != bgImageW ||
        old.bgImageH != bgImageH ||
        old.spotlightRect != spotlightRect ||
        old.blurSigma != blurSigma ||
        old.dimOpacity != dimOpacity;
  }
}
