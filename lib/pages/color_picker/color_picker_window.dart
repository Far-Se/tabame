import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/theme.dart';
import '../../models/util/color_picker_controller.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../widgets/widgets/color_picker_panel.dart';
import 'color_picker_painter.dart';
import 'win32_helper.dart';

// Virtual key codes
const int _vkEscape = 0x1B;
const int _vkLButton = 0x01;

class ColorPickerApp extends StatelessWidget {
  const ColorPickerApp({super.key, this.isStandalone = false});
  final bool isStandalone;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Globals.themeChangeNotifier,
      builder: (BuildContext context, _, __) {
        ThemeMode scheduled = ThemeMode.system;
        ThemeType themeType = userSettings.themeType;
        if (themeType.index == 3) {
          scheduled = userSettings.themeTypeMode == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;
        }
        ThemeMode themeMode =
            <ThemeMode>[ThemeMode.system, ThemeMode.light, ThemeMode.dark, scheduled][themeType.index];

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getLightThemeData(),
          darkTheme: AppTheme.getDarkThemeData(context),
          themeMode: themeMode,
          home: ColorPickerWindow(isStandalone: isStandalone),
        );
      },
    );
  }
}

class ColorPickerWindow extends StatefulWidget {
  const ColorPickerWindow({super.key, this.isStandalone = false});
  final bool isStandalone;

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
  bool _showPanel = false;

  // ── Window positioning around the cursor ──────────────────────────────────
  bool _showRight = true;
  bool _showBelow = true;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    if (widget.isStandalone) {
      // Ensure window resets to picker size on start/hot-restart
      Win32.setSize(Win32.hWnd, 171, 227);
      windowManager.setAlwaysOnTop(true);
    }

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
    if (_showPanel) return;
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

  void _onPick(CaptureResult capture) async {
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

    if (widget.isStandalone || userSettings.args.contains("-colorPicker")) {
      final List<List<ColorGridSample>> gridSamples =
          List<List<ColorGridSample>>.generate(capture.grid.length, (int row) {
        return List<ColorGridSample>.generate(capture.grid[row].length, (int col) {
          final PixelColor px = capture.grid[row][col];
          return ColorGridSample(r: px.r, g: px.g, b: px.b, hex: px.hex);
        });
      });

      final ColorPickerCapture captureData = ColorPickerCapture(
        center: ColorGridSample(r: capture.center.r, g: capture.center.g, b: capture.center.b, hex: capture.center.hex),
        grid: gridSamples,
      );

      ColorPickerController.instance.updateCapture(captureData);

      setState(() {
        _showPanel = true;
        reposition = false;
      });

      await windowManager.setSize(const Size(355, 580));
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setAlignment(Alignment.center);
    } else {
      // Brief flash then exit
      Future<void>.delayed(const Duration(milliseconds: 750), _exit);
      reposition = false;
    }
  }

  void _onPickRequested() async {
    final PointXY pos = WinUtils.getMousePos();
    final int hwnd = Win32.hWnd;

    windowManager.setAlwaysOnTop(true);
    // Use Win32 helper to resize and move immediately to avoid "dashboard dragging" feel
    Win32.setPosDPI(hwnd, pos, logicalWidth: 171, logicalHeight: 227);

    setState(() {
      _showPanel = false;
      reposition = true;
      _lbWasDown = true; // Avoid instant pick if button is still held
    });
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _showPanel ? _buildPanel() : _buildPicker(),
    );
  }

  Widget _buildPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ColorPickerPanel(
          onPickRequested: _onPickRequested,
          onClose: widget.isStandalone ? _exit : null,
          isStandalone: widget.isStandalone,
        ),
      ),
    );
  }

  Widget _buildPicker() {
    final EdgeInsets pickerPadding = EdgeInsets.only(
      left: _showRight ? _cursorInset : 0,
      top: _showBelow ? _cursorInset : 0,
      right: _showRight ? 0 : _cursorInset,
      bottom: _showBelow ? 0 : _cursorInset,
    );

    return MouseRegion(
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
    );
  }
}
