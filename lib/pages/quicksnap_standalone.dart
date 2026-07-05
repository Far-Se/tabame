// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/gestures/events.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/classes/boxes.dart';
import '../models/classes/quick_snap_apply.dart';
import '../models/classes/saved_maps.dart';
import '../models/screen_utils.dart';
import '../models/settings.dart';
import '../models/win32/imports.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../widgets/widgets/extracted_icon.dart';

Future<void> startQuickSnap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();
  await Boxes.registerBoxes(justLoad: true);
  checkThemeChange();

  final int vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final int vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  final WindowOptions windowOptions = WindowOptions(
    size: Size(vWidth.toDouble(), vHeight.toDouble()),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: 'Tabame QuickSnap',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    Win32Window.setHwnd(GetAncestor(GetActiveWindow(), 2));
  });

  // Standalone processes don't go through registerAll(), so the native "views"
  // hook that emits moveStart/moveEnd is off by default — enable it here or the
  // drag never registers (no live mouse-based zone highlight) and the drop never
  // snaps/resizes the window. Right-click-to-trigger is turned off: this view is
  // driven purely by plain title-bar window drags.
  await enableViews(true, rightClickToTrigger: false);
  await NativeHooks.hook();
  runApp(const QuickSnapStandAlone());
}

class QuickSnapStandAlone extends StatelessWidget {
  const QuickSnapStandAlone({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const QuickSnapStandaloneShell(),
    );
  }
}

/// A single zone (region) of a [QuickGrid], resolved onto a specific monitor,
/// in absolute (virtual-screen) physical pixels.
class _ZoneInstance {
  final int monitorId;
  final int zoneIndex;
  final Rect rect;
  const _ZoneInstance({required this.monitorId, required this.zoneIndex, required this.rect});
}

class QuickSnapStandaloneShell extends StatefulWidget {
  const QuickSnapStandaloneShell({super.key});

  @override
  State<QuickSnapStandaloneShell> createState() => _QuickSnapStandaloneShellState();
}

class _QuickSnapStandaloneShellState extends State<QuickSnapStandaloneShell> with TabameListener {
  static const double stripHeight = 26;

  Timer? _timer;
  int _tickCount = 0;

  late final Offset _virtualOrigin;

  /// monitor id -> active preset index. Each monitor keeps its own grid so the
  /// user can run a different layout per screen.
  final Map<int, int> _activeGridIndex = <int, int>{};

  /// hwnd -> canonical slot index, remembered across grid switches so a
  /// smaller grid can collapse extra windows into its last zone and a larger
  /// grid can re-expand them back into their original slots.
  final Map<int, int> _canonicalSlot = <int, int>{};
  int _maxZonesSeen = 0;

  List<_ZoneInstance> _zones = <_ZoneInstance>[];

  /// Stable first-seen ordering for taskbar strips. `WindowWatcher.list` is
  /// z-order, so activating a window (e.g. clicking a strip item) bumps it to
  /// the front and reshuffles the strip. Keying each hwnd to the order it was
  /// first seen keeps the strip stable across focus changes.
  final Map<int, int> _windowOrder = <int, int>{};
  int _windowOrderSeq = 0;

  /// hwnd -> z-order rank (0 = top of the stack). Windows snapped into the same
  /// zone overlap almost exactly, so the lowest-ranked one is the single window
  /// actually visible there — the strip highlights it so you can tell which is
  /// on top without alt-tabbing through the stack.
  final Map<int, int> _zOrder = <int, int>{};

  /// zoneIndex within [_zones] (or -1) currently under the cursor.
  int _hoveredZone = -1;
  bool _clickThroughEnabled = true;
  bool _dragging = false;

  /// Zone index (within [_zones]) the dragged window is currently over —
  /// distinct from [_hoveredZone], which only tracks the taskbar strip.
  int _dragHoverZone = -1;

  /// The grid switcher is hidden by default and revealed per-monitor when the
  /// cursor moves into the right band of that monitor. This holds the monitor id
  /// whose switcher is currently revealed (-1 = none).
  int _switcherMonitor = -1;

  /// One switcher key per monitor, so click-through can be disabled while the
  /// cursor is over that monitor's revealed switcher.
  final Map<int, GlobalKey> _switcherKeys = <int, GlobalKey>{};

  /// Width (in physical pixels) of the right band that reveals a monitor's
  /// switcher when the cursor enters it. Kept tiny so the switcher only appears
  /// when the cursor is right at the screen edge — docked to the right rather
  /// than the top so it doesn't cover the per-zone taskbar strips.
  static const double _switcherRevealBand = 3;

  /// Once revealed, the switcher stays visible until the cursor moves further
  /// than this (physical pixels) left of the monitor's right edge — a hysteresis
  /// band so the panel doesn't flicker away the moment you leave the 2px strip.
  static const double _switcherHideBand = 110;

  List<QuickGrid> get _presets => Boxes.quickGrids;

  /// The active preset index for [monitorId], defaulting to the first preset.
  int _gridIndexFor(int monitorId) {
    final int? idx = _activeGridIndex[monitorId];
    if (idx != null && idx >= 0 && idx < _presets.length) return idx;
    return _presets.isNotEmpty ? 0 : -1;
  }

  /// The active grid for [monitorId], or null when there are no presets.
  QuickGrid? _gridFor(int monitorId) {
    final int idx = _gridIndexFor(monitorId);
    return (idx >= 0 && idx < _presets.length) ? _presets[idx] : null;
  }

  /// The id of the leftmost monitor (smallest x), or -1 if none.
  int _leftmostMonitorId() {
    int result = -1;
    int minX = 1 << 30;
    for (final int id in Monitor.list) {
      final Square? m = Monitor.monitorSizes[id];
      if (m == null) continue;
      if (m.x < minX) {
        minX = m.x;
        result = id;
      }
    }
    return result;
  }

  /// The leftmost monitor docks its switcher on the left edge; every other
  /// monitor docks on the right.
  bool _dockLeft(int monitorId) => monitorId == _leftmostMonitorId();

  @override
  void initState() {
    super.initState();
    // Standalone processes don't go through AppStartup.registerHooks(), so the
    // native method-channel handler must be wired up here or moveStart/moveEnd
    // (and every other native event) silently never reach onViewsEvent below.
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);
    Monitor.fetchMonitors();
    _virtualOrigin = Offset(
      GetSystemMetrics(SM_XVIRTUALSCREEN).toDouble(),
      GetSystemMetrics(SM_YVIRTUALSCREEN).toDouble(),
    );

    if (_presets.isNotEmpty) {
      for (final int monitorId in Monitor.list) {
        _activeGridIndex[monitorId] = 0;
      }
      _rebuildZones();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Win32Window.setupOverlay(toolWindow: true);
      Win32Window.enableClickThrough();
      _kickRenderSurface();
    });

    unawaited(WindowWatcher.fetchWindows().then((_) {
      if (!mounted) return;
      setState(_syncWindowOrder);
      _arrangeExistingWindows();
    }));
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    NativeHooks.removeListener(this);
    super.dispose();
  }

  /// Hot restart leaves this transparent, always-on-top layered overlay showing
  /// its pre-restart frame: the Dart tree rebuilds (presets/state stay correct)
  /// but the Windows embedder never re-presents to the layered surface, so the
  /// whole overlay looks frozen. A genuine size change — not the same-size
  /// SWP_FRAMECHANGED setupOverlay already issues — forces the embedder to
  /// recreate its swap chain and resume the frame loop. No-op cost on cold start.
  void _kickRenderSurface() {
    final int hwnd = Win32Window.getHwnd();
    if (hwnd == 0) return;
    final int w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    final int h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    SetWindowPos(hwnd, 0, 0, 0, w, h - 1, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    Future<void>.delayed(const Duration(milliseconds: 32), () {
      SetWindowPos(hwnd, 0, 0, 0, w, h, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    });
  }

  void _activateGrid(int monitorId, int index) {
    if (index < 0 || index >= _presets.length) return;
    setState(() => _activeGridIndex[monitorId] = index);
    _rebuildZones();
    _reflowForMonitor(monitorId);
  }

  void _rebuildZones() {
    final List<_ZoneInstance> zones = <_ZoneInstance>[];
    int maxZones = _maxZonesSeen;
    for (final int monitorId in Monitor.list) {
      final Square? m = Monitor.monitorSizes[monitorId];
      if (m == null) continue;
      final QuickGrid? grid = _gridFor(monitorId);
      if (grid == null) continue;
      for (int i = 0; i < grid.zones.length; i++) {
        final QuickGridRect z = grid.zones[i];
        final Rect rect = Rect.fromLTRB(
          m.x + z.left * m.width,
          m.y + z.top * m.height,
          m.x + z.right * m.width,
          m.y + z.bottom * m.height,
        );
        zones.add(_ZoneInstance(monitorId: monitorId, zoneIndex: i, rect: rect));
      }
      if (grid.zones.length > maxZones) maxZones = grid.zones.length;
    }
    _zones = zones;
    _maxZonesSeen = maxZones;
  }

  /// Seeds canonical slots for any window on [monitorId] physically sitting in
  /// a zone that doesn't have one yet, then repositions every already-tracked
  /// window on that monitor into its collapsed/expanded slot under the
  /// monitor's newly-active grid. Windows on other monitors are left alone so
  /// each screen keeps its own layout.
  void _reflowForMonitor(int monitorId) {
    final QuickGrid? grid = _gridFor(monitorId);
    if (grid == null || grid.zones.isEmpty) return;

    for (final Window w in WindowWatcher.list) {
      if (Win32.getWindowMonitor(w.hWnd) != monitorId) continue;
      if (_canonicalSlot.containsKey(w.hWnd)) continue;
      final int? zoneIndex = _zoneIndexContaining(w.hWnd);
      if (zoneIndex != null) _canonicalSlot[w.hWnd] = zoneIndex;
    }

    for (final MapEntry<int, int> entry in _canonicalSlot.entries.toList()) {
      final int hWnd = entry.key;
      if (IsWindow(hWnd) == 0) continue;
      if (Win32.getWindowMonitor(hWnd) != monitorId) continue;
      final int targetZone = entry.value < grid.zones.length ? entry.value : grid.zones.length - 1;
      QuickSnapApply.apply(hWnd, grid.zones[targetZone], grid.gap, monitorId, topInsetPhysical: stripHeight);
    }
    _canonicalSlot.removeWhere((int hWnd, _) => IsWindow(hWnd) == 0);
  }

  /// One-time startup pass: snaps every currently-open window into a QuickSnap
  /// zone so the grid isn't just an overlay listing windows at their pre-launch
  /// sizes — each window is physically moved/resized into the zone it belongs
  /// to. A window is placed into the zone (on its own monitor) whose rect
  /// contains its center; if its center sits outside every zone, it falls back
  /// to the nearest zone by center distance. Minimized windows are skipped so
  /// we don't yank them back onto the screen.
  void _arrangeExistingWindows() {
    if (_zones.isEmpty) return;
    for (final Window w in WindowWatcher.list) {
      if (IsWindow(w.hWnd) == 0 || IsIconic(w.hWnd) != 0) continue;
      final int monitorId = Win32.getWindowMonitor(w.hWnd);
      final QuickGrid? grid = _gridFor(monitorId);
      if (grid == null || grid.zones.isEmpty) continue;

      final Square rect = Win32.getWindowRect(hwnd: w.hWnd);
      final Offset center = Offset(rect.x + rect.width / 2, rect.y + rect.height / 2);

      int targetZone = -1;
      double bestDist = double.infinity;
      for (final _ZoneInstance z in _zones) {
        if (z.monitorId != monitorId) continue;
        if (z.rect.contains(center)) {
          targetZone = z.zoneIndex;
          break;
        }
        final double dist = (z.rect.center - center).distanceSquared;
        if (dist < bestDist) {
          bestDist = dist;
          targetZone = z.zoneIndex;
        }
      }
      if (targetZone < 0) continue;

      _canonicalSlot[w.hWnd] = targetZone;
      QuickSnapApply.apply(w.hWnd, grid.zones[targetZone], grid.gap, monitorId, topInsetPhysical: stripHeight);
    }
    if (mounted) setState(() {});
  }

  /// The zone index (under the current grid) whose pixel rect contains
  /// [hWnd]'s center point, or null if it's on none of them.
  int? _zoneIndexContaining(int hWnd) {
    final Square rect = Win32.getWindowRect(hwnd: hWnd);
    final Offset center = Offset(rect.x + rect.width / 2, rect.y + rect.height / 2);
    for (final _ZoneInstance z in _zones) {
      if (z.rect.contains(center)) return z.zoneIndex;
    }
    return null;
  }

  void _tick() {
    if (!mounted) return;
    _tickCount++;
    if (_tickCount % 5 == 0) {
      unawaited(WindowWatcher.fetchWindows().then((_) {
        if (mounted) setState(_syncWindowOrder);
      }));
    }

    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final double mx = lpPoint.ref.x.toDouble();
    final double my = lpPoint.ref.y.toDouble();
    free(lpPoint);

    int hovered = -1;
    for (int i = 0; i < _zones.length; i++) {
      final Rect stripRect = Rect.fromLTWH(_zones[i].rect.left, _zones[i].rect.top, _zones[i].rect.width, stripHeight);
      if (stripRect.contains(Offset(mx, my))) {
        hovered = i;
        break;
      }
    }

    if (hovered != _hoveredZone) setState(() => _hoveredZone = hovered);

    if (_dragging) {
      int dragHover = -1;
      for (int i = 0; i < _zones.length; i++) {
        if (_zones[i].rect.contains(Offset(mx, my))) {
          dragHover = i;
          break;
        }
      }
      if (dragHover != _dragHoverZone) setState(() => _dragHoverZone = dragHover);
    }

    // Reveal a monitor's switcher only when the cursor hits its 2px edge strip
    // (left edge for the leftmost monitor, right edge otherwise), then keep it
    // revealed (hysteresis) until the cursor moves past the wider hide band.
    int switcherMonitor = -1;
    if (_presets.isNotEmpty) {
      if (_switcherMonitor != -1) {
        final Square? m = Monitor.monitorSizes[_switcherMonitor];
        if (m != null && my >= m.y && my < m.y + m.height) {
          final bool withinBand = _dockLeft(_switcherMonitor)
              ? (mx >= m.x && mx < m.x + _switcherHideBand)
              : (mx >= m.x + m.width - _switcherHideBand && mx < m.x + m.width);
          if (withinBand) switcherMonitor = _switcherMonitor;
        }
      }
      if (switcherMonitor == -1) {
        for (final int monitorId in Monitor.list) {
          final Square? m = Monitor.monitorSizes[monitorId];
          if (m == null) continue;
          final bool insideY = my >= m.y && my < m.y + m.height;
          final bool nearEdge = _dockLeft(monitorId)
              ? (mx >= m.x && mx < m.x + _switcherRevealBand)
              : (mx >= m.x + m.width - _switcherRevealBand && mx < m.x + m.width);
          if (insideY && nearEdge) {
            switcherMonitor = monitorId;
            break;
          }
        }
      }
    }
    if (switcherMonitor != _switcherMonitor) setState(() => _switcherMonitor = switcherMonitor);

    bool overSwitcher = false;
    if (switcherMonitor != -1) {
      final GlobalKey? key = _switcherKeys[switcherMonitor];
      overSwitcher = key != null && _isPointOverKey(key, mx, my);
    }
    final bool shouldBeInteractive = hovered != -1 || overSwitcher;
    if (shouldBeInteractive == _clickThroughEnabled) {
      _clickThroughEnabled = !shouldBeInteractive;
      if (shouldBeInteractive) {
        Win32Window.disableClickThrough();
      } else {
        Win32Window.enableClickThrough();
      }
    }
  }

  /// Whether absolute (physical, virtual-screen) point [mx],[my] falls inside
  /// the widget bound to [key], converting the widget's logical local bounds
  /// back to physical screen coordinates.
  bool _isPointOverKey(GlobalKey key, double mx, double my) {
    final RenderObject? renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return false;
    final double dpr = View.of(context).devicePixelRatio;
    final Offset local = renderObject.localToGlobal(Offset.zero);
    final Size size = renderObject.size;
    final Rect physical = Rect.fromLTWH(
      local.dx * dpr + _virtualOrigin.dx,
      local.dy * dpr + _virtualOrigin.dy,
      size.width * dpr,
      size.height * dpr,
    );
    return physical.contains(Offset(mx, my));
  }

  @override
  void onViewsEvent(ViewsAction action, int hWnd) {
    switch (action) {
      case ViewsAction.moveStart:
        setState(() {
          _dragging = true;
          _dragHoverZone = -1;
        });
      case ViewsAction.moveEnd:
        _handleMoveEnd(hWnd);
      default:
        break;
    }
  }

  void _handleMoveEnd(int hWnd) {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final double mx = lpPoint.ref.x.toDouble();
    final double my = lpPoint.ref.y.toDouble();
    free(lpPoint);

    // Prefer the zone the poll already determined the cursor is over (same
    // one that's visually highlighted); fall back to a fresh hit-test in case
    // the drop lands between two poll ticks.
    _ZoneInstance? target = (_dragHoverZone >= 0 && _dragHoverZone < _zones.length) ? _zones[_dragHoverZone] : null;
    target ??= _zones.cast<_ZoneInstance?>().firstWhere(
          (_ZoneInstance? z) => z != null && z.rect.contains(Offset(mx, my)),
          orElse: () => null,
        );

    setState(() {
      _dragging = false;
      _dragHoverZone = -1;
    });

    if (target == null) return;
    final QuickGrid? grid = _gridFor(target.monitorId);
    if (grid == null) return;

    QuickSnapApply.apply(hWnd, grid.zones[target.zoneIndex], grid.gap, target.monitorId, topInsetPhysical: stripHeight);
    _canonicalSlot[hWnd] = target.zoneIndex;
    _maxZonesSeen = _maxZonesSeen > grid.zones.length ? _maxZonesSeen : grid.zones.length;
  }

  /// Assigns a stable sequence number to any newly-seen window and prunes
  /// closed ones, so the taskbar strips keep a consistent left-to-right order
  /// regardless of the live z-order in `WindowWatcher.list`.
  void _syncWindowOrder() {
    for (final Window w in WindowWatcher.list) {
      _windowOrder.putIfAbsent(w.hWnd, () => _windowOrderSeq++);
    }
    _windowOrder.removeWhere((int hWnd, _) => !WindowWatcher.list.any((Window w) => w.hWnd == hWnd));

    // EnumWindows returns handles top-to-bottom in z-order, so its index is the
    // z-rank we use to pick the visible window in each zone.
    _zOrder.clear();
    final List<int> ordered = enumWindows();
    for (int i = 0; i < ordered.length; i++) {
      _zOrder[ordered[i]] = i;
    }
  }

  /// The hwnd of the window currently on top (visible) among [windows], or 0 if
  /// the list is empty. "On top" = smallest z-order rank.
  int _visibleHwnd(List<Window> windows) {
    int best = 0;
    int bestRank = 1 << 30;
    for (final Window w in windows) {
      final int rank = _zOrder[w.hWnd] ?? (1 << 30);
      if (rank < bestRank) {
        bestRank = rank;
        best = w.hWnd;
      }
    }
    return best;
  }

  void _focusWindow(int hWnd) => Win32.activateWindow(hWnd);

  @override
  Widget build(BuildContext context) {
    final double dpr = MediaQuery.of(context).devicePixelRatio;
    final Color accent = Design.accent;

    Offset toLocal(Offset absolutePhysical) => (absolutePhysical - _virtualOrigin) / dpr;
    Size toLocalSize(Size physical) => physical / dpr;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: <Widget>[
          for (int i = 0; i < _zones.length; i++)
            Builder(
              builder: (BuildContext context) {
                final List<Window> windows = _windowsInZone(_zones[i]);
                return Positioned(
                  left: toLocal(_zones[i].rect.topLeft).dx,
                  top: toLocal(_zones[i].rect.topLeft).dy,
                  width: toLocalSize(_zones[i].rect.size).width,
                  height: toLocalSize(_zones[i].rect.size).height,
                  child: _ZoneRegion(
                    index: i + 1,
                    accent: accent,
                    emphasized: _dragging,
                    dragTarget: _dragging && _dragHoverZone == i,
                    stripHeight: stripHeight / dpr,
                    hovered: _hoveredZone == i,
                    windows: windows,
                    visibleHwnd: _visibleHwnd(windows),
                    onFocusWindow: _focusWindow,
                  ),
                );
              },
            ),
          // Per-monitor grid switcher, docked to the right edge, hidden by
          // default and slid in from the right when the cursor enters that
          // monitor's right band.
          if (_presets.isNotEmpty)
            for (final int monitorId in Monitor.list)
              if (Monitor.monitorSizes[monitorId] != null)
                Builder(
                  builder: (BuildContext context) {
                    final Square m = Monitor.monitorSizes[monitorId]!;
                    final Offset tl = toLocal(Offset(m.x.toDouble(), m.y.toDouble()));
                    final Size localSize = toLocalSize(Size(m.width.toDouble(), m.height.toDouble()));
                    final bool show = _switcherMonitor == monitorId;
                    final bool dockLeft = _dockLeft(monitorId);
                    return Positioned(
                      left: tl.dx,
                      top: tl.dy,
                      width: localSize.width,
                      height: localSize.height,
                      child: Align(
                        alignment: dockLeft ? Alignment.centerLeft : Alignment.centerRight,
                        // Fully invisible and non-interactive when hidden, so it
                        // never bleeds onto an adjacent monitor.
                        child: IgnorePointer(
                          ignoring: !show,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            opacity: show ? 1 : 0,
                            child: Padding(
                              padding: dockLeft ? const EdgeInsets.only(left: 4) : const EdgeInsets.only(right: 4),
                              child: _GridSwitcher(
                                key: _switcherKeys.putIfAbsent(monitorId, () => GlobalKey()),
                                presets: _presets,
                                activeIndex: _gridIndexFor(monitorId),
                                accent: accent,
                                onSelected: (int index) => _activateGrid(monitorId, index),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  List<Window> _windowsInZone(_ZoneInstance zone) {
    final List<Window> result = WindowWatcher.list.where((Window w) {
      final Square rect = Win32.getWindowRect(hwnd: w.hWnd);
      final Offset center = Offset(rect.x + rect.width / 2, rect.y + rect.height / 2);
      return zone.rect.contains(center);
    }).toList();
    result.sort((Window a, Window b) => (_windowOrder[a.hWnd] ?? 1 << 30).compareTo(_windowOrder[b.hWnd] ?? 1 << 30));
    return result;
  }
}

// ── Per-region taskbar strip + zone outline ─────────────────────────────────

class _ZoneRegion extends StatelessWidget {
  const _ZoneRegion({
    required this.index,
    required this.accent,
    required this.emphasized,
    required this.dragTarget,
    required this.stripHeight,
    required this.hovered,
    required this.windows,
    required this.visibleHwnd,
    required this.onFocusWindow,
  });

  final int index;
  final Color accent;
  final bool emphasized;

  /// True when a window is currently being dragged over this exact zone —
  /// the region that will receive the resize if the user drops here.
  final bool dragTarget;
  final double stripHeight;
  final bool hovered;
  final List<Window> windows;

  /// The window currently on top of this zone's stack (0 if none), rendered
  /// with an accent highlight in the strip so it stands out from covered ones.
  final int visibleHwnd;
  final void Function(int hWnd) onFocusWindow;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: dragTarget ? accent.withValues(alpha: 0.18) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: accent.withValues(alpha: dragTarget ? 0.9 : (emphasized ? 0.55 : 0.18)),
                  width: dragTarget ? 2.5 : (emphasized ? 1.5 : 1),
                ),
                boxShadow: dragTarget
                    ? <BoxShadow>[BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 2)]
                    : null,
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    '$index',
                    style: TextStyle(color: accent.withValues(alpha: 0.35), fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: stripHeight,
          child: _TaskbarStrip(
            accent: accent,
            hovered: hovered,
            windows: windows,
            visibleHwnd: visibleHwnd,
            onFocusWindow: onFocusWindow,
          ),
        ),
      ],
    );
  }
}

class _TaskbarStrip extends StatefulWidget {
  const _TaskbarStrip({
    required this.accent,
    required this.hovered,
    required this.windows,
    required this.visibleHwnd,
    required this.onFocusWindow,
  });

  final Color accent;
  final bool hovered;
  final List<Window> windows;
  final int visibleHwnd;
  final void Function(int hWnd) onFocusWindow;

  @override
  State<_TaskbarStrip> createState() => _TaskbarStripState();
}

class _TaskbarStripState extends State<_TaskbarStrip> {
  int hovered = -1;
  @override
  Widget build(BuildContext context) {
    if (widget.windows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: widget.hovered ? 0.75 : 0.45),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        children: <Widget>[
          for (final Window w in widget.windows)
            Builder(
              builder: (BuildContext context) {
                // The window on top of this zone's stack is what you actually
                // see; every other item is covered behind it. Give the visible
                // one an accent fill + border and full-strength text, and dim
                // the covered ones so the strip alone tells you what's on top.
                final bool visible = w.hWnd == widget.visibleHwnd;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                  child: MouseRegion(
                    onEnter: (PointerEnterEvent e) => setState(() => hovered = w.hWnd),
                    onExit: (PointerExitEvent e) => setState(() => hovered = -1),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () => widget.onFocusWindow(w.hWnd),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: visible ? widget.accent.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(
                            color:
                                visible ? widget.accent.withValues(alpha: 0.20) : Colors.white.withValues(alpha: 0.08),
                            width: visible ? 1 : 0.5,
                          ),
                        ),
                        child: Opacity(
                          opacity: visible
                              ? 0.9
                              : hovered == w.hWnd
                                  ? 0.9
                                  : 0.7,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: buildExtractedIcon(WindowWatcher.icons[w.hWnd], width: 14, height: 14),
                              ),
                              const SizedBox(width: 5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 140),
                                child: Text(
                                  w.title,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: visible ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── Grid preset switcher ─────────────────────────────────────────────────────

class _GridSwitcher extends StatelessWidget {
  const _GridSwitcher({
    super.key,
    required this.presets,
    required this.activeIndex,
    required this.accent,
    required this.onSelected,
  });

  final List<QuickGrid> presets;
  final int activeIndex;
  final Color accent;
  final void Function(int index) onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < presets.length; i++)
            _GridSwitcherTab(
              preset: presets[i],
              accent: accent,
              isActive: activeIndex == i,
              onTap: () => onSelected(i),
            ),
        ],
      ),
    );
  }
}

class _GridSwitcherTab extends StatefulWidget {
  const _GridSwitcherTab({
    required this.preset,
    required this.accent,
    required this.isActive,
    required this.onTap,
  });

  final QuickGrid preset;
  final Color accent;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_GridSwitcherTab> createState() => _GridSwitcherTabState();
}

class _GridSwitcherTabState extends State<_GridSwitcherTab> {
  bool isHovered = false;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: widget.isActive ? widget.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isActive ? widget.accent.withValues(alpha: 0.45) : widget.accent.withValues(alpha: 0.01),
            width: 0.5,
          ),
        ),
        child: MouseRegion(
          onEnter: (PointerEnterEvent e) => setState(() => isHovered = true),
          onExit: (PointerExitEvent e) => setState(() => isHovered = false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                width: 46,
                height: 26,
                child: CustomPaint(painter: _MiniPainter(preset: widget.preset, accent: widget.accent)),
              ),
              const SizedBox(height: 4),
              Text(
                widget.preset.name,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: (widget.isActive || isHovered) ? 1 : 0.5),
                  fontWeight: widget.isActive ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints a scaled-down preview of a preset's zones — the same mini layout the
/// full-screen overlay draws in its notch tabs.
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
  bool shouldRepaint(_MiniPainter old) => old.preset != preset || old.accent != accent;
}
