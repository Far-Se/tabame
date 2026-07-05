// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' show min, max;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/classes/quick_snap_apply.dart';
import '../models/classes/saved_maps.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';

class ViewsScreen extends StatefulWidget {
  final void Function(List<Space> spaces)? onPicked;
  const ViewsScreen({super.key, this.onPicked});
  @override
  ViewsScreenState createState() => ViewsScreenState();
}

Future<bool> interfaceWindowSetup() async {
  Monitor.fetchMonitors();
  return true;
}

class Space {
  bool selected;
  bool hovered;
  int gridX;
  int gridY;
  double x;
  double y;
  Space({
    this.selected = false,
    this.hovered = false,
    required this.gridX,
    required this.gridY,
    required this.x,
    required this.y,
  });

  @override
  String toString() {
    return 'Space(enabled: $selected, hovered: $hovered, gridX: $gridX, gridY: $gridY, x: $x, y: $y)';
  }

  Space copyWith({
    bool? selected,
    bool? hovered,
    int? gridX,
    int? gridY,
    double? x,
    double? y,
  }) {
    return Space(
      selected: selected ?? this.selected,
      hovered: hovered ?? this.hovered,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      x: x ?? this.x,
      y: y ?? this.y,
    );
  }
}

class ViewsScreenState extends State<ViewsScreen> with TabameListener {
  final Future<bool> interfaceWindow = interfaceWindowSetup();
  final ViewsSettings settings = ViewsSettings();
  Timer? timer;
  // BUG FIX #4: Initialize to actual cursor monitor instead of -1,
  // avoiding a spurious monitor-change resize on the very first checker() call.
  int currentMonitor = 0;
  bool processing = false;

  Square monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  final List<Space> matrix = <Space>[];
  ViewsAction action = ViewsAction.open;
  int activeWindowHwnd = 0;

  int _activeIndex = -1;
  bool _showTopBar = false;
  int _hoveredZoneIndex = -1;

  final GlobalKey _gridKey = GlobalKey();
  // BUG FIX #3: Use a map keyed by preset id so stale keys aren't reused
  // when the preset list changes between build cycles.
  final Map<String, GlobalKey> _presetKeyMap = <String, GlobalKey>{};

  int lastX = 0;
  int lastY = 0;
  bool selecting = false;
  bool visible = false;
  Space spaceHovered = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  Space spaceStarted = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  Space spaceEnded = Space(gridX: 0, gridY: 0, x: 0, y: 0);
  final Space nowPos = Space(gridX: 0, gridY: 0, x: 0, y: 0);

  late Color borderColor;

  @override
  void initState() {
    super.initState();
    NativeHooks.addListener(this);
    // BUG FIX #4 cont.: fetch the real monitor at startup.
    final int monitor = Monitor.getCursorMonitor();
    currentMonitor = monitor;
    monitorData = Monitor.monitorSizes[monitor]!;
    setMatrix();
    settings.load().then((_) {
      setMatrix();
      if (user.lastQuickSnapZoneId.isNotEmpty) {
        final int index = Boxes.quickGrids.indexWhere(
          (QuickGrid p) => p.id == user.lastQuickSnapZoneId,
        );
        if (index != -1) {
          _activeIndex = index;
        }
      }
      if (_activeIndex == -1 && !user.quickSnapGrid && Boxes.quickGrids.isNotEmpty) {
        _activeIndex = 0;
      }
      if (mounted) setState(() {});
    });
    visible = true;
    startTimer();
    borderColor = Color.fromRGBO(
      255 - settings.bgColor.red8bit,
      255 - settings.bgColor.green8bit,
      255 - settings.bgColor.blue8bit,
      0.2,
    );
  }

  void setMatrix() {
    matrix.clear();
    final double width = monitorData.width / settings.scaleW;
    final double height = monitorData.height / settings.scaleH;
    for (int h = 0; h < settings.scaleH; h++) {
      for (int w = 0; w < settings.scaleW; w++) {
        matrix.add(Space(x: w * width, y: h * height, gridX: w, gridY: h));
      }
    }
  }

  void startTimer() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 50), (Timer t) {
      if (!visible) {
        t.cancel();
      } else {
        checker();
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    NativeHooks.removeListener(this);
    super.dispose();
  }

  void checker() async {
    if (!visible) return;
    if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) {
      hideViews();
      return;
    }
    if (processing) return;
    processing = true;

    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    int mX = lpPoint.ref.x;
    int mY = lpPoint.ref.y;
    free(lpPoint);

    if (monitor != currentMonitor) {
      currentMonitor = monitor;
      monitorData = Monitor.monitorSizes[monitor]!;
      await WindowManager.instance.setPosition(
        Offset(monitorData.x.toDouble(), monitorData.y.toDouble()),
      );
      await WindowManager.instance.setSize(
        Size(monitorData.width.toDouble(), monitorData.height.toDouble()),
      );
    }

    if ((mX != lastX || mY != lastY) &&
        monitorData.width != 0 &&
        mX.isBetweenEqual(monitorData.x, monitorData.length) &&
        mY.isBetweenEqual(monitorData.y, monitorData.wide)) {
      lastX = mX;
      lastY = mY;
      mX = mX - monitorData.x;
      mY = mY - monitorData.y;

      final bool mouseAtTop = mY < 90;
      if (mouseAtTop != _showTopBar) {
        setState(() => _showTopBar = mouseAtTop);
      }

      if (_showTopBar) {
        int newHoveredIndex = -2;
        if (_isMouseOverKey(_gridKey, mX, mY)) {
          newHoveredIndex = -1;
        } else {
          for (int i = 0; i < Boxes.quickGrids.length; i++) {
            // BUG FIX #3: look up key by preset id, not by positional list index.
            final GlobalKey? key = _presetKeyMap[Boxes.quickGrids[i].id];
            if (key != null && _isMouseOverKey(key, mX, mY)) {
              newHoveredIndex = i;
              break;
            }
          }
        }
        if (newHoveredIndex != -2 && newHoveredIndex != _activeIndex) {
          setState(() => _activeIndex = newHoveredIndex);
          user.lastQuickSnapZoneId = newHoveredIndex >= 0 ? Boxes.quickGrids[newHoveredIndex].id : '';
          Boxes.updateSettings('lastQuickSnapZoneId', user.lastQuickSnapZoneId);
        }
      }

      if (_activeIndex == -1) {
        final double width = monitorData.width / settings.scaleW;
        final double height = monitorData.height / settings.scaleH;
        Space? newHovered;
        for (final Space space in matrix) {
          if (mX.isBetweenEqual(space.x, space.x + width) && mY.isBetweenEqual(space.y, space.y + height)) {
            newHovered = space;
            break;
          }
        }
        if (newHovered != null && spaceHovered != newHovered) {
          for (final Space e in matrix) {
            e.hovered = false;
            e.selected = false;
          }
          newHovered.hovered = true;
          spaceHovered = newHovered;
          if (selecting) {
            final int minX = min(spaceStarted.gridX, spaceHovered.gridX);
            final int maxX = max(spaceStarted.gridX, spaceHovered.gridX);
            final int minY = min(spaceStarted.gridY, spaceHovered.gridY);
            final int maxY = max(spaceStarted.gridY, spaceHovered.gridY);
            for (final Space e in matrix) {
              e.selected = e.gridX.isBetweenEqual(minX, maxX) && e.gridY.isBetweenEqual(minY, maxY);
            }
          }
          if (mounted) setState(() {});
        }
      } else {
        final QuickGrid preset = Boxes.quickGrids[_activeIndex];
        int newHoveredZone = -1;
        final double mw = monitorData.width.toDouble();
        final double mh = monitorData.height.toDouble();
        for (int i = 0; i < preset.zones.length; i++) {
          final QuickGridRect z = preset.zones[i];
          if (mX >= z.left * mw && mX <= z.right * mw && mY >= z.top * mh && mY <= z.bottom * mh) {
            newHoveredZone = i;
            break;
          }
        }
        if (newHoveredZone != _hoveredZoneIndex) {
          setState(() => _hoveredZoneIndex = newHoveredZone);
        }
      }
    }

    processing = false;
  }

  bool fixedWindowsBug = false;

  @override
  void onViewsEvent(ViewsAction action, int hWnd) async {
    switch (action) {
      case ViewsAction.open:
        _handleOpen();
      case ViewsAction.selecting:
        _handleSelecting();
      case ViewsAction.selected:
        _handleSelected();
      case ViewsAction.moveStart:
        _handleMoveStart(hWnd);
      case ViewsAction.moveEnd:
        _handleMoveEnd(hWnd);
      case ViewsAction.switchUp:
      case ViewsAction.switchDown:
        _handleScale(action);
    }
    if (mounted) setState(() {});
  }

  void _handleOpen() {
    visible = true;
    final int monitor = Monitor.getCursorMonitor();
    currentMonitor = monitor;
    monitorData = Monitor.monitorSizes[monitor]!;
    startTimer();
  }

  void _handleSelecting() {
    selecting = true;
    spaceStarted = spaceHovered;
  }

  void _handleSelected() {
    spaceEnded = spaceHovered;
    selecting = false;
  }

  void _handleMoveStart(int windowHwnd) {
    // BUG FIX #5: was -9998 (four digits) — must be -99998 to fully offscreen.
    if (!fixedWindowsBug) WindowManager.instance.setPosition(const Offset(-99998, -99998));
    fixedWindowsBug = true;
    activeWindowHwnd = windowHwnd;
    final Pointer<RECT> lpRect = calloc<RECT>();
    GetWindowRect(activeWindowHwnd, lpRect);
    nowPos
      ..gridX = lpRect.ref.right - lpRect.ref.left
      ..gridY = lpRect.ref.bottom - lpRect.ref.top
      ..x = lpRect.ref.left.toDouble()
      ..y = lpRect.ref.top.toDouble();
    free(lpRect);
  }

  void _handleMoveEnd(int hWnd) {
    if (!visible) return;
    if ((GetAsyncKeyState(VK_ESCAPE) & 0x8000) != 0) {
      hideViews();
      return;
    }

    if (_activeIndex != -1) {
      final Square monitor = Monitor.monitorSizes[Win32.getCursorMonitor()]!;
      final double rx = (lastX - monitor.x).toDouble();
      final double ry = (lastY - monitor.y).toDouble();
      final QuickGrid preset = Boxes.quickGrids[_activeIndex];
      final double mw = monitor.width.toDouble();
      final double mh = monitor.height.toDouble();
      if (!Globals.snappedWindowOriginalSizes.containsKey(hWnd)) {
        Globals.snappedWindowOriginalSizes[hWnd] = <int>[
          Win32.getSize(hwnd: hWnd).width,
          Win32.getSize(hwnd: hWnd).height,
        ];
      }
      for (final QuickGridRect zone in preset.zones) {
        if (rx >= zone.left * mw && rx <= zone.right * mw && ry >= zone.top * mh && ry <= zone.bottom * mh) {
          _applyQuickSnapZone(hWnd, zone, preset);
          return;
        }
      }
      visible = false;
      hideViews();
      return;
    }

    timer?.cancel();
    spaceEnded = spaceHovered;
    selecting = false;

    final List<Space> spaces = matrix.where((Space e) => e.selected).toList();
    if (spaces.length < 2) {
      visible = false;
      hideViews();
      return;
    }

    if (!Globals.snappedWindowOriginalSizes.containsKey(hWnd)) {
      Globals.snappedWindowOriginalSizes[hWnd] = <int>[
        Win32.getSize(hwnd: hWnd).width,
        Win32.getSize(hwnd: hWnd).height,
      ];
    }

    // BUG FIX #1: compute true min/max instead of relying on .first/.last order,
    // which can be inverted when dragging bottom-right → top-left.
    final double minSX = spaces.map((Space s) => s.x).reduce(min);
    final double minSY = spaces.map((Space s) => s.y).reduce(min);
    final double maxSX = spaces.map((Space s) => s.x).reduce(max);
    final double maxSY = spaces.map((Space s) => s.y).reduce(max);

    final double cellW = monitorData.width / settings.scaleW;
    final double cellH = monitorData.height / settings.scaleH;
    final double windowWidth = maxSX - minSX + cellW;
    final double windowHeight = maxSY - minSY + cellH;

    const int diffX = 7;
    const int diffY = 2;
    final Square monitor = Monitor.monitorSizes[Win32.getCursorMonitor()]!;
    final int x = monitor.x + minSX.floor();
    final int y = monitor.y + minSY.floor();
    SetWindowPos(
      hWnd,
      NULL,
      x - diffX,
      y - diffY,
      windowWidth.ceil() + (diffX * 2),
      windowHeight.ceil() + (diffY * 2),
      SWP_NOZORDER,
    );

    for (final Space e in matrix) {
      e.selected = false;
      e.hovered = false;
    }
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => hideViews());
    visible = false;
    widget.onPicked?.call(spaces);
  }

  void _handleScale(ViewsAction action) {
    settings.scaleH = action == ViewsAction.switchDown
        ? (settings.scaleH - settings.scrollStepH)
        : (settings.scaleH + settings.scrollStepH);
    settings.scaleW = action == ViewsAction.switchDown
        ? (settings.scaleW - settings.scrollStepW)
        : (settings.scaleW + settings.scrollStepW);
    settings.scaleH = settings.scaleH.clamp(settings.minH, settings.maxH);
    settings.scaleW = settings.scaleW.clamp(settings.minW, settings.maxW);
    settings.save();
    setMatrix();
    lastX = 0;
    lastY = 0;
    selecting = false;
    spaceHovered = Space(gridX: 0, gridY: 0, x: 0, y: 0);
    spaceStarted = Space(gridX: 0, gridY: 0, x: 0, y: 0);
    spaceEnded = Space(gridX: 0, gridY: 0, x: 0, y: 0);
    checker();
    if (mounted) setState(() {});
  }

  bool _isMouseOverKey(GlobalKey key, int mX, int mY) {
    final RenderObject? renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return false;
    final Offset pos = renderObject.localToGlobal(Offset.zero);
    final Size size = renderObject.size;
    return mX >= pos.dx && mX <= pos.dx + size.width && mY >= pos.dy && mY <= pos.dy + size.height;
  }

  void hideViews() {
    // BUG FIX #6: reset selecting so a ghost selection isn't active on reopen.
    selecting = false;
    Win32.setPosition(const Offset(-99999, -99999));
    QuickMenuFunctions.hideQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final List<QuickGrid> presets = Boxes.quickGrids;

    // BUG FIX #3: sync key map by id so renamed/reordered presets get fresh keys.
    final Set<String> currentIds = presets.map((QuickGrid p) => p.id).toSet();
    _presetKeyMap.removeWhere((String id, _) => !currentIds.contains(id));
    for (final QuickGrid p in presets) {
      _presetKeyMap.putIfAbsent(p.id, () => GlobalKey());
    }

    final bool showGrid = user.quickSnapGrid;
    final bool hasPresets = presets.isNotEmpty;
    final bool showTopBar = showGrid || hasPresets;

    return Scaffold(
      backgroundColor: settings.bgColor.withValues(alpha: 0.75),
      body: Stack(
        children: <Widget>[
          // Main content
          if (_activeIndex == -1) _buildGrid() else _buildQuickSnapLayout(presets[_activeIndex], accent),

          // ── Notch top bar ──────────────────────────────────────────────────
          if (showTopBar)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              // Slides up so only the rounded bottom edge peeks above the top.
              // When hidden: offset so the full notch height is off-screen.
              top: _showTopBar ? 0 : -72,
              left: 0,
              right: 0,
              child: Align(
                alignment: Alignment.topCenter,
                child: _NotchBar(
                  key: ValueKey<bool>(_showTopBar),
                  gridKey: _gridKey,
                  presetKeyMap: _presetKeyMap,
                  presets: presets,
                  activeIndex: _activeIndex,
                  accent: accent,
                  showGrid: showGrid,
                ),
              ),
            ),

          // Selection size badge (grid mode only)
          if (_activeIndex == -1 && selecting)
            Positioned(
              bottom: 20,
              right: 20,
              child: _SelectionBadge(
                cols: (spaceHovered.gridX - spaceStarted.gridX).abs() + 1,
                rows: (spaceHovered.gridY - spaceStarted.gridY).abs() + 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickSnapLayout(QuickGrid preset, Color accent) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size sz = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: <Widget>[
            for (int i = 0; i < preset.zones.length; i++)
              _buildQuickSnapZoneTile(preset.zones[i], i, sz, accent, isHovered: _hoveredZoneIndex == i),
          ],
        );
      },
    );
  }

  Widget _buildQuickSnapZoneTile(
    QuickGridRect r,
    int idx,
    Size sz,
    Color accent, {
    bool isHovered = false,
  }) {
    final double left = r.left * sz.width;
    final double top = r.top * sz.height;
    final double width = (r.right - r.left) * sz.width;
    final double height = (r.bottom - r.top) * sz.height;

    // BUG FIX #2: capture index at construction time to avoid stale _activeIndex
    // if state changes between render and tap.
    final int capturedIndex = _activeIndex;

    return Positioned(
      left: left + 4,
      top: top + 4,
      width: width - 8,
      height: height - 8,
      child: GestureDetector(
        onTap: () {
          if (capturedIndex < 0 || capturedIndex >= Boxes.quickGrids.length) return;
          _applyQuickSnapZone(
            activeWindowHwnd,
            r,
            Boxes.quickGrids[capturedIndex],
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: isHovered ? 0.09 : 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: accent.withValues(alpha: isHovered ? 0.55 : 0.18),
              width: isHovered ? 1.5 : 1,
            ),
            boxShadow: isHovered
                ? <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              '${idx + 1}',
              style: TextStyle(
                color: accent.withValues(alpha: isHovered ? 0.9 : 0.35),
                fontSize: 26,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _applyQuickSnapZone(int hWnd, QuickGridRect zone, QuickGrid preset) {
    if (!Globals.snappedWindowOriginalSizes.containsKey(hWnd)) {
      Globals.snappedWindowOriginalSizes[hWnd] = <int>[nowPos.gridX, nowPos.gridY];
    }
    QuickSnapApply.apply(hWnd, zone, preset.gap, currentMonitor);
    visible = false;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => hideViews());
  }

  Widget _buildGrid() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(settings.scaleH, (int colIndex) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List<Widget>.generate(settings.scaleW, (int rowIndex) {
            final int spaceIndex = matrix.indexWhere(
              (Space e) => e.gridX == rowIndex && e.gridY == colIndex,
            );
            if (spaceIndex == -1) return const SizedBox.shrink();
            final Space space = matrix[spaceIndex];

            Color color = Colors.transparent;
            if (space.selected) {
              color = borderColor.withValues(alpha: 0.5);
            } else if (space.hovered) {
              color = borderColor.withValues(alpha: 0.2);
            }

            return Expanded(
              child: Container(
                height: monitorData.height / settings.scaleH,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: borderColor, width: 0.2),
                ),
              ),
            );
          }),
        );
      }),
    );
  }
}

// ── Notch bar ────────────────────────────────────────────────────────────────

/// A pill-shaped notch that is flush with the top edge of the overlay,
/// with rounded corners only on the bottom.
class _NotchBar extends StatelessWidget {
  const _NotchBar({
    super.key,
    required this.gridKey,
    required this.presetKeyMap,
    required this.presets,
    required this.activeIndex,
    required this.accent,
    required this.showGrid,
  });

  final GlobalKey gridKey;
  final Map<String, GlobalKey> presetKeyMap;
  final List<QuickGrid> presets;
  final int activeIndex;
  final Color accent;
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      // Flat top, rounded bottom — true notch shape.
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          border: Border(
            left: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
            right: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.only(left: 10, right: 10, top: 0, bottom: 10), // <- this
        child: IntrinsicWidth(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (showGrid) ...<Widget>[
                _NotchTab(
                  tabKey: gridKey,
                  isActive: activeIndex == -1,
                  accent: accent,
                  label: 'Grid',
                  painter: _GridPainter(accent: accent),
                ),
                if (presets.isNotEmpty) _NotchDivider(accent: accent),
              ],
              for (int i = 0; i < presets.length; i++) ...<Widget>[
                _NotchTab(
                  tabKey: presetKeyMap[presets[i].id]!,
                  isActive: activeIndex == i,
                  accent: accent,
                  label: presets[i].name,
                  painter: _MiniPainter(preset: presets[i], accent: accent),
                ),
                if (i < presets.length - 1) _NotchDivider(accent: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotchTab extends StatelessWidget {
  const _NotchTab({
    required this.tabKey,
    required this.isActive,
    required this.accent,
    required this.label,
    required this.painter,
  });

  final GlobalKey tabKey;
  final bool isActive;
  final Color accent;
  final String label;
  final CustomPainter painter;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: tabKey,
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? accent.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isActive ? accent.withValues(alpha: 0.45) : accent.withValues(alpha: 0.01),
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 48,
            height: 28,
            child: CustomPaint(painter: painter),
          ),
          const SizedBox(height: 4),
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Invisible bold placeholder to reserve width and prevent layout jitter on hover
              Text(
                label,
                style: TextStyle(
                  color: Colors.transparent,
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: isActive ? 1.0 : 0.5),
                  fontSize: Design.baseFontSize,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NotchDivider extends StatelessWidget {
  const _NotchDivider({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: Colors.white.withValues(alpha: 0.10),
    );
  }
}

// ── Selection badge ───────────────────────────────────────────────────────────

class _SelectionBadge extends StatelessWidget {
  const _SelectionBadge({required this.cols, required this.rows});
  final int cols;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
      ),
      child: Text(
        '$cols × $rows',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ── Painters ─────────────────────────────────────────────────────────────────

class _MiniPainter extends CustomPainter {
  _MiniPainter({required this.preset, required this.accent});
  final QuickGrid preset;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = accent.withValues(alpha: 0.08),
    );
    final Paint fill = Paint()..color = accent.withValues(alpha: 0.28);
    final Paint border = Paint()
      ..color = accent.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    for (final QuickGridRect r in preset.zones) {
      final Rect rect = Rect.fromLTRB(
        r.left * size.width + 1,
        r.top * size.height + 1,
        r.right * size.width - 1,
        r.bottom * size.height - 1,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), border);
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => old.preset != preset;
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(4)),
      Paint()..color = accent.withValues(alpha: 0.08),
    );
    final Paint paint = Paint()
      ..color = accent.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(i * size.width / 4, 2), Offset(i * size.width / 4, size.height - 2), paint);
      canvas.drawLine(Offset(2, i * size.height / 4), Offset(size.width - 2, i * size.height / 4), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
