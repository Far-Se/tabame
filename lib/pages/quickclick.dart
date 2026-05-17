import 'dart:async';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes/boxes_base.dart';
import '../models/classes/boxes/quick_menu_box.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';

// ─── constants ───────────────────────────────────────────────────────────────

const double _kLabelBarSize = 40.0;

// ─── overlay widget ──────────────────────────────────────────────────────────

class QuickClickOverlay extends StatefulWidget {
  const QuickClickOverlay({super.key});

  @override
  State<QuickClickOverlay> createState() => _QuickClickOverlayState();
}

class _QuickClickOverlayState extends State<QuickClickOverlay> with TabameListener {
  final List<String> rows = userSettings.quickClickConfig.verticalKeys.toUpperCaseAll().split('');
  final List<String> cols = userSettings.quickClickConfig.horizontalKeys.toUpperCaseAll().split('');

  late double screenWidth;
  late double screenHeight;

  int? selectedRow;
  int? selectedCol;

  // ── zone mode state ─────────────────────────────────────────────────────────
  //
  // Zone mode splits the screen into 4 quadrants.  The user first presses one
  // of the 4 zone letters shown at the quadrant centres, then the normal
  // row/col grid is drawn clipped to that quadrant.
  //
  // zoneMode: false = classic full-screen grid
  //           true  = zone picker (or zoomed zone grid when _selectedZone != null)
  bool zoneMode = false;

  /// Which quadrant is active (0=TL, 1=TR, 2=BL, 3=BR).  null = picker phase.
  int? _selectedZone;

  /// The four letters shown at the quadrant centres, derived from cols[0..3].
  List<String> get _zoneLabels {
    final List<String> src =
        cols.length >= 4 ? cols.sublist(0, 4) : <String>[...cols, ...List<String>.filled(4 - cols.length, '?')];
    return src;
  }

  /// Pixel rect of the selected zone within the overlay.
  Rect get _zoneRect {
    final double hw = screenWidth / 2;
    final double hh = screenHeight / 2;
    switch (_selectedZone) {
      case 0:
        return Rect.fromLTWH(0, 0, hw, hh); // top-left
      case 1:
        return Rect.fromLTWH(hw, 0, hw, hh); // top-right
      case 2:
        return Rect.fromLTWH(0, hh, hw, hh); // bottom-left
      case 3:
        return Rect.fromLTWH(hw, hh, hw, hh); // bottom-right
      default:
        return Rect.fromLTWH(0, 0, screenWidth, screenHeight);
    }
  }

  // ── drag state ──────────────────────────────────────────────────────────────
  bool _isDragging = false;
  Offset _dragCursorPos = Offset.zero;
  Timer? _dragPollTimer;

  int currentMonitor = -1;
  Square monitorData = Square(x: 0, y: 0, width: 0, height: 0);

  bool showInfoModal = false;
  bool overlayVisible = true;

  // ── init ────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    Win32.setWindowInvisible(true);
    NativeHooks.addListener(this);
    QuickClick.setQuickClickHotkeys(userSettings.quickClickConfig);
    QuickClick.enableQuickClick();
    _enableDpiAwareness();

    currentMonitor = Monitor.getCursorMonitor();
    monitorData = Monitor.monitorSizes[currentMonitor]!;
    WindowManager.instance.setPosition(Offset(monitorData.x.toDouble(), monitorData.y.toDouble()));
    WindowManager.instance.setSize(Size(monitorData.width.toDouble(), monitorData.height.toDouble()));
    WinUtils.makeWindowClickThrough(true);
    WinUtils.fixDrawBug();
    overlayVisible = Boxes.pref.getBool("quickClickOverlay") ?? true;
    screenWidth = monitorData.width.toDouble();
    screenHeight = monitorData.height.toDouble();
    Timer(const Duration(milliseconds: 200), () {
      _refocusPreviousWindow();
      WinUtils.makeWindowClickThrough(true);
      Win32.setWindowInvisible(false);
    });
  }

  // ── event handler ───────────────────────────────────────────────────────────
  int selecting = 0;
  @override
  void onQuickClickEvent(String eventName, Map<String, String> params) {
    switch (eventName) {
      case 'Esc':
        if (zoneMode && _selectedZone != null) {
          // Step back to zone picker rather than closing.
          setState(() {
            _selectedZone = null;
            selectedRow = null;
            selectedCol = null;
            selecting = 0;
            zoneMode = false;
          });
        } else {
          Win32.setPosition(const Offset(-99999, -99999));
          QuickMenuFunctions.toggleQuickMenu(visible: false);
        }
        break;

      case 'info':
        setState(() => showInfoModal = !showInfoModal);
        break;

      case 'overlay':
        setState(() {
          overlayVisible = !overlayVisible;
          Boxes.pref.setBool("quickClickOverlay", overlayVisible);
        });
        break;

      case 'zoneMode':
        toggleZoneMode();
        break;

      case 'nextMonitor':
      case 'prevMonitor':
        _updateMonitor();
        break;

      case 'moveY':
        if (zoneMode && _selectedZone == null) {
          // Y key selects a zone: index 0/1 → top zones, 2/3 → bottom zones.
          //   final int idx = int.tryParse(params['index'] ?? '0') ?? 0;
          // Map row index to the zone that contains that half:
          // top half rows (0 .. ceil(rows/2)-1) → pick zone based on pending col
          // We use Y to pick the row-half: even index → top (0), odd → bottom (2).
          // The col-half is chosen later via moveX.
          // Simpler UX: treat this as col selection in zone picker – noop until col received.
          break;
        }
        setState(() {
          selecting = 1;
          // In zone mode, selectedRow is relative to the zone's row subset.
          selectedRow = int.tryParse(params['index'] ?? '0') ?? 0;
          _moveCursorToSelection();
        });
        break;

      case 'moveX':
        if (zoneMode && _selectedZone == null) {
          // X key in picker phase: pick a zone by col index mapped to 4 zones.
          final int idx = int.tryParse(params['index'] ?? '0') ?? 0;
          if (idx < _zoneLabels.length) {
            setState(() => _selectedZone = idx);
          }
          break;
        }
        setState(() {
          selecting = 2;
          selectedCol = int.tryParse(params['index'] ?? '0') ?? 0;
          _moveCursorToSelection();
        });
        break;

      case 'dragStart':
        _startDragIndicator();
        break;
      case 'dragEnd':
        _stopDragIndicator();
        break;
      case 'nudge':
        if (selectedRow != null) {
          setState(() {
            selecting = 0;
            selectedRow = null;
          });
        }
        if (selectedCol != null) {
          setState(() {
            selecting = 0;
            selectedCol = null;
          });
        }
        break;
    }
  }

  // ── drag indicator helpers ──────────────────────────────────────────────────

  void _startDragIndicator() {
    _isDragging = true;
    _dragPollTimer?.cancel();
    // Poll cursor position at ~60 fps so the indicator follows the real cursor.
    _dragPollTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final Pointer<POINT> pt = calloc<POINT>();
      GetCursorPos(pt);
      // Convert absolute screen coords to local overlay coords.
      final double lx = (pt.ref.x - monitorData.x).toDouble();
      final double ly = (pt.ref.y - monitorData.y).toDouble();
      calloc.free(pt);
      if (mounted) {
        setState(() => _dragCursorPos = Offset(lx, ly));
      }
    });
    setState(() {});
  }

  void _stopDragIndicator() {
    _dragPollTimer?.cancel();
    _dragPollTimer = null;
    if (mounted) setState(() => _isDragging = false);
  }

  // ── dispose ─────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _dragPollTimer?.cancel();
    NativeHooks.removeListener(this);
    QuickClick.disableQuickClick();
    _refocusPreviousWindow();
    super.dispose();
  }

  /// Toggle zone mode on/off (can be called via a GlobalKey from outside).
  void toggleZoneMode() {
    setState(() {
      zoneMode = !zoneMode;
      _selectedZone = null;
      selectedRow = null;
      selectedCol = null;
      selecting = 0;
    });
  }

  Future<void> _refocusPreviousWindow() async {
    final int targetHwnd = Globals.lastFocusedWinHWND;
    Win32.activateWindow(targetHwnd);
    // await WindowWatcher.fetchWindows();
    // await Future<void>.delayed(const Duration(milliseconds: 50));
    // Win32.activateWindow(WindowWatcher.list.first.hWnd);
  }

  void _updateMonitor() {
    setState(() {
      currentMonitor = Monitor.getCursorMonitor();
      monitorData = Monitor.monitorSizes[currentMonitor]!;
      WindowManager.instance.setPosition(Offset(monitorData.x.toDouble(), monitorData.y.toDouble()));
      WindowManager.instance.setSize(Size(monitorData.width.toDouble(), monitorData.height.toDouble()));
      screenWidth = monitorData.width.toDouble();
      screenHeight = monitorData.height.toDouble();
    });
  }

  void _moveCursorToSelection() {
    // ── 1. Determine the grid's bounding rect (in local overlay px) ─────────
    final double gridLeft;
    final double gridTop;
    final double gridWidth;
    final double gridHeight;

    if (zoneMode && _selectedZone != null) {
      // Zone mode: the grid is inset by the label bars inside the zone rect.
      final Rect zone = _zoneRect;
      gridLeft = zone.left;
      gridTop = zone.top;
      gridWidth = zone.width;
      gridHeight = zone.height;
    } else {
      // Classic mode: the grid covers the full screen (label bars are floating
      // widgets that don't inset the painter).
      gridLeft = 0;
      gridTop = 0;
      gridWidth = screenWidth;
      gridHeight = screenHeight;
    }

    final double cellW = gridWidth / cols.length;
    final double cellH = gridHeight / rows.length;

    // ── 2. Compute the target local-overlay position ─────────────────────────
    double localX;
    double localY;

    if (selectedCol != null && selectedRow != null) {
      // Both axes known → snap to cell centre.
      localX = gridLeft + (selectedCol! + 0.5) * cellW;
      localY = gridTop + (selectedRow! + 0.5) * cellH;
    } else if (selectedCol != null) {
      // Only column known → centre horizontally on that column, keep current Y.
      localX = gridLeft + (selectedCol! + 0.5) * cellW;
      // Read the current cursor Y and convert to local coords.
      final Pointer<POINT> pt = calloc<POINT>();
      GetCursorPos(pt);
      localY = (pt.ref.y - monitorData.y).toDouble().clamp(0, screenHeight - 1);
      calloc.free(pt);
    } else if (selectedRow != null) {
      // Only row known → centre vertically on that row, keep current X.
      final Pointer<POINT> pt = calloc<POINT>();
      GetCursorPos(pt);
      localX = (pt.ref.x - monitorData.x).toDouble().clamp(0, screenWidth - 1);
      calloc.free(pt);
      localY = gridTop + (selectedRow! + 0.5) * cellH;
    } else {
      return; // nothing selected, nothing to do
    }

    // ── 3. Convert local overlay coords → absolute physical screen coords ────
    final int absX = (monitorData.x + localX).round();
    final int absY = (monitorData.y + localY).round();

    SetCursorPos(absX, absY);
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: <Widget>[
            zoneMode ? _buildZoneBody() : _buildClassicBody(),
            if (showInfoModal) _buildInfoModal(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoModal() {
    final QuickClickConfig config = userSettings.quickClickConfig;
    final String hKeys = config.horizontalKeys.toUpperCase();
    final String vKeys = config.verticalKeys.toUpperCase();
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface.withAlpha(240),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.onSurface.withAlpha(20)),
          boxShadow: <BoxShadow>[
            BoxShadow(color: Colors.black.withAlpha(100), blurRadius: 20, spreadRadius: 5),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  "QuickClick Hotkeys",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.onSurface),
                )
              ],
            ),
            const Divider(height: 24),
            _infoRow("Select Column", "Press [$hKeys]"),
            _infoRow("Select Row", "Press [$vKeys]"),
            _infoRow("Left Click", WinKeys.vk(config.leftClickKey)),
            _infoRow("Right Click", WinKeys.vk(config.rightClickKey)),
            _infoRow("Drag", WinKeys.vk(config.dragKey)),
            _infoRow("Scroll Up/Down", "${WinKeys.vk(config.scrollUpKey)} / ${WinKeys.vk(config.scrollDownKey)}"),
            _infoRow("Scroll Left/Right", "${WinKeys.vk(config.scrollLeftKey)} / ${WinKeys.vk(config.scrollRightKey)}"),
            const Divider(height: 24),
            _infoRow("Nudge Mouse", "Arrow Keys"),
            _infoRow(
              "Nudge Mouse Extra:",
              config.extraArrowBindings.entries
                  .map((MapEntry<String, List<int>> e) => "${e.key}: ${WinKeys.vk(e.value[0])}")
                  .join(", "),
            ),
            _infoRow("Toggle Overlay", WinKeys.vk(config.toggleOverlayKey)),
            _infoRow("Toggle Zone Mode", WinKeys.vk(config.zoneModeKey)),
            _infoRow("Next Monitor", WinKeys.vk(config.nextMonitorKey)),
            _infoRow("Prev Monitor", WinKeys.vk(config.prevMonitorKey)),
            _infoRow("Close", "Escape"),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value.replaceAll('VK_', ''),
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ── classic full-screen grid body ───────────────────────────────────────────

  Widget _buildClassicBody() {
    return Stack(
      children: <Widget>[
        if (overlayVisible) ...<Widget>[
          Container(color: Colors.black.withValues(alpha: 0.01)),
          CustomPaint(
            size: Size.infinite,
            painter: GridPainter(
              rows: rows,
              cols: cols,
              selectedRow: selectedRow,
              selectedCol: selectedCol,
              topOffset: 0,
              leftOffset: 0,
            ),
          ),
          _buildLabels(),
          Positioned(
            top: 12,
            right: 12,
            child: _CoordChip(label: _currentCoordinate()),
          ),
        ] else
          Positioned(
            top: 0,
            left: 0,
            child: SizedBox(
              width: 30,
              height: 30,
              child: CustomPaint(
                painter: RightTrianglePainter(color: userSettings.themeColors.accentColor),
              ),
            ),
          ),
        if (selecting == 2) _buildRowHint(selectedCol!),
        if (selecting == 1) _buildColHint(selectedRow!),
        if (_isDragging) _buildDragIndicator(),
      ],
    );
  }

  // ── zone mode body ──────────────────────────────────────────────────────────

  Widget _buildZoneBody() {
    if (_selectedZone == null) {
      return _buildZonePicker();
    }
    return _buildZonedGrid();
  }

  // Phase 1 – picker: 4 quadrants with a letter at the center seam.
  Widget _buildZonePicker() {
    final Color accent = userSettings.themeColors.accentColor;
    final double hw = screenWidth / 2;
    final double hh = screenHeight / 2;

    // Zone descriptors: index, letter, left, top.
    final List<(int, String, double, double)> zones = <(int, String, double, double)>[
      (0, _zoneLabels[0], 0, 0),
      (1, _zoneLabels[1], hw, 0),
      (2, _zoneLabels[2], 0, hh),
      (3, _zoneLabels[3], hw, hh),
    ];

    return Stack(
      children: <Widget>[
        // Near-transparent background keeps the window hittable.
        Container(color: Colors.black.withValues(alpha: 0.01)),

        // Quadrant divider lines.
        CustomPaint(
          size: Size.infinite,
          painter: _QuadrantDividerPainter(accent: accent),
        ),

        // Quadrant overlays.
        for (final (int idx, String letter, double left, double top) in zones)
          Positioned(
            left: left,
            top: top,
            width: hw,
            height: hh,
            child: _ZoneQuadrant(
              letter: letter,
              accent: accent,
              onTap: () => setState(() => _selectedZone = idx),
            ),
          ),

        // Small ESC hint.
        const Positioned(
          top: 12,
          right: 12,
          child: _CoordChip(label: 'Zone?'),
        ),
      ],
    );
  }

  // Phase 2 – full grid drawn inside the selected zone quadrant.
  // ALL rows and cols are shown — the zone only narrows the screen area,
  // giving the user finer precision within that quadrant.
  Widget _buildZonedGrid() {
    final Rect zone = _zoneRect;
    final Color accent = userSettings.themeColors.accentColor;
    final Color text = userSettings.themeColors.textColor;

    return Stack(
      children: <Widget>[
        Container(color: Colors.black.withValues(alpha: 0.01)),

        // Dim the rest of the screen outside the zone.
        CustomPaint(
          size: Size.infinite,
          painter: _ZoneDimPainter(zoneRect: zone, accent: accent),
        ),

        // Full grid painter, clipped and positioned inside the zone rect.
        Positioned(
          left: zone.left,
          top: zone.top,
          width: zone.width,
          height: zone.height,
          child: ClipRect(
            child: CustomPaint(
              size: Size(zone.width, zone.height),
              painter: GridPainter(
                rows: rows,
                cols: cols,
                selectedRow: selectedRow,
                selectedCol: selectedCol,
                topOffset: 0,
                leftOffset: 0,
              ),
            ),
          ),
        ),

        // ── col labels bar (top of zone) ────────────────────────────
        Positioned(
          left: zone.left,
          top: zone.top,
          width: zone.width,
          height: _kLabelBarSize,
          child: Row(
            children: List<Widget>.generate(cols.length, (int i) {
              final bool active = selectedCol == i;
              return Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      color: active ? accent : text,
                      fontSize: active ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: active ? 0.7 : 0.35),
                          blurRadius: active ? 14 : 6,
                        ),
                      ],
                    ),
                    child: Text(cols[i]),
                  ),
                ),
              );
            }),
          ),
        ),

        // ── row labels bar (left of zone) ────────────────────────────
        Positioned(
          left: zone.left,
          top: zone.top,
          width: _kLabelBarSize,
          height: zone.height,
          child: Column(
            children: List<Widget>.generate(rows.length, (int i) {
              final bool active = selectedRow == i;
              return Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      color: active ? accent : text,
                      fontSize: active ? 22 : 18,
                      fontWeight: FontWeight.bold,
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: active ? 0.7 : 0.35),
                          blurRadius: active ? 14 : 6,
                        ),
                      ],
                    ),
                    child: Text(rows[i]),
                  ),
                ),
              );
            }),
          ),
        ),

        // ── corner cap (top-left of zone) ────────────────────────────
        Positioned(
          left: zone.left,
          top: zone.top,
          width: _kLabelBarSize,
          height: _kLabelBarSize,
          child: Container(
            color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
            alignment: Alignment.center,
            child: Text(
              'Z${_selectedZone! + 1}',
              style: TextStyle(
                color: accent.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // Coordinate chip — same _currentCoordinate() used everywhere.
        Positioned(
          top: 12,
          right: 12,
          child: _CoordChip(label: _currentCoordinate()),
        ),

        // Contextual row hints inside zone (col selected, waiting for row).
        if (selecting == 2 && selectedCol != null) _buildZoneRowHint(zone, selectedCol!),

        // Contextual col hints inside zone (row selected, waiting for col).
        if (selecting == 1 && selectedRow != null) _buildZoneColHint(zone, selectedRow!),

        if (_isDragging) _buildDragIndicator(),
      ],
    );
  }

  Widget _buildZoneRowHint(Rect zone, int colIndex) {
    final double cellW = (zone.width - _kLabelBarSize) / cols.length;
    final double cellH = (zone.height - _kLabelBarSize) / rows.length;
    final double colRight = zone.left + _kLabelBarSize + (colIndex + 1) * cellW;
    const double panelWidth = 36.0;
    final double left = (colRight + 4).clamp(0, screenWidth - panelWidth);

    return Positioned(
      left: left,
      top: zone.top + _kLabelBarSize,
      width: panelWidth,
      height: zone.height - _kLabelBarSize,
      child: Column(
        children: List<Widget>.generate(rows.length, (int i) {
          return SizedBox(
            height: cellH,
            child: Center(child: _HintKey(label: rows[i])),
          );
        }),
      ),
    );
  }

  Widget _buildZoneColHint(Rect zone, int rowIndex) {
    final double cellW = (zone.width - _kLabelBarSize) / cols.length;
    final double cellH = (zone.height - _kLabelBarSize) / rows.length;
    final double rowBottom = zone.top + _kLabelBarSize + (rowIndex + 1) * cellH;
    const double panelHeight = 36.0;
    final double top = (rowBottom + 4).clamp(0, screenHeight - panelHeight);

    return Positioned(
      left: zone.left + _kLabelBarSize,
      top: top,
      width: zone.width - _kLabelBarSize,
      height: panelHeight,
      child: Row(
        children: List<Widget>.generate(cols.length, (int i) {
          return SizedBox(
            width: cellW,
            child: Center(child: _HintKey(label: cols[i])),
          );
        }),
      ),
    );
  }

  // ── coordinate label ────────────────────────────────────────────────────────

  String _currentCoordinate() {
    if (selectedRow == null && selectedCol == null) return '—';
    final String r = selectedRow != null ? rows[selectedRow!] : '_';
    final String c = selectedCol != null ? cols[selectedCol!] : '_';
    return '$r$c';
  }

  Widget _buildLabels() {
    final Color accent = userSettings.themeColors.accentColor;
    final Color text = userSettings.themeColors.textColor;

    return Stack(
      children: <Widget>[
        // ── top column labels overlay ─────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _kLabelBarSize,
          child: Row(
            children: List<Widget>.generate(cols.length, (int i) {
              final bool active = selectedCol == i;

              return Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF0D0F14).withValues(alpha: 0.72),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      color: active ? accent : text,
                      fontSize: active ? 26 : 22,
                      fontWeight: FontWeight.bold,
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: active ? 0.7 : 0.35),
                          blurRadius: active ? 16 : 8,
                        ),
                      ],
                    ),
                    child: Text(cols[i]),
                  ),
                ),
              );
            }),
          ),
        ),

        // ── left row labels overlay ───────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          bottom: 0,
          width: _kLabelBarSize,
          child: Column(
            children: List<Widget>.generate(rows.length, (int i) {
              final bool active = selectedRow == i;

              return Expanded(
                child: Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF0D0F14).withValues(alpha: 0.72),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 120),
                    style: TextStyle(
                      color: active ? accent : text,
                      fontSize: active ? 26 : 22,
                      fontWeight: FontWeight.bold,
                      shadows: <Shadow>[
                        Shadow(
                          color: accent.withValues(alpha: active ? 0.7 : 0.35),
                          blurRadius: active ? 16 : 8,
                        ),
                      ],
                    ),
                    child: Text(rows[i]),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── contextual hint: row keys floated inside the active column ───────────────
  //
  // When the user has pressed a column key we render the full list of row keys
  // vertically centred inside that column stripe, right next to the left edge
  // of the col (so it doesn't occlude the adjacent column).

  Widget _buildRowHint(int colIndex) {
    const double gridLeft = 0;
    final double gridWidth = screenWidth - 0;
    final double gridHeight = screenHeight - 0;
    final double cellWidth = gridWidth / cols.length;
    final double cellHeight = gridHeight / rows.length;

    // Position the hint panel flush with the right edge of the active column.
    final double colRight = gridLeft + (colIndex + 1) * cellWidth;
    // Clamp so the panel never goes off-screen on the right.
    const double panelWidth = 38.0;
    final double left = (colRight + 4).clamp(0, screenWidth - panelWidth);

    return Positioned(
      left: left,
      top: 0,
      width: panelWidth,
      height: gridHeight,
      child: Column(
        children: List<Widget>.generate(rows.length, (int i) {
          return SizedBox(
            height: cellHeight,
            child: Center(
              child: _HintKey(label: rows[i]),
            ),
          );
        }),
      ),
    );
  }

  // ── contextual hint: col keys floated inside the active row ──────────────────

  Widget _buildColHint(int rowIndex) {
    const double gridLeft = 0;
    final double gridWidth = screenWidth - 0;
    final double gridHeight = screenHeight - 0;
    final double cellWidth = gridWidth / cols.length;
    final double cellHeight = gridHeight / rows.length;

    // Position the hint panel just below the active row.
    final double rowBottom = 0 + (rowIndex + 1) * cellHeight;
    const double panelHeight = 38.0;
    final double top = (rowBottom + 4).clamp(0, screenHeight - panelHeight);

    return Positioned(
      left: gridLeft,
      top: top,
      width: gridWidth,
      height: panelHeight,
      child: Row(
        children: List<Widget>.generate(cols.length, (int i) {
          return SizedBox(
            width: cellWidth,
            child: Center(
              child: _HintKey(label: cols[i]),
            ),
          );
        }),
      ),
    );
  }

  // ── drag indicator ──────────────────────────────────────────────────────────

  Widget _buildDragIndicator() {
    const double size = 48.0;
    const double offset = 16.0; // distance from cursor tip

    return Positioned(
      left: _dragCursorPos.dx + offset,
      top: _dragCursorPos.dy - size / 2,
      child: const _DragBadge(),
    );
  }

  // ── keyboard handler ────────────────────────────────────────────────────────
}

class RightTrianglePainter extends CustomPainter {
  final Color color;

  RightTrianglePainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    // Define the gradient from the top boundary to the bottom boundary
    final Rect rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final LinearGradient gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: <Color>[
        color,
        color.withValues(alpha: 0),
        color.withValues(alpha: 0),
      ],
    );

    final Paint paint = Paint()
      ..shader = gradient.createShader(rect) // Apply the gradient shader
      ..style = PaintingStyle.fill;

    final Path path = Path();

    // Draw the top-left right-angle triangle
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
// ─── small reusable widgets ───────────────────────────────────────────────────

/// The coordinate chip shown in the top-right corner.
class _CoordChip extends StatelessWidget {
  const _CoordChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: userSettings.themeColors.accentColor.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: userSettings.themeColors.accentColor,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}

/// A single hint key pill shown in the contextual overlays.
class _HintKey extends StatelessWidget {
  const _HintKey({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.3),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: accent.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

/// The animated badge that follows the cursor while a drag is in progress.
class _DragBadge extends StatelessWidget {
  const _DragBadge();

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0F14).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Simple animated "grab" icon made from two rectangles.
          _DragIcon(color: accent),
        ],
      ),
    );
  }
}

/// Minimal grab-hand icon drawn with Canvas so there's no asset dependency.
class _DragIcon extends StatelessWidget {
  const _DragIcon({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(14, 16),
      painter: _GrabIconPainter(color: color),
    );
  }
}

class _GrabIconPainter extends CustomPainter {
  const _GrabIconPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Three horizontal lines suggesting a grab/move handle.
    for (int i = 0; i < 3; i++) {
      final double y = size.height * (0.25 + i * 0.25);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GrabIconPainter old) => old.color != color;
}

// ─── zone mode helpers ────────────────────────────────────────────────────────

/// Draws the two divider lines (cross) splitting the screen into 4 quadrants.
class _QuadrantDividerPainter extends CustomPainter {
  const _QuadrantDividerPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = 1.5;
    // Vertical centre line.
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), p);
    // Horizontal centre line.
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), p);
  }

  @override
  bool shouldRepaint(covariant _QuadrantDividerPainter old) => old.accent != accent;
}

/// Dims everything outside [zoneRect] and draws a bright border around it.
class _ZoneDimPainter extends CustomPainter {
  const _ZoneDimPainter({required this.zoneRect, required this.accent});
  final Rect zoneRect;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.2);

    // Draw dim overlay as four rectangles surrounding the zone rect.
    // final Rect full = Rect.fromLTWH(0, 0, size.width, size.height);
    // Top.
    if (zoneRect.top > 0) canvas.drawRect(Rect.fromLTRB(0, 0, size.width, zoneRect.top), dimPaint);
    // Bottom.
    if (zoneRect.bottom < size.height) {
      canvas.drawRect(Rect.fromLTRB(0, zoneRect.bottom, size.width, size.height), dimPaint);
    }
    // Left (between top and bottom of zone).
    if (zoneRect.left > 0) canvas.drawRect(Rect.fromLTRB(0, zoneRect.top, zoneRect.left, zoneRect.bottom), dimPaint);
    // Right.
    if (zoneRect.right < size.width) {
      canvas.drawRect(Rect.fromLTRB(zoneRect.right, zoneRect.top, size.width, zoneRect.bottom), dimPaint);
    }

    // Bright border around the active zone.
    canvas.drawRect(
      zoneRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accent.withValues(alpha: 0.55),
    );
  }

  @override
  bool shouldRepaint(covariant _ZoneDimPainter old) => old.zoneRect != zoneRect || old.accent != accent;
}

/// A single quadrant tile shown in the zone picker phase.
class _ZoneQuadrant extends StatelessWidget {
  const _ZoneQuadrant({required this.letter, required this.accent, required this.onTap});
  final String letter;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.01), // hittable but near-transparent
          border: Border.all(color: accent.withValues(alpha: 0.08), width: 1),
        ),
        child: Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0D0F14).withValues(alpha: 0.78),
              border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
              boxShadow: <BoxShadow>[
                BoxShadow(color: accent.withValues(alpha: 0.20), blurRadius: 24),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              letter,
              style: TextStyle(
                color: accent,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                shadows: <Shadow>[
                  Shadow(color: accent.withValues(alpha: 0.6), blurRadius: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── grid painter ─────────────────────────────────────────────────────────────

class GridPainter extends CustomPainter {
  const GridPainter({
    required this.rows,
    required this.cols,
    required this.selectedRow,
    required this.selectedCol,
    required this.topOffset,
    required this.leftOffset,
  });

  final List<String> rows;
  final List<String> cols;
  final int? selectedRow;
  final int? selectedCol;

  /// Pixels from the top where the grid starts (= height of the col-label bar).
  final double topOffset;

  /// Pixels from the left where the grid starts (= width of the row-label bar).
  final double leftOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final double gridW = size.width - leftOffset;
    final double gridH = size.height - topOffset;
    final double cellW = gridW / cols.length;
    final double cellH = gridH / rows.length;

    // ── active cell highlight ────────────────────────────────────────────────
    if (selectedRow != null && selectedCol != null) {
      final double x = leftOffset + selectedCol! * cellW;
      final double y = topOffset + selectedRow! * cellH;
      final Rect rect = Rect.fromLTWH(x, y, cellW, cellH);

      canvas.drawRect(
        rect,
        Paint()..color = userSettings.themeColors.accentColor.withValues(alpha: 0.08),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = userSettings.themeColors.accentColor.withValues(alpha: 0.45),
      );
    }

    // ── active col stripe (dim) ──────────────────────────────────────────────
    if (selectedCol != null && selectedRow == null) {
      final double x = leftOffset + selectedCol! * cellW;
      canvas.drawRect(
        Rect.fromLTWH(x, topOffset, cellW, gridH),
        Paint()..color = userSettings.themeColors.accentColor.withValues(alpha: 0.05),
      );
    }

    // ── active row stripe (dim) ──────────────────────────────────────────────
    if (selectedRow != null && selectedCol == null) {
      final double y = topOffset + selectedRow! * cellH;
      canvas.drawRect(
        Rect.fromLTWH(leftOffset, y, gridW, cellH),
        Paint()..color = userSettings.themeColors.accentColor.withValues(alpha: 0.05),
      );
    }

    // ── grid lines ───────────────────────────────────────────────────────────
    final Paint linePaint = Paint()
      ..color = userSettings.themeColors.accentColor.withValues(alpha: 0.10)
      ..strokeWidth = 1;

    // Vertical lines (cols.length + 1 lines, starting at leftOffset).
    for (int i = 0; i <= cols.length; i++) {
      final double x = leftOffset + i * cellW;
      canvas.drawLine(Offset(x, topOffset), Offset(x, size.height), linePaint);
    }

    // Horizontal lines (rows.length + 1 lines, starting at topOffset).
    for (int i = 0; i <= rows.length; i++) {
      final double y = topOffset + i * cellH;
      canvas.drawLine(Offset(leftOffset, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter old) =>
      old.selectedRow != selectedRow || old.selectedCol != selectedCol || old.rows != rows || old.cols != cols;
}

// ─── DPI awareness ────────────────────────────────────────────────────────────

void _enableDpiAwareness() {
  try {
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  } catch (_) {}
}
