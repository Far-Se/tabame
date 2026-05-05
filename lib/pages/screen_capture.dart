// main.dart
// Flutter Windows Screen Capture + Photo Editor
// Features:
//   - Monitor-aware screen region capture
//   - Post-capture modal: Copy to Clipboard / Copy File / Open Editor
//   - Saves to %localappdata%\Tabame\screenshots
//   - Full photo editor with all annotation tools when "Open Editor" is pressed
//
// Dependencies (pubspec.yaml):
//   ffi: ^2.1.0
//   win32: ^5.5.4
//   window_manager: ^0.3.9
//   image: ^4.2.0
//   tabamewin32: ^1.0.0   (for captureMonitor / ClipboardExtended)
//   path_provider: ^2.1.4
//   flutter_colorpicker: ^1.1.0

// ignore_for_file: unused_element, dead_code

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/widgets/color_picker.dart';
import '../widgets/widgets/custom_tooltip.dart';
import '../widgets/widgets/emoji_picker_modal.dart';
import '../widgets/widgets/font_picker/models/picker_font.dart';
import '../widgets/widgets/font_picker/ui/font_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> startScreenCapture({bool freezeMode = false}) async {
  WidgetsFlutterBinding.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(400, 400),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
    title: 'Tabame Screen Capture',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await Boxes.registerBoxes(justLoad: true);
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
    Win32Window._hwnd = GetAncestor(GetActiveWindow(), 2);
  });

  runApp(ScreenCaptureApp(freezeMode: freezeMode));
}

// ─────────────────────────────────────────────────────────────────────────────
// App state: which view is active
// ─────────────────────────────────────────────────────────────────────────────

enum AppView { capture, editor }

enum CaptureActionMode {
  ask,
  copyImageToClipboard,
  copyImageFileToClipboard,
  openPhotoEditor,
}

class CaptureActionChoice {
  const CaptureActionChoice({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.mode,
    this.uploadHost,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final CaptureActionMode? mode;
  final ScreenCaptureUploadHost? uploadHost;

  static const String askId = 'builtin:ask';
  static const String copyImageId = 'builtin:copy-image';
  static const String copyFileId = 'builtin:copy-file';
  static const String openEditorId = 'builtin:open-editor';

  static const List<CaptureActionChoice> builtIn = <CaptureActionChoice>[
    CaptureActionChoice(
      id: askId,
      mode: CaptureActionMode.ask,
      title: 'Ask',
      subtitle: 'Show the action popup after each capture',
      icon: Icons.help_outline,
    ),
    CaptureActionChoice(
      id: copyImageId,
      mode: CaptureActionMode.copyImageToClipboard,
      title: 'Copy Image to Clipboard',
      subtitle: 'Copy the captured bitmap and close',
      icon: Icons.image_outlined,
    ),
    CaptureActionChoice(
      id: copyFileId,
      mode: CaptureActionMode.copyImageFileToClipboard,
      title: 'Copy Image File to Clipboard',
      subtitle: 'Copy the saved screenshot file and close',
      icon: Icons.file_copy_outlined,
    ),
    CaptureActionChoice(
      id: openEditorId,
      mode: CaptureActionMode.openPhotoEditor,
      title: 'Open Photo Editor',
      subtitle: 'Open the screenshot directly in the editor',
      icon: Icons.edit_outlined,
    ),
  ];

  static String uploadHostId(String hostId) => 'upload:$hostId';

  static String fromLegacyMode(CaptureActionMode mode) {
    switch (mode) {
      case CaptureActionMode.ask:
        return askId;
      case CaptureActionMode.copyImageToClipboard:
        return copyImageId;
      case CaptureActionMode.copyImageFileToClipboard:
        return copyFileId;
      case CaptureActionMode.openPhotoEditor:
        return openEditorId;
    }
  }
}

class AppState extends ChangeNotifier {
  AppView view = AppView.capture;
  String? capturedFilePath;
  Uint8List? capturedImageBytes;
  int capturedW = 0;
  int capturedH = 0;

  void openEditor(String filePath, Uint8List bytes, int w, int h) {
    capturedFilePath = filePath;
    capturedImageBytes = bytes;
    capturedW = w;
    capturedH = h;
    view = AppView.editor;
    notifyListeners();
  }

  void backToCapture() {
    view = AppView.capture;
    notifyListeners();
  }
}

final AppState appState = AppState();

// ─────────────────────────────────────────────────────────────────────────────
// Win32 helpers
// ─────────────────────────────────────────────────────────────────────────────

class Win32Window {
  static int _hwnd = 0;

  static int getHwnd() {
    if (_hwnd != 0) return _hwnd;
    _hwnd = GetAncestor(GetActiveWindow(), 2);
    return _hwnd;
  }

  static void setupOverlay() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;

    final int style = GetWindowLongPtr(hwnd, GWL_STYLE);
    SetWindowLongPtr(
      hwnd,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(
      hwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TOPMOST, //| WS_EX_TOOLWINDOW,
    );

    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    final int screenW = GetSystemMetrics(SM_CXSCREEN);
    final int screenH = GetSystemMetrics(SM_CYSCREEN);
    SetWindowPos(
      hwnd,
      HWND_TOPMOST,
      0,
      0,
      screenW,
      screenH,
      SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  static void enableClickThrough() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;
    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE);
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }

  static void disableClickThrough() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;
    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT & ~WS_EX_LAYERED & ~WS_EX_NOACTIVATE);
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen capture helpers
// ─────────────────────────────────────────────────────────────────────────────

class ScreenCapture {
  /// Capture a screen region (screen coords) → PNG bytes
  static Future<Uint8List?> captureRegionToPng(Rect screenRect) async {
    final int x = screenRect.left.round();
    final int y = screenRect.top.round();
    final int w = screenRect.width.round().clamp(1, 1000000);
    final int h = screenRect.height.round().clamp(1, 1000000);

    final int screenDc = GetDC(NULL);
    final int memDc = CreateCompatibleDC(screenDc);
    final int bmp = CreateCompatibleBitmap(screenDc, w, h);
    SelectObject(memDc, bmp);
    BitBlt(memDc, 0, 0, w, h, screenDc, x, y, SRCCOPY);

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

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  static Future<void> copyPngToClipboard(Uint8List pngBytes) async {
    ClipboardExtended.copyImage(pngBytes);
  }

  static Future<void> copyFileToClipboard(String filePath) async {
    ClipboardExtension.copyFile(filePath);
  }

  /// Save PNG to %localappdata%\Tabame\screenshots\<timestamp>.png
  static Future<String> saveToFile(Uint8List pngBytes) async {
    final DateTime date = DateTime.now();

    String shortMonth = intl.DateFormat('MMM').format(date);

    final Directory dir = Directory('${WinUtils.getTabameAppDataFolder()}\\screenshots\\${date.year} - $shortMonth');
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final String ts =
        DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-').replaceFirst(RegExp(r'^.*?T'), '');
    final String path = '${dir.path}\\$ts.png';
    await File(path).writeAsBytes(pngBytes);
    return path;
  }

  static Future<_FrozenMonitorSnapshot?> captureMonitorSnapshot(int monitorHandle) async {
    Monitor.fetchMonitors();
    final Square? monitorBounds = Monitor.monitorSizes[monitorHandle];
    if (monitorBounds == null) return null;

    final int? monitorNumber = Monitor.monitorIds[monitorHandle];
    if (monitorNumber == null || monitorNumber <= 0) return null;

    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      await excludeWindowFromCapture(hwnd);
    }

    final MonitorCapture? capture = await captureMonitor(monitorIndex: monitorNumber - 1);
    if (capture == null || capture.width <= 0 || capture.height <= 0 || capture.pixels.isEmpty) {
      return null;
    }

    return _FrozenMonitorSnapshot(
      monitorHandle: monitorHandle,
      screenRect: Rect.fromLTWH(
        monitorBounds.x.toDouble(),
        monitorBounds.y.toDouble(),
        monitorBounds.width.toDouble(),
        monitorBounds.height.toDouble(),
      ),
      rgbaBytes: _bgraToRgba(capture.pixels),
      pixelWidth: capture.width,
      pixelHeight: capture.height,
    );
  }

  static Uint8List encodeRgbaToPng(Uint8List rgbaBytes, int width, int height) {
    final img.Image image = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgbaBytes.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    return Uint8List.fromList(img.encodePng(image));
  }

  static Uint8List _bgraToRgba(Uint8List bgraBytes) {
    final Uint8List rgbaBytes = Uint8List(bgraBytes.length);
    for (int i = 0; i < bgraBytes.length; i += 4) {
      rgbaBytes[i] = bgraBytes[i + 2];
      rgbaBytes[i + 1] = bgraBytes[i + 1];
      rgbaBytes[i + 2] = bgraBytes[i];
      rgbaBytes[i + 3] = 255;
    }
    return rgbaBytes;
  }
}

class _FrozenMonitorSnapshot {
  const _FrozenMonitorSnapshot({
    required this.monitorHandle,
    required this.screenRect,
    required this.rgbaBytes,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final int monitorHandle;
  final Rect screenRect;
  final Uint8List rgbaBytes;
  final int pixelWidth;
  final int pixelHeight;
}

// ─────────────────────────────────────────────────────────────────────────────
// Root app widget
// ─────────────────────────────────────────────────────────────────────────────

class ScreenCaptureApp extends StatelessWidget {
  const ScreenCaptureApp({
    super.key,
    required this.freezeMode,
  });

  final bool freezeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: AppShell(freezeMode: freezeMode),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.freezeMode,
  });

  final bool freezeMode;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Timer? _monitorTimer;
  int _currentMonitor = -1;
  Square _monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  AppView _lastView = appState.view;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Win32Window.setupOverlay();
      Win32Window.disableClickThrough();
    });
    Monitor.fetchMonitors();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _checkMonitor());
    appState.addListener(_handleAppStateChanged);
    unawaited(_syncWindowForView(appState.view));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      WidgetsBinding.instance.platformDispatcher.onMetricsChanged?.call();
      final ui.Size size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width + 1, size.height + 1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await windowManager.setSize(size);
    });
  }

  void _handleAppStateChanged() {
    if (_lastView == appState.view) return;
    _lastView = appState.view;
    unawaited(_syncWindowForView(appState.view));
  }

  Future<void> _syncWindowForView(AppView view) async {
    if (!mounted) return;
    if (view == AppView.editor) {
      Win32Window.disableClickThrough();
      await windowManager.setAlwaysOnTop(false);
      final double maxWidth = (_monitorData.width > 0 ? _monitorData.width : 1600).toDouble();
      final double maxHeight = (_monitorData.height > 0 ? _monitorData.height : 1000).toDouble();
      final double preferredWidth = (appState.capturedW + 360).clamp(980, maxWidth * 0.92).toDouble();
      final double preferredHeight = (appState.capturedH + 240).clamp(720, maxHeight * 0.9).toDouble();
      final Size editorSize = Size(preferredWidth, preferredHeight);
      await windowManager.setHasShadow(true);
      await windowManager.setMinimumSize(const Size(980, 720));
      await windowManager.setSize(editorSize);
      if (_monitorData.width > 0 && _monitorData.height > 0) {
        final double left = _monitorData.x + ((_monitorData.width - editorSize.width) / 2);
        final double top = _monitorData.y + ((_monitorData.height - editorSize.height) / 2);
        await windowManager.setPosition(Offset(left, top), animate: false);
      } else {
        await windowManager.center();
      }
      await windowManager.show();
      await windowManager.focus();
      return;
    }

    await windowManager.setHasShadow(false);
    await windowManager.setMinimumSize(const Size(200, 200));
    Win32Window.setupOverlay();
    await _checkMonitor(force: true);
    Win32Window.disableClickThrough();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _checkMonitor({bool force = false}) async {
    if (!mounted || (appState.view == AppView.editor && !force)) return;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);

    if (force || monitor != _currentMonitor) {
      _currentMonitor = monitor;
      final Square? m = Monitor.monitorSizes[monitor];
      if (m != null) {
        _monitorData = m;
        await WindowManager.instance.setPosition(Offset(_monitorData.x.toDouble(), _monitorData.y.toDouble()));
        await WindowManager.instance.setSize(Size(_monitorData.width.toDouble(), _monitorData.height.toDouble()));
      }
    }
  }

  @override
  void dispose() {
    appState.removeListener(_handleAppStateChanged);
    _monitorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: appState,
        builder: (_, __) {
          if (appState.view == AppView.editor) {
            return PhotoEditorView(
              initialImageBytes: appState.capturedImageBytes!,
              imageW: appState.capturedW,
              imageH: appState.capturedH,
              filePath: appState.capturedFilePath!,
            );
          }
          return ScreenCaptureView(freezeMode: widget.freezeMode);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen Capture View
// ─────────────────────────────────────────────────────────────────────────────

class ScreenCaptureView extends StatefulWidget {
  const ScreenCaptureView({
    super.key,
    required this.freezeMode,
  });

  final bool freezeMode;

  @override
  State<ScreenCaptureView> createState() => _ScreenCaptureViewState();
}

class _ScreenCaptureViewState extends State<ScreenCaptureView> {
  String _captureActionId = CaptureActionChoice.askId;
  List<FancyShotProfile> _fancyShotProfiles = <FancyShotProfile>[];
  List<ScreenCaptureUploadHost> _uploadHosts = <ScreenCaptureUploadHost>[];
  String? _selectedFancyShotPresetName;
  Offset? _captureStart;
  Offset? _captureCurrent;
  bool _capturing = false;
  bool _captureEnabled = true;
  bool _applyingPreset = false;
  Timer? _tickerTimer;
  final Set<String> _pressedScreenCaptureHotkeys = <String>{};
  final Map<int, _FrozenMonitorSnapshot> _frozenMonitorSnapshots = <int, _FrozenMonitorSnapshot>{};
  Future<void>? _frozenSnapshotWarmup;

  @override
  void initState() {
    super.initState();
    _fancyShotProfiles = FancyShot.loadProfiles();
    _uploadHosts = FancyShot.loadUploadHosts();
    final String? savedActionId = Boxes.pref.getString("screenCaptureModeKey");
    if (savedActionId != null && _captureChoices().any((CaptureActionChoice choice) => choice.id == savedActionId)) {
      _captureActionId = savedActionId;
    } else {
      final int legacyIndex = Boxes.pref.getInt("screenCaptureMode") ?? 0;
      final int safeIndex = legacyIndex.clamp(0, CaptureActionMode.values.length - 1);
      _captureActionId = CaptureActionChoice.fromLegacyMode(CaptureActionMode.values[safeIndex]);
    }
    final String fancySaved = Boxes.pref.getString("screenCaptureFancyShot") ?? "";
    if (fancySaved != "" && _fancyShotProfiles.any((FancyShotProfile e) => e.name == fancySaved)) {
      _selectedFancyShotPresetName = fancySaved;
    }
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _ticker());
    if (widget.freezeMode) {
      _frozenSnapshotWarmup = _warmFrozenMonitorSnapshots();
    }
  }

  List<CaptureActionChoice> _captureChoices() {
    return <CaptureActionChoice>[
      ...CaptureActionChoice.builtIn,
      ..._uploadHosts.map(
        (ScreenCaptureUploadHost host) => CaptureActionChoice(
          id: CaptureActionChoice.uploadHostId(host.id),
          title: host.name,
          subtitle: 'Run custom uploader command',
          icon: Icons.cloud_upload_outlined,
          uploadHost: host,
        ),
      ),
    ];
  }

  void _ticker() {
    _handleScreenDrawHotkeys();
  }

  void _resetActiveCaptureSelection() {
    if (!_capturing && _captureStart == null && _captureCurrent == null) return;
    setState(() {
      _captureStart = null;
      _captureCurrent = null;
      _capturing = false;
    });
  }

  Future<void> _warmFrozenMonitorSnapshots() async {
    Monitor.fetchMonitors();
    for (final int monitorHandle in Monitor.list) {
      await _ensureFrozenMonitorSnapshot(monitorHandle);
    }
  }

  Future<_FrozenMonitorSnapshot?> _ensureFrozenMonitorSnapshot(int monitorHandle) async {
    final _FrozenMonitorSnapshot? existing = _frozenMonitorSnapshots[monitorHandle];
    if (existing != null) return existing;
    final _FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(monitorHandle);
    if (snapshot != null) {
      _frozenMonitorSnapshots[monitorHandle] = snapshot;
    }
    return snapshot;
  }

  Future<Uint8List?> _captureFrozenRegionToPng(Rect screenRect) async {
    final Rect normalizedRect = screenRect.normalized();
    final Pointer<RECT> rectPtr = calloc<RECT>()
      ..ref.left = normalizedRect.left.round()
      ..ref.top = normalizedRect.top.round()
      ..ref.right = normalizedRect.right.round()
      ..ref.bottom = normalizedRect.bottom.round();

    late final int monitorHandle;
    try {
      monitorHandle = MonitorFromRect(rectPtr, 2);
    } finally {
      calloc.free(rectPtr);
    }

    final _FrozenMonitorSnapshot? snapshot = await _ensureFrozenMonitorSnapshot(monitorHandle);
    if (snapshot == null) return null;

    final Rect safeRect = normalizedRect.intersect(snapshot.screenRect);
    if (safeRect.isEmpty) return null;

    final int outputWidth = normalizedRect.width.round().clamp(1, 1000000);
    final int outputHeight = normalizedRect.height.round().clamp(1, 1000000);
    final double scaleX = snapshot.pixelWidth / snapshot.screenRect.width;
    final double scaleY = snapshot.pixelHeight / snapshot.screenRect.height;
    final Uint8List outputRgba = Uint8List(outputWidth * outputHeight * 4);

    for (int row = 0; row < outputHeight; row++) {
      final int sy = ((normalizedRect.top + row - snapshot.screenRect.top) * scaleY).floor();
      if (sy < 0 || sy >= snapshot.pixelHeight) continue;
      for (int col = 0; col < outputWidth; col++) {
        final int sx = ((normalizedRect.left + col - snapshot.screenRect.left) * scaleX).floor();
        if (sx < 0 || sx >= snapshot.pixelWidth) continue;
        final int srcIndex = (sy * snapshot.pixelWidth + sx) * 4;
        final int dstIndex = (row * outputWidth + col) * 4;
        outputRgba[dstIndex] = snapshot.rgbaBytes[srcIndex];
        outputRgba[dstIndex + 1] = snapshot.rgbaBytes[srcIndex + 1];
        outputRgba[dstIndex + 2] = snapshot.rgbaBytes[srcIndex + 2];
        outputRgba[dstIndex + 3] = snapshot.rgbaBytes[srcIndex + 3];
      }
    }

    return ScreenCapture.encodeRgbaToPng(outputRgba, outputWidth, outputHeight);
  }

  void _handleScreenDrawHotkeys() {
    const String hotkey = 'CTRL+ALT+V';
    final bool pressed = _isHotkeyPressed(
      keyVk: 0x56,
      ctrl: true,
      alt: true,
    );
    if (!pressed) {
      _pressedScreenCaptureHotkeys.remove(hotkey);
      return;
    }
    if (_pressedScreenCaptureHotkeys.contains(hotkey)) return;

    _pressedScreenCaptureHotkeys.add(hotkey);
    _toggleScreenCaptureEnabled();
  }

  bool _isHotkeyPressed(
      {required int keyVk, bool ctrl = false, bool alt = false, bool shift = false, bool win = false}) {
    if (GetKeyState(keyVk) >= 0) return false;
    if (ctrl && !_isAnyKeyPressed(<int>[VK_LCONTROL, VK_RCONTROL, VK_CONTROL])) return false;
    if (alt && !_isAnyKeyPressed(<int>[VK_LMENU, VK_RMENU, VK_MENU])) return false;
    if (shift && !_isAnyKeyPressed(<int>[VK_LSHIFT, VK_RSHIFT, VK_SHIFT])) return false;
    if (win && !_isAnyKeyPressed(<int>[VK_LWIN, VK_RWIN])) return false;
    return true;
  }

  bool _isAnyKeyPressed(List<int> keys) => keys.any((int vk) => GetKeyState(vk) < 0);

  void _toggleScreenCaptureEnabled() {
    setState(() {
      _captureEnabled = !_captureEnabled;
      _captureStart = null;
      _captureCurrent = null;
      _capturing = false;
    });
    if (_captureEnabled) {
      Win32Window.disableClickThrough();
      windowManager.focus();
    } else {
      Navigator.of(context).maybePop();
      Win32Window.enableClickThrough();
    }
  }

  @override
  void dispose() {
    _tickerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Size size = MediaQuery.of(context).size;

    if (!_captureEnabled) {
      return const SizedBox.expand();
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          windowManager.close();
        }
      },
      child: Stack(
        children: <Widget>[
          // Dim overlay with crosshair region selector
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent event) {
                if ((event.buttons & kSecondaryMouseButton) != 0 && _capturing) {
                  _resetActiveCaptureSelection();
                }
              },
              onPointerMove: (PointerMoveEvent event) {
                if ((event.buttons & kSecondaryMouseButton) != 0 && _capturing) {
                  _resetActiveCaptureSelection();
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) {
                  setState(() {
                    _captureStart = d.localPosition;
                    _captureCurrent = d.localPosition;
                    _capturing = true;
                  });
                },
                onPanUpdate: (DragUpdateDetails d) {
                  if (!_capturing || _captureStart == null) return;
                  setState(() => _captureCurrent = d.localPosition);
                },
                onPanEnd: (_) async {
                  if (_captureStart == null || _captureCurrent == null) {
                    _capturing = false;
                    return;
                  }
                  final Offset s = _captureStart!;
                  final Offset e = _captureCurrent!;
                  setState(() {
                    _captureStart = null;
                    _captureCurrent = null;
                    _capturing = false;
                  });
                  final Rect localRect = Rect.fromPoints(s, e);
                  if (localRect.width < 4 || localRect.height < 4) return;

                  await _doCapture(localRect);
                },
                child: CustomPaint(
                  size: size,
                  painter: _CapturePainter(
                    start: _captureStart,
                    current: _captureCurrent,
                  ),
                ),
              ),
            ),
          ),

          // Crosshair cursor layer
          if (!_capturing) const Positioned.fill(child: _CrosshairCursor()),

          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _CaptureActionDropdown(
                    value: _captureActionId,
                    uploadHosts: _uploadHosts,
                    onChanged: (String actionId) {
                      Boxes.pref.setString("screenCaptureModeKey", actionId);
                      setState(() => _captureActionId = actionId);
                    },
                  ),
                  const SizedBox(width: 12),
                  _FancyShotPresetDropdown(
                    presetNames: _fancyShotProfiles.map((FancyShotProfile profile) => profile.name).toList(),
                    value: _selectedFancyShotPresetName,
                    onChanged: (String? presetName) {
                      if (presetName == "none") presetName = "";
                      Boxes.pref.setString("screenCaptureFancyShot", presetName ?? "");
                      setState(() => _selectedFancyShotPresetName = presetName);
                    },
                  ),
                ],
              ),
            ),
          ),

          // HUD hint
          Positioned(
            top: 74,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: const Text(
                  'Drag to select a region  •  Ctrl+Alt+V disable/enable  •  ESC to exit',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
          if (_applyingPreset)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.36),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10141C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Applying preset',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _doCapture(Rect localRect) async {
    // Convert to screen coordinates
    final Pointer<POINT> clientTopLeft = calloc<POINT>();
    try {
      final int hwnd = Win32Window.getHwnd();
      if (hwnd == 0) return;
      clientTopLeft.ref.x = 0;
      clientTopLeft.ref.y = 0;
      if (ClientToScreen(hwnd, clientTopLeft) == 0) return;

      final Rect screenRect = Rect.fromLTWH(
        clientTopLeft.ref.x + localRect.left,
        clientTopLeft.ref.y + localRect.top,
        localRect.width,
        localRect.height,
      );

      // Hide the overlay window before capturing. A delay alone is not enough on
      // Windows because layered/shadow surfaces can still be included by GDI.
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 120));

      Uint8List? pngBytes;
      try {
        if (widget.freezeMode) {
          if (_frozenSnapshotWarmup != null) {
            await _frozenSnapshotWarmup;
          }
          pngBytes = await _captureFrozenRegionToPng(screenRect);
        } else {
          pngBytes = await ScreenCapture.captureRegionToPng(screenRect);
        }
      } finally {
        ShowWindow(hwnd, SW_SHOW);
      }
      if (pngBytes == null || !mounted) return;

      Uint8List outputBytes = pngBytes;
      if ((_selectedFancyShotPresetName ?? '').isNotEmpty) {
        setState(() => _applyingPreset = true);
        await Future<void>.delayed(const Duration(milliseconds: 16));
        try {
          outputBytes = await _applySelectedPreset(pngBytes);
        } finally {
          if (mounted) setState(() => _applyingPreset = false);
        }
      }

      final img.Image? outputImage = img.decodeImage(outputBytes);
      if (outputImage == null) return;

      // Save to disk
      final String filePath = await ScreenCapture.saveToFile(outputBytes);

      await windowManager.focus();
      if (!mounted) return;

      await _handleCaptureResult(
        pngBytes: outputBytes,
        filePath: filePath,
        imageW: outputImage.width,
        imageH: outputImage.height,
      );
    } finally {
      calloc.free(clientTopLeft);
    }
  }

  Future<Uint8List> _applySelectedPreset(Uint8List pngBytes) async {
    final String? presetName = _selectedFancyShotPresetName;
    if (presetName == null || presetName.isEmpty) return pngBytes;

    FancyShotProfile? preset;
    for (final FancyShotProfile profile in _fancyShotProfiles) {
      if (profile.name == presetName) {
        preset = profile.copyWith();
        break;
      }
    }
    preset ??= FancyShot.profileByName(presetName);
    if (preset == null) return pngBytes;

    return FancyShot.renderPresetCapture(
      captureBytes: pngBytes,
      profile: preset,
    );
  }

  Future<void> _handleCaptureResult({
    required Uint8List pngBytes,
    required String filePath,
    required int imageW,
    required int imageH,
  }) async {
    final List<CaptureActionChoice> choices = _captureChoices();
    final CaptureActionChoice choice = choices.firstWhere(
      (CaptureActionChoice item) => item.id == _captureActionId,
      orElse: () => CaptureActionChoice.builtIn.first,
    );

    if (choice.uploadHost != null) {
      final bool started = await _runUploadHost(choice.uploadHost!, filePath);
      if (started) await _finishPostCaptureAction();
      return;
    }

    switch (choice.mode ?? CaptureActionMode.ask) {
      case CaptureActionMode.ask:
        _showCaptureModal(pngBytes, filePath, imageW, imageH);
        return;
      case CaptureActionMode.copyImageToClipboard:
        await ScreenCapture.copyPngToClipboard(pngBytes);
        await _finishPostCaptureAction();
        return;
      case CaptureActionMode.copyImageFileToClipboard:
        await ScreenCapture.copyFileToClipboard(filePath);
        await _finishPostCaptureAction();
        return;
      case CaptureActionMode.openPhotoEditor:
        appState.openEditor(filePath, pngBytes, imageW, imageH);
        return;
    }
  }

  Future<void> _finishPostCaptureAction() async {
    if (kDebugMode) {
      appState.backToCapture();
      await windowManager.focus();
      return;
    }
    await windowManager.close();
  }

  Future<bool> _runUploadHost(ScreenCaptureUploadHost host, String filePath) async {
    try {
      final String escapedFilePath = filePath.replaceAll("'", "''");
      final String resolvedCommand = host.command.contains(r'${file}')
          ? host.command.replaceAll(r'${file}', "'$escapedFilePath'")
          : '${host.command} \'$escapedFilePath\'';
      await Process.start(
        'powershell.exe',
        <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          resolvedCommand,
        ],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Uploader Failed'),
          content: Text(
            'Could not start "${host.name}".\n\n$error',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return false;
    }
  }

  void _showCaptureModal(Uint8List pngBytes, String filePath, int w, int h) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _CaptureModal(
        pngBytes: pngBytes,
        filePath: filePath,
        imageW: w,
        imageH: h,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capture selection painter
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureActionDropdown extends StatelessWidget {
  final String value;
  final List<ScreenCaptureUploadHost> uploadHosts;
  final ValueChanged<String> onChanged;

  const _CaptureActionDropdown({
    required this.value,
    required this.uploadHosts,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final List<CaptureActionChoice> options = <CaptureActionChoice>[
      ...CaptureActionChoice.builtIn,
      ...uploadHosts.map(
        (ScreenCaptureUploadHost host) => CaptureActionChoice(
          id: CaptureActionChoice.uploadHostId(host.id),
          title: host.name,
          subtitle: 'Run custom uploader command',
          icon: Icons.cloud_upload_outlined,
          uploadHost: host,
        ),
      ),
    ];
    final CaptureActionChoice selected = options.firstWhere(
      (CaptureActionChoice option) => option.id == value,
      orElse: () => CaptureActionChoice.builtIn.first,
    );

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String>(
        tooltip: 'Capture action',
        color: const Color(0xFF121826),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white24),
        ),
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => options
            .map(
              (CaptureActionChoice option) => PopupMenuItem<String>(
                value: option.id,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: option.id == value ? const Color(0xFF4A9EFF).withValues(alpha: 0.18) : Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        option.icon,
                        size: 18,
                        color: option.id == value ? const Color(0xFF7DB8FF) : Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            option.title,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            option.subtitle,
                            style: const TextStyle(color: Colors.white54, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        child: Container(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF4A9EFF).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(selected.icon, size: 18, color: const Color(0xFF7DB8FF)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'After Capture',
                      style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      selected.title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _FancyShotPresetDropdown extends StatelessWidget {
  final List<String> presetNames;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _FancyShotPresetDropdown({
    required this.presetNames,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final String label = value ?? 'None';

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String?>(
        tooltip: 'FancyShot preset',
        color: const Color(0xFF121826),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white24),
        ),
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String?>>[
          const PopupMenuItem<String?>(
            value: 'none',
            child: _PresetMenuRow(
              icon: Icons.block,
              title: 'None',
              subtitle: 'Use the raw captured image',
            ),
          ),
          ...presetNames.map(
            (String presetName) => PopupMenuItem<String?>(
              value: presetName,
              child: _PresetMenuRow(
                icon: Icons.auto_awesome,
                title: presetName,
                subtitle: 'FancyShot preset',
              ),
            ),
          ),
        ],
        child: Container(
          constraints: const BoxConstraints(minWidth: 240, maxWidth: 240),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.74),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, size: 18, color: Color(0xFF7DFFB1)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Preset',
                      style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PresetMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white70),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditorPresetButton extends StatelessWidget {
  const _EditorPresetButton({
    required this.presetNames,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final List<String> presetNames;
  final String? value;
  final bool busy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final String label = value ?? 'Original';

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String?>(
        tooltip: 'Apply FancyShot preset',
        enabled: !busy,
        color: const Color(0xFF121826),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String?>>[
          const PopupMenuItem<String?>(
            value: 'none',
            child: _PresetMenuRow(
              icon: Icons.image_outlined,
              title: 'Original',
              subtitle: 'Use the original captured image',
            ),
          ),
          ...presetNames.map(
            (String presetName) => PopupMenuItem<String?>(
              value: presetName,
              child: _PresetMenuRow(
                icon: Icons.auto_awesome,
                title: presetName,
                subtitle: 'Apply to the original capture',
              ),
            ),
          ),
        ],
        child: Container(
          constraints: const BoxConstraints(minWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: busy
                    ? const Padding(
                        padding: EdgeInsets.all(7),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7DFFB1)),
                      )
                    : const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7DFFB1)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'Preset',
                      style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 0.6),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      busy ? 'Applying…' : label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _CapturePainter extends CustomPainter {
  final Offset? start;
  final Offset? current;
  _CapturePainter({this.start, this.current});

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent dim
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );

    if (start == null || current == null) return;

    final Rect sel = Rect.fromPoints(start!, current!).normalized();

    // Clear the selected region
    canvas.drawRect(sel, Paint()..blendMode = BlendMode.clear);

    // Dashed selection border
    final Paint dashedPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawDashed(canvas, sel, dashedPaint);

    // Size label
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${sel.width.round()} × ${sel.height.round()}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          backgroundColor: Colors.black.withValues(alpha: 0.75),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double labelX = (sel.center.dx - tp.width / 2).clamp(6.0, size.width - tp.width - 6.0);
    final double labelY = min(sel.bottom + 8, size.height - tp.height - 6);
    tp.paint(canvas, Offset(labelX, labelY));
  }

  void _drawDashed(Canvas canvas, Rect r, Paint p) {
    const double dash = 6, gap = 4;
    void line(Offset a, Offset b) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      double pos = 0;
      bool drawing = true;
      while (pos < len) {
        final double end = (pos + (drawing ? dash : gap)).clamp(0.0, len);
        if (drawing) canvas.drawLine(a + dir * pos, a + dir * end, p);
        pos = end;
        drawing = !drawing;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_CapturePainter old) => old.start != start || old.current != current;
}

extension _RectNorm on Rect {
  Rect normalized() => Rect.fromLTRB(
        left < right ? left : right,
        top < bottom ? top : bottom,
        left < right ? right : left,
        top < bottom ? bottom : top,
      );
}

Rect _fitImageRect(Size viewportSize, ui.Image? image, {Rect? override}) {
  if (override != null) return override;
  if (image == null || viewportSize.width <= 0 || viewportSize.height <= 0) {
    return Rect.zero;
  }
  final double scale = min(viewportSize.width / image.width, viewportSize.height / image.height);
  final double width = image.width * scale;
  final double height = image.height * scale;
  return Rect.fromLTWH(
    (viewportSize.width - width) / 2,
    (viewportSize.height - height) / 2,
    width,
    height,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Crosshair cursor widget
// ─────────────────────────────────────────────────────────────────────────────

class _CrosshairCursor extends StatefulWidget {
  const _CrosshairCursor();
  @override
  State<_CrosshairCursor> createState() => _CrosshairCursorState();
}

class _CrosshairCursorState extends State<_CrosshairCursor> {
  Offset _pos = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (PointerHoverEvent e) => setState(() => _pos = e.localPosition),
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CrosshairPainter(_pos),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Offset pos;
  _CrosshairPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, pos.dy), Offset(size.width, pos.dy), p);
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, size.height), p);

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${pos.dx.round()}, ${pos.dy.round()}',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 12,
          backgroundColor: Colors.black.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + const Offset(10, 10));
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.pos != pos;
}

// ─────────────────────────────────────────────────────────────────────────────
// Post-capture modal
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureModal extends StatefulWidget {
  final Uint8List pngBytes;
  final String filePath;
  final int imageW;
  final int imageH;

  const _CaptureModal({
    required this.pngBytes,
    required this.filePath,
    required this.imageW,
    required this.imageH,
  });

  @override
  State<_CaptureModal> createState() => _CaptureModalState();
}

class _CaptureModalState extends State<_CaptureModal> {
  String? _statusMsg;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 30,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Preview
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 260),
                color: Colors.black,
                child: Image.memory(
                  widget.pngBytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),

            // Info bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white.withValues(alpha: 0.04),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.image_outlined, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.imageW} × ${widget.imageH}px',
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.folder_outlined, size: 14, color: Colors.white38),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.filePath,
                      style: const TextStyle(color: Colors.white24, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Status message
            if (_statusMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _statusMsg!,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
              ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  _ModalAction(
                    icon: Icons.content_copy,
                    label: 'Copy Image to Clipboard',
                    subtitle: 'Copy image to system clipboard',
                    color: const Color(0xFF4A9EFF),
                    onTap: () async {
                      await ScreenCapture.copyPngToClipboard(widget.pngBytes);
                      setState(() => _statusMsg = '✓ Copied to clipboard!');
                    },
                  ),
                  const SizedBox(height: 10),
                  _ModalAction(
                    icon: Icons.file_copy_outlined,
                    label: 'Copy Image File to Clipboard',
                    subtitle: 'Copy the saved screenshot file to clipboard',
                    color: const Color(0xFF9B59B6),
                    onTap: () async {
                      await ScreenCapture.copyFileToClipboard(widget.filePath);
                      setState(() => _statusMsg = '✓ Screenshot file copied!');
                    },
                  ),
                  const SizedBox(height: 10),
                  _ModalAction(
                    icon: Icons.edit,
                    label: 'Open Photo Editor',
                    subtitle: 'Annotate and draw on the screenshot',
                    color: const Color(0xFF2ECC71),
                    onTap: () {
                      Navigator.of(context).pop();
                      appState.openEditor(
                        widget.filePath,
                        widget.pngBytes,
                        widget.imageW,
                        widget.imageH,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close', style: TextStyle(color: Colors.white38)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModalAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModalAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ModalAction> createState() => _ModalActionState();
}

class _ModalActionState extends State<_ModalAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _hovered ? widget.color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? widget.color.withValues(alpha: 0.6) : Colors.white24,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(widget.icon, color: widget.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.label,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────
//  PHOTO EDITOR
// ─────────────────────────────────────────────────────────────────────────────
// ─────────────────────────────────────────────────────────────────────────────

// ── Tool enum ─────────────────────────────────────────────────────────────────

enum EditorTool {
  select,
  pen,
  highlight,
  line,
  rect,
  ellipse,
  arrow,
  ruler,
  sizebox,
  text,
  emoji,
  stepCounter,
  infoBalloon,
  blur,
  pixelate,
  smartDelete,
  imageElement,
  magnifier,
  spotlight,
}

// ── Color palette ─────────────────────────────────────────────────────────────

class _Palette {
  static const List<Color> colors = <ui.Color>[
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Color(0xFF00FF00),
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.white,
    Colors.black,
  ];
}

// ── Draw shape model ──────────────────────────────────────────────────────────

class EditorShape {
  final String id;
  final EditorTool tool;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double opacity;
  bool selected;
  final String? text;
  final bool textBackground;
  final Color? textColor;
  final double? fontSize;
  final String? fontFamily;
  final int? stepNumber;
  final Uint8List? imageBytes;
  final int? imageW;
  final int? imageH;
  final Color? fillColor;

  EditorShape({
    required this.id,
    required this.tool,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.opacity,
    this.selected = false,
    this.text,
    this.textBackground = true,
    this.textColor,
    this.fontSize,
    this.fontFamily,
    this.stepNumber,
    this.imageBytes,
    this.imageW,
    this.imageH,
    this.fillColor,
  });

  EditorShape copyWith({
    String? id,
    List<Offset>? points,
    bool? selected,
    String? text,
    bool? textBackground,
    Color? textColor,
    double? fontSize,
    Uint8List? imageBytes,
    int? imageW,
    int? imageH,
    String? fontFamily,
    Color? fillColor,
  }) {
    return EditorShape(
      id: id ?? this.id,
      tool: tool,
      points: points ?? this.points,
      color: color,
      strokeWidth: strokeWidth,
      opacity: opacity,
      selected: selected ?? this.selected,
      text: text ?? this.text,
      textBackground: textBackground ?? this.textBackground,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      stepNumber: stepNumber,
      imageBytes: imageBytes ?? this.imageBytes,
      imageW: imageW ?? this.imageW,
      imageH: imageH ?? this.imageH,
      fillColor: fillColor ?? this.fillColor,
    );
  }
}

// ── Editor controller ─────────────────────────────────────────────────────────

class EditorController extends ChangeNotifier {
  EditorTool activeTool = EditorTool.pen;
  Color strokeColor = Colors.red;
  double strokeWidth = 2.0;
  double opacity = 1.0;
  bool textBackground = true;
  double fontSize = 16.0;
  Color? textColor;
  String fontFamily = 'Roboto';
  bool gridVisible = false;

  int _stepCount = 1;
  int get nextStepNumber => _stepCount;
  void resetStepCounter() {
    _stepCount = 1;
    notifyListeners();
  }

  void toggleGrid() {
    gridVisible = !gridVisible;
    notifyListeners();
  }

  final List<EditorShape> _shapes = <EditorShape>[];
  final List<EditorShape> _redo = <EditorShape>[];
  int _shapeCounter = 0;

  List<EditorShape> get shapes => List<EditorShape>.unmodifiable(_shapes);

  EditorShape? currentShape;
  Offset? currentEnd;
  int? selectedShapeIndex;

  EditorShape? get selectedShape {
    final int? i = selectedShapeIndex;
    if (i == null || i < 0 || i >= _shapes.length) return null;
    return _shapes[i];
  }

  void setTool(EditorTool t) {
    activeTool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    strokeColor = c;
    notifyListeners();
  }

  void setStrokeWidth(double w) {
    strokeWidth = w;
    notifyListeners();
  }

  void setOpacity(double o) {
    opacity = o;
    notifyListeners();
  }

  void setFontFamily(String family) {
    fontFamily = family;
    notifyListeners();
  }

  String _nextShapeId() {
    _shapeCounter++;
    return 'editor-shape-$_shapeCounter';
  }

  void startShape(Offset pos) {
    _redo.clear();
    currentShape = EditorShape(
      id: _nextShapeId(),
      tool: activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      textBackground: textBackground,
      stepNumber: activeTool == EditorTool.stepCounter ? _stepCount : null,
    );
    notifyListeners();
  }

  void updateShape(Offset pos, {bool shiftHeld = false}) {
    if (currentShape == null) return;
    Offset end = pos;
    if (shiftHeld) end = _snap45(currentShape!.points.first, pos);
    currentEnd = end;
    if (currentShape!.tool == EditorTool.pen || currentShape!.tool == EditorTool.highlight) {
      currentShape = currentShape!.copyWith(points: <ui.Offset>[...currentShape!.points, pos]);
    }
    notifyListeners();
  }

  void endShape() {
    if (currentShape == null) return;
    final Offset end = currentEnd ?? currentShape!.points.last;
    EditorShape committed;
    if (currentShape!.tool == EditorTool.pen || currentShape!.tool == EditorTool.highlight) {
      committed = currentShape!;
    } else {
      committed = currentShape!.copyWith(points: <ui.Offset>[currentShape!.points.first, end]);
    }
    if (committed.tool == EditorTool.spotlight) {
      _shapes.removeWhere((EditorShape shape) => shape.tool == EditorTool.spotlight);
      selectedShapeIndex = null;
    }
    _shapes.add(committed);
    if (committed.tool == EditorTool.stepCounter) _stepCount++;
    currentShape = null;
    currentEnd = null;
    notifyListeners();
  }

  EditorShape commitTextShape(
    Offset pos,
    String text, {
    double? size,
    String? family,
    Color? explicitTextColor,
    bool? useBackground,
    EditorTool? tool,
  }) {
    final EditorShape shape = EditorShape(
      id: _nextShapeId(),
      tool: tool ?? activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      text: text,
      textBackground: useBackground ?? textBackground,
      textColor: explicitTextColor ?? textColor,
      fontSize: size ?? fontSize,
      fontFamily: family ?? fontFamily,
    );
    _redo.clear();
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  EditorShape commitRegionShape(EditorTool tool, Rect region, Uint8List bytes, int w, int h, {Color? fillColor}) {
    final EditorShape shape = EditorShape(
      id: _nextShapeId(),
      tool: tool,
      points: <ui.Offset>[region.topLeft, region.bottomRight],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      imageBytes: bytes,
      imageW: w,
      imageH: h,
      fillColor: fillColor,
    );
    _redo.clear();
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  void undo() {
    if (_shapes.isEmpty) return;
    _redo.add(_shapes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _shapes.add(_redo.removeLast());
    notifyListeners();
  }

  void clearAll() {
    _shapes.clear();
    _redo.clear();
    currentShape = null;
    currentEnd = null;
    selectedShapeIndex = null;
    notifyListeners();
  }

  void selectShapeAt(Offset pos) {
    _clearSelection();
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        _shapes[i].selected = true;
        selectedShapeIndex = i;
        notifyListeners();
        return;
      }
    }
    selectedShapeIndex = null;
    notifyListeners();
  }

  void selectShapeById(String id) {
    _clearSelection();
    for (int i = 0; i < _shapes.length; i++) {
      if (_shapes[i].id != id) continue;
      _shapes[i].selected = true;
      selectedShapeIndex = i;
      notifyListeners();
      return;
    }
  }

  void _clearSelection() {
    for (final EditorShape shape in _shapes) {
      shape.selected = false;
    }
  }

  void moveSelected(Offset delta) {
    if (selectedShapeIndex == null) return;
    final EditorShape s = _shapes[selectedShapeIndex!];
    _shapes[selectedShapeIndex!] = s.copyWith(
      points: s.points.map((ui.Offset p) => p + delta).toList(),
    );
    notifyListeners();
  }

  void deleteShapeAt(Offset pos) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        _shapes.removeAt(i);
        selectedShapeIndex = null;
        notifyListeners();
        return;
      }
    }
  }

  bool _hitTest(EditorShape s, Offset pos) {
    if (s.points.isEmpty) return false;
    final Offset a = s.points.first;

    if (s.tool == EditorTool.pen || s.tool == EditorTool.highlight) {
      return s.points.any((ui.Offset p) => (p - pos).distance < 8);
    }

    if (s.tool == EditorTool.text) {
      return _textBounds(s, a).inflate(8).contains(pos);
    }

    if (s.tool == EditorTool.infoBalloon) {
      return _infoBalloonBounds(s, a).inflate(10).contains(pos);
    }

    if (s.tool == EditorTool.emoji) {
      return _emojiBounds(s, a).inflate(8).contains(pos);
    }

    if (s.tool == EditorTool.stepCounter) {
      return Rect.fromCircle(center: a, radius: 22).contains(pos);
    }

    if (s.points.length < 2) return false;
    final Offset b = s.points.last;

    if (s.tool == EditorTool.rect ||
        s.tool == EditorTool.blur ||
        s.tool == EditorTool.pixelate ||
        s.tool == EditorTool.smartDelete ||
        s.tool == EditorTool.imageElement ||
        s.tool == EditorTool.spotlight ||
        s.tool == EditorTool.magnifier) {
      return Rect.fromPoints(a, b).inflate(6).contains(pos);
    }

    final Offset center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return (center - pos).distance < 24;
  }

  Rect _textBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    final double fontSize = shape.fontSize ?? (shape.strokeWidth * 8 + 12);
    final Color textColor = shape.textColor ?? shape.color;
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: _textStyleForHitTest(shape, color: textColor, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    Rect bounds = Rect.fromLTWH(pos.dx, pos.dy, textPainter.width, textPainter.height);
    if (shape.textBackground) {
      bounds = Rect.fromLTWH(pos.dx - 4, pos.dy - 2, textPainter.width + 8, textPainter.height + 4);
    }
    return bounds;
  }

  Rect _emojiBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: shape.fontSize ?? 32),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromLTWH(pos.dx, pos.dy, textPainter.width, textPainter.height);
  }

  Rect _infoBalloonBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    const double padding = 10;
    const double tailHeight = 14;
    final double fontSize = shape.fontSize ?? (shape.strokeWidth * 6 + 12);
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: _textStyleForHitTest(shape, color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    final double bubbleWidth = textPainter.width + padding * 2;
    final double bubbleHeight = textPainter.height + padding * 2;
    final Rect bubble = Rect.fromLTWH(
      pos.dx - bubbleWidth / 2,
      pos.dy - bubbleHeight - tailHeight,
      bubbleWidth,
      bubbleHeight,
    );
    return bubble.expandToInclude(Rect.fromLTWH(pos.dx - 8, bubble.bottom, 16, tailHeight));
  }

  TextStyle _textStyleForHitTest(EditorShape shape, {required Color color, required double fontSize}) {
    if (shape.tool == EditorTool.emoji) {
      return TextStyle(fontSize: fontSize);
    }
    final String? family = shape.fontFamily;
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      fontFamily: family == null ? null : GoogleFonts.getFont(family).fontFamily,
    );
  }

  Offset _snap45(Offset start, Offset end) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double angle = atan2(dy, dx);
    final double len = sqrt(dx * dx + dy * dy);
    final double snapped = (angle / (pi / 4)).round() * (pi / 4);
    return Offset(start.dx + cos(snapped) * len, start.dy + sin(snapped) * len);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Photo Editor View
// ─────────────────────────────────────────────────────────────────────────────

class PhotoEditorView extends StatefulWidget {
  final Uint8List initialImageBytes;
  final int imageW;
  final int imageH;
  final String filePath;

  const PhotoEditorView({
    super.key,
    required this.initialImageBytes,
    required this.imageW,
    required this.imageH,
    required this.filePath,
  });

  @override
  State<PhotoEditorView> createState() => _PhotoEditorViewState();
}

class _PhotoEditorViewState extends State<PhotoEditorView> {
  final EditorController _ctrl = EditorController();
  final FocusNode _focusNode = FocusNode();
  late final Uint8List _originalImageBytes;
  ui.Image? _backgroundImage;
  List<FancyShotProfile> _editorFancyShotProfiles = <FancyShotProfile>[];
  String? _selectedEditorPresetName;
  final Map<String, ui.Image> _shapeImages = <String, ui.Image>{};
  bool _shiftHeld = false;
  Offset? _lastSelectPos;
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _selectMode = false;
  bool _isRegionDragging = false;
  bool _captureMoreBusy = false;
  bool _presetBusy = false;

  @override
  void initState() {
    super.initState();
    _originalImageBytes = Uint8List.fromList(widget.initialImageBytes);
    _editorFancyShotProfiles = FancyShot.loadProfiles();
    _ctrl.addListener(_handleControllerChanged);
    _decodeBackground();
  }

  Future<void> _decodeBackground() async {
    await _decodeBackgroundBytes(_originalImageBytes);
  }

  Future<void> _decodeBackgroundBytes(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _backgroundImage = frame.image);
  }

  Future<void> _applyEditorFancyShotPreset(String? presetName) async {
    final String? normalizedName = presetName == null || presetName.isEmpty || presetName == 'none' ? null : presetName;
    if (_presetBusy) return;

    setState(() {
      _presetBusy = true;
      _selectedEditorPresetName = normalizedName;
    });

    try {
      Uint8List bytes = _originalImageBytes;
      if (normalizedName != null) {
        FancyShotProfile? preset;
        for (final FancyShotProfile profile in _editorFancyShotProfiles) {
          if (profile.name == normalizedName) {
            preset = profile.copyWith();
            break;
          }
        }
        preset ??= FancyShot.profileByName(normalizedName);
        if (preset != null) {
          bytes = await FancyShot.renderPresetCapture(
            captureBytes: _originalImageBytes,
            profile: preset,
          );
        }
      }

      if (!mounted) return;
      await _decodeBackgroundBytes(bytes);
    } finally {
      if (mounted) {
        setState(() => _presetBusy = false);
      }
    }
  }

  void _handleControllerChanged() {
    if (_selectMode && _ctrl.activeTool != EditorTool.select) {
      _selectMode = false;
    }
    unawaited(_syncShapeImages());
  }

  bool _needsDecodedImage(EditorShape shape) {
    return (shape.tool == EditorTool.blur || shape.tool == EditorTool.imageElement) &&
        shape.imageBytes != null &&
        shape.imageW != null &&
        shape.imageH != null;
  }

  Future<ui.Image?> _decodeRawRgbaImage(Uint8List? bytes, int? width, int? height) async {
    if (bytes == null || width == null || height == null || width <= 0 || height <= 0) return null;
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _syncShapeImages() async {
    bool changed = false;
    final Set<String> liveIds = _ctrl.shapes.map((EditorShape shape) => shape.id).toSet();
    final List<String> removedIds = _shapeImages.keys.where((String id) => !liveIds.contains(id)).toList();
    for (final String id in removedIds) {
      _shapeImages.remove(id);
      changed = true;
    }

    for (final EditorShape shape in _ctrl.shapes) {
      if (!_needsDecodedImage(shape) || _shapeImages.containsKey(shape.id)) continue;
      final ui.Image? image = await _decodeRawRgbaImage(shape.imageBytes, shape.imageW, shape.imageH);
      if (!mounted || image == null) continue;
      _shapeImages[shape.id] = image;
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  Future<void> _ensureAllShapeImagesDecoded() async {
    for (final EditorShape shape in _ctrl.shapes) {
      if (!_needsDecodedImage(shape) || _shapeImages.containsKey(shape.id)) continue;
      final ui.Image? image = await _decodeRawRgbaImage(shape.imageBytes, shape.imageW, shape.imageH);
      if (image != null) _shapeImages[shape.id] = image;
    }
  }

  bool _isRegionTool(EditorTool t) {
    return t == EditorTool.blur ||
        t == EditorTool.pixelate ||
        t == EditorTool.smartDelete ||
        t == EditorTool.imageElement;
  }

  Rect _imageRect(Size viewSize) {
    return _fitImageRect(viewSize, _backgroundImage);
  }

  Offset? _viewToImage(Offset viewPos, Size viewSize) {
    final Rect rect = _imageRect(viewSize);
    final ui.Image? image = _backgroundImage;
    if (image == null || rect.isEmpty || !rect.contains(viewPos)) return null;
    final double scale = rect.width / image.width;
    return Offset((viewPos.dx - rect.left) / scale, (viewPos.dy - rect.top) / scale);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleControllerChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        color: const Color(0xFF090B10),
        child: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF11151D),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.36),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              children: <Widget>[
                _EditorWindowBar(
                  filePath: widget.filePath,
                  onBack: () => appState.backToCapture(),
                ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                        child: _EditorToolbar(ctrl: _ctrl, onBack: () => appState.backToCapture()),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A0D13),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints constraints) {
                                final Size canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
                                return Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: _backgroundImage == null
                                          ? const Center(
                                              child: SizedBox(
                                                width: 40,
                                                height: 40,
                                                child: CircularProgressIndicator(),
                                              ),
                                            )
                                          : GestureDetector(
                                              behavior: HitTestBehavior.translucent,
                                              onPanStart: (DragStartDetails details) =>
                                                  _onPanStart(details, canvasSize),
                                              onPanUpdate: (DragUpdateDetails details) =>
                                                  _onPanUpdate(details, canvasSize),
                                              onPanEnd: _onPanEnd,
                                              onTapDown: (TapDownDetails details) => _onTapDown(details, canvasSize),
                                              onSecondaryTapDown: (TapDownDetails details) {
                                                final Offset? imagePos =
                                                    _viewToImage(details.localPosition, canvasSize);
                                                if (imagePos != null) _ctrl.deleteShapeAt(imagePos);
                                              },
                                              child: ListenableBuilder(
                                                listenable: _ctrl,
                                                builder: (_, __) => CustomPaint(
                                                  size: canvasSize,
                                                  painter: _EditorPainter(
                                                    shapes: _ctrl.shapes,
                                                    currentShape: _ctrl.currentShape,
                                                    currentEnd: _ctrl.currentEnd,
                                                    backgroundImage: _backgroundImage,
                                                    shapeImages: _shapeImages,
                                                    gridVisible: _ctrl.gridVisible,
                                                    dragStart: _dragStart,
                                                    dragCurrent: _dragCurrent,
                                                    isRegionDrag: _isRegionDragging,
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        _SaveButton(
                          ctrl: _ctrl,
                          backgroundImage: _backgroundImage,
                          filePath: widget.filePath,
                          shapeImages: _shapeImages,
                          onCaptureMore: _captureMoreFromScreen,
                          captureMoreBusy: _captureMoreBusy,
                        ),
                        const SizedBox(height: 10),
                        _EditorPresetButton(
                          presetNames:
                              _editorFancyShotProfiles.map((FancyShotProfile profile) => profile.name).toList(),
                          value: _selectedEditorPresetName,
                          busy: _presetBusy,
                          onChanged: _applyEditorFancyShotPreset,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
      final bool lCtrl = HardwareKeyboard.instance.isControlPressed;
      if (lCtrl && e.logicalKey == LogicalKeyboardKey.keyZ) {
        _ctrl.undo();
        return;
      }
      if (lCtrl && e.logicalKey == LogicalKeyboardKey.keyY) {
        _ctrl.redo();
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape) appState.backToCapture();

      final Map<LogicalKeyboardKey, EditorTool> toolKeys = <LogicalKeyboardKey, EditorTool>{
        LogicalKeyboardKey.keyS: EditorTool.select,
        LogicalKeyboardKey.keyP: EditorTool.pen,
        LogicalKeyboardKey.keyH: EditorTool.highlight,
        LogicalKeyboardKey.keyL: EditorTool.line,
        LogicalKeyboardKey.keyR: EditorTool.rect,
        LogicalKeyboardKey.keyE: EditorTool.ellipse,
        LogicalKeyboardKey.keyA: EditorTool.arrow,
        LogicalKeyboardKey.keyM: EditorTool.ruler,
        LogicalKeyboardKey.keyB: EditorTool.sizebox,
        LogicalKeyboardKey.keyT: EditorTool.text,
        LogicalKeyboardKey.keyN: EditorTool.stepCounter,
        LogicalKeyboardKey.keyI: EditorTool.infoBalloon,
        LogicalKeyboardKey.keyG: EditorTool.imageElement,
        LogicalKeyboardKey.keyF: EditorTool.blur,
        LogicalKeyboardKey.keyX: EditorTool.pixelate,
        LogicalKeyboardKey.keyD: EditorTool.smartDelete,
      };
      if (toolKeys.containsKey(e.logicalKey)) {
        _ctrl.setTool(toolKeys[e.logicalKey]!);
        _selectMode = _ctrl.activeTool == EditorTool.select;
      }
    }
    if (e is KeyUpEvent) _shiftHeld = false;
  }

  void _onPanStart(DragStartDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      _ctrl.selectShapeAt(pos);
      _lastSelectPos = pos;
      return;
    }
    if (_isRegionTool(_ctrl.activeTool)) {
      setState(() {
        _dragStart = pos;
        _dragCurrent = pos;
        _isRegionDragging = true;
      });
      return;
    }
    _ctrl.startShape(pos);
  }

  void _onPanUpdate(DragUpdateDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      if (_lastSelectPos != null) {
        _ctrl.moveSelected(pos - _lastSelectPos!);
        _lastSelectPos = pos;
      }
      return;
    }
    if (_isRegionTool(_ctrl.activeTool) && _dragStart != null) {
      setState(() => _dragCurrent = pos);
      return;
    }
    _ctrl.updateShape(pos, shiftHeld: _shiftHeld);
  }

  Future<void> _onPanEnd(DragEndDetails _) async {
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      _lastSelectPos = null;
      return;
    }
    if (_isRegionTool(_ctrl.activeTool) && _dragStart != null && _dragCurrent != null) {
      final Rect region = Rect.fromPoints(_dragStart!, _dragCurrent!).normalized();
      if (region.width > 4 && region.height > 4) {
        if (_ctrl.activeTool == EditorTool.imageElement) {
          await _createImageElementFromRegion(region);
        } else {
          await _commitRegion(region);
        }
      }
      setState(() {
        _dragStart = null;
        _dragCurrent = null;
        _isRegionDragging = false;
      });
      return;
    }
    _ctrl.endShape();
  }

  void _onTapDown(TapDownDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_selectMode) {
      _ctrl.selectShapeAt(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.text || _ctrl.activeTool == EditorTool.infoBalloon) {
      _showTextDialog(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.emoji) {
      _showEmojiDialog(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.stepCounter) {
      _ctrl.startShape(pos);
      _ctrl.endShape();
      return;
    }
  }

  Future<void> _commitRegion(Rect region) async {
    final img.Image? composite = await _renderCompositeImagePackage();
    if (composite == null) return;
    final img.Image crop = _cropCompositeRegion(composite, region);
    final Uint8List rgba = Uint8List.fromList(crop.getBytes(order: img.ChannelOrder.rgba));
    _ctrl.commitRegionShape(
      _ctrl.activeTool,
      region,
      rgba,
      crop.width,
      crop.height,
      fillColor: _smartDeleteFillColor(crop),
    );
    await _syncShapeImages();
  }

  img.Image _cropCompositeRegion(img.Image composite, Rect region) {
    final Rect safeRect =
        region.normalized().intersect(Rect.fromLTWH(0, 0, composite.width.toDouble(), composite.height.toDouble()));
    return img.copyCrop(
      composite,
      x: safeRect.left.floor().clamp(0, composite.width - 1),
      y: safeRect.top.floor().clamp(0, composite.height - 1),
      width: max(1, safeRect.width.round()),
      height: max(1, safeRect.height.round()),
    );
  }

  Color _smartDeleteFillColor(img.Image source) {
    if (source.width == 0 || source.height == 0) {
      return Colors.white;
    }
    final img.Pixel pixel = source.getPixelSafe(0, 0);
    return Color.fromARGB(
      pixel.a.toInt(),
      pixel.r.toInt(),
      pixel.g.toInt(),
      pixel.b.toInt(),
    );
  }

  Future<img.Image?> _renderCompositeImagePackage() async {
    final ui.Image? backgroundImage = _backgroundImage;
    if (backgroundImage == null) return null;
    await _ensureAllShapeImagesDecoded();
    final Uint8List? pngBytes = await _renderEditorPngBytes(
      backgroundImage: backgroundImage,
      shapes: _ctrl.shapes,
      shapeImages: _shapeImages,
    );
    if (pngBytes == null) return null;
    return img.decodeImage(pngBytes);
  }

  Rect _imageBoundsRect() {
    final ui.Image? image = _backgroundImage;
    if (image == null) return Rect.zero;
    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  Rect _duplicateInsertRect(Rect sourceRect) {
    final Rect imageBounds = _imageBoundsRect();
    Rect shifted = sourceRect.shift(const Offset(24, 24));
    if (shifted.right > imageBounds.right) shifted = shifted.shift(Offset(imageBounds.right - shifted.right, 0));
    if (shifted.bottom > imageBounds.bottom) shifted = shifted.shift(Offset(0, imageBounds.bottom - shifted.bottom));
    if (shifted.left < imageBounds.left) shifted = shifted.shift(Offset(imageBounds.left - shifted.left, 0));
    if (shifted.top < imageBounds.top) shifted = shifted.shift(Offset(0, imageBounds.top - shifted.top));
    return shifted;
  }

  Rect _defaultInsertedImageRect(int width, int height) {
    final Rect imageBounds = _imageBoundsRect();
    if (imageBounds.isEmpty) return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final double scale = min(1.0, min(imageBounds.width * 0.6 / width, imageBounds.height * 0.6 / height));
    return Rect.fromCenter(
      center: imageBounds.center,
      width: width * scale,
      height: height * scale,
    );
  }

  Future<void> _createImageElementFromRegion(Rect region) async {
    final img.Image? composite = await _renderCompositeImagePackage();
    if (composite == null) return;
    final img.Image crop = _cropCompositeRegion(composite, region);
    final Uint8List rgba = Uint8List.fromList(crop.getBytes(order: img.ChannelOrder.rgba));
    final EditorShape shape = _ctrl.commitRegionShape(
      EditorTool.imageElement,
      _duplicateInsertRect(region),
      rgba,
      crop.width,
      crop.height,
    );
    await _syncShapeImages();
    _ctrl.setTool(EditorTool.select);
    _selectMode = true;
    _ctrl.selectShapeById(shape.id);
  }

  Future<void> _captureMoreFromScreen() async {
    if (_captureMoreBusy) return;
    setState(() => _captureMoreBusy = true);
    final int hwnd = Win32Window.getHwnd();
    try {
      if (hwnd != 0) ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final bool captured = await WinUtils.screenCapture();
      if (hwnd != 0) ShowWindow(hwnd, SW_SHOW);
      await windowManager.focus();
      if (!captured) return;

      final File file = File('${WinUtils.getTempFolder()}\\capture.png');
      if (!file.existsSync()) return;
      final Uint8List pngBytes = await file.readAsBytes();
      final img.Image? image = img.decodeImage(pngBytes);
      if (image == null) return;

      final Uint8List rgba = Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgba));
      final EditorShape shape = _ctrl.commitRegionShape(
        EditorTool.imageElement,
        _defaultInsertedImageRect(image.width, image.height),
        rgba,
        image.width,
        image.height,
      );
      await _syncShapeImages();
      _ctrl.setTool(EditorTool.select);
      _selectMode = true;
      _ctrl.selectShapeById(shape.id);
    } finally {
      if (mounted) setState(() => _captureMoreBusy = false);
      if (hwnd != 0) ShowWindow(hwnd, SW_SHOW);
    }
  }

  Future<void> _showTextDialog(Offset pos) async {
    final TextEditingController tc = TextEditingController();
    double localSize = _ctrl.fontSize;
    String localFontFamily = _ctrl.fontFamily;

    Future<void> openFontPicker(StateSetter setSt) async {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (BuildContext pickerCtx) => Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 900,
            height: 700,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FontPicker(
                showInDialog: false,
                initialFontFamily: localFontFamily,
                onFontChanged: (PickerFont font) {
                  setSt(() {
                    localFontFamily = font.fontFamily;
                  });
                },
              ),
            ),
          ),
        ),
      );
    }

    final List<dynamic>? result = await showDialog<List<dynamic>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSt) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(
              _ctrl.activeTool == EditorTool.infoBalloon ? 'Info Balloon' : 'Enter Text',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: tc,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Type here…',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                    ),
                    onSubmitted: (String v) => Navigator.pop(ctx, <dynamic>[v, localSize, localFontFamily]),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: localSize,
                          min: 8,
                          max: 120,
                          activeColor: Colors.yellowAccent,
                          onChanged: (double v) => setSt(() => localSize = v),
                        ),
                      ),
                      Text(localSize.round().toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Font Family', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    subtitle:
                        Text(localFontFamily, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.font_download, color: Colors.white54),
                    onTap: () => openFontPicker(setSt),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, <dynamic>[tc.text, localSize, localFontFamily]),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && result.isNotEmpty) {
      final double chosenSize = result[1] as double;
      final String chosenFontFamily = result[2] as String;
      _ctrl.fontSize = chosenSize;
      _ctrl.setFontFamily(chosenFontFamily);
      _ctrl.commitTextShape(
        pos,
        result[0] as String,
        size: chosenSize,
        family: chosenFontFamily,
      );
    }
  }

  Future<void> _showEmojiDialog(Offset pos) async {
    final TextEditingController emojiController = TextEditingController();
    double localSize = max(_ctrl.fontSize, 24);

    final List<dynamic>? result = await showDialog<List<dynamic>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSt) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Emoji', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  EmojiPickerTextField(
                    controller: emojiController,
                    autofocus: true,
                    dialogTitle: 'Pick emoji',
                    decoration: const InputDecoration(
                      hintText: 'Pick or paste an emoji',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: localSize,
                          min: 18,
                          max: 160,
                          activeColor: Colors.yellowAccent,
                          onChanged: (double value) => setSt(() => localSize = value),
                        ),
                      ),
                      Text(
                        localSize.round().toString(),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, <dynamic>[emojiController.text.trim(), localSize]),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || result.isEmpty) return;
    final String emoji = (result[0] as String).trim();
    if (emoji.isEmpty) return;
    _ctrl.commitTextShape(
      pos,
      emoji,
      size: result[1] as double,
      family: null,
      explicitTextColor: null,
      useBackground: false,
      tool: EditorTool.emoji,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor Painter
// ─────────────────────────────────────────────────────────────────────────────

class _EditorPainter extends CustomPainter {
  final List<EditorShape> shapes;
  final EditorShape? currentShape;
  final Offset? currentEnd;
  final ui.Image? backgroundImage;
  final Map<String, ui.Image> shapeImages;
  final bool gridVisible;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final bool isRegionDrag;
  final Rect? imageRectOverride;

  _EditorPainter({
    required this.shapes,
    required this.currentShape,
    required this.currentEnd,
    required this.backgroundImage,
    required this.shapeImages,
    required this.gridVisible,
    this.dragStart,
    this.dragCurrent,
    this.isRegionDrag = false,
    this.imageRectOverride,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = backgroundImage;
    final Rect imageRect = _displayImageRect(size);

    if (image != null && !imageRect.isEmpty) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      final double scale = imageRect.width / image.width;
      canvas.save();
      canvas.clipRect(imageRect);
      canvas.translate(imageRect.left, imageRect.top);
      canvas.scale(scale, scale);

      final EditorShape? spotlightShape = _effectiveSpotlightShape();
      if (spotlightShape != null) {
        final Rect spotlightRect = _shapeRect(spotlightShape).intersect(_imageBounds());
        if (!spotlightRect.isEmpty) {
          _drawSpotlightRect(canvas, spotlightRect);
        }
      }

      for (final EditorShape s in shapes) {
        if (s.tool == EditorTool.spotlight) continue;
        _paintShape(canvas, s, null);
      }
      if (currentShape != null && currentShape!.tool != EditorTool.spotlight) {
        _paintShape(canvas, currentShape!, currentEnd);
      }

      // Region drag preview; drag coordinates are stored in image space.
      if (isRegionDrag && dragStart != null && dragCurrent != null) {
        final Rect r = Rect.fromPoints(dragStart!, dragCurrent!).normalized();
        canvas.drawRect(r, Paint()..color = Colors.cyan.withValues(alpha: 0.25));
        _drawDashedRect(canvas, r, Colors.cyanAccent);
      }

      canvas.restore();
    }

    if (gridVisible) _paintGrid(canvas, size);
  }

  Rect _displayImageRect(Size size) {
    return _fitImageRect(size, backgroundImage, override: imageRectOverride);
  }

  EditorShape? _effectiveSpotlightShape() {
    if (currentShape?.tool == EditorTool.spotlight) {
      final EditorShape spotlight = currentShape!;
      return spotlight.copyWith(points: <Offset>[spotlight.points.first, currentEnd ?? spotlight.points.first]);
    }
    for (int i = shapes.length - 1; i >= 0; i--) {
      if (shapes[i].tool == EditorTool.spotlight) return shapes[i];
    }
    return null;
  }

  Rect _shapeRect(EditorShape shape) {
    if (shape.points.isEmpty) return Rect.zero;
    final Offset start = shape.points.first;
    final Offset end = shape.points.length > 1 ? shape.points.last : start;
    return Rect.fromPoints(start, end).normalized();
  }

  Paint _makePaint(EditorShape s) => Paint()
    ..color = s.color.withValues(alpha: s.opacity)
    ..strokeWidth = s.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _paintShape(Canvas canvas, EditorShape s, Offset? liveEnd) {
    final Paint paint = _makePaint(s);
    final Offset start = s.points.isNotEmpty ? s.points.first : Offset.zero;
    final Offset end = liveEnd ?? (s.points.length > 1 ? s.points.last : start);

    if (s.selected) {
      final Paint selPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..strokeWidth = s.strokeWidth + 4
        ..style = PaintingStyle.stroke;
      _drawShape(canvas, s.tool, start, end, s.points, selPaint, s.color, s.strokeWidth);
    }

    switch (s.tool) {
      case EditorTool.text:
        _drawText(canvas, s, start);
        return;
      case EditorTool.emoji:
        _drawEmoji(canvas, s, start);
        return;
      case EditorTool.infoBalloon:
        _drawInfoBalloon(canvas, s, start);
        return;
      case EditorTool.stepCounter:
        _drawStepCounter(canvas, s, start);
        return;
      case EditorTool.blur:
        _drawBlurRect(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.pixelate:
        _drawPixelateRect(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.smartDelete:
        _drawSmartDeleteRect(canvas, Rect.fromPoints(start, end).normalized(), s.fillColor);
        return;
      case EditorTool.imageElement:
        _drawImageElement(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.spotlight:
        _drawDashedRect(canvas, Rect.fromPoints(start, end).normalized(), Colors.white70);
        return;
      default:
        break;
    }

    _drawShape(canvas, s.tool, start, end, s.points, paint, s.color, s.strokeWidth);

    if (s.tool == EditorTool.ruler ||
        s.tool == EditorTool.line ||
        s.tool == EditorTool.sizebox ||
        s.tool == EditorTool.arrow) {
      _paintMeasurement(canvas, s.tool, start, end, s.color);
    }
  }

  void _drawShape(Canvas canvas, EditorTool tool, Offset start, Offset end, List<Offset> points, Paint paint,
      Color color, double sw) {
    switch (tool) {
      case EditorTool.pen:
        if (points.length < 2) return;
        final Path path = Path()..moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, paint);
      case EditorTool.highlight:
        final Paint hp = Paint()
          ..color = color.withValues(alpha: 0.27)
          ..strokeWidth = sw * 16
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (points.length <= 2) {
          canvas.drawLine(start, end, hp);
        } else {
          final Path p = Path()..moveTo(points.first.dx, points.first.dy);
          for (int i = 1; i < points.length; i++) {
            p.lineTo(points[i].dx, points[i].dy);
          }
          canvas.drawPath(p, hp);
        }
      case EditorTool.line:
        canvas.drawLine(start, end, paint);
      case EditorTool.rect:
      case EditorTool.sizebox:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
      case EditorTool.ellipse:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
      case EditorTool.arrow:
        _drawArrow(canvas, start, end, paint);
      case EditorTool.ruler:
        _drawRuler(canvas, start, end, paint);
      default:
        break;
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const double headLen = 14.0, headAngle = 0.45;
    canvas.drawLine(
        end, Offset(end.dx - headLen * cos(angle - headAngle), end.dy - headLen * sin(angle - headAngle)), paint);
    canvas.drawLine(
        end, Offset(end.dx - headLen * cos(angle + headAngle), end.dy - headLen * sin(angle + headAngle)), paint);
  }

  void _drawRuler(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final double dx = end.dx - start.dx, dy = end.dy - start.dy;
    final double len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final double nx = -dy / len, ny = dx / len;
    const double tick = 6;
    canvas.drawLine(
        Offset(start.dx + nx * tick, start.dy + ny * tick), Offset(start.dx - nx * tick, start.dy - ny * tick), paint);
    canvas.drawLine(
        Offset(end.dx + nx * tick, end.dy + ny * tick), Offset(end.dx - nx * tick, end.dy - ny * tick), paint);
  }

  void _drawText(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final double fs = s.fontSize ?? (s.strokeWidth * 8 + 12);
    final Color tc = s.textColor ?? s.color;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: _textStyleForShape(s, color: tc, fontSize: fs),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (s.textBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4), const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: 0.72),
      );
    }
    tp.paint(canvas, pos);
  }

  void _drawEmoji(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(fontSize: s.fontSize ?? 32),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  TextStyle _textStyleForShape(EditorShape shape, {required Color color, required double fontSize}) {
    if (shape.tool == EditorTool.emoji) {
      return TextStyle(fontSize: fontSize);
    }
    final String? family = shape.fontFamily;
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      fontFamily: family == null ? null : GoogleFonts.getFont(family).fontFamily,
    );
  }

  void _drawInfoBalloon(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    const double padding = 10, tailH = 14, radius = 8;
    final double fontSize = s.fontSize ?? (s.strokeWidth * 6 + 12);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: _textStyleForShape(s, color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    final double bw = tp.width + padding * 2, bh = tp.height + padding * 2;
    final Rect bubble = Rect.fromLTWH(pos.dx - bw / 2, pos.dy - bh - tailH, bw, bh);
    final Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(bubble, const Radius.circular(radius)))
      ..moveTo(pos.dx - 8, bubble.bottom)
      ..lineTo(pos.dx, pos.dy)
      ..lineTo(pos.dx + 8, bubble.bottom)
      ..close();
    canvas.drawPath(path, Paint()..color = s.color.withValues(alpha: 0.9));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    tp.paint(canvas, Offset(bubble.left + padding, bubble.top + padding));
  }

  void _drawStepCounter(Canvas canvas, EditorShape s, Offset pos) {
    const double r = 14;
    canvas.drawCircle(pos, r, Paint()..color = s.color);
    canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = Colors.black38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final TextPainter tp = TextPainter(
      text: TextSpan(
          text: '${s.stepNumber ?? 1}',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  Rect _imageBounds() {
    final ui.Image? image = backgroundImage;
    if (image == null) return Rect.zero;
    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  void _drawBlurRect(Canvas canvas, EditorShape shape, Rect rect) {
    final ui.Image? image = shapeImages[shape.id];
    final Rect clipped = rect.intersect(_imageBounds());
    if (image == null || clipped.isEmpty) {
      canvas.drawRect(rect, Paint()..color = Colors.white12);
      _drawDashedRect(canvas, rect, Colors.white54);
      return;
    }

    canvas.save();
    canvas.clipRect(clipped);
    canvas.saveLayer(
      clipped.inflate(24),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      clipped.inflate(16),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    canvas.drawRect(clipped, Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.restore();
    _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawPixelateRect(Canvas canvas, EditorShape shape, Rect rect) {
    final Rect clipped = rect.intersect(_imageBounds());
    if (clipped.isEmpty) {
      _drawDashedRect(canvas, rect, Colors.orangeAccent);
      return;
    }
    _paintPixelatedRgba(canvas, clipped, shape.imageBytes, shape.imageW, shape.imageH, blockSize: 14);
    _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawSmartDeleteRect(Canvas canvas, Rect rect, Color? fillColor) {
    canvas.drawRect(rect, Paint()..color = fillColor ?? Colors.white);
    _drawDashedRect(canvas, rect, Colors.redAccent);
  }

  void _drawImageElement(Canvas canvas, EditorShape shape, Rect rect) {
    final ui.Image? image = shapeImages[shape.id];
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = Colors.white10);
      _drawDashedRect(canvas, rect, Colors.white54);
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (shape.selected) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.lightBlueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _drawSpotlightRect(Canvas canvas, Rect rect) {
    final ui.Image? image = backgroundImage;
    final Rect full = _imageBounds();
    final Path outside = Path()
      ..addRect(full)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;

    if (image != null) {
      canvas.save();
      canvas.clipPath(outside);
      canvas.saveLayer(
        full,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        full,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.28));
      canvas.restore();
    } else {
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawDashedRect(Canvas canvas, Rect r, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double dash = 6, gap = 4;
    void line(Offset a, Offset b) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      double pos = 0;
      bool draw = true;
      while (pos < len) {
        final double end = (pos + (draw ? dash : gap)).clamp(0.0, len);
        if (draw) canvas.drawLine(a + dir * pos, a + dir * end, p);
        pos = end;
        draw = !draw;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  void _paintMeasurement(Canvas canvas, EditorTool tool, Offset start, Offset end, Color color) {
    final double dx = end.dx - start.dx, dy = end.dy - start.dy;
    final double dist = sqrt(dx * dx + dy * dy);
    final double angleDeg = atan2(dy, dx) * 180 / pi;
    String label;
    if (tool == EditorTool.sizebox) {
      final Rect r = Rect.fromPoints(start, end);
      label = 'X:${r.left.round()} Y:${r.top.round()} W:${r.width.round()} H:${r.height.round()}';
    } else {
      label = '${dist.round()}px  Δ${dx.round()},${dy.round()}  ${angleDeg.toStringAsFixed(1)}°';
    }
    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final TextPainter tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              backgroundColor: Colors.black.withValues(alpha: 0.9),
              fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - 30));
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor Toolbar
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List?> _renderEditorPngBytes({
  required ui.Image backgroundImage,
  required List<EditorShape> shapes,
  required Map<String, ui.Image> shapeImages,
}) async {
  final int width = backgroundImage.width;
  final int height = backgroundImage.height;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

  final _EditorPainter painter = _EditorPainter(
    shapes: shapes,
    currentShape: null,
    currentEnd: null,
    backgroundImage: backgroundImage,
    shapeImages: shapeImages,
    gridVisible: false,
    imageRectOverride: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  painter.paint(canvas, Size(width.toDouble(), height.toDouble()));

  final ui.Image rendered = await recorder.endRecording().toImage(width, height);
  final ByteData? byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

void _paintPixelatedRgba(
  Canvas canvas,
  Rect bounds,
  Uint8List? rgba,
  int? imageW,
  int? imageH, {
  double blockSize = 14,
}) {
  if (rgba == null || imageW == null || imageH == null || imageW <= 0 || imageH <= 0) {
    canvas.drawRect(bounds, Paint()..color = Colors.black.withValues(alpha: 0.20));
    return;
  }

  final int cols = (bounds.width / blockSize).ceil().clamp(1, 1000000).toInt();
  final int rows = (bounds.height / blockSize).ceil().clamp(1, 1000000).toInt();

  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final Rect dst = Rect.fromLTWH(
        bounds.left + col * blockSize,
        bounds.top + row * blockSize,
        blockSize,
        blockSize,
      ).intersect(bounds);
      if (dst.isEmpty) continue;

      final int sx0 = ((dst.left - bounds.left) / bounds.width * imageW).floor().clamp(0, imageW - 1).toInt();
      final int sy0 = ((dst.top - bounds.top) / bounds.height * imageH).floor().clamp(0, imageH - 1).toInt();
      final int sx1 = ((dst.right - bounds.left) / bounds.width * imageW).ceil().clamp(sx0 + 1, imageW).toInt();
      final int sy1 = ((dst.bottom - bounds.top) / bounds.height * imageH).ceil().clamp(sy0 + 1, imageH).toInt();

      int r = 0, g = 0, b = 0, a = 0, count = 0;
      final int stepX = max(1, ((sx1 - sx0) / 4).floor());
      final int stepY = max(1, ((sy1 - sy0) / 4).floor());
      for (int y = sy0; y < sy1; y += stepY) {
        for (int x = sx0; x < sx1; x += stepX) {
          final int index = (y * imageW + x) * 4;
          if (index + 3 >= rgba.length) continue;
          r += rgba[index];
          g += rgba[index + 1];
          b += rgba[index + 2];
          a += rgba[index + 3];
          count++;
        }
      }
      if (count == 0) continue;
      canvas.drawRect(
        dst,
        Paint()
          ..color = Color.fromARGB(
            (a / count).round().clamp(0, 255).toInt(),
            (r / count).round().clamp(0, 255).toInt(),
            (g / count).round().clamp(0, 255).toInt(),
            (b / count).round().clamp(0, 255).toInt(),
          ),
      );
    }
  }
}

class _EditorWindowBar extends StatelessWidget {
  const _EditorWindowBar({
    required this.filePath,
    required this.onBack,
  });

  final String filePath;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final String fileName = filePath.split(RegExp(r'[\\/]')).last;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFF161B24),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: onBack,
            tooltip: 'Back to Capture',
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            color: Colors.white70,
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                final bool maximized = await windowManager.isMaximized();
                if (maximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Row(
                children: <Widget>[
                  const Icon(Icons.photo_size_select_large_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 10),
                  Text(
                    'Photo Editor',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _WindowBarButton(
            icon: Icons.minimize_rounded,
            tooltip: 'Minimize',
            onTap: () => windowManager.minimize(),
          ),
          _WindowBarButton(
            icon: Icons.crop_square_rounded,
            tooltip: 'Maximize / Restore',
            onTap: () async {
              final bool maximized = await windowManager.isMaximized();
              if (maximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _WindowBarButton(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            isClose: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _WindowBarButton extends StatelessWidget {
  const _WindowBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isClose ? Colors.redAccent.withValues(alpha: 0.0) : Colors.transparent,
          ),
          child: Icon(icon, size: 18, color: isClose ? Colors.redAccent.shade100 : Colors.white70),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onBack;

  const _EditorToolbar({required this.ctrl, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TipBtn(
              icon: Icons.arrow_back,
              tooltip: 'Back to Capture (ESC)',
              onTap: onBack,
            ),
            const Divider(color: Colors.white24, height: 10),
            _EditorToolBtn(Icons.mouse_rounded, EditorTool.select, ctrl, 'Select (S)'),
            const Divider(color: Colors.white24, height: 10),
            _EditorToolBtn(Icons.edit, EditorTool.pen, ctrl, 'Pen (P)'),
            _EditorToolBtn(Icons.highlight, EditorTool.highlight, ctrl, 'Highlight (H)'),
            _EditorToolBtn(Icons.remove, EditorTool.line, ctrl, 'Line (L)'),
            _EditorToolBtn(Icons.crop_square, EditorTool.rect, ctrl, 'Rect (R)'),
            _EditorToolBtn(Icons.circle_outlined, EditorTool.ellipse, ctrl, 'Ellipse (E)'),
            _EditorToolBtn(Icons.arrow_forward, EditorTool.arrow, ctrl, 'Arrow (A)'),
            const Divider(color: Colors.white24, height: 10),
            _EditorToolBtn(Icons.text_fields, EditorTool.text, ctrl, 'Text (T)'),
            _EditorToolBtn(Icons.emoji_emotions_outlined, EditorTool.emoji, ctrl, 'Emoji'),
            _EditorToolBtn(Icons.format_list_numbered, EditorTool.stepCounter, ctrl, 'Step (N)'),
            _EditorToolBtn(Icons.chat_bubble_outline, EditorTool.infoBalloon, ctrl, 'Balloon (I)'),
            const Divider(color: Colors.white24, height: 10),
            _EditorToolBtn(Icons.blur_on, EditorTool.blur, ctrl, 'Blur (F)'),
            _EditorToolBtn(Icons.grid_3x3, EditorTool.pixelate, ctrl, 'Pixelate (X)'),
            _EditorToolBtn(Icons.auto_fix_high, EditorTool.smartDelete, ctrl, 'Smart Delete (D)'),
            _EditorToolBtn(Icons.image_outlined, EditorTool.imageElement, ctrl, 'Image (G)'),
            _EditorToolBtn(Icons.highlight_alt, EditorTool.spotlight, ctrl, 'Spotlight'),
            const Divider(color: Colors.white24, height: 10),
            _EditorToolBtn(Icons.straighten, EditorTool.ruler, ctrl, 'Ruler (M)'),
            _EditorToolBtn(Icons.aspect_ratio, EditorTool.sizebox, ctrl, 'Sizebox (B)'),
            const Divider(color: Colors.white24, height: 10),
            _EditorColorBtn(ctrl),
            _EditorWidthBtn(ctrl),
            const Divider(color: Colors.white24, height: 10),
            _TipBtn(icon: Icons.undo, tooltip: 'Undo (Ctrl+Z)', onTap: ctrl.undo),
            _TipBtn(icon: Icons.redo, tooltip: 'Redo (Ctrl+Y)', onTap: ctrl.redo),
            _TipBtn(icon: Icons.delete_sweep, tooltip: 'Clear All', onTap: ctrl.clearAll),
            _TipBtn(icon: Icons.grid_on, tooltip: 'Toggle Grid', onTap: ctrl.toggleGrid),
            _TipBtn(icon: Icons.exposure_zero, tooltip: 'Reset Steps', onTap: ctrl.resetStepCounter),
          ],
        ),
      ),
    );
  }
}

class _EditorToolBtn extends StatelessWidget {
  final IconData icon;
  final EditorTool tool;
  final EditorController ctrl;
  final String tooltip;

  const _EditorToolBtn(this.icon, this.tool, this.ctrl, this.tooltip);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (_, __) {
        final bool active = ctrl.activeTool == tool;
        return CustomTooltip(
          message: tooltip,
          child: IconButton(
            icon: Icon(icon, size: 18),
            color: active ? Colors.yellowAccent : Colors.white70,
            onPressed: () => ctrl.setTool(tool),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        );
      },
    );
  }
}

class _TipBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TipBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: Colors.white70,
        onPressed: onTap,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

// Color picker popup button
class _EditorColorBtn extends StatefulWidget {
  final EditorController ctrl;
  const _EditorColorBtn(this.ctrl);
  @override
  State<_EditorColorBtn> createState() => _EditorColorBtnState();
}

class _EditorColorBtnState extends State<_EditorColorBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlay;
  final LayerLink _link = LayerLink();

  void _show() {
    _closeTimer?.cancel();
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 420,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(42, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    ..._Palette.colors.map((ui.Color c) => GestureDetector(
                          onTap: () {
                            widget.ctrl.setColor(c);
                            _hide();
                          },
                          child: ListenableBuilder(
                            listenable: widget.ctrl,
                            builder: (_, __) => Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: widget.ctrl.strokeColor == c
                                    ? Border.all(color: Colors.white, width: 2.5)
                                    : Border.all(color: Colors.white24),
                              ),
                            ),
                          ),
                        )),
                    CustomColorPicker(
                      startColor: widget.ctrl.strokeColor,
                      themeOptions: <List<int>>[<int>[]],
                      colorIndex: 0,
                      onColorChanged: (Color color) {
                        widget.ctrl.setColor(color);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), _hide);
  }

  void _hide() {
    _closeTimer?.cancel();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: ListenableBuilder(
        listenable: widget.ctrl,
        builder: (_, __) => MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleHide(),
          child: CustomTooltip(
            message: 'Color',
            child: Container(
              width: 36,
              height: 28,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.ctrl.strokeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Width popup button
class _EditorWidthBtn extends StatefulWidget {
  final EditorController ctrl;
  const _EditorWidthBtn(this.ctrl);
  @override
  State<_EditorWidthBtn> createState() => _EditorWidthBtnState();
}

class _EditorWidthBtnState extends State<_EditorWidthBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlay;
  final LayerLink _link = LayerLink();
  static const List<double> _widths = <double>[1, 2, 4, 8];

  void _show() {
    _closeTimer?.cancel();
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(42, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _widths
                      .map((double w) => GestureDetector(
                            onTap: () {
                              widget.ctrl.setStrokeWidth(w);
                              _hide();
                            },
                            child: ListenableBuilder(
                              listenable: widget.ctrl,
                              builder: (_, __) => Container(
                                width: 36,
                                height: 32,
                                margin: const EdgeInsets.only(right: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: widget.ctrl.strokeWidth == w ? Colors.white24 : Colors.transparent,
                                ),
                                child: Container(
                                  width: 24,
                                  height: w,
                                  decoration: BoxDecoration(
                                    color: widget.ctrl.strokeColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), _hide);
  }

  void _hide() {
    _closeTimer?.cancel();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: ListenableBuilder(
        listenable: widget.ctrl,
        builder: (_, __) => MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleHide(),
          child: CustomTooltip(
            message: 'Stroke Width',
            child: Container(
              width: 36,
              height: 28,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Container(
                width: 24,
                height: widget.ctrl.strokeWidth.clamp(1.0, 8.0),
                decoration: BoxDecoration(
                  color: widget.ctrl.strokeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Save / Export button (bottom right)
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final EditorController ctrl;
  final ui.Image? backgroundImage;
  final String filePath;
  final Map<String, ui.Image> shapeImages;
  final Future<void> Function() onCaptureMore;
  final bool captureMoreBusy;

  const _SaveButton({
    required this.ctrl,
    required this.backgroundImage,
    required this.filePath,
    required this.shapeImages,
    required this.onCaptureMore,
    required this.captureMoreBusy,
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saving = false;
  String? _msg;

  Future<Uint8List?> _renderEditedPng() async {
    final ui.Image? backgroundImage = widget.backgroundImage;
    if (backgroundImage == null) return null;
    return _renderEditorPngBytes(
      backgroundImage: backgroundImage,
      shapes: widget.ctrl.shapes,
      shapeImages: widget.shapeImages,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final Uint8List? pngBytes = await _renderEditedPng();
      if (pngBytes == null) return;
      final String savedPath = await ScreenCapture.saveToFile(pngBytes);
      if (mounted) {
        setState(() {
          _msg = 'Saved to $savedPath';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final Uint8List? pngBytes = await _renderEditedPng();
      if (pngBytes == null) return;
      await ScreenCapture.copyPngToClipboard(pngBytes);
      if (mounted) {
        setState(() {
          _msg = 'Copied to clipboard';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_msg!, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A9EFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_alt, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Edited'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _saving ? null : _copyToClipboard,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy to clipboard'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: widget.captureMoreBusy ? null : widget.onCaptureMore,
              icon: widget.captureMoreBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(widget.captureMoreBusy ? 'Capturing…' : 'Capture More'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => appState.backToCapture(),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('New Capture'),
            ),
          ],
        ),
      ],
    );
  }
}
