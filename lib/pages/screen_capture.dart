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
import 'package:just_audio/just_audio.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/screen_utils.dart';
import '../models/settings.dart';
import '../models/win32/imports.dart';
import '../models/win32/mixed.dart';
import '../models/win32/screenshot.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/widgets/custom_tooltip.dart';
import 'photo_editor.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Isolate helpers — must be top-level so compute() can send them
// ─────────────────────────────────────────────────────────────────────────────

/// Plain data descriptor for one monitor's contribution to a cropped capture.
/// All fields are primitive/Uint8List so the object is sendable across isolates.
class _SnapshotSlice {
  const _SnapshotSlice({
    required this.rgba,
    required this.snapW,
    required this.snapH,
    required this.snapLeft,
    required this.snapTop,
    required this.scaleX,
    required this.scaleY,
    required this.selLeft,
    required this.selTop,
    required this.dstColStart,
    required this.dstRowStart,
    required this.dstColEnd,
    required this.dstRowEnd,
  });

  final Uint8List rgba;
  final int snapW;
  final int snapH;
  final double snapLeft;
  final double snapTop;
  final double scaleX;
  final double scaleY;
  final double selLeft;
  final double selTop;
  final int dstColStart;
  final int dstRowStart;
  final int dstColEnd;
  final int dstRowEnd;
}

/// Isolate worker: crop pixels from one or more monitor slices then PNG-encode.
/// [args] = [List<_SnapshotSlice> slices, int outputWidth, int outputHeight]
Uint8List _cropAndEncodePngIsolate(List<dynamic> args) {
  final List<_SnapshotSlice> slices = args[0] as List<_SnapshotSlice>;
  final int outputWidth = args[1] as int;
  final int outputHeight = args[2] as int;

  final Uint8List outputRgba = Uint8List(outputWidth * outputHeight * 4);

  for (final _SnapshotSlice s in slices) {
    for (int dstRow = s.dstRowStart; dstRow < s.dstRowEnd; dstRow++) {
      // Hoist the source-row offset out of the inner column loop.
      final int sy = ((s.selTop + dstRow - s.snapTop) * s.scaleY).floor().clamp(0, s.snapH - 1);
      final int srcRowBase = sy * s.snapW * 4;
      final int dstRowBase = dstRow * outputWidth * 4;

      for (int dstCol = s.dstColStart; dstCol < s.dstColEnd; dstCol++) {
        final int sx = ((s.selLeft + dstCol - s.snapLeft) * s.scaleX).floor().clamp(0, s.snapW - 1);
        final int srcIdx = srcRowBase + sx * 4;
        final int dstIdx = dstRowBase + dstCol * 4;
        outputRgba[dstIdx] = s.rgba[srcIdx];
        outputRgba[dstIdx + 1] = s.rgba[srcIdx + 1];
        outputRgba[dstIdx + 2] = s.rgba[srcIdx + 2];
        outputRgba[dstIdx + 3] = s.rgba[srcIdx + 3];
      }
    }
  }

  return _encodeRgbaToPngIsolate(<dynamic>[outputRgba, outputWidth, outputHeight]);
}

/// Isolate worker: encode a raw RGBA buffer to PNG bytes.
/// [args] = [Uint8List rgbaBytes, int width, int height]
Uint8List _encodeRgbaToPngIsolate(List<dynamic> args) {
  final Uint8List rgbaBytes = args[0] as Uint8List;
  final int width = args[1] as int;
  final int height = args[2] as int;
  final img.Image image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgbaBytes.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

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

  // Position offscreen first so the window never appears on-screen before we
  // have the snapshots ready (avoids the cursor-disappear flash).
  await windowManager.setPosition(const Offset(-32000, -32000));

  Map<int, FrozenMonitorSnapshot> preloadedSnapshots = <int, FrozenMonitorSnapshot>{};

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    Win32Window.hwnd = GetAncestor(GetActiveWindow(), 2);
    await Boxes.registerBoxes(justLoad: true);
    Settings.load();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    // Keep hidden while we capture – window is offscreen but we also hide it
    // so the layered surface is definitely absent from GDI capture.
    ShowWindow(Win32Window.hwnd, SW_HIDE);
  });

  // Capture all monitors while the window is hidden and offscreen.
  Monitor.fetchMonitors();
  for (final int monitorHandle in Monitor.list) {
    final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
      monitorHandle,
      engine: Settings.getCaptureEngine(),
    );
    if (snapshot != null) {
      preloadedSnapshots[monitorHandle] = snapshot;
    }
  }

  // Now show the window.
  ShowWindow(Win32Window.hwnd, SW_SHOW);
  await windowManager.focus();

  runApp(ScreenCaptureApp(freezeMode: freezeMode, preloadedSnapshots: preloadedSnapshots));
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

enum CaptureEngine {
  bitBlt,
  directX,
}

extension CaptureEngineLabel on CaptureEngine {
  String get label {
    switch (this) {
      case CaptureEngine.bitBlt:
        return 'BitBlt';
      case CaptureEngine.directX:
        return 'DirectX';
    }
  }
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

  // --- String Getters / Setters ---
  static String? getString(String key) => _data[key] as String?;

  static void setString(String key, String value) {
    _data[key] = value;
    save();
  }

  // --- Boolean Getters / Setters ---
  static bool? getBool(String key) => _data[key] as bool?;

  static void setBool(String key, bool value) {
    _data[key] = value;
    save();
  }

  // --- Integer Getters / Setters ---
  static int? getInt(String key) => _data[key] as int?;

  static void setInt(String key, int value) {
    _data[key] = value;
    save();
  }

  // --- Specific Settings ---
  static int getCaptureDelaySeconds() {
    // Reuses the new getInt helper with a fallback default of 0
    return getInt('captureDelaySeconds') ?? 0;
  }

  static void setCaptureDelaySeconds(int value) {
    setInt('captureDelaySeconds', value);
  }

  static CaptureEngine getCaptureEngine() {
    final int savedIndex = getInt('captureEngine') ?? CaptureEngine.bitBlt.index;
    if (savedIndex < 0 || savedIndex >= CaptureEngine.values.length) return CaptureEngine.bitBlt;
    return CaptureEngine.values[savedIndex];
  }

  static void setCaptureEngine(CaptureEngine value) {
    setInt('captureEngine', value.index);
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
    // Zero-copy view into native memory — no extra allocation needed.
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

    // Encode on a background isolate so the UI thread is never blocked.
    return compute(_encodeRgbaToPngIsolate, <dynamic>[rgba, w, h]);
  }

  static Future<void> copyPngToClipboard(Uint8List pngBytes) async {
    ClipboardExtended.copyImage(pngBytes);
  }

  static Future<void> copyFileToClipboard(String filePath) async {
    ClipboardExtension.copyFile(filePath);
  }

  /// Save PNG to %localappdata%\Tabame\screenshots\<timestamp>.png
  static Future<String> saveToFile(Uint8List pngBytes) async {
    return await ScreenUtils.saveScreenshot(pngBytes);
  }

  static Future<FrozenMonitorSnapshot?> captureMonitorSnapshot(
    int monitorHandle, {
    CaptureEngine engine = CaptureEngine.bitBlt,
  }) async {
    final MonitorBitmapCapture? capture = await _captureMonitorBitmap(monitorHandle, engine);
    if (capture == null || capture.width <= 0 || capture.height <= 0 || capture.rgbaBytes.isEmpty) {
      return null;
    }

    // Composite the hardware cursor on top of the captured bitmap.
    // Windows never includes the cursor in BitBlt/PrintWindow captures, so we
    // render it manually using DrawIconEx onto a memory DC and alpha-blend the
    // result into the RGBA buffer.
    final Uint8List rgbaWithCursor = _compositeSystemCursor(
      capture.rgbaBytes,
      capture.width,
      capture.height,
      capture.left,
      capture.top,
    );

    return FrozenMonitorSnapshot(
      monitorHandle: monitorHandle,
      screenRect: Rect.fromLTWH(
        capture.left.toDouble(),
        capture.top.toDouble(),
        capture.width.toDouble(),
        capture.height.toDouble(),
      ),
      rgbaBytes: rgbaWithCursor,
      pixelWidth: capture.width,
      pixelHeight: capture.height,
    );
  }

  static Future<MonitorBitmapCapture?> _captureMonitorBitmap(int monitorHandle, CaptureEngine engine) async {
    switch (engine) {
      case CaptureEngine.bitBlt:
        return captureMonitorBitmapByHandle(monitorHandle);
      case CaptureEngine.directX:
        return _captureMonitorBitmapWithDirectX(monitorHandle);
    }
  }

  static Future<MonitorBitmapCapture?> _captureMonitorBitmapWithDirectX(int monitorHandle) async {
    final Pointer<MONITORINFOEX> monitorInfo = calloc<MONITORINFOEX>();
    monitorInfo.ref.monitorInfo.cbSize = sizeOf<MONITORINFOEX>();

    try {
      if (GetMonitorInfo(monitorHandle, monitorInfo.cast()) == 0) return null;

      final RECT rect = monitorInfo.ref.monitorInfo.rcMonitor;
      final MonitorCapture? capture = await captureMonitorBitmapAlternative(monitorHandle: monitorHandle);
      if (capture == null || capture.width <= 0 || capture.height <= 0 || capture.pixels.isEmpty) {
        return null;
      }
      final int expectedBytes = capture.width * capture.height * 4;
      if (capture.pixels.length < expectedBytes) return null;
      final Uint8List bgraPixels = Uint8List.sublistView(capture.pixels, 0, expectedBytes);

      return MonitorBitmapCapture(
        deviceName: monitorInfo.ref.szDevice,
        left: rect.left,
        top: rect.top,
        width: capture.width,
        height: capture.height,
        rgbaBytes: ScreenRegionCapture.bgraToRgba(bgraPixels),
      );
    } finally {
      calloc.free(monitorInfo);
    }
  }

  /// Render the current Windows cursor onto [rgbaBytes] in-place (copy returned).
  /// [monitorLeft]/[monitorTop] are the screen coordinates of the bitmap's origin.
  static Uint8List _compositeSystemCursor(
    Uint8List rgbaBytes,
    int bmpWidth,
    int bmpHeight,
    int monitorLeft,
    int monitorTop,
  ) {
    // 1. Get cursor info (position + HICON handle).
    final Pointer<CURSORINFO> ci = calloc<CURSORINFO>();
    ci.ref.cbSize = sizeOf<CURSORINFO>();
    final bool hasCursor = GetCursorInfo(ci) != 0 && ci.ref.hCursor != 0;
    if (!hasCursor) {
      calloc.free(ci);
      return rgbaBytes;
    }

    final int hCursor = ci.ref.hCursor;
    final int cursorScreenX = ci.ref.ptScreenPos.x;
    final int cursorScreenY = ci.ref.ptScreenPos.y;
    calloc.free(ci);

    // 2. Find the cursor hotspot so we draw at the correct pixel.
    final Pointer<ICONINFO> ii = calloc<ICONINFO>();
    int hotspotX = 0;
    int hotspotY = 0;
    if (GetIconInfo(hCursor, ii) != 0) {
      hotspotX = ii.ref.xHotspot;
      hotspotY = ii.ref.yHotspot;
      // Free the mask/color bitmaps returned by GetIconInfo.
      if (ii.ref.hbmMask != 0) DeleteObject(ii.ref.hbmMask);
      if (ii.ref.hbmColor != 0) DeleteObject(ii.ref.hbmColor);
    }
    calloc.free(ii);

    // 3. Compute where the top-left of the cursor icon lands in bitmap coords.
    final int drawX = cursorScreenX - hotspotX - monitorLeft;
    final int drawY = cursorScreenY - hotspotY - monitorTop;

    // 4. Determine cursor size (standard system cursor size).
    final int cxCursor = GetSystemMetrics(SM_CXCURSOR);
    final int cyCursor = GetSystemMetrics(SM_CYCURSOR);
    if (cxCursor <= 0 || cyCursor <= 0) return rgbaBytes;

    // Clip to bitmap bounds – bail out entirely if cursor is off-screen.
    if (drawX + cxCursor < 0 || drawY + cyCursor < 0 || drawX >= bmpWidth || drawY >= bmpHeight) {
      return rgbaBytes;
    }

    // 5. Render cursor into a 32-bit ARGB memory DC.
    final int screenDc = GetDC(NULL);
    final int cursorDc = CreateCompatibleDC(screenDc);
    final int totalBytes = cxCursor * cyCursor * 4;

    // We need a 32-bpp DIB so we can read back alpha.
    final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();
    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = cxCursor;
    bmi.ref.bmiHeader.biHeight = -cyCursor; // top-down
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    final Pointer<Uint8> dibBitsRaw = calloc<Uint8>(cxCursor * cyCursor * 4);
    // CreateDIBSection wants a Pointer<Pointer<NativeType>> for the ppvBits arg.
    // We pass NULL (0) and use a pre-allocated buffer via a compatible bitmap instead,
    // so we create a normal DIB and read it back with GetDIBits.
    final int dibBmp = CreateCompatibleBitmap(screenDc, cxCursor, cyCursor);
    calloc.free(bmi);

    if (dibBmp == 0) {
      DeleteDC(cursorDc);
      ReleaseDC(NULL, screenDc);
      calloc.free(dibBitsRaw);
      return rgbaBytes;
    }

    SelectObject(cursorDc, dibBmp);
    // Fill with black so XOR-mask cursors blend correctly.
    final int blackBrush = GetStockObject(BLACK_BRUSH);
    final Pointer<RECT> fillRect = calloc<RECT>();
    fillRect.ref.left = 0;
    fillRect.ref.top = 0;
    fillRect.ref.right = cxCursor;
    fillRect.ref.bottom = cyCursor;
    FillRect(cursorDc, fillRect, blackBrush);
    calloc.free(fillRect);

    DrawIconEx(cursorDc, 0, 0, hCursor, cxCursor, cyCursor, 0, NULL, DI_NORMAL);

    // 6. Read back the rendered cursor pixels (BGRA).
    final Pointer<BITMAPINFO> bmi2 = calloc<BITMAPINFO>();
    bmi2.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi2.ref.bmiHeader.biWidth = cxCursor;
    bmi2.ref.bmiHeader.biHeight = -cyCursor;
    bmi2.ref.bmiHeader.biPlanes = 1;
    bmi2.ref.bmiHeader.biBitCount = 32;
    bmi2.ref.bmiHeader.biCompression = BI_RGB;
    GetDIBits(cursorDc, dibBmp, 0, cyCursor, dibBitsRaw.cast(), bmi2, DIB_RGB_COLORS);
    calloc.free(bmi2);

    // Zero-copy view — read pixels directly from native memory before freeing.
    final Uint8List cursorBgra = dibBitsRaw.asTypedList(totalBytes);

    // 7. Alpha-blend the cursor onto a copy of the snapshot RGBA buffer.
    final Uint8List result = Uint8List.fromList(rgbaBytes);

    for (int cy = 0; cy < cyCursor; cy++) {
      final int dstY = drawY + cy;
      if (dstY < 0 || dstY >= bmpHeight) continue;
      for (int cx = 0; cx < cxCursor; cx++) {
        final int dstX = drawX + cx;
        if (dstX < 0 || dstX >= bmpWidth) continue;

        final int srcIdx = (cy * cxCursor + cx) * 4;
        final int srcB = cursorBgra[srcIdx];
        final int srcG = cursorBgra[srcIdx + 1];
        final int srcR = cursorBgra[srcIdx + 2];
        final int srcA = cursorBgra[srcIdx + 3];

        if (srcA == 0 && srcR == 0 && srcG == 0 && srcB == 0) continue;

        final int dstIdx = (dstY * bmpWidth + dstX) * 4;

        if (srcA == 0) {
          // XOR cursor pixel (monochrome mask) – invert destination.
          // XOR of two bytes is always in [0,255], no clamp needed.
          if (srcR != 0 || srcG != 0 || srcB != 0) {
            result[dstIdx] = result[dstIdx] ^ srcR;
            result[dstIdx + 1] = result[dstIdx + 1] ^ srcG;
            result[dstIdx + 2] = result[dstIdx + 2] ^ srcB;
          }
        } else {
          // Normal alpha-blend using integer fixed-point (no FPU division).
          // out = (src * srcA + dst * (255 - srcA)) >> 8
          final int ia = 255 - srcA;
          result[dstIdx] = ((srcR * srcA + result[dstIdx] * ia) >> 8).clamp(0, 255);
          result[dstIdx + 1] = ((srcG * srcA + result[dstIdx + 1] * ia) >> 8).clamp(0, 255);
          result[dstIdx + 2] = ((srcB * srcA + result[dstIdx + 2] * ia) >> 8).clamp(0, 255);
          result[dstIdx + 3] = 255;
        }
      }
    }

    DeleteObject(dibBmp);
    DeleteDC(cursorDc);
    ReleaseDC(NULL, screenDc);
    calloc.free(dibBitsRaw); // free after loop — view is no longer used

    return result;
  }

  /// Encodes RGBA bytes to PNG on a background isolate so the UI thread
  /// is never blocked by the (potentially heavy) compression work.
  static Future<Uint8List> encodeRgbaToPng(Uint8List rgbaBytes, int width, int height) {
    return compute(_encodeRgbaToPngIsolate, <dynamic>[rgbaBytes, width, height]);
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
    this.preloadedSnapshots = const <int, FrozenMonitorSnapshot>{},
  });

  final bool freezeMode;
  final Map<int, FrozenMonitorSnapshot> preloadedSnapshots;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.theme.accentColor;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.dark(
          primary: accent,
          surface: userSettings.theme.background,
        ),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: FancyShotCaptureWidget(
        freezeMode: freezeMode,
        preloadedSnapshots: preloadedSnapshots,
      ),
    );
  }
}

class FancyShotCaptureWidget extends StatefulWidget {
  const FancyShotCaptureWidget({
    super.key,
    required this.freezeMode,
    this.preloadedSnapshots = const <int, FrozenMonitorSnapshot>{},
  });

  final bool freezeMode;

  /// Snapshots captured before the widget was shown (e.g. by startScreenCapture).
  /// When empty the widget checks [_staticCache] first, then captures itself.
  final Map<int, FrozenMonitorSnapshot> preloadedSnapshots;

  // ── Static pre-capture API ──────────────────────────────────────────────────

  /// Snapshots captured via [captureScreenshots] before the widget is shown.
  /// Consumed once by the first [FancyShotCaptureWidget] that initialises.
  static Map<int, FrozenMonitorSnapshot>? _staticCache;

  /// Call this **before** launching [FancyShotCaptureWidget] (e.g. before
  /// calling `refreshQuickMenu`). It hides the current window, captures every
  /// monitor, and stores the result in a static cache that the widget picks up
  /// automatically in [initState], avoiding a second hide/capture cycle.
  ///
  /// ```dart
  /// await FancyShotCaptureWidget.captureScreenshots();
  /// Globals.quickMenuPage = QuickMenuPage.fancyShotFreeze;
  /// QuickMenuFunctions.refreshQuickMenu();
  /// ```
  static Future<void> captureScreenshots() async {
    Settings.load();
    final CaptureEngine captureEngine = Settings.getCaptureEngine();
    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final Map<int, FrozenMonitorSnapshot> captured = <int, FrozenMonitorSnapshot>{};
    try {
      Monitor.fetchMonitors();
      for (final int monitorHandle in Monitor.list) {
        final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
          monitorHandle,
          engine: captureEngine,
        );
        if (snapshot != null) {
          captured[monitorHandle] = snapshot;
        }
      }
    } finally {
      if (hwnd != 0) {
        ShowWindow(hwnd, SW_SHOW);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
    }

    _staticCache = captured;
  }

  @override
  State<FancyShotCaptureWidget> createState() => _FancyShotCaptureWidgetState();
}

class _FancyShotCaptureWidgetState extends State<FancyShotCaptureWidget> {
  Timer? _monitorTimer;
  int _currentMonitor = -1;
  Square _monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  AppView _lastView = appState.view;

  /// Snapshots that are ready to pass down to ScreenCaptureView.
  /// Starts as null; populated either from widget.preloadedSnapshots or by
  /// _captureInitialSnapshots() when the widget does the capture itself.
  Map<int, FrozenMonitorSnapshot>? _readySnapshots;

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

    WinUtils.fixDrawBug();
    if (widget.preloadedSnapshots.isNotEmpty) {
      // Snapshots passed directly (standalone startScreenCapture path).
      _readySnapshots = Map<int, FrozenMonitorSnapshot>.of(widget.preloadedSnapshots);
    } else if (FancyShotCaptureWidget._staticCache != null) {
      // Snapshots pre-captured via FancyShotCaptureWidget.captureScreenshots().
      _readySnapshots = FancyShotCaptureWidget._staticCache!;
      FancyShotCaptureWidget._staticCache = null; // consume once
    } else {
      // Embedded launch with no pre-capture: capture now (hides window briefly).
      unawaited(_captureInitialSnapshots());
    }
  }

  /// Hide the window, capture all monitors, re-show, then mark _readySnapshots.
  /// This mirrors what startScreenCapture does for the standalone flow.
  Future<void> _captureInitialSnapshots() async {
    Settings.load();
    final CaptureEngine captureEngine = Settings.getCaptureEngine();
    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final Map<int, FrozenMonitorSnapshot> captured = <int, FrozenMonitorSnapshot>{};
    try {
      Monitor.fetchMonitors();
      for (final int monitorHandle in Monitor.list) {
        final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
          monitorHandle,
          engine: captureEngine,
        );
        if (snapshot != null) {
          captured[monitorHandle] = snapshot;
        }
      }
    } finally {
      if (hwnd != 0) {
        ShowWindow(hwnd, SW_SHOW);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
    }

    if (!mounted) return;
    setState(() {
      _readySnapshots = captured;
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
        // Only reposition the window when in editor view (sized to one monitor).
        // In capture view the window spans the full virtual desktop – don't move it.
        if (appState.view == AppView.editor) {
          await WindowManager.instance.setPosition(Offset(_monitorData.x.toDouble(), _monitorData.y.toDouble()));
          await WindowManager.instance.setSize(Size(_monitorData.width.toDouble(), _monitorData.height.toDouble()));
        }
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
    // Show nothing (transparent) while the initial capture is in progress.
    // This is brief (~120 ms) and only happens on embedded launches.
    final Map<int, FrozenMonitorSnapshot> snapshots = _readySnapshots ?? const <int, FrozenMonitorSnapshot>{};

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
              return ScreenCaptureView(
                freezeMode: widget.freezeMode,
                preloadedSnapshots: snapshots,
              );
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
          return ScreenCaptureView(
            freezeMode: widget.freezeMode,
            preloadedSnapshots: snapshots,
          );
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
    this.preloadedSnapshots = const <int, FrozenMonitorSnapshot>{},
  });

  final bool freezeMode;
  final Map<int, FrozenMonitorSnapshot> preloadedSnapshots;

  @override
  State<ScreenCaptureView> createState() => _ScreenCaptureViewState();
}

class _ScreenCaptureViewState extends State<ScreenCaptureView> {
  String _captureActionId = CaptureActionChoice.askId;
  List<FancyShotProfile> _fancyShotProfiles = <FancyShotProfile>[];
  List<ScreenCaptureUploadHost> _uploadHosts = <ScreenCaptureUploadHost>[];
  String? _selectedFancyShotPresetName;
  CaptureEngine _captureEngine = CaptureEngine.bitBlt;
  int _captureDelaySeconds = 0;
  int? _countdownValue;
  Offset? _captureStart;
  Offset? _captureCurrent;
  bool _capturing = false;
  bool _captureEnabled = true;
  bool _applyingPreset = false;
  Timer? _tickerTimer;
  // final Set<String> _pressedScreenCaptureHotkeys = <String>{};
  final Map<int, FrozenMonitorSnapshot> _frozenMonitorSnapshots = <int, FrozenMonitorSnapshot>{};
  final Map<int, ui.Image> _frozenMonitorImages = <int, ui.Image>{};
  final Set<int> _frozenMonitorImageLoadsInProgress = <int>{};
  Future<void>? _frozenSnapshotWarmup;
  bool _visibleFrozenMonitorSyncInProgress = false;

  /// Window rect snapshotted at pointer-down, used to capture on click (no drag).
  Rect? _clickedWindowRect;

  /// Widget-local rect of the window currently highlighted under the cursor.
  /// Non-null when the crosshair is hovering a window without dragging.
  Rect? _windowHighlight;

  /// Virtual-desktop top-left (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN).
  /// Used to translate screen-space snapshot rects into widget-local coords.
  Offset _virtualOrigin = Offset.zero;

  /// The monitor the cursor is currently on, in widget-local coordinates
  /// (screen coords minus _virtualOrigin). Used to anchor the settings button,
  /// loading indicator, and modals to the active monitor instead of the full
  /// virtual-desktop canvas.
  Rect _currentMonitorRect = Rect.zero;

  /// Live mode: true while we are hiding the window and capturing a snapshot
  /// so the region selector can operate on a frozen frame.
  bool _liveSnapshotLoading = false;

  /// Live mode: true once we have a live-captured snapshot ready to display
  /// as a frozen background while the user draws a selection.
  bool _liveSnapshotReady = false;

  /// The pointer position recorded at the moment the user pressed down in live
  /// mode, before the snapshot was ready.  Replayed as _captureStart once the
  /// snapshot completes so the drag continues seamlessly.
  Offset? _livePointerDown;

  /// Latest pointer position tracked via raw Listener events during the async
  /// live capture phase (while GestureDetector pan events are suspended).
  Offset? _livePointerCurrent;

  /// Whether the pointer is still held down (tracked via Listener so we know
  /// whether to auto-start the drag once the snapshot is ready).
  bool _livePointerHeld = false;

  @override
  void initState() {
    super.initState();

    _fancyShotProfiles = FancyShot.loadProfiles();
    Settings.load();
    _uploadHosts = FancyShot.loadUploadHosts();

    // Cache the virtual-desktop origin once; it never changes at runtime.
    _virtualOrigin = Offset(
      GetSystemMetrics(SM_XVIRTUALSCREEN).toDouble(),
      GetSystemMetrics(SM_YVIRTUALSCREEN).toDouble(),
    );
    final String? savedActionId = Settings.getString("screenCaptureModeKey");
    if (savedActionId != null && _captureChoices().any((CaptureActionChoice choice) => choice.id == savedActionId)) {
      _captureActionId = savedActionId;
    }
    final String fancySaved = Settings.getString("screenCaptureFancyShot") ?? "";
    if (fancySaved != "" && _fancyShotProfiles.any((FancyShotProfile e) => e.name == fancySaved)) {
      _selectedFancyShotPresetName = fancySaved;
    }
    _captureEngine = Settings.getCaptureEngine();
    _captureDelaySeconds = Settings.getCaptureDelaySeconds();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _ticker());

    // Seed the frozen snapshot maps with any snapshots captured at startup.
    _frozenMonitorSnapshots.addAll(widget.preloadedSnapshots);

    if (widget.freezeMode) {
      _frozenSnapshotWarmup = _decodeFrozenMonitorImages();
      unawaited(_syncVisibleFrozenMonitor(forceRefresh: true));
    }

    // Initialise current-monitor rect from the cursor position.
    _updateCurrentMonitorRect();
  }

  /// Called when the parent rebuilds ScreenCaptureView with new props —
  /// specifically when preloadedSnapshots arrives after _captureInitialSnapshots()
  /// completes in the embedded-launch path.
  @override
  void didUpdateWidget(ScreenCaptureView old) {
    super.didUpdateWidget(old);
    if (widget.preloadedSnapshots != old.preloadedSnapshots && widget.preloadedSnapshots.isNotEmpty) {
      // New snapshots arrived – seed the maps and decode them.
      for (final MapEntry<int, FrozenMonitorSnapshot> e in widget.preloadedSnapshots.entries) {
        _frozenMonitorSnapshots.putIfAbsent(e.key, () => e.value);
      }
      if (widget.freezeMode) {
        _frozenSnapshotWarmup = _decodeFrozenMonitorImages();
        unawaited(_syncVisibleFrozenMonitor(forceRefresh: true));
      }
    }
  }

  /// Read the cursor position and update _currentMonitorRect.
  void _updateCurrentMonitorRect() {
    final Pointer<POINT> pt = calloc<POINT>();
    try {
      if (GetCursorPos(pt) == 0) return;
      final int handle = MonitorFromPoint(pt.ref, MONITOR_DEFAULTTONEAREST);
      final Square? m = Monitor.monitorSizes[handle];
      if (m != null) {
        final Rect r = Rect.fromLTWH(
          m.x.toDouble() - _virtualOrigin.dx,
          m.y.toDouble() - _virtualOrigin.dy,
          m.width.toDouble(),
          m.height.toDouble(),
        );
        if (r != _currentMonitorRect) {
          setState(() => _currentMonitorRect = r);
        }
      }
    } finally {
      calloc.free(pt);
    }
  }

  List<CaptureActionChoice> _captureChoices() {
    return <CaptureActionChoice>[
      ...CaptureActionChoice.builtIn,
      ..._uploadHosts.map(
        (ScreenCaptureUploadHost host) => CaptureActionChoice(
          id: CaptureActionChoice.uploadHostId(host.id),
          title: host.name,
          subtitle: host.isBuiltIn ? 'Upload via ${host.name}' : 'Run custom uploader command',
          icon: host.isBuiltIn ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
          uploadHost: host,
        ),
      ),
    ];
  }

  void _ticker() {
    if (widget.freezeMode || _liveSnapshotReady) {
      unawaited(_syncVisibleFrozenMonitor());
    }
    _updateCurrentMonitorRect();
  }

  void _resetActiveCaptureSelection() {
    if (!_capturing && _captureStart == null && _captureCurrent == null) return;
    setState(() {
      _captureStart = null;
      _captureCurrent = null;
      _capturing = false;
    });
  }

  /// Decode all pre-loaded RGBA snapshots into ui.Image objects.
  /// No hide/show is needed here because the snapshots were already captured
  /// before the window became visible.
  Future<void> _decodeFrozenMonitorImages() async {
    for (final int monitorHandle in _frozenMonitorSnapshots.keys) {
      if (_frozenMonitorImages.containsKey(monitorHandle)) continue;
      final FrozenMonitorSnapshot snapshot = _frozenMonitorSnapshots[monitorHandle]!;
      await _ensureFrozenMonitorImage(monitorHandle, snapshot: snapshot, notify: false);
    }
    if (mounted) setState(() {});
  }

  /// Capture all monitors fresh (used by live mode when the user starts a
  /// region drag).  The window is hidden for the duration of the capture so
  /// GDI does not include the overlay surface.
  Future<void> _captureLiveSnapshot() async {
    if (_liveSnapshotLoading) return;
    setState(() => _liveSnapshotLoading = true);

    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    try {
      // Clear old frozen data so we get fresh captures.
      for (final ui.Image img in _frozenMonitorImages.values) {
        img.dispose();
      }
      _frozenMonitorImages.clear();
      _frozenMonitorSnapshots.clear();

      Monitor.fetchMonitors();
      for (final int monitorHandle in Monitor.list) {
        final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
          monitorHandle,
          engine: _captureEngine,
        );
        if (snapshot != null) {
          _frozenMonitorSnapshots[monitorHandle] = snapshot;
          await _ensureFrozenMonitorImage(monitorHandle, snapshot: snapshot, notify: false);
        }
      }
    } finally {
      if (hwnd != 0) {
        ShowWindow(hwnd, SW_SHOW);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
      if (mounted) {
        setState(() {
          _liveSnapshotLoading = false;
          _liveSnapshotReady = true;
          // If the pointer is still held, immediately start the drag selection
          // using the position recorded when the user first pressed down.
          if (_livePointerHeld && _livePointerDown != null) {
            _captureStart = _livePointerDown;
            _captureCurrent = _livePointerCurrent ?? _livePointerDown;
            _capturing = true;
          }
        });
        unawaited(_syncVisibleFrozenMonitor(forceRefresh: true));
      }
    }
  }

  Future<void> _setCaptureEngine(CaptureEngine engine) async {
    if (_captureEngine == engine) return;

    Settings.setCaptureEngine(engine);
    for (final ui.Image image in _frozenMonitorImages.values) {
      image.dispose();
    }
    _frozenMonitorImages.clear();
    _frozenMonitorSnapshots.clear();

    if (!mounted) return;
    setState(() {
      _captureEngine = engine;
      _liveSnapshotReady = false;
      _liveSnapshotLoading = false;
      _livePointerDown = null;
      _livePointerCurrent = null;
      _livePointerHeld = false;
      _captureStart = null;
      _captureCurrent = null;
      _capturing = false;
    });

    if (widget.freezeMode) {
      _frozenSnapshotWarmup = _captureInitialFrozenSnapshots();
      await _frozenSnapshotWarmup;
      unawaited(_syncVisibleFrozenMonitor(forceRefresh: true));
    }
  }

  Future<void> _captureInitialFrozenSnapshots() async {
    final int hwnd = Win32Window.getHwnd();
    if (hwnd != 0) {
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final Map<int, FrozenMonitorSnapshot> captured = <int, FrozenMonitorSnapshot>{};
    try {
      Monitor.fetchMonitors();
      for (final int monitorHandle in Monitor.list) {
        final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
          monitorHandle,
          engine: _captureEngine,
        );
        if (snapshot != null) {
          captured[monitorHandle] = snapshot;
        }
      }
    } finally {
      if (hwnd != 0) {
        ShowWindow(hwnd, SW_SHOW);
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      }
    }

    if (!mounted) return;
    _frozenMonitorSnapshots
      ..clear()
      ..addAll(captured);
    await _decodeFrozenMonitorImages();
  }

  /// Reset live snapshot state so the overlay goes back to transparent.
  void _resetLiveSnapshot() {
    if (!_liveSnapshotReady && !_liveSnapshotLoading) return;
    for (final ui.Image img in _frozenMonitorImages.values) {
      img.dispose();
    }
    _frozenMonitorImages.clear();
    _frozenMonitorSnapshots.clear();
    // Restore the preloaded snapshots so freeze mode still works correctly
    // if the user switches modes.
    _frozenMonitorSnapshots.addAll(widget.preloadedSnapshots);
    setState(() {
      _liveSnapshotReady = false;
      _liveSnapshotLoading = false;
      _livePointerDown = null;
      _livePointerCurrent = null;
      _livePointerHeld = false;
      _captureStart = null;
      _captureCurrent = null;
      _capturing = false;
    });
  }

  void _showCaptureSettingsModal(BuildContext context) {
    const double modalWidth = 320;
    final double left =
        _currentMonitorRect.isEmpty ? 0 : (_currentMonitorRect.left + (_currentMonitorRect.width - modalWidth) / 2);
    final double top = _currentMonitorRect.isEmpty ? 80 : (_currentMonitorRect.top + 80);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (BuildContext context) {
        return Stack(
          children: <Widget>[
            Positioned(
              left: left,
              top: top,
              width: modalWidth,
              child: _CaptureSettingsModal(
                captureChoices: _captureChoices(),
                currentActionId: _captureActionId,
                currentCaptureEngine: _captureEngine,
                fancyShotPresets: _fancyShotProfiles.map((FancyShotProfile p) => p.name).toList(),
                currentPresetName: _selectedFancyShotPresetName,
                currentDelay: _captureDelaySeconds,
                onActionChanged: (String actionId) {
                  Settings.setString("screenCaptureModeKey", actionId);
                  setState(() => _captureActionId = actionId);
                },
                onPresetChanged: (String? presetName) {
                  if (presetName == "none") presetName = "";
                  Settings.setString("screenCaptureFancyShot", presetName ?? "");
                  setState(() => _selectedFancyShotPresetName = presetName);
                },
                onDelayChanged: (int v) {
                  Settings.setCaptureDelaySeconds(v);
                  setState(() => _captureDelaySeconds = v);
                },
                onCaptureEngineChanged: (CaptureEngine engine) {
                  unawaited(_setCaptureEngine(engine));
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<FrozenMonitorSnapshot?> _ensureFrozenMonitorSnapshot(int monitorHandle) async {
    final FrozenMonitorSnapshot? existing = _frozenMonitorSnapshots[monitorHandle];
    if (existing != null) return existing;
    final FrozenMonitorSnapshot? snapshot = await ScreenCapture.captureMonitorSnapshot(
      monitorHandle,
      engine: _captureEngine,
    );
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
    // Run in freeze mode always; in live mode only once a snapshot is loaded.
    if ((!widget.freezeMode && !_liveSnapshotReady) || !mounted || _visibleFrozenMonitorSyncInProgress) return;

    _visibleFrozenMonitorSyncInProgress = true;
    try {
      // Decode images for any snapshot that doesn't have one yet.
      bool anyNew = false;
      for (final int handle in _frozenMonitorSnapshots.keys) {
        if (!_frozenMonitorImages.containsKey(handle) && !_frozenMonitorImageLoadsInProgress.contains(handle)) {
          await _ensureFrozenMonitorImage(handle, snapshot: _frozenMonitorSnapshots[handle], notify: false);
          anyNew = true;
        }
      }
      if (anyNew && mounted) setState(() {});
    } finally {
      _visibleFrozenMonitorSyncInProgress = false;
    }
  }

  /// Capture [screenRect] from all frozen monitor snapshots that intersect it.
  ///
  /// Each monitor snapshot covers its own portion of the virtual desktop.
  /// Pixels that fall inside [screenRect] are copied from whichever snapshot
  /// owns them, so a selection that spans two (or more) monitors produces a
  /// seamlessly composited output image.  Regions not covered by any snapshot
  /// (e.g. the gap between two non-adjacent monitors) are left as transparent
  /// black.
  ///
  /// The pixel-copy loop and PNG encoding are both performed on a background
  /// isolate via [compute] so the UI thread is never blocked.
  Future<Uint8List?> _captureFrozenRegionToPng(Rect screenRect) async {
    final Rect sel = screenRect.normalized();

    final int outputWidth = sel.width.round().clamp(1, 1000000);
    final int outputHeight = sel.height.round().clamp(1, 1000000);

    // Build lightweight, isolate-sendable slice descriptors for every
    // snapshot that overlaps the selection.
    final List<_SnapshotSlice> slices = <_SnapshotSlice>[];

    for (final int monitorHandle in List<int>.from(_frozenMonitorSnapshots.keys)) {
      final FrozenMonitorSnapshot? snapshot = await _ensureFrozenMonitorSnapshot(monitorHandle);
      if (snapshot == null) continue;

      final Rect intersection = sel.intersect(snapshot.screenRect);
      if (intersection.isEmpty) continue;

      slices.add(_SnapshotSlice(
        rgba: snapshot.rgbaBytes,
        snapW: snapshot.pixelWidth,
        snapH: snapshot.pixelHeight,
        snapLeft: snapshot.screenRect.left,
        snapTop: snapshot.screenRect.top,
        scaleX: snapshot.pixelWidth / snapshot.screenRect.width,
        scaleY: snapshot.pixelHeight / snapshot.screenRect.height,
        selLeft: sel.left,
        selTop: sel.top,
        dstColStart: (intersection.left - sel.left).round(),
        dstRowStart: (intersection.top - sel.top).round(),
        dstColEnd: (intersection.right - sel.left).round(),
        dstRowEnd: (intersection.bottom - sel.top).round(),
      ));
    }

    if (slices.isEmpty) return null;

    // Offload the pixel-copy loop AND PNG encoding to a background isolate.
    return compute(
      _cropAndEncodePngIsolate,
      <dynamic>[slices, outputWidth, outputHeight],
    );
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
      QuickMenuFunctions.hideQuickMenu();
    } else {
      if (userSettings.args.contains('-screenCapture')) windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui.Size size = MediaQuery.of(context).size;

    // Show the frozen background whenever we have at least one decoded image.
    // In live mode, only after the snapshot capture completes.
    final bool showFrozenBg = _frozenMonitorImages.isNotEmpty && (widget.freezeMode || _liveSnapshotReady);

    if (!_captureEnabled) {
      return const SizedBox.expand();
    }

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (KeyEvent e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          if (!widget.freezeMode && _liveSnapshotReady) {
            _resetLiveSnapshot();
          } else {
            closeMainWindow();
          }
        }
      },
      child: Stack(
        children: <Widget>[
          if (showFrozenBg)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  size: size,
                  painter: _AllMonitorsFrozenPainter(
                    images: _frozenMonitorImages,
                    snapshots: _frozenMonitorSnapshots,
                    virtualOrigin: _virtualOrigin,
                  ),
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
                  } else if (!widget.freezeMode && _liveSnapshotReady) {
                    _resetLiveSnapshot();
                  } else {
                    closeMainWindow();
                  }
                  return;
                }

                // Record down position and snapshot the current window highlight
                // so we can detect a click (no drag) in onPanEnd.
                _livePointerDown = event.localPosition;
                _livePointerCurrent = event.localPosition;
                _clickedWindowRect = _windowHighlight;

                if (!widget.freezeMode && !_liveSnapshotReady) {
                  _livePointerHeld = true;
                  unawaited(_captureLiveSnapshot());
                }
              },
              onPointerMove: (PointerMoveEvent event) {
                if ((event.buttons & kSecondaryMouseButton) != 0 && _capturing) {
                  _resetActiveCaptureSelection();
                  return;
                }

                // Track position continuously so we can replay it once the
                // live snapshot is ready.
                if (!widget.freezeMode && _liveSnapshotLoading) {
                  _livePointerCurrent = event.localPosition;
                }

                // Once the snapshot is ready and capture is active, keep
                // updating the selection rectangle from raw pointer events so
                // there is no gap between snapshot-ready and first GestureDetector
                // onPanUpdate.
                if (_capturing && _captureStart != null) {
                  setState(() => _captureCurrent = event.localPosition);
                }
              },
              onPointerUp: (PointerUpEvent event) {
                _livePointerHeld = false;

                if (_capturing && _captureStart != null && _liveSnapshotReady) {
                  final Offset s = _captureStart!;
                  final Offset e = _captureCurrent ?? s;
                  setState(() {
                    _captureStart = null;
                    _captureCurrent = null;
                    _capturing = false;
                  });
                  final Rect localRect = Rect.fromPoints(s, e);
                  if (localRect.width < 4 || localRect.height < 4) {
                    _resetLiveSnapshot();
                    return;
                  }
                  unawaited(_doCaptureWithDelay(localRect));
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (DragStartDetails d) {
                  // In live mode before snapshot is ready, we let the Listener
                  // handle everything; GestureDetector is bypassed.
                  if (!widget.freezeMode && !_liveSnapshotReady) return;

                  setState(() {
                    _windowHighlight = null;
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
                  if (localRect.width < 6 || localRect.height < 6) {
                    // Treat as a click — use the window that was highlighted
                    // at pointer-down time (snapshotted into _clickedWindowRect).
                    final Rect? winRect = _clickedWindowRect;
                    _clickedWindowRect = null;
                    if (winRect != null && !winRect.isEmpty) {
                      await _doCaptureWithDelay(winRect);
                    } else if (!widget.freezeMode) {
                      _resetLiveSnapshot();
                    }
                    return;
                  }
                  _clickedWindowRect = null;
                  await _doCaptureWithDelay(localRect);
                },
                child: CustomPaint(
                  size: size,
                  painter: _CapturePainter(
                    start: _captureStart,
                    current: _captureCurrent,
                    windowHighlight: _windowHighlight,
                  ),
                ),
              ),
            ),
          ),

          // Crosshair cursor layer
          if (!_capturing)
            Positioned.fill(
              child: _CrosshairCursor(
                freezeMode: widget.freezeMode,
                frozenSnapshots: _frozenMonitorSnapshots,
                virtualOrigin: _virtualOrigin,
                onWindowHighlight: (Rect? r) {
                  if (_windowHighlight != r) setState(() => _windowHighlight = r);
                },
              ),
            ),

          // Loading indicator while live snapshot is being captured.
          if (!widget.freezeMode && _liveSnapshotLoading)
            Positioned(
              left: _currentMonitorRect.left,
              top: _currentMonitorRect.top,
              width: _currentMonitorRect.width,
              height: _currentMonitorRect.height,
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.30),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10141C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white24),
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
                          'Capturing screen…',
                          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            top: _currentMonitorRect.top + 16,
            left: _currentMonitorRect.left,
            width: _currentMonitorRect.width,
            child: Center(
              child: _CaptureSettingsButton(
                activeAction: _captureChoices().firstWhere((CaptureActionChoice c) => c.id == _captureActionId),
                activePresetName: _selectedFancyShotPresetName,
                onTap: () => _showCaptureSettingsModal(context),
              ),
            ),
          ),

          if (_applyingPreset)
            Positioned(
              left: _currentMonitorRect.left,
              top: _currentMonitorRect.top,
              width: _currentMonitorRect.width,
              height: _currentMonitorRect.height,
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

          // Countdown overlay — shown when _captureDelaySeconds > 0 and ticking.
          if (_countdownValue != null)
            Positioned(
              left: _currentMonitorRect.left,
              top: _currentMonitorRect.top,
              width: _currentMonitorRect.width,
              height: _currentMonitorRect.height,
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: Text(
                    '$_countdownValue',
                    style: const TextStyle(
                      fontSize: 120,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: <Shadow>[
                        Shadow(
                          color: Colors.black,
                          blurRadius: 24,
                          offset: Offset(0, 4),
                        ),
                        Shadow(
                          color: Colors.black,
                          blurRadius: 8,
                          offset: Offset(0, 0),
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

  Future<void> _doCaptureWithDelay(Rect rect) async {
    if (_captureDelaySeconds == 0) {
      await _doCapture(rect);
      return;
    }

    final AudioPlayer player = AudioPlayer();
    await player.setAsset('resources/beep.mp3');
    // Disable capture interaction while countdown runs.
    setState(() => _captureEnabled = false);
    for (int i = _captureDelaySeconds; i > 0; i--) {
      setState(() => _countdownValue = i);

      player.seek(Duration.zero).then((_) => player.play());
      // await player.play();
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await player.seek(Duration.zero);
    await player.play();
    setState(() {
      _countdownValue = null;
      _captureEnabled = true;
    });
    await player.dispose();
    await _doCapture(rect);
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

      Uint8List? pngBytes;

      if (widget.freezeMode) {
        // Freeze mode: snapshots are already captured; no need to hide window.
        if (_frozenSnapshotWarmup != null) {
          await _frozenSnapshotWarmup;
        }
        pngBytes = await _captureFrozenRegionToPng(screenRect);
      } else {
        // Live mode: the snapshot was captured before the drag started in
        // _captureLiveSnapshot(), so we can crop from it directly.
        // No need to hide the window again.
        pngBytes = await _captureFrozenRegionToPng(screenRect);
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

      // NOTE: Do NOT reset the live snapshot here.
      // Keeping _liveSnapshotReady = true means the frozen background stays
      // visible while the post-capture modal is on screen, eliminating the
      // flash caused by the overlay disappearing before the modal appears.
      // _resetLiveSnapshot() is called from _handleCaptureResult (for
      // non-modal paths) or from the modal's onClose callback instead.

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

  Future<void> hideQuickMenuOffScreen() async {
    await WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
    if (kDebugMode && !Globals.debugHotkeys) return;
    Win32.setPosition(const Offset(-99999, -99999));
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
      if (!widget.freezeMode) _resetLiveSnapshot();
      await hideQuickMenuOffScreen();
      await UploadUtils.runUploadHost(choice.uploadHost!, filePath, onSuccess: (String url) async {
        if (choice.uploadHost!.uploadType != UploadHostType.custom) {
          ClipboardExtended.copy(url);
          // Process.start('cmd.exe', <String>['/c', 'start', '', url], mode: ProcessStartMode.detached);
          await _finishPostCaptureAction();
        }
      }, onError: (String e) {
        WinUtils.msgBox("Upload Error", e);
      });
      // await _finishPostCaptureAction();
      return;
    }

    switch (choice.mode ?? CaptureActionMode.ask) {
      case CaptureActionMode.ask:
        // Keep the frozen background alive — _resetLiveSnapshot() is called
        // from the modal's onClose so the overlay stays until modal closes.
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
        if (!widget.freezeMode) _resetLiveSnapshot();
        await hideQuickMenuOffScreen();
        await ScreenCapture.copyPngToClipboard(pngBytes);
        await _finishPostCaptureAction();
        return;
      case CaptureActionMode.copyImageFileToClipboard:
        if (!widget.freezeMode) _resetLiveSnapshot();
        await hideQuickMenuOffScreen();
        await ScreenCapture.copyFileToClipboard(filePath);
        await _finishPostCaptureAction();
        return;
      case CaptureActionMode.openPhotoEditor:
        if (!widget.freezeMode) _resetLiveSnapshot();
        await hideQuickMenuOffScreen();
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
    if (kDebugMode) {
      appState.backToCapture();
      await windowManager.focus();
      return;
    }
    await ScreenUtils.playCameraSound();
    closeMainWindow();
  }

  void _showCaptureModal(
    Uint8List pngBytes,
    String filePath,
    int w,
    int h, {
    required Uint8List editorPngBytes,
    required String editorFilePath,
  }) {
    const double modalWidth = 480;
    // Position the modal centered on the active monitor using explicit pixel
    // offsets, bypassing the Align+insetPadding distortion that showDialog adds.
    final double left =
        _currentMonitorRect.isEmpty ? 0 : (_currentMonitorRect.left + (_currentMonitorRect.width - modalWidth) / 2);
    final double top =
        _currentMonitorRect.isEmpty ? 0 : (_currentMonitorRect.top + (_currentMonitorRect.height * 0.18));

    showGeneralDialog<void>(
      context: context,
      barrierLabel: 'capture_modal',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (BuildContext ctx, Animation<double> anim, Animation<double> _, Widget child) {
        return FadeTransition(opacity: anim, child: child);
      },
      pageBuilder: (BuildContext ctx, _, __) => Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: top,
            width: modalWidth,
            child: _AnimatedCaptureModal(
              pngBytes: pngBytes,
              filePath: filePath,
              editorPngBytes: editorPngBytes,
              editorFilePath: editorFilePath,
              imageW: w,
              imageH: h,
              onClose: () {
                if (!widget.freezeMode) _resetLiveSnapshot();
                closeMainWindow();
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Capture selection painter
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Multi-monitor frozen background painter
// ─────────────────────────────────────────────────────────────────────────────

/// Paints the frozen screenshot for every monitor at its correct position
/// within the virtual-desktop canvas.  The widget's coordinate space has its
/// origin at (vLeft, vTop) – i.e. the top-left corner of the virtual desktop.
class _AllMonitorsFrozenPainter extends CustomPainter {
  final Map<int, ui.Image> images;
  final Map<int, FrozenMonitorSnapshot> snapshots;

  /// Virtual-desktop origin (SM_XVIRTUALSCREEN, SM_YVIRTUALSCREEN).
  final Offset virtualOrigin;

  const _AllMonitorsFrozenPainter({
    required this.images,
    required this.snapshots,
    required this.virtualOrigin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final MapEntry<int, ui.Image> entry in images.entries) {
      final FrozenMonitorSnapshot? snapshot = snapshots[entry.key];
      if (snapshot == null) continue;
      final ui.Image image = entry.value;

      // Destination rect in widget-local coordinates:
      // shift the screen rect by the virtual origin so (vLeft,vTop) → (0,0).
      final Rect dst = snapshot.screenRect.translate(
        -virtualOrigin.dx,
        -virtualOrigin.dy,
      );

      paintImage(
        canvas: canvas,
        rect: dst,
        image: image,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.low,
      );
    }
  }

  @override
  bool shouldRepaint(_AllMonitorsFrozenPainter old) =>
      old.images != images || old.snapshots != snapshots || old.virtualOrigin != virtualOrigin;
}

// ─────────────────────────────────────────────────────────────────────────────
// Capture settings button & modal
// ─────────────────────────────────────────────────────────────────────────────

class _CaptureSettingsButton extends StatefulWidget {
  final CaptureActionChoice activeAction;
  final String? activePresetName;
  final VoidCallback onTap;

  const _CaptureSettingsButton({
    required this.activeAction,
    required this.activePresetName,
    required this.onTap,
  });

  @override
  State<_CaptureSettingsButton> createState() => _CaptureSettingsButtonState();
}

class _CaptureSettingsButtonState extends State<_CaptureSettingsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool hasPreset = (widget.activePresetName ?? "").isNotEmpty;
    final Color accent = userSettings.theme.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? accent.withValues(alpha: 0.5) : Colors.white24,
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              if (_hovered)
                BoxShadow(
                  color: accent.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.activeAction.icon,
                size: 14,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 10),
              Container(
                width: 1,
                height: 14,
                color: Colors.white24,
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.auto_awesome,
                  size: 14,
                  color: hasPreset ? accent : Colors.white.withValues(alpha: 0.3),
                  shadows: hasPreset
                      ? <Shadow>[
                          Shadow(
                            color: accent.withValues(alpha: 0.8),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureSettingsModal extends StatefulWidget {
  final List<CaptureActionChoice> captureChoices;
  final String currentActionId;
  final CaptureEngine currentCaptureEngine;
  final List<String> fancyShotPresets;
  final String? currentPresetName;
  final int currentDelay;
  final ValueChanged<String> onActionChanged;
  final ValueChanged<CaptureEngine> onCaptureEngineChanged;
  final ValueChanged<String?> onPresetChanged;
  final ValueChanged<int> onDelayChanged;

  const _CaptureSettingsModal({
    required this.captureChoices,
    required this.currentActionId,
    required this.currentCaptureEngine,
    required this.fancyShotPresets,
    required this.currentPresetName,
    required this.currentDelay,
    required this.onActionChanged,
    required this.onCaptureEngineChanged,
    required this.onPresetChanged,
    required this.onDelayChanged,
  });

  @override
  State<_CaptureSettingsModal> createState() => _CaptureSettingsModalState();
}

class _CaptureSettingsModalState extends State<_CaptureSettingsModal> {
  late int _selectedDelay;

  @override
  void initState() {
    super.initState();
    _selectedDelay = widget.currentDelay;
  }

  @override
  Widget build(BuildContext context) {
    const Color onSurface = Colors.white;
    final Color accent = userSettings.theme.accentColor;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 320,
        decoration: BoxDecoration(
          color: userSettings.theme.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 32,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: <Widget>[
                  Icon(Icons.settings_input_component_outlined, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    'CAPTURE ENGINE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  CustomTooltip(
                    message: 'Frozen Capture',
                    child: IconButton(
                      icon: const Icon(Icons.center_focus_strong, size: 14, color: Colors.greenAccent),
                      onPressed: () async {
                        Navigator.of(context).maybePop();
                        QuickMenuFunctions.hideQuickMenu();
                        await Future<void>.delayed(const Duration(milliseconds: 100));
                        Globals.quickMenuPage = QuickMenuPage.fancyShotFreeze;
                        await FancyShotCaptureWidget.captureScreenshots();
                        QuickMenuFunctions.refreshQuickMenu();
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  CustomTooltip(
                    message: "Live Capture",
                    child: IconButton(
                      icon: const Icon(Icons.center_focus_strong_outlined, size: 14, color: Colors.greenAccent),
                      onPressed: () async {
                        Navigator.of(context).maybePop();
                        QuickMenuFunctions.hideQuickMenu();
                        await Future<void>.delayed(const Duration(milliseconds: 100));
                        Globals.quickMenuPage = QuickMenuPage.fancyShotLive;
                        QuickMenuFunctions.refreshQuickMenu();
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  CustomTooltip(
                    message: "Open ScreenDraw",
                    child: IconButton(
                      icon: const Icon(Icons.draw_outlined, size: 14),
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        QuickMenuFunctions.hideQuickMenu();
                        WinUtils.startTabame(closeCurrent: false, arguments: "-screenDraw");
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  CustomTooltip(
                    message: "Open Screen Recording",
                    child: IconButton(
                      icon: const Icon(Icons.radio_button_checked, size: 14),
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        QuickMenuFunctions.hideQuickMenu();
                        WinUtils.startTabame(closeCurrent: false, arguments: "-screenRecording");
                      },
                    ),
                  ),
                  const SizedBox(width: 5),
                  CustomTooltip(
                    message: "Open Spotlight",
                    child: IconButton(
                      icon: const Icon(Icons.highlight_alt, size: 14),
                      onPressed: () {
                        Navigator.of(context).maybePop();
                        QuickMenuFunctions.hideQuickMenu();
                        WinUtils.startTabame(closeCurrent: false, arguments: "-spotlight");
                      },
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white10),

            _buildSectionLabel(label: 'CAPTURE ENGINE', icon: Icons.screenshot_monitor_outlined),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: <Widget>[
                  _ModalChoiceRow(
                    icon: Icons.filter_none,
                    title: CaptureEngine.bitBlt.label,
                    subtitle: 'Classic GDI capture',
                    selected: widget.currentCaptureEngine == CaptureEngine.bitBlt,
                    onTap: () {
                      widget.onCaptureEngineChanged(CaptureEngine.bitBlt);
                      Navigator.pop(context);
                    },
                  ),
                  _ModalChoiceRow(
                    icon: Icons.screenshot_monitor_outlined,
                    title: CaptureEngine.directX.label,
                    subtitle: 'Windows Graphics Capture',
                    selected: widget.currentCaptureEngine == CaptureEngine.directX,
                    onTap: () {
                      widget.onCaptureEngineChanged(CaptureEngine.directX);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1, color: Colors.white10),

            // Actions Section
            _buildSectionLabel(label: 'AFTER CAPTURE', icon: Icons.bolt_outlined),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: widget.captureChoices.map((CaptureActionChoice choice) {
                  final bool selected = choice.id == widget.currentActionId;
                  return _ModalChoiceRow(
                    icon: choice.icon,
                    title: choice.title,
                    subtitle: choice.subtitle,
                    selected: selected,
                    onTap: () {
                      widget.onActionChanged(choice.id);
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1, color: Colors.white10),

            // FancyShot Section
            _buildSectionLabel(label: 'FANCYSHOT PRESET', icon: Icons.auto_awesome),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                children: <Widget>[
                  _ModalChoiceRow(
                    icon: Icons.block,
                    title: 'None',
                    subtitle: 'Use raw captured image',
                    selected: (widget.currentPresetName ?? '').isEmpty,
                    onTap: () {
                      widget.onPresetChanged(null);
                      Navigator.pop(context);
                    },
                  ),
                  ...widget.fancyShotPresets.map((String name) {
                    final bool selected = name == widget.currentPresetName;
                    return _ModalChoiceRow(
                      icon: Icons.auto_awesome,
                      title: name,
                      subtitle: 'Apply visual framing',
                      selected: selected,
                      onTap: () {
                        widget.onPresetChanged(name);
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(height: 1, color: Colors.white10),

            // Capture Delay Section
            _buildSectionLabel(label: 'CAPTURE DELAY', icon: Icons.timer_outlined),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Row(
                children: <int>[0, 3, 5, 10].map((int seconds) {
                  final bool selected = _selectedDelay == seconds;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _DelayButton(
                        label: seconds == 0 ? '0s' : '${seconds}s',
                        selected: selected,
                        onTap: () {
                          setState(() => _selectedDelay = seconds);
                          widget.onDelayChanged(seconds);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel({required String label, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: Colors.white38),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: userSettings.theme.textColor.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }
}

class _DelayButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DelayButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_DelayButton> createState() => _DelayButtonState();
}

class _DelayButtonState extends State<_DelayButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.theme.accentColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? accent.withValues(alpha: 0.18)
                : (_hovered ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.03)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected ? accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.selected ? Colors.white : Colors.white60,
              fontSize: 13,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalChoiceRow extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModalChoiceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_ModalChoiceRow> createState() => _ModalChoiceRowState();
}

class _ModalChoiceRowState extends State<_ModalChoiceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.theme.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.selected
                ? accent.withValues(alpha: 0.12)
                : (_hovered ? Colors.white.withValues(alpha: 0.05) : Colors.transparent),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected ? accent.withValues(alpha: 0.3) : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: widget.selected ? accent.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  widget.icon,
                  size: 16,
                  color: widget.selected ? accent : Colors.white60,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: widget.selected ? Colors.white : userSettings.theme.textColor.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    // Text(
                    //   widget.subtitle,
                    //   style: const TextStyle(
                    //     color: Colors.white38,
                    //     fontSize: 11,
                    //   ),
                    // ),
                  ],
                ),
              ),
              if (widget.selected) Icon(Icons.check_circle, size: 14, color: accent),
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
  final Rect? windowHighlight;
  _CapturePainter({this.start, this.current, this.windowHighlight});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.35);

    if (start == null || current == null) {
      canvas.drawRect(Offset.zero & size, dimPaint);

      // Draw window highlight when no drag selection is active.
      if (windowHighlight != null && !windowHighlight!.isEmpty) {
        final Rect r = windowHighlight!;
        // Cut out the window rect from the dim so it appears brighter.
        final Path dimPath = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(Offset.zero & size)
          ..addRect(r);
        canvas.drawPath(dimPath, dimPaint);

        // Accent border around the window.
        canvas.drawRect(
          r,
          Paint()
            ..color = userSettings.theme.accentColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );

        // "Click to capture" label above the window rect.
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: '${r.width.round()} × ${r.height.round()}  •  click to capture',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              backgroundColor: Colors.black.withValues(alpha: 0.75),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final double labelX = (r.center.dx - tp.width / 2).clamp(6.0, size.width - tp.width - 6.0);
        final double labelY = (r.top - tp.height - 6).clamp(6.0, size.height - tp.height - 6.0);
        tp.paint(canvas, Offset(labelX, labelY));
        // No window highlight: uniform dim already drawn above.
      }
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
      ..color = userSettings.theme.accentColor
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
  bool shouldRepaint(_CapturePainter old) =>
      old.start != start || old.current != current || old.windowHighlight != windowHighlight;
}

// ─────────────────────────────────────────────────────────────────────────────
// Crosshair cursor widget
// ─────────────────────────────────────────────────────────────────────────────

// EnumWindows callback — file-level buffer (FFI callbacks must be top-level).
final List<int> _ewBuffer = <int>[];
int _ewProc(int hWnd, int lParam) {
  _ewBuffer.add(hWnd);
  return 1; // continue
}

/// A visible top-level window with its logical rect pre-computed.
class _WindowEntry {
  final int hwnd;
  final Rect logicalRect; // widget-local coords (physical / dpi - virtualOrigin)
  const _WindowEntry(this.hwnd, this.logicalRect);
}

// ─────────────────────────────────────────────────────────────────────────────
// Crosshair cursor widget
// ─────────────────────────────────────────────────────────────────────────────

class _CrosshairCursor extends StatefulWidget {
  const _CrosshairCursor({
    required this.freezeMode,
    required this.frozenSnapshots,
    required this.virtualOrigin,
    required this.onWindowHighlight,
  });
  final bool freezeMode;
  final Map<int, FrozenMonitorSnapshot> frozenSnapshots;
  final Offset virtualOrigin;
  final ValueChanged<Rect?> onWindowHighlight;

  @override
  State<_CrosshairCursor> createState() => _CrosshairCursorState();
}

class _CrosshairCursorState extends State<_CrosshairCursor> {
  Offset _pos = Offset.zero;
  int _lastMatchHwnd = 0;
  List<_WindowEntry> _windows = <_WindowEntry>[];
  Timer? _refreshTimer;

  /// Our own overlay HWND — excluded from the list.
  final int _ownHwnd = Win32Window.getHwnd();

  /// Desktop HWND — excluded.
  final int _desktopHwnd = GetDesktopWindow();

  /// Read the current cursor position from Win32 and convert it to
  /// widget-local coordinates (screen − virtualOrigin).
  Offset _cursorToLocal() {
    final Pointer<POINT> pt = calloc<POINT>();
    try {
      if (GetCursorPos(pt) != 0) {
        return Offset(
          pt.ref.x.toDouble() - widget.virtualOrigin.dx,
          pt.ref.y.toDouble() - widget.virtualOrigin.dy,
        );
      }
    } finally {
      calloc.free(pt);
    }
    return Offset.zero;
  }

  @override
  void initState() {
    super.initState();
    // Seed _pos with the real cursor position so the magnifier and crosshair
    // appear at the correct location on the very first frame, without waiting
    // for the first onHover event.
    _pos = _cursorToLocal();
    _refreshWindows();
    // Refresh window list periodically so new windows are picked up.
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) _refreshWindows();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Enumerate all visible top-level windows and pre-compute their
  /// DPI-corrected, invisible-border-stripped logical rects.
  void _refreshWindows() {
    _ewBuffer.clear();
    EnumWindows(Pointer.fromFunction<WNDENUMPROC>(_ewProc, 0), 0);
    // EnumWindows returns windows in Z-order (front → back).
    final List<_WindowEntry> entries = <_WindowEntry>[];

    final Pointer<RECT> wr = calloc<RECT>();
    for (final int hwnd in _ewBuffer) {
      // Skip our own overlay, the desktop, and invisible/minimised windows.
      if (hwnd == _ownHwnd || hwnd == _desktopHwnd) continue;
      if (IsWindowVisible(hwnd) == 0) continue;
      if (IsIconic(hwnd) != 0) continue; // minimised

      // Skip windows with no title and no area (background/shell helpers).
      GetWindowRect(hwnd, wr);
      final int w = wr.ref.right - wr.ref.left;
      final int h = wr.ref.bottom - wr.ref.top;
      if (w <= 0 || h <= 0) continue;

      int left = wr.ref.left;
      int top = wr.ref.top;
      int right = wr.ref.right;
      int bottom = wr.ref.bottom;

      // DPI scale from the monitor the window centre sits on.
      final Pointer<POINT> centre = calloc<POINT>();
      centre.ref.x = (left + right) ~/ 2;
      centre.ref.y = (top + bottom) ~/ 2;
      final int mon = MonitorFromPoint(centre.ref, MONITOR_DEFAULTTONEAREST);
      calloc.free(centre);

      double scaleX = 1.0;
      double scaleY = 1.0;
      final Dpi? dpi = Monitor.dpi[mon];
      if (dpi != null) {
        scaleX = dpi.x / 96.0;
        scaleY = dpi.y / 96.0;
      }

      // Strip invisible border (physical px) before DPI conversion.
      final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(hwnd);
      left += border.left;
      top += border.top;
      right -= border.right;
      bottom -= border.bottom;

      // Physical → logical widget-local.
      // Round to nearest integer *before* subtracting virtualOrigin so that
      // sub-pixel rounding errors from the DPI division do not accumulate into
      // a ±1 px border around the captured window.
      final Rect logRect = Rect.fromLTRB(
        (left / scaleX).roundToDouble() - widget.virtualOrigin.dx + 1,
        (top / scaleY).roundToDouble() - widget.virtualOrigin.dy + 1,
        (right / scaleX).roundToDouble() - widget.virtualOrigin.dx - 1,
        (bottom / scaleY).roundToDouble() - widget.virtualOrigin.dy - 1,
      );

      entries.add(_WindowEntry(hwnd, logRect));
    }
    calloc.free(wr);

    _windows = entries;
  }

  /// Find the topmost window (first in Z-order list) whose rect contains [pos].
  Rect? _hitTest(Offset localPos) {
    for (final _WindowEntry e in _windows) {
      if (e.logicalRect.contains(localPos)) return e.logicalRect;
    }
    return null;
  }

  void _onHover(Offset localPos) {
    final Rect? rect = _hitTest(localPos);
    final int matchHwnd = rect != null ? _windows.firstWhere((_WindowEntry e) => e.logicalRect == rect).hwnd : 0;

    if (matchHwnd != _lastMatchHwnd) {
      _lastMatchHwnd = matchHwnd;
      widget.onWindowHighlight(rect);
    }

    setState(() => _pos = localPos);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (PointerHoverEvent e) => _onHover(e.localPosition),
      onExit: (_) {
        _lastMatchHwnd = 0;
        widget.onWindowHighlight(null);
      },
      child: IgnorePointer(
        child: CustomPaint(
          painter: _CrosshairPainter(
            pos: _pos,
            freezeMode: widget.freezeMode,
            frozenSnapshots: widget.frozenSnapshots,
            virtualOrigin: widget.virtualOrigin,
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Offset pos;
  final bool freezeMode;
  final Map<int, FrozenMonitorSnapshot> frozenSnapshots;
  final Offset virtualOrigin;

  // Magnifier constants
  static const int _magPixelRadius = 6; // pixels sampled each side
  static const int _magPixelSize = 8; // display px per sampled pixel
  static const int _magGrid = _magPixelRadius * 2 + 1; // 13 cells
  static final double _magSize = _magGrid * _magPixelSize.toDouble(); // 104
  static const double _magOffset = 20; // gap from crosshair tip

  _CrosshairPainter({
    required this.pos,
    required this.freezeMode,
    required this.frozenSnapshots,
    required this.virtualOrigin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ── Crosshair lines ────────────────────────────────────────────────────
    final Paint linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, pos.dy), Offset(size.width, pos.dy), linePaint);
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, size.height), linePaint);

    // ── Coordinate label ──────────────────────────────────────────────────
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

    const double pad = 10;
    // Prefer bottom-right; flip to left when near right edge, flip to top when near bottom.
    final double labelX = (pos.dx + pad + tp.width > size.width - 4) ? pos.dx - pad - tp.width : pos.dx + pad;
    final double labelY = (pos.dy + pad + tp.height > size.height - 4) ? pos.dy - pad - tp.height : pos.dy + pad;
    tp.paint(canvas, Offset(labelX, labelY));

    // ── Magnifier (freeze mode only) ──────────────────────────────────────
    if (!freezeMode || frozenSnapshots.isEmpty) return;

    // Find which snapshot the cursor is in (widget-local → screen coords).
    final double screenX = pos.dx + virtualOrigin.dx;
    final double screenY = pos.dy + virtualOrigin.dy;

    FrozenMonitorSnapshot? snap;
    for (final FrozenMonitorSnapshot s in frozenSnapshots.values) {
      if (s.screenRect.contains(Offset(screenX, screenY))) {
        snap = s;
        break;
      }
    }
    if (snap == null) return;

    // Map screen pos → pixel coords inside the snapshot.
    final double scaleX = snap.pixelWidth / snap.screenRect.width;
    final double scaleY = snap.pixelHeight / snap.screenRect.height;
    final int centerPx = ((screenX - snap.screenRect.left) * scaleX).round();
    final int centerPy = ((screenY - snap.screenRect.top) * scaleY).round();

    // Determine magnifier placement: prefer bottom-right of crosshair, flip near edges.
    double magLeft = pos.dx + _magOffset;
    double magTop = pos.dy + _magOffset;
    if (magLeft + _magSize > size.width - 4) magLeft = pos.dx - _magOffset - _magSize;
    if (magTop + _magSize > size.height - 4) magTop = pos.dy - _magOffset - _magSize;

    final Rect magRect = Rect.fromLTWH(magLeft, magTop, _magSize, _magSize);

    // Background
    canvas.drawRect(
      magRect.inflate(1.5),
      Paint()..color = Colors.black.withValues(alpha: 0.75),
    );

    // Draw sampled pixels
    for (int dy = -_magPixelRadius; dy <= _magPixelRadius; dy++) {
      for (int dx = -_magPixelRadius; dx <= _magPixelRadius; dx++) {
        final int px = (centerPx + dx).clamp(0, snap.pixelWidth - 1);
        final int py = (centerPy + dy).clamp(0, snap.pixelHeight - 1);

        final int byteIdx = (py * snap.pixelWidth + px) * 4;
        if (byteIdx + 3 >= snap.rgbaBytes.length) continue;

        final int r = snap.rgbaBytes[byteIdx];
        final int g = snap.rgbaBytes[byteIdx + 1];
        final int b = snap.rgbaBytes[byteIdx + 2];

        final double cellX = magLeft + (dx + _magPixelRadius) * _magPixelSize.toDouble();
        final double cellY = magTop + (dy + _magPixelRadius) * _magPixelSize.toDouble();
        canvas.drawRect(
          Rect.fromLTWH(cellX, cellY, _magPixelSize.toDouble(), _magPixelSize.toDouble()),
          Paint()..color = Color.fromARGB(255, r, g, b),
        );
      }
    }

    // Grid lines
    final Paint gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (int i = 0; i <= _magGrid; i++) {
      final double x = magLeft + i * _magPixelSize;
      final double y = magTop + i * _magPixelSize;
      canvas.drawLine(Offset(x, magTop), Offset(x, magTop + _magSize), gridPaint);
      canvas.drawLine(Offset(magLeft, y), Offset(magLeft + _magSize, y), gridPaint);
    }

    // Center reticle
    final double cx = magLeft + _magPixelRadius * _magPixelSize.toDouble() + _magPixelSize / 2;
    final double cy = magTop + _magPixelRadius * _magPixelSize.toDouble() + _magPixelSize / 2;
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: _magPixelSize.toDouble(), height: _magPixelSize.toDouble()),
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = userSettings.theme.accentColor,
    );

    // Border around whole magnifier
    canvas.drawRect(
      magRect,
      Paint()
        ..color = Colors.white24
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Pixel colour hex label under magnifier
    final int cpIdx = (centerPy * snap.pixelWidth + centerPx) * 4;
    if (cpIdx + 2 < snap.rgbaBytes.length) {
      final int r = snap.rgbaBytes[cpIdx];
      final int g = snap.rgbaBytes[cpIdx + 1];
      final int b = snap.rgbaBytes[cpIdx + 2];
      final String hex = '#${r.toRadixString(16).padLeft(2, '0')}'
              '${g.toRadixString(16).padLeft(2, '0')}'
              '${b.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();

      final TextPainter hexTp = TextPainter(
        text: TextSpan(
          text: hex,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
            backgroundColor: Colors.black.withValues(alpha: 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      hexTp.paint(
        canvas,
        Offset(
          magLeft + (_magSize - hexTp.width) / 2,
          magTop + _magSize + 4,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) =>
      old.pos != pos || old.frozenSnapshots != frozenSnapshots || old.freezeMode != freezeMode;
}

// ─────────────────────────────────────────────────────────────────────────────
// Post-capture modal — animated wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Wraps [_CaptureModal] with a smooth fade + slide-up entrance animation so
/// the modal appears gracefully instead of popping in abruptly.
class _AnimatedCaptureModal extends StatefulWidget {
  final Uint8List pngBytes;
  final String filePath;
  final Uint8List editorPngBytes;
  final String editorFilePath;
  final int imageW;
  final int imageH;
  final Function() onClose;

  const _AnimatedCaptureModal({
    required this.onClose,
    required this.pngBytes,
    required this.filePath,
    required this.editorPngBytes,
    required this.editorFilePath,
    required this.imageW,
    required this.imageH,
  });

  @override
  State<_AnimatedCaptureModal> createState() => _AnimatedCaptureModalState();
}

class _AnimatedCaptureModalState extends State<_AnimatedCaptureModal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: _CaptureModal(
          pngBytes: widget.pngBytes,
          filePath: widget.filePath,
          editorPngBytes: widget.editorPngBytes,
          editorFilePath: widget.editorFilePath,
          imageW: widget.imageW,
          imageH: widget.imageH,
          onClose: widget.onClose,
        ),
      ),
    );
  }
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
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: userSettings.theme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: userSettings.theme.accentColor.withValues(alpha: 0.2)),
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
              color: userSettings.theme.textColor.withValues(alpha: 0.04),
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
            color:
                _hovered ? widget.color.withValues(alpha: 0.15) : userSettings.theme.textColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color:
                  _hovered ? widget.color.withValues(alpha: 0.6) : userSettings.theme.textColor.withValues(alpha: 0.1),
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
                        style:
                            TextStyle(color: userSettings.theme.textColor, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        style: TextStyle(color: userSettings.theme.textColor.withValues(alpha: 0.6), fontSize: 12)),
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
