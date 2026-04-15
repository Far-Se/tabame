import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/win32/win32.dart';
import 'win32_helper.dart';
import 'color_picker_painter.dart';

// Virtual key codes
const int _vkEscape = 0x1B;
const int _vkLButton = 0x01;

class ColorPickerApp extends StatelessWidget {
  const ColorPickerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColorPickerWindow(),
    );
  }
}

class ColorPickerWindow extends StatefulWidget {
  const ColorPickerWindow({super.key});

  @override
  State<ColorPickerWindow> createState() => _ColorPickerWindowState();
}

class _ColorPickerWindowState extends State<ColorPickerWindow> with WindowListener {
  static const double _pickerWidth = 137;
  static const double _pickerHeight = 193;
  static const double _cursorInset = 34;

  // ── State ──────────────────────────────────────────────────────────────────

  List<List<PixelColor>> _grid = List<List<PixelColor>>.generate(
    11,
    (_) => List<PixelColor>.generate(11, (_) => const PixelColor(0, 0, 0)),
  );
  PixelColor _center = const PixelColor(0, 0, 0);
  bool _copied = false;
  int _copiedTimer = 0;

  // Prevent double-triggering on the first left-click frame.
  final DateTime _startTime = DateTime.now();

  // Track previous left-button state so we fire on press, not hold.
  bool _lbWasDown = false;

  Timer? _ticker;

  // ── Window positioning around the cursor ──────────────────────────────────
  bool _showRight = true;
  bool _showBelow = true;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // ~60 fps
    _ticker = Timer.periodic(const Duration(milliseconds: 16), _tick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  // ── Main update loop ──────────────────────────────────────────────────────

  void _tick(Timer _) {
    final CaptureResult capture = Win32Helper.captureGrid();

    // ── Escape → exit ──────────────────────────────────────────────────────
    if (Win32Helper.isKeyDown(_vkEscape)) {
      _exit();
      return;
    }

    // ── Left-click (rising edge, after 400 ms grace period) ───────────────
    final bool lbDown = Win32Helper.isKeyDown(_vkLButton);
    final int elapsed = DateTime.now().difference(_startTime).inMilliseconds;

    if (lbDown && !_lbWasDown && elapsed > 400) {
      _lbWasDown = true;
      _onPick(capture);
      return;
    }
    if (!lbDown) _lbWasDown = false;

    // ── Copied flash timer ─────────────────────────────────────────────────
    if (_copied) {
      _copiedTimer--;
      if (_copiedTimer <= 0) {
        _copied = false;
        _copiedTimer = 0;
      }
    }

    // ── Reposition window next to cursor ──────────────────────────────────
    _repositionWindow(capture.cursorX, capture.cursorY);

    setState(() {
      _grid = capture.grid;
      _center = capture.center;
    });
  }

  // ── Pick colour → clipboard + grid.json + exit ────────────────────────────

  void _onPick(CaptureResult capture) {
    // if (!reposition) return;
    final String hex = capture.center.hex;
    final PixelColor c = capture.center;

    // Copy to clipboard
    final String clipText = '$hex RGB(${c.r},${c.g},${c.b})';
    setClipboardText(clipText);

    // Save grid.json next to the executable
    _saveGridJson(capture);

    setState(() {
      _copied = true;
      _copiedTimer = 45;
      _grid = capture.grid;
      _center = capture.center;
    });

    // Brief flash then exit
    Future<void>.delayed(const Duration(milliseconds: 750), _exit);
    reposition = false;
  }

  // ── Reposition window ─────────────────────────────────────────────────────
  bool reposition = true;
  void _repositionWindow(int cx, int cy) {
    if (!reposition) return;
    final ({int bottom, int left, int right, int top}) bounds = Win32Helper.monitorBoundsAt(cx, cy);

    _showRight = (cx + (_cursorInset / 2) + _pickerWidth) <= bounds.right;
    _showBelow = (cy + (_cursorInset / 2) + _pickerHeight) <= bounds.bottom;

    double left = _showRight ? cx - (_cursorInset / 2) : cx - _pickerWidth - (_cursorInset / 2);
    double top = _showBelow ? cy - (_cursorInset / 2) : cy - _pickerHeight - (_cursorInset / 2);

    left = left.clamp(bounds.left.toDouble(), (bounds.right - (_pickerWidth + (_cursorInset / 2))).toDouble());
    top = top.clamp(bounds.top.toDouble(), (bounds.bottom - (_pickerHeight + (_cursorInset / 2))).toDouble());

    windowManager.setPosition(Offset(left, top), animate: false);
  }

  // ── Write grid.json ───────────────────────────────────────────────────────

  void _saveGridJson(CaptureResult capture) {
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

  // ── Exit ──────────────────────────────────────────────────────────────────

  void _exit() {
    _ticker?.cancel();
    windowManager.close();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EdgeInsets pickerPadding = EdgeInsets.only(
      left: _showRight ? _cursorInset : 0,
      top: _showBelow ? _cursorInset : 0,
      right: _showRight ? 0 : _cursorInset,
      bottom: _showBelow ? 0 : _cursorInset,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: MouseRegion(
        onEnter: (_) => reposition = true,
        child: KeyboardListener(
          focusNode: FocusNode()..requestFocus(),
          onKeyEvent: (KeyEvent e) {
            if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
              _exit();
            }
          },
          child: SizedBox.expand(
            child: ColoredBox(
              color: Colors.transparent,
              child: Padding(
                padding: pickerPadding,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: ColorPickerPainter(
                        grid: _grid,
                        center: _center,
                        copied: _copied,
                      ),
                      size: const Size(_pickerWidth, _pickerHeight),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
