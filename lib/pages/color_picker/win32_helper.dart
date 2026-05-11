import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:just_audio/just_audio.dart';
import 'package:win32/win32.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/win32/win_utils.dart';

/// Pixel data for one grid cell.
class PixelColor {
  final int r, g, b;
  const PixelColor(this.r, this.g, this.b);
  String get hex => '#${r.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${g.toRadixString(16).padLeft(2, '0').toUpperCase()}'
      '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
}

/// Result of a single screen-capture pass.
class CaptureResult {
  final List<List<PixelColor>> grid; // [row][col], 11×11
  final PixelColor center;
  final int cursorX, cursorY;
  const CaptureResult({
    required this.grid,
    required this.center,
    required this.cursorX,
    required this.cursorY,
  });
}

class Win32Helper {
  static const int _gridSize = 11;
  static const int _half = 5; // floor(11/2)

  // ── Cursor position ───────────────────────────────────────────────────────

  static ({int x, int y}) getCursorPos() {
    final Pointer<POINT> pt = calloc<POINT>();
    try {
      GetCursorPos(pt);
      return (x: pt.ref.x, y: pt.ref.y);
    } finally {
      calloc.free(pt);
    }
  }

  // ── Async key state ───────────────────────────────────────────────────────

  /// Returns true when the given virtual key is currently pressed.
  static bool isKeyDown(int vk) {
    return (GetAsyncKeyState(vk) & 0x8000) != 0;
  }

  // ── Screen capture ────────────────────────────────────────────────────────

  /// Captures an 11×11 region centred on the cursor and returns pixel data.
  static CaptureResult captureGrid() {
    final ({int x, int y}) pos = getCursorPos();
    final int cx = pos.x;
    final int cy = pos.y;

    final int srcX = cx - _half;
    final int srcY = cy - _half;

    // Get a DC for the entire screen.
    final int screenDC = GetDC(NULL);
    // Create a compatible (memory) DC.
    final int memDC = CreateCompatibleDC(screenDC);

    // Create a DIB section so we can read raw pixel bytes directly.
    final Pointer<BITMAPINFOHEADER> bi = calloc<BITMAPINFOHEADER>();
    bi.ref.biSize = sizeOf<BITMAPINFOHEADER>();
    bi.ref.biWidth = _gridSize;
    bi.ref.biHeight = -_gridSize; // top-down
    bi.ref.biPlanes = 1;
    bi.ref.biBitCount = 32;
    bi.ref.biCompression = BI_RGB;

    // ignore: always_specify_types
    final ppvBits = calloc<Pointer<Uint8>>();
    final int hBmp = CreateDIBSection(
      screenDC,
      bi.cast(),
      DIB_RGB_COLORS,
      ppvBits.cast(),
      NULL,
      0,
    );

    SelectObject(memDC, hBmp);
    BitBlt(memDC, 0, 0, _gridSize, _gridSize, screenDC, srcX, srcY, SRCCOPY);

    // ppvBits points to the raw BGRA pixels.
    final Pointer<Uint8> pixels = ppvBits.value;
    const int stride = _gridSize * 4;

    final List<List<PixelColor>> grid = List<List<PixelColor>>.generate(_gridSize, (int row) {
      return List<PixelColor>.generate(_gridSize, (int col) {
        final int offset = row * stride + col * 4;
        final int b = pixels[offset];
        final int g = pixels[offset + 1];
        final int r = pixels[offset + 2];
        return PixelColor(r, g, b);
      });
    });

    final PixelColor center = grid[_half][_half];

    // Clean up
    DeleteObject(hBmp);
    DeleteDC(memDC);
    ReleaseDC(NULL, screenDC);
    calloc.free(bi);
    calloc.free(ppvBits);

    return CaptureResult(
      grid: grid,
      center: center,
      cursorX: cx,
      cursorY: cy,
    );
  }

  // ── Screen bounds for the monitor containing a point ─────────────────────

  static ({int left, int top, int right, int bottom}) monitorBoundsAt(int x, int y) {
    final Pointer<POINT> pt = calloc<POINT>();
    pt.ref.x = x;
    pt.ref.y = y;
    final int hMon = MonitorFromPoint(pt.ref, MONITOR_DEFAULTTONEAREST);
    final Pointer<MONITORINFO> mi = calloc<MONITORINFO>();
    mi.ref.cbSize = sizeOf<MONITORINFO>();
    GetMonitorInfo(hMon, mi);
    final RECT rc = mi.ref.rcMonitor;
    final ({int bottom, int left, int right, int top}) result =
        (left: rc.left, top: rc.top, right: rc.right, bottom: rc.bottom);
    calloc.free(pt);
    calloc.free(mi);
    return result;
  }

  static void saveGridJson(CaptureResult capture) {
    try {
      final List<dynamic> rows = List<dynamic>.generate(capture.grid.length, (int row) {
        return List<dynamic>.generate(capture.grid[row].length, (int col) {
          final PixelColor px = capture.grid[row][col];
          return <String, Object>{'hex': px.hex, 'r': px.r, 'g': px.g, 'b': px.b};
        });
      });

      final Map<String, Object> payload = <String, Object>{
        'cursor': <String, int>{'x': capture.cursorX, 'y': capture.cursorY},
        'center': <String, Object>{
          'hex': capture.center.hex,
          'r': capture.center.r,
          'g': capture.center.g,
          'b': capture.center.b,
        },
        'grid': rows,
      };

      final String exeDir = WinUtils.getTabameAppDataFolder();
      File('$exeDir/grid.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payload));
    } catch (_) {
      // Non-fatal — just skip the file write.
    }
  }

  static Future<void> instantColorPicker() async {
    if (QuickMenuFunctions.isQuickMenuVisible) {
      QuickMenuFunctions.toggleQuickMenu(visible: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final AudioPlayer player = AudioPlayer();
    await player.setAsset('resources/beep.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await player.seek(Duration.zero);
    await player.play();

    final CaptureResult capture = Win32Helper.captureGrid();
    Win32Helper.saveGridJson(capture);
    QuickMenuFunctions.openQuickMenuWithAction("Color Picker", center: true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.dispose();
  }
}

// ── Clipboard helper ──────────────────────────────────────────────────────────

void setClipboardText(String text) {
  if (OpenClipboard(NULL) == 0) return; // returns BOOL (int), not Dart bool
  EmptyClipboard();

  final List<int> units = text.codeUnits;
  // +1 for null terminator, *2 for UTF-16 (WCHAR)
  final Pointer<NativeType> hMem = GlobalAlloc(GMEM_MOVEABLE, (units.length + 1) * 2);
  if (hMem.address == 0) {
    CloseClipboard();
    return;
  }
  final Pointer<Uint16> ptr = GlobalLock(hMem).cast<Uint16>();
  for (int i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  ptr[units.length] = 0; // null terminator
  GlobalUnlock(hMem);
  // CF_UNICODETEXT = 13; use the integer constant directly
  SetClipboardData(13, hMem.address);
  CloseClipboard();
}
