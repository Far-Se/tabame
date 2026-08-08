import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/quick_snap_apply.dart';
import '../../models/classes/saved_maps.dart';

import '../../models/settings.dart';
import '../../platform/monitor_service.dart';
import '../../platform/platform_models.dart';
import '../../platform/quick_snap_service.dart';
import '../../platform/window_service.dart';

// ignore_for_file: public_member_api_docs

/// Shown when selecting a zone for a neutral [PlatformWindow] snapshot.
class QuickSnapPicker extends StatefulWidget {
  const QuickSnapPicker({super.key, required this.window});

  final PlatformWindow window;

  @override
  State<QuickSnapPicker> createState() => _QuickSnapPickerState();
}

class _QuickSnapPickerState extends State<QuickSnapPicker> {
  QuickGrid? _selectedPreset;

  List<QuickGrid> get _presets => Boxes.quickGrids;

  void _applyZone(QuickGridRect zone) {
    unawaited(_applyZoneAsync(zone));
  }

  Future<void> _applyZoneAsync(QuickGridRect zone) async {
    final QuickGrid? preset = _selectedPreset;
    if (preset == null) return;
    final QuickSnapService service = QuickSnapService.instance;
    if (!service.isAvailable) return;
    final List<PlatformMonitor> monitors = await MonitorService.instance.enumerate();
    final PlatformMonitor? monitor =
        QuickSnapGeometry.monitorForWindow(widget.window, monitors) ?? await MonitorService.instance.cursorMonitor();
    if (monitor == null) return;
    await WindowService.instance.activate(widget.window);
    final bool applied = await QuickSnapApply.apply(widget.window, monitor, zone, preset.gap);
    if (!applied || !mounted) return;
    QuickMenuFunctions.keepOpen = true;
    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!QuickSnapService.instance.isAvailable) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(QuickSnapService.instance.unavailableReason, textAlign: TextAlign.center),
      );
    }
    if (_selectedPreset != null || _presets.length == 1) {
      _selectedPreset ??= _presets.first;
      user.lastQuickSnapZoneId = _selectedPreset!.id;
      return _ZoneGrid(
        preset: _selectedPreset!,
        onZoneTapped: _applyZone,
        onBack: () {
          user.lastQuickSnapZoneId = "";
          setState(() => _selectedPreset = null);
        },
      );
    } else if (user.lastQuickSnapZoneId != "") {
      if (_presets.any((QuickGrid element) => element.id == user.lastQuickSnapZoneId)) {
        _selectedPreset = _presets.firstWhere((QuickGrid element) => element.id == user.lastQuickSnapZoneId);
        return _ZoneGrid(
          preset: _selectedPreset!,
          onZoneTapped: _applyZone,
          onBack: () {
            user.lastQuickSnapZoneId = "";
            setState(() => _selectedPreset = null);
          },
        );
      }
      user.lastQuickSnapZoneId = "";
    }
    return _PresetList(
      presets: _presets,
      onPresetTapped: (QuickGrid preset) {
        user.lastQuickSnapZoneId = preset.id;
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
    final Color accent = Design.accent;
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
          color: _hov ? Design.accent.withValues(alpha: 0.08) : Colors.transparent,
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
                    painter: _MiniPainter(preset: widget.preset, accent: Design.accent),
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
    final Color accent = Design.accent;
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
