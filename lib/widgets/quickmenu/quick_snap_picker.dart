import 'dart:async';

import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';

// ignore_for_file: public_member_api_docs

/// Shown when middle-clicking a taskbar item.
///
/// Flow:
///   1. List of [QuickGrid] presets (thumbnails).
///   2. After selecting a preset → grid of individual zones to pick.
///   3. Picking a zone → `Win32.changePosition` on [hWnd] and pop.
class QuickSnapPicker extends StatefulWidget {
  const QuickSnapPicker({super.key, required this.hWnd});

  final int hWnd;

  @override
  State<QuickSnapPicker> createState() => _QuickSnapPickerState();
}

class _QuickSnapPickerState extends State<QuickSnapPicker> {
  QuickGrid? _selectedPreset;

  List<QuickGrid> get _presets => Boxes.quickGrids;

  // ── Apply logic ──────────────────────────────────────────────────────────────

  // ignore: unused_element
  void _applyZone2(QuickGridRect zone) {
    // Determine which monitor the window currently lives on.
    // NOTE: we use widget.hWnd (the target window) not Win32.hWnd (tabame itself).
    final int monitorId = Win32.getWindowMonitor(Win32.hWnd);
    Square? monSize = Monitor.monitorSizes[monitorId];

    // Fallback: use the primary / first monitor
    if (monSize == null && Monitor.monitorSizes.isNotEmpty) {
      monSize = Monitor.monitorSizes.values.first;
    }

    if (monSize == null) return;

    final int mx = monSize.x;
    final int my = monSize.y;
    final int mw = monSize.width;
    final int mh = monSize.height;

    // ── Restore maximized state first so the window has real borders ──────────
    Win32.restoreIfMaximized(widget.hWnd);

    // ── Measure invisible border (Win10/11 shadow/gutter) ────────────────────
    // GetWindowRect includes ~8px invisible resize handles on left/right/bottom.
    // setWindowPos uses those same coordinates, so two adjacent zones with no
    // gap would still have a visible gap equal to borderLeft + borderRight.
    // We compensate by expanding each dimension by the invisible border widths.
    final ({int left, int top, int right, int bottom}) border = Win32.getInvisibleBorder(widget.hWnd);

    // ── Compute target rect from fractional zone + monitor ───────────────────
    final int g = (_selectedPreset?.gap ?? 0);
    final int half = g ~/ 2;

    // Zone pixel rect (no border compensation yet)
    final int zx = mx + (zone.left * mw).round();
    final int zy = my + (zone.top * mh).round();
    final int zw = ((zone.right - zone.left) * mw).round();
    final int zh = ((zone.bottom - zone.top) * mh).round();

    // Expand the SetWindowPos rect by invisible borders so the *visible* area
    // aligns perfectly with zone boundaries. Then inset by gap/2.
    final int x = zx - border.left + half;
    final int y = zy - border.top + half;
    final int w = (zw + border.left + border.right - g).clamp(100, mw);
    final int h = (zh + border.top + border.bottom - g).clamp(60, mh);
    QuickMenuFunctions.keepOpen = true;
    SetForegroundWindow(widget.hWnd);
    if (!Globals.snappedWindowOriginalSizes.containsKey(widget.hWnd)) {
      Globals.snappedWindowOriginalSizes[widget.hWnd] = <int>[
        Win32.getSize(hwnd: widget.hWnd).width,
        Win32.getSize(hwnd: widget.hWnd).height,
      ];
    }

    Win32.setPosDPI(widget.hWnd, PointXY(X: x, Y: y), logicalWidth: w, logicalHeight: h);
    // Win32.changePosition(widget.hWnd, x, y, w, h);
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    Navigator.of(context).pop();
  }

  void _applyZone(QuickGridRect zone) {
    final int monitorId = Win32.getWindowMonitor(Win32.hWnd);
    Square? monSize = Monitor.monitorSizes[monitorId];
    if (monSize == null && Monitor.monitorSizes.isNotEmpty) {
      monSize = Monitor.monitorSizes.values.first;
    }
    if (monSize == null) return;

    // Get DPI scale for this monitor
    final Dpi? dpi = Monitor.dpi[monitorId];
    final double scaleX = dpi != null ? dpi.x / 96.0 : 1.0;
    final double scaleY = dpi != null ? dpi.y / 96.0 : 1.0;

    // Convert physical monitor rect → logical
    final double mx = monSize.x / scaleX;
    final double my = monSize.y / scaleY;
    final double mw = monSize.width / scaleX;
    final double mh = monSize.height / scaleY;

    Win32.restoreIfMaximized(widget.hWnd);

    // Invisible border is in physical pixels — convert to logical
    final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(widget.hWnd);
    final double borderLeft = border.left / scaleX;
    final double borderTop = border.top / scaleY;
    final double borderRight = border.right / scaleX;
    final double borderBottom = border.bottom / scaleY;

    final double g = (_selectedPreset?.gap ?? 0) / scaleX; // gap is likely logical already — adjust if not
    final double half = g / 2;

    // Zone rect in logical coords
    final double zx = mx + zone.left * mw;
    final double zy = my + zone.top * mh;
    final double zw = (zone.right - zone.left) * mw;
    final double zh = (zone.bottom - zone.top) * mh;

    final int x = (zx - borderLeft + half).round();
    final int y = (zy - borderTop + half).round();
    final int w = (zw + borderLeft + borderRight - g).round().clamp(100, mw.round());
    final int h = (zh + borderTop + borderBottom - g).round().clamp(60, mh.round());

    QuickMenuFunctions.keepOpen = true;
    SetForegroundWindow(widget.hWnd);
    if (!Globals.snappedWindowOriginalSizes.containsKey(widget.hWnd)) {
      final ({int height, int width}) size = Win32.getSize(hwnd: widget.hWnd);
      Globals.snappedWindowOriginalSizes[widget.hWnd] = <int>[size.width, size.height];
    }

    // setPosDPI now receives logical coords and scales correctly
    Win32.setPosDPI(widget.hWnd, PointXY(X: x, Y: y), logicalWidth: w, logicalHeight: h);
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    Navigator.of(context).pop();
  }
  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_selectedPreset != null || _presets.length == 1) {
      _selectedPreset ??= _presets.first;
      userSettings.lastQuickSnapZoneId = _selectedPreset!.id;
      return _ZoneGrid(
        preset: _selectedPreset!,
        onZoneTapped: _applyZone,
        onBack: () {
          userSettings.lastQuickSnapZoneId = "";
          setState(() => _selectedPreset = null);
        },
      );
    } else if (userSettings.lastQuickSnapZoneId != "") {
      if (_presets.any((QuickGrid element) => element.id == userSettings.lastQuickSnapZoneId)) {
        _selectedPreset = _presets.firstWhere((QuickGrid element) => element.id == userSettings.lastQuickSnapZoneId);
        return _ZoneGrid(
          preset: _selectedPreset!,
          onZoneTapped: _applyZone,
          onBack: () {
            userSettings.lastQuickSnapZoneId = "";
            setState(() => _selectedPreset = null);
          },
        );
      } else {
        userSettings.lastQuickSnapZoneId = "";
      }
    }
    return _PresetList(
      presets: _presets,
      onPresetTapped: (QuickGrid preset) {
        userSettings.lastQuickSnapZoneId = preset.id;
        setState(() => _selectedPreset = preset);
      },
    );
  }
}

// ── Preset list ──────────────────────────────────────────────────────────────

class _PresetList extends StatelessWidget {
  const _PresetList({required this.presets, required this.onPresetTapped});

  final List<QuickGrid> presets;
  final void Function(QuickGrid) onPresetTapped;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (presets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.view_quilt_rounded, size: 40, color: onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text('No zone presets',
                style: theme.textTheme.titleSmall?.copyWith(color: onSurface.withValues(alpha: 0.5))),
            const SizedBox(height: 6),
            Text('Create one in Settings → QuickSnap Zones',
                style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.4)),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.view_quilt_rounded, size: 18, color: accent),
              const SizedBox(width: 8),
              Text('Snap to Zone', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${presets.length} preset${presets.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.55))),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final QuickGrid preset in presets)
          _PresetTile(preset: preset, accent: accent, onTap: () => onPresetTapped(preset)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PresetTile extends StatefulWidget {
  const _PresetTile({required this.preset, required this.accent, required this.onTap});
  final QuickGrid preset;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PresetTile> createState() => _PresetTileState();
}

class _PresetTileState extends State<_PresetTile> {
  bool _hov = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          color: _hov ? userSettings.themeColors.accent.withValues(alpha: 0.08) : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: <Widget>[
              // Mini preview
              SizedBox(
                width: 64,
                height: 40,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: CustomPaint(
                    painter: _MiniPainter(preset: widget.preset, accent: userSettings.themeColors.accent),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(widget.preset.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      '${widget.preset.zones.length} zone${widget.preset.zones.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.55)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Zone grid (step 2) ───────────────────────────────────────────────────────

class _ZoneGrid extends StatefulWidget {
  const _ZoneGrid({required this.preset, required this.onZoneTapped, required this.onBack});
  final QuickGrid preset;
  final void Function(QuickGridRect) onZoneTapped;
  final VoidCallback onBack;

  @override
  State<_ZoneGrid> createState() => _ZoneGridState();
}

class _ZoneGridState extends State<_ZoneGrid> {
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 16, 8),
          child: Row(
            children: <Widget>[
              if (Boxes.quickGrids.length > 1)
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  tooltip: 'Back',
                  onPressed: widget.onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(widget.preset.name,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              Text('Pick a zone', style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.5))),
            ],
          ),
        ),
        const Divider(height: 1),
        const SizedBox(height: 12),

        // 16:9 interactive canvas
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints bc) {
                final Size sz = Size(bc.maxWidth, bc.maxHeight);
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: <Widget>[
                      // Background
                      Container(
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      // Zone rectangles
                      for (int i = 0; i < widget.preset.zones.length; i++)
                        _buildZoneTile(widget.preset.zones[i], i, sz, accent, onSurface),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildZoneTile(QuickGridRect r, int idx, Size sz, Color accent, Color onSurface) {
    final bool hov = _hovered == idx;
    final double left = r.left * sz.width;
    final double top = r.top * sz.height;
    final double width = (r.right - r.left) * sz.width;
    final double height = (r.bottom - r.top) * sz.height;

    return Positioned(
      left: left + 2,
      top: top + 2,
      width: width - 4,
      height: height - 4,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = idx),
        onExit: (_) => setState(() => _hovered = null),
        child: GestureDetector(
          onTap: () => widget.onZoneTapped(r),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            decoration: BoxDecoration(
              color: hov ? accent.withValues(alpha: 0.28) : accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: hov ? accent.withValues(alpha: 0.85) : accent.withValues(alpha: 0.35),
                width: hov ? 1.8 : 1.0,
              ),
              boxShadow: hov
                  ? <BoxShadow>[
                      BoxShadow(color: accent.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 1),
                    ]
                  : null,
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 130),
                style: TextStyle(
                  fontSize: hov ? 18 : 14,
                  fontWeight: FontWeight.w800,
                  color: accent.withValues(alpha: hov ? 1.0 : 0.60),
                ),
                child: Text('${idx + 1}'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mini thumbnail painter ────────────────────────────────────────────────────

class _MiniPainter extends CustomPainter {
  _MiniPainter({required this.preset, required this.accent});
  final QuickGrid preset;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = accent.withValues(alpha: 0.07));
    final Paint fill = Paint()..color = accent.withValues(alpha: 0.20);
    final Paint border = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final QuickGridRect r in preset.zones) {
      final Rect rect = Rect.fromLTRB(
          r.left * size.width + 1, r.top * size.height + 1, r.right * size.width - 1, r.bottom * size.height - 1);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), border);
    }
  }

  @override
  bool shouldRepaint(_MiniPainter old) => old.preset != preset;
}
