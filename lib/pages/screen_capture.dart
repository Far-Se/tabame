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
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/win32/mixed.dart';
import '../models/win32/screenshot.dart';
import '../models/win32/win_utils.dart';
import '../widgets/interface/fancyshot.dart';
import 'photo_editor.dart';

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
  await windowManager.setPosition(const Offset(-1000, -1000));
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    Win32Window._hwnd = GetAncestor(GetActiveWindow(), 2);
    await Boxes.registerBoxes(justLoad: true);
    Settings.load();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
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

Future<void> openPhotoEditorForCapture({
  required String filePath,
  required Uint8List bytes,
  required int imageW,
  required int imageH,
}) async {
  if (kReleaseMode) {
    final String escapedFilePath = filePath.replaceAll('"', '\\"');
    WinUtils.startTabame(
      closeCurrent: false,
      arguments: '-editor -file "$escapedFilePath"',
    );
    return;
  }

  appState.openEditor(filePath, bytes, imageW, imageH);
}

class Settings {
  static String get _path => '${WinUtils.getTabameAppDataFolder(settings: true)}\\screen_capture.json';
  static Map<String, dynamic> _data = <String, dynamic>{};

  static void load() {
    try {
      final File file = File(_path);
      if (file.existsSync()) {
        final String content = file.readAsStringSync();
        _data = jsonDecode(content) as Map<String, dynamic>;
      }

      // Migration from Boxes.pref if new settings are missing
      bool migrated = false;
      if (!_data.containsKey("screenCaptureModeKey")) {
        final String? oldMode = Boxes.pref.getString("screenCaptureModeKey");
        if (oldMode != null) {
          _data["screenCaptureModeKey"] = oldMode;
          migrated = true;
        }
      }
      if (!_data.containsKey("screenCaptureFancyShot")) {
        final String? oldFancy = Boxes.pref.getString("screenCaptureFancyShot");
        if (oldFancy != null) {
          _data["screenCaptureFancyShot"] = oldFancy;
          migrated = true;
        }
      }
      if (migrated) save();
    } catch (e) {
      // ignore
    }
  }

  static void save() {
    try {
      final File file = File(_path);
      file.writeAsStringSync(jsonEncode(_data));
    } catch (e) {
      // ignore
    }
  }

  static String? getString(String key) => _data[key] as String?;
  static void setString(String key, String value) {
    _data[key] = value;
    save();
  }
}

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

  static void setVisible(bool visible) {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;
    ShowWindow(hwnd, visible ? SW_SHOW : SW_HIDE);
    if (visible) {
      SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
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
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      WinUtils.setSortByDateModifiedDesc(dir.path);
    }

    final String ts =
        DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-').replaceFirst(RegExp(r'^.*?T'), '');
    final String path = '${dir.path}\\$ts.png';
    await File(path).writeAsBytes(pngBytes);
    return path;
  }

  static Future<FrozenMonitorSnapshot?> captureMonitorSnapshot(int monitorHandle) async {
    final MonitorBitmapCapture? capture = captureMonitorBitmapByHandle(monitorHandle);
    if (capture == null || capture.width <= 0 || capture.height <= 0 || capture.rgbaBytes.isEmpty) {
      return null;
    }

    return FrozenMonitorSnapshot(
      monitorHandle: monitorHandle,
      screenRect: Rect.fromLTWH(
        capture.left.toDouble(),
        capture.top.toDouble(),
        capture.width.toDouble(),
        capture.height.toDouble(),
      ),
      rgbaBytes: capture.rgbaBytes,
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

class FrozenMonitorSnapshot {
  const FrozenMonitorSnapshot({
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
      home: FancyShotCaptureWidget(freezeMode: freezeMode),
    );
  }
}

class FancyShotCaptureWidget extends StatefulWidget {
  const FancyShotCaptureWidget({
    super.key,
    required this.freezeMode,
  });

  final bool freezeMode;

  @override
  State<FancyShotCaptureWidget> createState() => _FancyShotCaptureWidgetState();
}

class _FancyShotCaptureWidgetState extends State<FancyShotCaptureWidget> {
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
    if (kReleaseMode) {
      try {
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
      } catch (e) {
        return const SizedBox();
      }
    }
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
  final Map<int, FrozenMonitorSnapshot> _frozenMonitorSnapshots = <int, FrozenMonitorSnapshot>{};
  final Map<int, ui.Image> _frozenMonitorImages = <int, ui.Image>{};
  final Set<int> _frozenMonitorImageLoadsInProgress = <int>{};
  Future<void>? _frozenSnapshotWarmup;
  int? _visibleFrozenMonitorHandle;
  bool _visibleFrozenMonitorSyncInProgress = false;

  @override
  void initState() {
    super.initState();

    _fancyShotProfiles = FancyShot.loadProfiles();
    Settings.load();
    _uploadHosts = FancyShot.loadUploadHosts();
    final String? savedActionId = Settings.getString("screenCaptureModeKey");
    if (savedActionId != null && _captureChoices().any((CaptureActionChoice choice) => choice.id == savedActionId)) {
      _captureActionId = savedActionId;
    }
    final String fancySaved = Settings.getString("screenCaptureFancyShot") ?? "";
    if (fancySaved != "" && _fancyShotProfiles.any((FancyShotProfile e) => e.name == fancySaved)) {
      _selectedFancyShotPresetName = fancySaved;
    }
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _ticker());
    if (widget.freezeMode) {
      _frozenSnapshotWarmup = _warmFrozenMonitorSnapshots();
      unawaited(_syncVisibleFrozenMonitor(forceRefresh: true));
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
    // _handleScreenDrawHotkeys();
    if (widget.freezeMode) {
      unawaited(_syncVisibleFrozenMonitor());
    }
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
    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
    try {
      Monitor.fetchMonitors();
      for (final int monitorHandle in Monitor.list) {
        final FrozenMonitorSnapshot? snapshot = await _ensureFrozenMonitorSnapshot(monitorHandle);

        if (snapshot != null) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await _ensureFrozenMonitorImage(
            monitorHandle,
            snapshot: snapshot,
            notify: false,
          );
        }
      }
    } finally {
      if (hwnd != 0) {
        ShowWindow(hwnd, SW_SHOW);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<FrozenMonitorSnapshot?> _ensureFrozenMonitorSnapshot(int monitorHandle) async {
    final FrozenMonitorSnapshot? existing = _frozenMonitorSnapshots[monitorHandle];
    if (existing != null) return existing;
    final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(monitorHandle);
    if (snapshot != null) {
      _frozenMonitorSnapshots[monitorHandle] = snapshot;
    }
    return snapshot;
  }

  Future<ui.Image?> _ensureFrozenMonitorImage(
    int monitorHandle, {
    FrozenMonitorSnapshot? snapshot,
    bool notify = true,
  }) async {
    final ui.Image? existing = _frozenMonitorImages[monitorHandle];
    if (existing != null) return existing;

    if (!_frozenMonitorImageLoadsInProgress.add(monitorHandle)) {
      while (_frozenMonitorImageLoadsInProgress.contains(monitorHandle) && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      return _frozenMonitorImages[monitorHandle];
    }

    try {
      snapshot ??= await _ensureFrozenMonitorSnapshot(monitorHandle);
      if (snapshot == null) return null;

      final ui.Image image = await _decodeFrozenMonitorImage(
        snapshot.rgbaBytes,
        snapshot.pixelWidth,
        snapshot.pixelHeight,
      );

      if (!mounted) {
        image.dispose();
        return null;
      }

      final ui.Image? cached = _frozenMonitorImages[monitorHandle];
      if (cached != null) {
        image.dispose();
        return cached;
      }

      _frozenMonitorImages[monitorHandle] = image;
      if (notify) {
        setState(() {});
      }

      return image;
    } finally {
      _frozenMonitorImageLoadsInProgress.remove(monitorHandle);
    }
  }

  Future<ui.Image> _decodeFrozenMonitorImage(
    Uint8List rgbaBytes,
    int width,
    int height,
  ) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgbaBytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );

    return completer.future;
  }

  Future<void> _syncVisibleFrozenMonitor({bool forceRefresh = false}) async {
    if (!widget.freezeMode || !mounted || _visibleFrozenMonitorSyncInProgress) return;

    _visibleFrozenMonitorSyncInProgress = true;

    final Pointer<POINT> cursorPoint = calloc<POINT>();
    try {
      if (GetCursorPos(cursorPoint) == 0) return;
      final int monitorHandle = MonitorFromPoint(cursorPoint.ref, MONITOR_DEFAULTTONEAREST);
      if (monitorHandle == 0) return;

      final bool monitorChanged = _visibleFrozenMonitorHandle != monitorHandle;
      if (monitorChanged) {
        if (!mounted) return;
        setState(() {
          _visibleFrozenMonitorHandle = monitorHandle;
        });
      }

      if (!forceRefresh && !monitorChanged && _frozenMonitorImages.containsKey(monitorHandle)) {
        return;
      }

      final FrozenMonitorSnapshot? snapshot = await _ensureFrozenMonitorSnapshot(monitorHandle);
      if (snapshot == null) return;
      await _ensureFrozenMonitorImage(monitorHandle, snapshot: snapshot);
    } finally {
      calloc.free(cursorPoint);
      _visibleFrozenMonitorSyncInProgress = false;
    }
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

    final FrozenMonitorSnapshot? snapshot = await _ensureFrozenMonitorSnapshot(monitorHandle);
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
    for (final ui.Image image in _frozenMonitorImages.values) {
      image.dispose();
    }
    super.dispose();
  }

  void closeMainWindow() async {
    if (Globals.quickMenuPage == QuickMenuPage.fancyShotLive ||
        Globals.quickMenuPage == QuickMenuPage.fancyShotFreeze) {
      _toggleScreenCaptureEnabled();
      Navigator.of(context).maybePop();
      QuickMenuFunctions.refreshQuickMenu();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      QuickMenuFunctions.toggleQuickMenu(visible: false);
    } else {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui.Size size = MediaQuery.of(context).size;

    final ui.Image? frozenBackgroundImage = widget.freezeMode && _visibleFrozenMonitorHandle != null
        ? _frozenMonitorImages[_visibleFrozenMonitorHandle!]
        : null;
    if (!_captureEnabled) {
      return const SizedBox.expand();
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          closeMainWindow();
        }
      },
      child: Stack(
        children: <Widget>[
          if (widget.freezeMode && frozenBackgroundImage != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RawImage(
                  image: frozenBackgroundImage,
                  fit: BoxFit.fill,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          // Dim overlay with crosshair region selector
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (PointerDownEvent event) {
                if ((event.buttons & kSecondaryMouseButton) != 0) {
                  if (_capturing) {
                    _resetActiveCaptureSelection();
                  } else {
                    closeMainWindow();
                  }
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
                      Settings.setString("screenCaptureModeKey", actionId);
                      setState(() => _captureActionId = actionId);
                    },
                  ),
                  const SizedBox(width: 12),
                  _FancyShotPresetDropdown(
                    presetNames: _fancyShotProfiles.map((FancyShotProfile profile) => profile.name).toList(),
                    value: _selectedFancyShotPresetName,
                    onChanged: (String? presetName) {
                      if (presetName == "none") presetName = "";
                      Settings.setString("screenCaptureFancyShot", presetName ?? "");
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
          if (_frozenSnapshotWarmup != null) {
            await _frozenSnapshotWarmup;
          }
          pngBytes = await _captureFrozenRegionToPng(screenRect);
          // pngBytes = await ScreenCapture.captureRegionToPng(screenRect);
        }
      } finally {
        ShowWindow(hwnd, SW_SHOW);
      }
      if (pngBytes == null || !mounted) return;

      final List<CaptureActionChoice> choices = _captureChoices();
      final CaptureActionChoice choice = choices.firstWhere(
        (CaptureActionChoice item) => item.id == _captureActionId,
        orElse: () => CaptureActionChoice.builtIn.first,
      );

      Uint8List outputBytes = pngBytes;
      final bool needsPresetForResult = choice.uploadHost != null ||
          choice.mode == CaptureActionMode.ask ||
          choice.mode == CaptureActionMode.copyImageToClipboard ||
          choice.mode == CaptureActionMode.copyImageFileToClipboard;
      if (needsPresetForResult && (_selectedFancyShotPresetName ?? '').isNotEmpty) {
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

      final String? filePath =
          choice.mode == CaptureActionMode.openPhotoEditor ? null : await ScreenCapture.saveToFile(outputBytes);
      final bool editorNeedsRawFile =
          choice.mode == CaptureActionMode.openPhotoEditor || choice.mode == CaptureActionMode.ask;
      final String rawFilePath = editorNeedsRawFile
          ? (identical(outputBytes, pngBytes)
              ? filePath ?? await ScreenCapture.saveToFile(pngBytes)
              : await ScreenCapture.saveToFile(pngBytes))
          : filePath ?? await ScreenCapture.saveToFile(pngBytes);

      await windowManager.focus();
      if (!mounted) return;

      await _handleCaptureResult(
        pngBytes: outputBytes,
        filePath: filePath ?? rawFilePath,
        editorPngBytes: pngBytes,
        editorFilePath: rawFilePath,
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
    required Uint8List editorPngBytes,
    required String editorFilePath,
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
        _showCaptureModal(
          pngBytes,
          filePath,
          imageW,
          imageH,
          editorPngBytes: editorPngBytes,
          editorFilePath: editorFilePath,
        );
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
        await openPhotoEditorForCapture(
          filePath: editorFilePath,
          bytes: editorPngBytes,
          imageW: imageW,
          imageH: imageH,
        );
        closeMainWindow();
        return;
    }
  }

  Future<void> _finishPostCaptureAction() async {
    // if (kDebugMode) {
    //   appState.backToCapture();
    //   await windowManager.focus();
    //   return;
    // }
    closeMainWindow();
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

  void _showCaptureModal(
    Uint8List pngBytes,
    String filePath,
    int w,
    int h, {
    required Uint8List editorPngBytes,
    required String editorFilePath,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _CaptureModal(
          pngBytes: pngBytes,
          filePath: filePath,
          editorPngBytes: editorPngBytes,
          editorFilePath: editorFilePath,
          imageW: w,
          imageH: h,
          onClose: () {
            closeMainWindow();
          }),
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
            child: PresetMenuRow(
              icon: Icons.block,
              title: 'None',
              subtitle: 'Use the raw captured image',
            ),
          ),
          ...presetNames.map(
            (String presetName) => PopupMenuItem<String?>(
              value: presetName,
              child: PresetMenuRow(
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

class PresetMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const PresetMenuRow({
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

class _CapturePainter extends CustomPainter {
  final Offset? start;
  final Offset? current;
  _CapturePainter({this.start, this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.35);

    if (start == null || current == null) {
      canvas.drawRect(Offset.zero & size, dimPaint);
      return;
    }

    final Rect sel = Rect.fromPoints(start!, current!).normalized();

    final Path dimPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(sel);
    canvas.drawPath(dimPath, dimPaint);

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
  final Uint8List editorPngBytes;
  final String editorFilePath;
  final int imageW;
  final int imageH;
  final Function() onClose;

  const _CaptureModal({
    required this.onClose,
    required this.pngBytes,
    required this.filePath,
    required this.editorPngBytes,
    required this.editorFilePath,
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
                      widget.onClose();
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
                      widget.onClose();
                    },
                  ),
                  const SizedBox(height: 10),
                  _ModalAction(
                    icon: Icons.edit,
                    label: 'Open Photo Editor',
                    subtitle: 'Annotate and draw on the screenshot',
                    color: const Color(0xFF2ECC71),
                    onTap: () async {
                      Navigator.of(context).pop();
                      await openPhotoEditorForCapture(
                        filePath: widget.editorFilePath,
                        bytes: widget.editorPngBytes,
                        imageW: widget.imageW,
                        imageH: widget.imageH,
                      );
                      widget.onClose();
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Recapture', style: TextStyle(color: Colors.white38)),
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
