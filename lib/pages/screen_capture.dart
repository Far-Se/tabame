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
import '../widgets/widgets/font_picker/models/picker_font.dart';
import '../widgets/widgets/font_picker/ui/font_picker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> startScreenCapture() async {
  WidgetsFlutterBinding.ensureInitialized();

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1920, 1080),
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

  runApp(const ScreenCaptureApp());
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
      exStyle | WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Root app widget
// ─────────────────────────────────────────────────────────────────────────────

class ScreenCaptureApp extends StatelessWidget {
  const ScreenCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Timer? _monitorTimer;
  int _currentMonitor = 0;
  Square _monitorData = Square(x: 0, y: 0, width: 0, height: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Win32Window.setupOverlay();
      Win32Window.disableClickThrough();
    });
    Monitor.fetchMonitors();
    _monitorTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _checkMonitor());

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

  Future<void> _checkMonitor() async {
    if (!mounted || appState.view == AppView.editor) return;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);

    if (monitor != _currentMonitor) {
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
          return const ScreenCaptureView();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen Capture View
// ─────────────────────────────────────────────────────────────────────────────

class ScreenCaptureView extends StatefulWidget {
  const ScreenCaptureView({super.key});
  @override
  State<ScreenCaptureView> createState() => _ScreenCaptureViewState();
}

class _ScreenCaptureViewState extends State<ScreenCaptureView> {
  CaptureActionMode _captureActionMode = CaptureActionMode.ask;
  List<FancyShotProfile> _fancyShotProfiles = <FancyShotProfile>[];
  String? _selectedFancyShotPresetName;
  Offset? _captureStart;
  Offset? _captureCurrent;
  bool _capturing = false;
  bool _captureEnabled = true;
  Timer? _tickerTimer;
  final Set<String> _pressedScreenCaptureHotkeys = <String>{};

  @override
  void initState() {
    super.initState();
    _fancyShotProfiles = FancyShot.loadProfiles();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _ticker());
  }

  void _ticker() {
    _handleScreenDrawHotkeys();
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
                setState(() => _captureCurrent = d.localPosition);
              },
              onPanEnd: (_) async {
                if (_captureStart == null || _captureCurrent == null) return;
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
                    value: _captureActionMode,
                    onChanged: (CaptureActionMode mode) {
                      setState(() => _captureActionMode = mode);
                    },
                  ),
                  const SizedBox(width: 12),
                  _FancyShotPresetDropdown(
                    presetNames: _fancyShotProfiles.map((FancyShotProfile profile) => profile.name).toList(),
                    value: _selectedFancyShotPresetName,
                    onChanged: (String? presetName) {
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
        pngBytes = await ScreenCapture.captureRegionToPng(screenRect);
      } finally {
        ShowWindow(hwnd, SW_SHOW);
      }
      if (pngBytes == null || !mounted) return;

      final Uint8List outputBytes = await _applySelectedPreset(pngBytes);
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
    if (presetName == null) return pngBytes;

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
    switch (_captureActionMode) {
      case CaptureActionMode.ask:
        _showCaptureModal(pngBytes, filePath, imageW, imageH);
        return;
      case CaptureActionMode.copyImageToClipboard:
        await ScreenCapture.copyPngToClipboard(pngBytes);
        await _finishClipboardAction();
        return;
      case CaptureActionMode.copyImageFileToClipboard:
        await ScreenCapture.copyFileToClipboard(filePath);
        await _finishClipboardAction();
        return;
      case CaptureActionMode.openPhotoEditor:
        appState.openEditor(filePath, pngBytes, imageW, imageH);
        return;
    }
  }

  Future<void> _finishClipboardAction() async {
    if (kDebugMode) {
      appState.backToCapture();
      await windowManager.focus();
      return;
    }
    await windowManager.close();
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
  final CaptureActionMode value;
  final ValueChanged<CaptureActionMode> onChanged;

  const _CaptureActionDropdown({
    required this.value,
    required this.onChanged,
  });

  static const List<({CaptureActionMode mode, String title, String subtitle, IconData icon})> _options =
      <({CaptureActionMode mode, String title, String subtitle, IconData icon})>[
    (
      mode: CaptureActionMode.ask,
      title: 'Ask',
      subtitle: 'Show the action popup after each capture',
      icon: Icons.help_outline,
    ),
    (
      mode: CaptureActionMode.copyImageToClipboard,
      title: 'Copy Image to Clipboard',
      subtitle: 'Copy the captured bitmap and close',
      icon: Icons.image_outlined,
    ),
    (
      mode: CaptureActionMode.copyImageFileToClipboard,
      title: 'Copy Image File to Clipboard',
      subtitle: 'Copy the saved screenshot file and close',
      icon: Icons.file_copy_outlined,
    ),
    (
      mode: CaptureActionMode.openPhotoEditor,
      title: 'Open Photo Editor',
      subtitle: 'Open the screenshot directly in the editor',
      icon: Icons.edit_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ({CaptureActionMode mode, String title, String subtitle, IconData icon}) selected = _options.firstWhere(
      (({IconData icon, CaptureActionMode mode, String subtitle, String title}) option) => option.mode == value,
    );

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<CaptureActionMode>(
        tooltip: 'Capture action',
        color: const Color(0xFF121826),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Colors.white24),
        ),
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => _options
            .map(
              (({IconData icon, CaptureActionMode mode, String subtitle, String title}) option) =>
                  PopupMenuItem<CaptureActionMode>(
                value: option.mode,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: option.mode == value ? const Color(0xFF4A9EFF).withValues(alpha: 0.18) : Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        option.icon,
                        size: 18,
                        color: option.mode == value ? const Color(0xFF7DB8FF) : Colors.white70,
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
            value: null,
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
    tp.paint(canvas, sel.bottomRight + const Offset(4, 4));
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
  stepCounter,
  infoBalloon,
  blur,
  pixelate,
  smartDelete,
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
    List<Offset>? points,
    bool? selected,
    String? text,
    Uint8List? imageBytes,
    int? imageW,
    int? imageH,
    String? fontFamily,
  }) {
    return EditorShape(
      tool: tool,
      points: points ?? this.points,
      color: color,
      strokeWidth: strokeWidth,
      opacity: opacity,
      selected: selected ?? this.selected,
      text: text ?? this.text,
      textBackground: textBackground,
      textColor: textColor,
      fontSize: fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      stepNumber: stepNumber,
      imageBytes: imageBytes ?? this.imageBytes,
      imageW: imageW ?? this.imageW,
      imageH: imageH ?? this.imageH,
      fillColor: fillColor,
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

  void startShape(Offset pos) {
    _redo.clear();
    currentShape = EditorShape(
      tool: activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
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
    _shapes.add(committed);
    if (committed.tool == EditorTool.stepCounter) _stepCount++;
    currentShape = null;
    currentEnd = null;
    notifyListeners();
  }

  void commitTextShape(Offset pos, String text, {double? size}) {
    _shapes.add(EditorShape(
      tool: activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      text: text,
      textBackground: textBackground,
      textColor: textColor,
      fontSize: size ?? fontSize,
      fontFamily: fontFamily,
    ));
    notifyListeners();
  }

  void commitRegionShape(EditorTool tool, Rect region, Uint8List bytes, int w, int h, {Color? fillColor}) {
    _shapes.add(EditorShape(
      tool: tool,
      points: <ui.Offset>[region.topLeft, region.bottomRight],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      imageBytes: bytes,
      imageW: w,
      imageH: h,
      fillColor: fillColor,
    ));
    notifyListeners();
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
    notifyListeners();
  }

  void selectShapeAt(Offset pos) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        for (EditorShape s in _shapes) {
          s.selected = false;
        }
        _shapes[i].selected = true;
        selectedShapeIndex = i;
        notifyListeners();
        return;
      }
    }
    for (EditorShape s in _shapes) {
      s.selected = false;
    }
    selectedShapeIndex = null;
    notifyListeners();
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

    if (s.tool == EditorTool.text || s.tool == EditorTool.infoBalloon) {
      return Rect.fromCircle(center: a, radius: 30).contains(pos);
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
        s.tool == EditorTool.spotlight ||
        s.tool == EditorTool.magnifier) {
      return Rect.fromPoints(a, b).inflate(6).contains(pos);
    }

    final Offset center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return (center - pos).distance < 24;
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
  ui.Image? _backgroundImage;
  img.Image? _sourceImage;
  bool _shiftHeld = false;
  Offset? _lastSelectPos;
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _selectMode = false;

  // For region tools (blur/pixelate/smartDelete)
  bool _isRegionDragging = false;

  @override
  void initState() {
    super.initState();
    _decodeBackground();
  }

  Future<void> _decodeBackground() async {
    _sourceImage = img.decodeImage(widget.initialImageBytes);
    // final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(widget.initialImageBytes);
    // final ui.ImageDescriptor desc = ui.ImageDescriptor.raw(
    //   buf,
    //   width: widget.imageW,
    //   height: widget.imageH,
    //   pixelFormat: ui.PixelFormat.rgba8888,
    // );
    // Use flutter's standard PNG decode instead for background
    final ui.Codec codec = await ui.instantiateImageCodec(widget.initialImageBytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _backgroundImage = frame.image);
  }

  bool _isRegionTool(EditorTool t) => t == EditorTool.blur || t == EditorTool.pixelate || t == EditorTool.smartDelete;

  Rect _imageRect(Size viewSize) {
    final ui.Image? image = _backgroundImage;
    if (image == null || viewSize.width <= 0 || viewSize.height <= 0) return Rect.zero;
    final double scale = min(viewSize.width / image.width, viewSize.height / image.height);
    final double w = image.width * scale;
    final double h = image.height * scale;
    return Rect.fromLTWH((viewSize.width - w) / 2, (viewSize.height - h) / 2, w, h);
  }

  Offset? _viewToImage(Offset viewPos) {
    final Size viewSize = MediaQuery.of(context).size;
    final Rect rect = _imageRect(viewSize);
    final ui.Image? image = _backgroundImage;
    if (image == null || rect.isEmpty || !rect.contains(viewPos)) return null;
    final double scale = rect.width / image.width;
    return Offset((viewPos.dx - rect.left) / scale, (viewPos.dy - rect.top) / scale);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: <Widget>[
          // Background: center the captured image
          Positioned.fill(
            child: Container(color: const Color(0xFF0A0A0F)),
          ),
          // Image canvas centered
          Positioned.fill(
            child: Center(
              child: _backgroundImage != null
                  ? FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _backgroundImage!.width.toDouble(),
                        height: _backgroundImage!.height.toDouble(),
                        child: RawImage(image: _backgroundImage),
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          // Drawing layer (fills whole screen; shapes are in image space via transform)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onTapDown: _onTapDown,
              onSecondaryTapDown: (TapDownDetails d) {
                final Offset? imagePos = _viewToImage(d.localPosition);
                if (imagePos != null) _ctrl.deleteShapeAt(imagePos);
              },
              child: ListenableBuilder(
                listenable: _ctrl,
                builder: (_, __) => CustomPaint(
                  size: screenSize,
                  painter: _EditorPainter(
                    shapes: _ctrl.shapes,
                    currentShape: _ctrl.currentShape,
                    currentEnd: _ctrl.currentEnd,
                    backgroundImage: _backgroundImage,
                    gridVisible: _ctrl.gridVisible,
                    dragStart: _dragStart,
                    dragCurrent: _dragCurrent,
                    isRegionDrag: _isRegionDragging,
                  ),
                ),
              ),
            ),
          ),
          // Toolbar
          Positioned(
            left: 8,
            top: 8,
            child: _EditorToolbar(ctrl: _ctrl, onBack: () => appState.backToCapture()),
          ),
          // Save button
          Positioned(
            right: 16,
            bottom: 16,
            child: _SaveButton(ctrl: _ctrl, backgroundImage: _backgroundImage, filePath: widget.filePath),
          ),
        ],
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

  void _onPanStart(DragStartDetails d) {
    final Offset? imagePos = _viewToImage(d.localPosition);
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

  void _onPanUpdate(DragUpdateDetails d) {
    final Offset? imagePos = _viewToImage(d.localPosition);
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

  void _onPanEnd(DragEndDetails _) {
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      _lastSelectPos = null;
      return;
    }
    if (_isRegionTool(_ctrl.activeTool) && _dragStart != null && _dragCurrent != null) {
      final Rect region = Rect.fromPoints(_dragStart!, _dragCurrent!).normalized();
      if (region.width > 4 && region.height > 4) {
        _commitRegion(region);
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

  void _onTapDown(TapDownDetails d) {
    final Offset? imagePos = _viewToImage(d.localPosition);
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
    if (_ctrl.activeTool == EditorTool.stepCounter) {
      _ctrl.startShape(pos);
      _ctrl.endShape();
      return;
    }
  }

  void _commitRegion(Rect region) {
    if (_backgroundImage == null) return;
    final Color fillColor = _smartDeleteFillColor(region);
    _ctrl.commitRegionShape(
      _ctrl.activeTool,
      region,
      Uint8List(0),
      region.width.round(),
      region.height.round(),
      fillColor: fillColor,
    );
  }

  Color _smartDeleteFillColor(Rect region) {
    final img.Image? source = _sourceImage;
    if (source == null || source.width == 0 || source.height == 0) {
      return Colors.white;
    }

    final int x = region.left.floor().clamp(0, source.width - 1);
    final int y = region.top.floor().clamp(0, source.height - 1);
    final img.Pixel pixel = source.getPixelSafe(x, y);
    return Color.fromARGB(
      pixel.a.toInt(),
      pixel.r.toInt(),
      pixel.g.toInt(),
      pixel.b.toInt(),
    );
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
      _ctrl.setFontFamily(result[2] as String);
      _ctrl.commitTextShape(pos, result[0] as String, size: result[1] as double);
    }
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
  final bool gridVisible;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final bool isRegionDrag;

  _EditorPainter({
    required this.shapes,
    required this.currentShape,
    required this.currentEnd,
    required this.backgroundImage,
    required this.gridVisible,
    this.dragStart,
    this.dragCurrent,
    this.isRegionDrag = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = backgroundImage;
    final Rect imageRect = _displayImageRect(size);

    if (image != null && !imageRect.isEmpty) {
      final double scale = imageRect.width / image.width;
      canvas.save();
      canvas.clipRect(imageRect);
      canvas.translate(imageRect.left, imageRect.top);
      canvas.scale(scale, scale);

      for (final EditorShape s in shapes) {
        _paintShape(canvas, s, null);
      }
      if (currentShape != null) _paintShape(canvas, currentShape!, currentEnd);

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
    final ui.Image? image = backgroundImage;
    if (image == null || size.width <= 0 || size.height <= 0) return Rect.zero;
    final double scale = min(size.width / image.width, size.height / image.height);
    final double w = image.width * scale;
    final double h = image.height * scale;
    return Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);
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
      case EditorTool.infoBalloon:
        _drawInfoBalloon(canvas, s, start);
        return;
      case EditorTool.stepCounter:
        _drawStepCounter(canvas, s, start);
        return;
      case EditorTool.blur:
        _drawBlurRect(canvas, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.pixelate:
        _drawPixelateRect(canvas, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.smartDelete:
        _drawSmartDeleteRect(canvas, Rect.fromPoints(start, end).normalized(), s.fillColor);
        return;
      case EditorTool.spotlight:
        _drawSpotlightRect(canvas, canvas.getSaveCount().toDouble(), Rect.fromPoints(start, end).normalized());
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
    final String family = s.fontFamily ?? 'Roboto';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(
          color: tc,
          fontSize: fs,
          fontWeight: FontWeight.bold,
          fontFamily: GoogleFonts.getFont(family).fontFamily,
        ),
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

  void _drawInfoBalloon(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    const double padding = 10, tailH = 14, radius = 8;
    final String family = s.fontFamily ?? 'Roboto';
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(
          color: Colors.white,
          fontSize: s.strokeWidth * 6 + 12,
          fontFamily: GoogleFonts.getFont(family).fontFamily,
        ),
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

  void _drawBlurRect(Canvas canvas, Rect rect) {
    final ui.Image? image = backgroundImage;
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
    canvas.drawImageRect(image, clipped, clipped, Paint());
    canvas.restore();
    canvas.restore();
    _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawPixelateRect(Canvas canvas, Rect rect) {
    final ui.Image? image = backgroundImage;
    final Rect clipped = rect.intersect(_imageBounds());
    if (image == null || clipped.isEmpty) {
      _drawDashedRect(canvas, rect, Colors.orangeAccent);
      return;
    }

    const double blockSize = 12.0;
    final int cols = (clipped.width / blockSize).ceil();
    final int rows = (clipped.height / blockSize).ceil();

    canvas.save();
    canvas.clipRect(clipped);

    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final Rect dst = Rect.fromLTWH(
          clipped.left + col * blockSize,
          clipped.top + row * blockSize,
          blockSize,
          blockSize,
        ).intersect(clipped);
        if (dst.isEmpty) continue;

        final double sampleX = dst.center.dx.clamp(clipped.left, clipped.right - 1.0);
        final double sampleY = dst.center.dy.clamp(clipped.top, clipped.bottom - 1.0);

        canvas.drawImageRect(
          image,
          Rect.fromLTWH(sampleX, sampleY, 1, 1),
          dst,
          Paint()
            ..filterQuality = FilterQuality.none
            ..isAntiAlias = false,
        );
      }
    }
    canvas.restore();
    _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawSmartDeleteRect(Canvas canvas, Rect rect, Color? fillColor) {
    canvas.drawRect(rect, Paint()..color = fillColor ?? Colors.white);
    _drawDashedRect(canvas, rect, Colors.redAccent);
  }

  void _drawSpotlightRect(Canvas canvas, double _, Rect rect) {
    canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.08));
    canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
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
    tp.paint(canvas, mid + const Offset(6, -14));
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

class _EditorToolbar extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onBack;

  const _EditorToolbar({required this.ctrl, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Container(
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
              // Back button
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
              _EditorToolBtn(Icons.format_list_numbered, EditorTool.stepCounter, ctrl, 'Step (N)'),
              _EditorToolBtn(Icons.chat_bubble_outline, EditorTool.infoBalloon, ctrl, 'Balloon (I)'),
              const Divider(color: Colors.white24, height: 10),
              _EditorToolBtn(Icons.blur_on, EditorTool.blur, ctrl, 'Blur (F)'),
              _EditorToolBtn(Icons.grid_3x3, EditorTool.pixelate, ctrl, 'Pixelate (X)'),
              _EditorToolBtn(Icons.auto_fix_high, EditorTool.smartDelete, ctrl, 'Smart Delete (D)'),
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

  const _SaveButton({
    required this.ctrl,
    required this.backgroundImage,
    required this.filePath,
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saving = false;
  String? _msg;

  Future<Uint8List?> _renderEditedPng() async {
    if (widget.backgroundImage == null) return null;

    final int w = widget.backgroundImage!.width;
    final int h = widget.backgroundImage!.height;
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));

    canvas.drawImage(widget.backgroundImage!, Offset.zero, Paint());

    final _EditorPainter painter = _EditorPainter(
      shapes: widget.ctrl.shapes,
      currentShape: null,
      currentEnd: null,
      backgroundImage: widget.backgroundImage,
      gridVisible: false,
    );
    painter.paint(canvas, Size(w.toDouble(), h.toDouble()));

    final ui.Picture picture = recorder.endRecording();
    final ui.Image rendered = await picture.toImage(w, h);
    final ByteData? byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Failed to encode');

    return byteData.buffer.asUint8List();
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
