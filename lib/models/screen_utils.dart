// ignore_for_file: unused_element, dead_code

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart' as intl;
import 'package:just_audio/just_audio.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../models/win32/win_utils.dart';
import '../widgets/interface/fancyshot.dart';

// ---------------------------------------------------------------------------
// Rect extension — shared by both files
// ---------------------------------------------------------------------------

extension RectNormExtension on Rect {
  Rect normalized() => Rect.fromLTRB(
        left < right ? left : right,
        top < bottom ? top : bottom,
        left < right ? right : left,
        top < bottom ? bottom : top,
      );
}

// ---------------------------------------------------------------------------
// Settings base class
//
// Both screen_draw.dart and screen_capture.dart have a local `Settings` class
// with the same load/save/get/set pattern backed by a JSON file.  Each screen
// supplies its own _path by overriding the getter; everything else is shared.
//
// Usage:
//   class Settings extends SettingsBase {
//     static String get _path => '...\\screen_draw.json';
//     // delegate every static call to the singleton instance:
//     static void load() => _instance.loadFrom(_path);
//     ...
//   }
//
// Because Dart does not allow static abstract members, the simplest pattern
// is to keep the two thin wrappers in each file and delegate to the helpers
// below.
// ---------------------------------------------------------------------------

/// Shared JSON-file-backed key-value store.
/// Instantiate once per file (or use static delegation).
class SettingsStore {
  Map<String, dynamic> _data = <String, dynamic>{};

  void loadFrom(String path) {
    try {
      final File file = File(path);
      if (file.existsSync()) {
        final String content = file.readAsStringSync();
        _data = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // ignore
    }
  }

  void saveTo(String path) {
    try {
      File(path).writeAsStringSync(jsonEncode(_data));
    } catch (_) {
      // ignore
    }
  }

  // ── Typed getters / setters ──────────────────────────────────────────────

  String? getString(String key) => _data[key] as String?;

  void setString(String key, String? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  bool? getBool(String key) => _data[key] as bool?;

  void setBool(String key, bool value) {
    _data[key] = value;
  }

  int? getInt(String key) => _data[key] as int?;

  void setInt(String key, int value) {
    _data[key] = value;
  }

  bool containsKey(String key) => _data.containsKey(key);

  /// Expose raw data for migration helpers.
  Map<String, dynamic> get raw => _data;
}

// ---------------------------------------------------------------------------
// Win32Window — shared overlay/HWND helpers
//
// Identical across both files except screen_capture.dart's setupOverlay() has
// an async delay and slightly different exStyle flags (no WS_EX_TOOLWINDOW).
// The common operations are factored here; each file may call setupOverlay()
// with the appropriate flags.
// ---------------------------------------------------------------------------

class Win32Window {
  static int hwnd = 0;

  /// Returns the Flutter window HWND, discovering it on first call.
  static int getHwnd() {
    if (hwnd != 0) return hwnd;
    hwnd = GetAncestor(GetActiveWindow(), 2);
    return hwnd;
  }

  /// Allow callers (e.g. startScreenDraw) to set the HWND directly.
  static void setHwnd(int hWnd) => hwnd = hWnd;

  // ── Visibility ────────────────────────────────────────────────────────────

  /// Show or hide the overlay window and, when showing, bring it topmost.
  static void setVisible(bool visible) {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;
    ShowWindow(hwnd, visible ? SW_SHOW : SW_HIDE);
    if (visible) {
      SetWindowPos(
        hwnd,
        HWND_TOPMOST,
        0,
        0,
        0,
        0,
        SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW,
      );
    }
  }

  // ── Overlay setup ─────────────────────────────────────────────────────────

  /// Make the window borderless, layered, and topmost, spanning the full
  /// virtual desktop.
  ///
  /// Pass [toolWindow] = true (screen_draw) to also set WS_EX_TOOLWINDOW.
  /// Pass [delayMs] > 0 (screen_capture) to add an initial async delay.
  static Future<void> setupOverlay({
    bool toolWindow = false,
    int delayMs = 0,
  }) async {
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }

    final int hwnd = getHwnd();
    if (hwnd == 0) return;

    // Remove title-bar / resize decorations.
    final int style = GetWindowLongPtr(hwnd, GWL_STYLE);
    SetWindowLongPtr(
      hwnd,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );

    int exFlags = WS_EX_LAYERED | WS_EX_TOPMOST;
    if (toolWindow) exFlags |= WS_EX_TOOLWINDOW;

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | exFlags);

    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    final int vLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
    final int vTop = GetSystemMetrics(SM_YVIRTUALSCREEN);
    final int vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final int vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);

    SetWindowPos(
      hwnd,
      HWND_TOPMOST,
      vLeft,
      vTop,
      vWidth,
      vHeight,
      SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  // ── Click-through ─────────────────────────────────────────────────────────

  /// Enable click-through: window is visible but the mouse passes through.
  static void enableClickThrough() {
    int hwnd = getHwnd();
    if (hwnd == 0) return;

    int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);

    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }

  /// Disable click-through: window captures mouse events again.
  static void disableClickThrough() {
    int hwnd = getHwnd();
    if (hwnd == 0) return;

    int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT);

    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }
}

class ScreenUtils {
  static Future<void> playCameraSound() async {
    final AudioPlayer player = AudioPlayer();
    await player.setAsset('resources/camera_click.mp3');
    await player.seek(Duration.zero);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await player.dispose();
  }

  static Future<String> saveScreenshot(
    Uint8List pngBytes,
  ) async {
    final DateTime date = DateTime.now();

    String shortMonth = intl.DateFormat('MMM').format(date);

    final Directory dir =
        Directory('${WinUtils.getTabameAppDataFolder()}\\fancyshot\\screenshots\\${date.year} - $shortMonth');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      WinUtils.setSortByDateModifiedDesc(dir.path);
    }
    DateTime now = DateTime.now();
    final String ts = intl.DateFormat('d EEEE HH-mm-ss').format(now);
    final String path = '${dir.path}\\$ts.png';
    await File(path).writeAsBytes(pngBytes);
    return path;
  }
}

// ---------------------------------------------------------------------------
// ScreenRegionCapture — GDI-based pixel capture helpers
//
// The BGRA→RGBA loop and GDI object management pattern is identical in both
// files.  Centralised here so each file only calls the high-level helpers.
// ---------------------------------------------------------------------------

class ScreenRegionCapture {
  /// Capture [screenRect] (screen / physical coords) using GDI BitBlt and
  /// return raw RGBA bytes (width × height × 4).
  ///
  /// Returns null if the bitmap could not be created.
  static Uint8List? captureRgba(Rect screenRect) {
    final int x = screenRect.left.round();
    final int y = screenRect.top.round();
    final int w = screenRect.width.round().clamp(1, 100000);
    final int h = screenRect.height.round().clamp(1, 100000);

    final int screenDc = GetDC(NULL);
    final int memDc = CreateCompatibleDC(screenDc);
    final int bmp = CreateCompatibleBitmap(screenDc, w, h);
    SelectObject(memDc, bmp);
    BitBlt(memDc, 0, 0, w, h, screenDc, x, y, SRCCOPY | CAPTUREBLT);

    final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();
    final Pointer<Uint8> bgra = calloc<Uint8>(w * h * 4);
    try {
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = w;
      bmi.ref.bmiHeader.biHeight = -h;
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_RGB;

      if (GetDIBits(memDc, bmp, 0, h, bgra.cast(), bmi, DIB_RGB_COLORS) == 0) {
        return null;
      }

      return bgraToRgba(bgra.asTypedList(w * h * 4));
    } finally {
      DeleteObject(bmp);
      DeleteDC(memDc);
      ReleaseDC(NULL, screenDc);
      calloc.free(bgra);
      calloc.free(bmi);
    }
  }

  /// Capture [screenRect] and encode the result as a PNG.
  static Future<Uint8List?> captureRegionToPng(Rect screenRect) async {
    final int w = screenRect.width.round().clamp(1, 1000000);
    final int h = screenRect.height.round().clamp(1, 1000000);
    final Uint8List? rgba = captureRgba(screenRect);
    if (rgba == null) return null;
    return encodeRgbaToPng(rgba, w, h);
  }

  /// Encode an RGBA byte buffer as a PNG.
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

  /// Swap BGRA → RGBA in-place (returns a new buffer).
  static Uint8List bgraToRgba(Uint8List src) {
    final Uint8List out = Uint8List(src.length);
    for (int i = 0; i < src.length; i += 4) {
      out[i] = src[i + 2]; // R ← B
      out[i + 1] = src[i + 1]; // G
      out[i + 2] = src[i]; // B ← R
      out[i + 3] = 255; // A
    }
    return out;
  }

  /// Copy the PNG to the system clipboard as a bitmap.
  static Future<void> copyPngToClipboard(Uint8List pngBytes) async {
    ClipboardExtended.copyImage(pngBytes);
  }

  /// Copy a file path to the clipboard (as a file drop).
  static Future<void> copyFileToClipboard(String filePath) async {
    ClipboardExtension.copyFile(filePath);
  }

  /// Save [pngBytes] to %localappdata%\Tabame\screenshots\<year - Mon>\<ts>.png
  /// and return the full path.
  static Future<String> saveToFile(Uint8List pngBytes) async {
    final DateTime date = DateTime.now();
    final String shortMonth = intl.DateFormat('MMM').format(date);
    final Directory dir = Directory(
      '${WinUtils.getTabameAppDataFolder()}\\fancyshot\\screenshots\\${date.year} - $shortMonth',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      WinUtils.setSortByDateModifiedDesc(dir.path);
    }
    final String ts = intl.DateFormat('d EEEE HH-mm-ss').format(date);
    final String path = '${dir.path}\\$ts.png';
    await File(path).writeAsBytes(pngBytes);
    return path;
  }
}

class UploadUtils {
  static Future<bool> runUploadHost(ScreenCaptureUploadHost host, String filePath,
      {required Function(String url) onSuccess, required Function(String description) onError}) async {
    switch (host.uploadType) {
      case UploadHostType.catbox:
        return uploadToCatbox(filePath, onSuccess: onSuccess, onError: onError);
      case UploadHostType.prntscr:
        return uploadToPrntScr(filePath, onSuccess: onSuccess, onError: onError);
      case UploadHostType.imgur:
        return uploadToImgur(filePath, onSuccess: onSuccess, onError: onError);
      case UploadHostType.custom:
        return runCustomUploadCommand(host, filePath, onSuccess: onSuccess, onError: onError);
    }
  }

  static Future<bool> uploadToCatbox(
    String filePath, {
    required void Function(String url) onSuccess,
    required void Function(String description) onError,
  }) async {
    try {
      final File file = File(filePath);
      if (!file.existsSync()) {
        onError('File not found:\n$filePath');
        return false;
      }

      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final Uri uri = Uri.parse('https://catbox.moe/user/api.php');
      final HttpClientRequest request = await client.postUrl(uri);

      final String boundary = '----TabameBoundary${DateTime.now().millisecondsSinceEpoch}';
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      final BytesBuilder body = BytesBuilder();

      void addField(String name, String value) {
        body.add(utf8.encode('--$boundary\r\n'));
        body.add(
          utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
        );
        body.add(utf8.encode('$value\r\n'));
      }

      addField('reqtype', 'fileupload');

      final Uint8List fileBytes = file.readAsBytesSync();
      final String fileName = file.path.split(Platform.pathSeparator).last;
      body.add(utf8.encode('--$boundary\r\n'));
      body.add(utf8.encode(
        'Content-Disposition: form-data; name="fileToUpload"; filename="$fileName"\r\n',
      ));
      body.add(utf8.encode('Content-Type: image/png\r\n\r\n'));
      body.add(fileBytes);
      body.add(utf8.encode('\r\n'));
      body.add(utf8.encode('--$boundary--\r\n'));

      final Uint8List bodyBytes = body.toBytes();
      request.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length.toString());
      request.add(bodyBytes);

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200 && responseBody.startsWith('https://')) {
        final String url = responseBody.trim();
        ClipboardExtended.copy(url);
        // await Process.start(
        //   'cmd.exe',
        //   <String>['/c', 'start', '', url],
        //   mode: ProcessStartMode.detached,
        // );
        onSuccess(url);
        return true;
      } else {
        onError('HTTP ${response.statusCode}\n\n$responseBody');
        return false;
      }
    } catch (e) {
      onError('$e');
      return false;
    }
  }

  static Future<bool> uploadToImgur(
    String filePath, {
    required void Function(String url) onSuccess,
    required void Function(String description) onError,
  }) async {
    try {
      final File file = File(filePath);
      if (!file.existsSync()) {
        onError('File not found:\n$filePath');
        return false;
      }

      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final Uri uri = Uri.parse(
        'https://api.imgur.com/3/upload?client_id=d70305e7c3ac5c6',
      );

      final HttpClientRequest request = await client.postUrl(uri);

      final String boundary = '----WebKitFormBoundary${DateTime.now().millisecondsSinceEpoch}';

      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.refererHeader, 'https://imgur.com/');

      final BytesBuilder body = BytesBuilder();

      void addField(String name, String value) {
        body.add(utf8.encode('--$boundary\r\n'));
        body.add(utf8.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'));
        body.add(utf8.encode('$value\r\n'));
      }

      void addFile(String path, Uint8List bytes) {
        final String fileName = path.split(Platform.pathSeparator).last;

        body.add(utf8.encode('--$boundary\r\n'));
        body.add(utf8.encode(
          'Content-Disposition: form-data; name="image"; filename="$fileName"\r\n',
        ));
        body.add(utf8.encode('Content-Type: application/octet-stream\r\n\r\n'));
        body.add(bytes);
        body.add(utf8.encode('\r\n'));
      }

      final Uint8List fileBytes = await file.readAsBytes();

      // required fields from your request
      addFile(filePath, fileBytes);
      addField('type', 'file');
      addField('name', filePath.split(Platform.pathSeparator).last);

      body.add(utf8.encode('--$boundary--\r\n'));

      final Uint8List bodyBytes = body.toBytes();

      request.headers.set(
        HttpHeaders.contentLengthHeader,
        bodyBytes.length.toString(),
      );

      request.add(bodyBytes);

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();

      client.close();

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> json = jsonDecode(responseBody) as Map<String, dynamic>;

          final bool success = json['success'] == true;
          final String? link = json['data']?['link'];

          if (success && link != null && link.startsWith('http')) {
            onSuccess(link);
            return true;
          } else {
            onError('Upload failed:\n$responseBody');
            return false;
          }
        } catch (e) {
          onError('JSON parse error: $e\n\n$responseBody');
          return false;
        }
      } else {
        onError('HTTP ${response.statusCode}\n\n$responseBody');
        return false;
      }
    } catch (e) {
      onError('$e');
      return false;
    }
  }

  static Future<bool> uploadToPrntScr(
    String filePath, {
    required void Function(String url) onSuccess,
    required void Function(String description) onError,
  }) async {
    try {
      final File file = File(filePath);
      if (!file.existsSync()) {
        onError('File not found:\n$filePath');
        return false;
      }

      final HttpClient client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);

      final Uri uri = Uri.parse('https://prntscr.com/upload.php');
      final HttpClientRequest request = await client.postUrl(uri);

      final String boundary = '----WebKitFormBoundary${DateTime.now().millisecondsSinceEpoch}';

      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );

      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/json, text/javascript, */*; q=0.01',
      );

      request.headers.set(HttpHeaders.refererHeader, 'https://prnt.sc/');

      final BytesBuilder body = BytesBuilder();

      void addFile(String fieldName, String path, Uint8List bytes) {
        final String fileName = path.split(Platform.pathSeparator).last;

        body.add(utf8.encode('--$boundary\r\n'));
        body.add(utf8.encode(
          'Content-Disposition: form-data; name="$fieldName"; filename="$fileName"\r\n',
        ));
        body.add(utf8.encode('Content-Type: image/jpeg\r\n\r\n'));
        body.add(bytes);
        body.add(utf8.encode('\r\n'));
      }

      final Uint8List fileBytes = await file.readAsBytes();
      addFile('image', filePath, fileBytes);

      body.add(utf8.encode('--$boundary--\r\n'));

      final Uint8List bodyBytes = body.toBytes();

      request.headers.set(
        HttpHeaders.contentLengthHeader,
        bodyBytes.length.toString(),
      );

      request.add(bodyBytes);

      final HttpClientResponse response = await request.close();
      final String responseBody = await response.transform(utf8.decoder).join();

      client.close();

      if (response.statusCode == 200) {
        try {
          final Map<String, dynamic> json = jsonDecode(responseBody) as Map<String, dynamic>;

          final String? url = json['data'];

          if (url != null && url.startsWith('http')) {
            onSuccess(url);
            return true;
          } else {
            onError('Invalid response format:\n$responseBody');
            return false;
          }
        } catch (e) {
          onError('JSON parse error: $e\n\n$responseBody');
          return false;
        }
      } else {
        onError('HTTP ${response.statusCode}\n\n$responseBody');
        return false;
      }
    } catch (e) {
      onError('$e');
      return false;
    }
  }

  /// Run a custom upload command defined by [host], substituting the file path.
  ///
  /// Returns true if the process was launched successfully.
  static Future<bool> runCustomUploadCommand(
    ScreenCaptureUploadHost host,
    String filePath, {
    required void Function(String url) onSuccess,
    required void Function(String description) onError,
  }) async {
    try {
      final String escapedFilePath = filePath.replaceAll("'", "''");
      final String resolvedCommand = host.command.contains(r'${file}')
          ? host.command.replaceAll(r'${file}', "'$escapedFilePath'")
          : "${host.command} '$escapedFilePath'";
      final Process result = await Process.start(
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
      onSuccess(result.stdout as String);
      return true;
    } catch (_) {
      onError("");
      return false;
    }
  }
}
