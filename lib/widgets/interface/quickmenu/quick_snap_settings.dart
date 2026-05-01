import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/windows_scroll.dart';
import '../grid_settings.dart';

// ignore_for_file: public_member_api_docs

// ============================================================
// Main Settings Page
// ============================================================

class QuickSnapSettingsPage extends StatefulWidget {
  const QuickSnapSettingsPage({super.key});

  @override
  State<QuickSnapSettingsPage> createState() => _QuickSnapSettingsPageState();
}

class _QuickSnapSettingsPageState extends State<QuickSnapSettingsPage> {
  late List<QuickGrid> _zones;
  int? _editingIndex;
  bool _showGridSettings = false;

  @override
  void initState() {
    super.initState();
    _zones = List<QuickGrid>.from(Boxes.quickGrids);
  }

  void _save() {
    Boxes.quickGrids = List<QuickGrid>.from(_zones);
    setState(() {});
  }

  Widget _buildHooksToggle(Color accent, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Global QuickSnap Hooks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('Enable hardware-level hooks to trigger layouts while dragging',
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: globalSettings.quickSnapOverlay,
                  onChanged: (bool value) {
                    setState(() {
                      globalSettings.quickSnapOverlay = value;
                      Boxes.updateSettings('quickSnapOverlay', value);
                    });
                  },
                  activeThumbColor: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.lightbulb_outline_rounded, size: 16, color: accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'PRO TIP: With hooks active, start dragging any window and PRESS RIGHT CLICK to open the QuickSnap layout overlay instantly.',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addQuickGrid() {
    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final QuickGrid zone = QuickGrid(
      id: id,
      name: 'New Preset ${_zones.length + 1}',
      layoutType: QuickGridLayoutType.horizontal,
      zones: QuickGrid.buildDefault(QuickGridLayoutType.horizontal, 2),
    );
    _zones.add(zone);
    _save();
    setState(() => _editingIndex = _zones.length - 1);
  }

  void _deleteQuickGrid(int index) {
    _zones.removeAt(index);
    if (_editingIndex == index) _editingIndex = null;
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_editingIndex != null && _editingIndex! < _zones.length) {
      return _ZoneEditor(
        zone: _zones[_editingIndex!],
        onBack: () => setState(() => _editingIndex = null),
        onSave: (QuickGrid updated) {
          _zones[_editingIndex!] = updated;
          _save();
        },
      );
    }

    if (_showGridSettings) {
      return Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showGridSettings = false),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text("Back to QuickSnap Presets"),
              ),
            ),
          ),
          const Divider(height: 1),
          const Expanded(child: ViewsInterface()),
        ],
      );
    }
    return _buildList();
  }

  Widget _buildList() {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildHooksToggle(accent, theme),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('QuickSnap Zones',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text('Define custom screen regions and snap windows to them for an organized workspace',
                            style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addQuickGrid,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Preset'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: theme.colorScheme.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: _GridSettingsTile(onTap: () => setState(() => _showGridSettings = true)),
        ),
        if (_zones.isEmpty)
          _EmptyState(onAdd: _addQuickGrid)
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _zones.length; i++)
                  _ZoneListTile(
                    zone: _zones[i],
                    onEdit: () => setState(() => _editingIndex = i),
                    onDelete: () => _deleteQuickGrid(i),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ============================================================
// Zone List Tile
// ============================================================

class _ZoneListTile extends StatelessWidget {
  const _ZoneListTile({required this.zone, required this.onEdit, required this.onDelete});

  final QuickGrid zone;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              SizedBox(width: 80, height: 50, child: _ZoneMiniPreview(zone: zone)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(zone.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 3),
                    Text(
                      '${zone.zones.length} zone${zone.zones.length == 1 ? '' : 's'} · ${zone.layoutType.label}',
                      style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              IconButton(icon: Icon(Icons.edit_rounded, size: 18, color: accent), tooltip: 'Edit', onPressed: onEdit),
              IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: theme.colorScheme.error),
                  tooltip: 'Delete',
                  onPressed: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Mini Preview
// ============================================================

class _ZoneMiniPreview extends StatelessWidget {
  const _ZoneMiniPreview({required this.zone});
  final QuickGrid zone;

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _ZonePreviewPainter(zone: zone, accent: accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ZonePreviewPainter extends CustomPainter {
  _ZonePreviewPainter({required this.zone, required this.accent});
  final QuickGrid zone;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = accent.withValues(alpha: 0.07));
    final Paint fill = Paint()..color = accent.withValues(alpha: 0.18);
    final Paint border = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final QuickGridRect r in zone.zones) {
      final Rect rect = Rect.fromLTRB(
          r.left * size.width + 1, r.top * size.height + 1, r.right * size.width - 1, r.bottom * size.height - 1);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), fill);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), border);
    }
  }

  @override
  bool shouldRepaint(_ZonePreviewPainter old) => old.zone != zone;
}

// ============================================================
// Zone Editor
// ============================================================

class _ZoneEditor extends StatefulWidget {
  const _ZoneEditor({required this.zone, required this.onBack, required this.onSave});
  final QuickGrid zone;
  final VoidCallback onBack;
  final void Function(QuickGrid) onSave;

  @override
  State<_ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<_ZoneEditor> {
  late QuickGrid _zone;
  late TextEditingController _nameController;
  int? _selectedFreestyleZone;

  @override
  void initState() {
    super.initState();
    _zone = widget.zone.copyWith();
    _nameController = TextEditingController(text: _zone.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _commit() {
    final String name = _nameController.text.trim();
    _zone = _zone.copyWith(name: name.isEmpty ? _zone.name : name);
    widget.onSave(_zone);
  }

  void _changeLayout(QuickGridLayoutType type) {
    setState(() {
      if (type == QuickGridLayoutType.freestyle) {
        // Keep zones as-is, just switch the type
        _zone = _zone.copyWith(layoutType: type);
      } else {
        final int count = math.max(_zone.zones.length, 2);
        _zone = _zone.copyWith(
          layoutType: type,
          zones: QuickGrid.buildDefault(type, count),
        );
      }
      _selectedFreestyleZone = null;
    });
    _commit();
  }

  void _addZone() {
    final List<QuickGridRect> newZones = QuickGrid.buildDefault(_zone.layoutType, _zone.zones.length + 1);
    setState(() => _zone = _zone.copyWith(zones: newZones));
    _commit();
  }

  void _removeZone() {
    if (_zone.zones.length <= 1) return;
    final List<QuickGridRect> newZones = QuickGrid.buildDefault(_zone.layoutType, _zone.zones.length - 1);
    setState(() => _zone = _zone.copyWith(zones: newZones));
    _commit();
  }

  void _addFreestyleZone() {
    final List<QuickGridRect> zones = List<QuickGridRect>.from(_zone.zones);
    final double off = (zones.length * 0.04) % 0.3;
    zones.add(QuickGridRect(
      left: (0.1 + off).clamp(0.0, 0.6),
      top: (0.08 + off).clamp(0.0, 0.55),
      right: (0.45 + off).clamp(0.15, 0.95),
      bottom: (0.65 + off).clamp(0.2, 0.95),
    ));
    setState(() {
      _zone = _zone.copyWith(zones: zones);
      _selectedFreestyleZone = zones.length - 1;
    });
    _commit();
  }

  void _deleteFreestyleZone(int index) {
    final List<QuickGridRect> zones = List<QuickGridRect>.from(_zone.zones)..removeAt(index);
    setState(() {
      _zone = _zone.copyWith(zones: zones);
      _selectedFreestyleZone = null;
    });
    _commit();
  }

  void _updateFreestyleZone(int index, QuickGridRect newRect) {
    final List<QuickGridRect> zones = List<QuickGridRect>.from(_zone.zones);
    zones[index] = newRect;
    setState(() => _zone = _zone.copyWith(zones: zones));
    _commit();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;
    final bool isFreestyle = _zone.layoutType == QuickGridLayoutType.freestyle;

    return WindowsScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── Top bar ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  tooltip: 'Back',
                  onPressed: () {
                    _commit();
                    widget.onBack();
                  },
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    decoration:
                        const InputDecoration(border: InputBorder.none, isDense: true, hintText: 'Zone preset name'),
                    onChanged: (_) => _commit(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Controls ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
            child: Row(
              children: <Widget>[
                Text('Layout:', style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
                const SizedBox(width: 8),
                for (final QuickGridLayoutType type in QuickGridLayoutType.values) ...<Widget>[
                  _LayoutChip(
                    label: type.label,
                    icon: _layoutIcon(type),
                    selected: _zone.layoutType == type,
                    accent: accent,
                    onTap: () => _changeLayout(type),
                  ),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                if (isFreestyle) ...<Widget>[
                  _AddZoneChip(accent: accent, onTap: _addFreestyleZone),
                ] else ...<Widget>[
                  Text('${_zone.zones.length} zones',
                      style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
                  const SizedBox(width: 6),
                  _CountButton(icon: Icons.remove_rounded, onTap: _zone.zones.length > 1 ? _removeZone : null),
                  const SizedBox(width: 4),
                  _CountButton(icon: Icons.add_rounded, onTap: _zone.zones.length < 12 ? _addZone : null),
                ],
              ],
            ),
          ),

          // ── Gap ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.space_bar_rounded, size: 14, color: onSurface.withValues(alpha: 0.55)),
                const SizedBox(width: 6),
                Text('Gap between zones:', style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
                const SizedBox(width: 10),
                _GapSpinner(
                  value: _zone.gap,
                  onChanged: (int v) {
                    setState(() => _zone = _zone.copyWith(gap: v));
                    _commit();
                  },
                  accent: accent,
                ),
                const SizedBox(width: 8),
                Text('px', style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.55))),
                const SizedBox(width: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Applied as inset when snapping windows',
                    style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ),
          ),

          // ── Canvas ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 450),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: isFreestyle
                      ? _ZoneFreestyleCanvas(
                          zone: _zone,
                          accent: accent,
                          selectedZone: _selectedFreestyleZone,
                          onUpdated: (List<QuickGridRect> zones) {
                            setState(() => _zone = _zone.copyWith(zones: zones));
                            _commit();
                          },
                          onSelectionChanged: (int? idx) => setState(() => _selectedFreestyleZone = idx),
                        )
                      : _ZoneCanvas(
                          zone: _zone,
                          accent: accent,
                          onUpdated: (List<QuickGridRect> zones) {
                            setState(() => _zone = _zone.copyWith(zones: zones));
                            _commit();
                          },
                        ),
                ),
              ),
            ),
          ),

          // ── Freestyle sub-panel ─────────────────────────────
          if (isFreestyle) ...<Widget>[
            if (_selectedFreestyleZone != null && _selectedFreestyleZone! < _zone.zones.length) ...<Widget>[
              _ManualZoneEditor(
                key: const ValueKey<String>('mze-editor'),
                zoneIndex: _selectedFreestyleZone!,
                rect: _zone.zones[_selectedFreestyleZone!],
                allRects: _zone.zones,
                gap: _zone.gap,
                totalZones: _zone.zones.length,
                accent: accent,
                onChanged: (QuickGridRect r) => _updateFreestyleZone(_selectedFreestyleZone!, r),
                onDelete: () => _deleteFreestyleZone(_selectedFreestyleZone!),
              ),
            ] else ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.touch_app_rounded, size: 14, color: onSurface.withValues(alpha: 0.4)),
                    const SizedBox(width: 6),
                    Text(
                      _zone.zones.isEmpty
                          ? 'Tap "Add Zone" to create your first zone'
                          : 'Click a zone to select it · drag to move · drag handles to resize',
                      style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            ],
            // Zone chip list
            if (_zone.zones.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: _ZoneIndexList(zone: _zone, accent: accent),
              ),
          ] else ...<Widget>[
            // H/V hint + chip list
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              child: Row(
                children: <Widget>[
                  Icon(Icons.drag_indicator_rounded, size: 14, color: onSurface.withValues(alpha: 0.4)),
                  const SizedBox(width: 6),
                  Text('Drag the dividers to resize zones',
                      style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: _ZoneIndexList(zone: _zone, accent: accent),
            ),
          ],
        ],
      ),
    );
  }

  IconData _layoutIcon(QuickGridLayoutType type) {
    return switch (type) {
      QuickGridLayoutType.horizontal => Icons.view_column_rounded,
      QuickGridLayoutType.vertical => Icons.view_stream_rounded,
      QuickGridLayoutType.freestyle => Icons.crop_free_rounded,
    };
  }
}

// ============================================================
// Layout chip
// ============================================================

class _LayoutChip extends StatelessWidget {
  const _LayoutChip(
      {required this.label, required this.icon, required this.selected, required this.accent, required this.onTap});

  final String label;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? accent.withValues(alpha: 0.4) : onSurface.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: selected ? accent : onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                    color: selected ? accent : onSurface.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Add Zone Chip (freestyle)
// ============================================================

class _AddZoneChip extends StatelessWidget {
  const _AddZoneChip({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add_rounded, size: 14, color: accent),
            const SizedBox(width: 5),
            Text('Add Zone', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Count button (+/-)
// ============================================================

class _CountButton extends StatelessWidget {
  const _CountButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: onTap == null ? 0.04 : 0.09),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: onSurface.withValues(alpha: onTap == null ? 0.25 : 0.75)),
      ),
    );
  }
}

// ============================================================
// H/V Zone Canvas (divider drag)
// ============================================================

class _DivHit {
  const _DivHit(this.index, this.isVertical);
  final int index;
  final bool isVertical;
}

class _ZoneCanvas extends StatefulWidget {
  const _ZoneCanvas({required this.zone, required this.accent, required this.onUpdated});
  final QuickGrid zone;
  final Color accent;
  final void Function(List<QuickGridRect>) onUpdated;

  @override
  State<_ZoneCanvas> createState() => _ZoneCanvasState();
}

class _ZoneCanvasState extends State<_ZoneCanvas> {
  int _hoveredZone = -1;
  int _draggingDiv = -1;

  List<QuickGridRect> get _rects => widget.zone.zones;

  _DivHit? _hitTestDivider(Offset frac) {
    const double kTol = 0.028;
    final QuickGridLayoutType type = widget.zone.layoutType;
    for (int i = 0; i < _rects.length - 1; i++) {
      final QuickGridRect r = _rects[i];
      if (type == QuickGridLayoutType.horizontal) {
        if ((frac.dx - r.right).abs() < kTol && frac.dy >= r.top - kTol && frac.dy <= r.bottom + kTol) {
          return _DivHit(i, false);
        }
      } else {
        if ((frac.dy - r.bottom).abs() < kTol && frac.dx >= r.left - kTol && frac.dx <= r.right + kTol) {
          return _DivHit(i, true);
        }
      }
    }
    return null;
  }

  Offset _toFrac(Offset local, Size size) => Offset(local.dx / size.width, local.dy / size.height);

  void _startDrag(Offset frac) {
    final _DivHit? hit = _hitTestDivider(frac);
    if (hit == null) return;
    setState(() {
      _draggingDiv = hit.index;
    });
  }

  void _updateDrag(Offset frac) {
    if (_draggingDiv < 0 || _draggingDiv >= _rects.length - 1) return;
    final List<QuickGridRect> updated = _rects.map((QuickGridRect r) => r.copyWith()).toList();
    const double kMin = 0.05;
    if (widget.zone.layoutType == QuickGridLayoutType.horizontal) {
      final double nx = frac.dx.clamp(updated[_draggingDiv].left + kMin, updated[_draggingDiv + 1].right - kMin);
      updated[_draggingDiv] = updated[_draggingDiv].copyWith(right: nx);
      updated[_draggingDiv + 1] = updated[_draggingDiv + 1].copyWith(left: nx);
    } else {
      final double ny = frac.dy.clamp(updated[_draggingDiv].top + kMin, updated[_draggingDiv + 1].bottom - kMin);
      updated[_draggingDiv] = updated[_draggingDiv].copyWith(bottom: ny);
      updated[_draggingDiv + 1] = updated[_draggingDiv + 1].copyWith(top: ny);
    }
    setState(() {});
    widget.onUpdated(updated);
  }

  void _endDrag() => setState(() => _draggingDiv = -1);

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        final Size canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          onHover: (PointerEvent e) {
            final Offset frac = _toFrac(e.localPosition, canvasSize);
            int hov = -1;
            for (int i = 0; i < _rects.length; i++) {
              final QuickGridRect r = _rects[i];
              if (frac.dx >= r.left && frac.dx <= r.right && frac.dy >= r.top && frac.dy <= r.bottom) {
                hov = i;
                break;
              }
            }
            if (_hoveredZone != hov) setState(() => _hoveredZone = hov);
          },
          onExit: (_) => setState(() => _hoveredZone = -1),
          child: GestureDetector(
            onPanStart: (DragStartDetails d) => _startDrag(_toFrac(d.localPosition, canvasSize)),
            onPanUpdate: (DragUpdateDetails d) => _updateDrag(_toFrac(d.localPosition, canvasSize)),
            onPanEnd: (_) => _endDrag(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                size: canvasSize,
                painter: _HvCanvasPainter(
                  rects: _rects,
                  accent: accent,
                  onSurface: onSurface,
                  hoveredZone: _hoveredZone,
                  draggingDiv: _draggingDiv,
                  layoutType: widget.zone.layoutType,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HvCanvasPainter extends CustomPainter {
  _HvCanvasPainter({
    required this.rects,
    required this.accent,
    required this.onSurface,
    required this.hoveredZone,
    required this.draggingDiv,
    required this.layoutType,
  });

  final List<QuickGridRect> rects;
  final Color accent;
  final Color onSurface;
  final int hoveredZone;
  final int draggingDiv;
  final QuickGridLayoutType layoutType;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = onSurface.withValues(alpha: 0.05),
    );
    for (int i = 0; i < rects.length; i++) {
      final QuickGridRect r = rects[i];
      final bool hov = (i == hoveredZone);
      final Rect rect =
          Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);
      final RRect rr = RRect.fromRectAndRadius(rect.deflate(3), const Radius.circular(8));
      canvas.drawRRect(rr, Paint()..color = accent.withValues(alpha: hov ? 0.22 : 0.10));
      canvas.drawRRect(
          rr,
          Paint()
            ..color = accent.withValues(alpha: hov ? 0.65 : 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hov ? 1.5 : 1.0);
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style:
              TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent.withValues(alpha: hov ? 0.9 : 0.55)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
    for (int i = 0; i < rects.length - 1; i++) {
      final QuickGridRect r = rects[i];
      final bool isDrag = (i == draggingDiv);
      final Paint p = Paint()
        ..color = isDrag ? accent : accent.withValues(alpha: 0.45)
        ..strokeWidth = isDrag ? 2.5 : 1.5;
      if (layoutType == QuickGridLayoutType.horizontal) {
        final double x = r.right * size.width;
        canvas.drawLine(Offset(x, r.top * size.height + 6), Offset(x, r.bottom * size.height - 6), p);
        _drawGrip(canvas, Offset(x, size.height / 2), false, accent, isDrag);
      } else {
        final double y = r.bottom * size.height;
        canvas.drawLine(Offset(r.left * size.width + 6, y), Offset(r.right * size.width - 6, y), p);
        _drawGrip(canvas, Offset(size.width / 2, y), true, accent, isDrag);
      }
    }
  }

  void _drawGrip(Canvas canvas, Offset center, bool horiz, Color accent, bool active) {
    final Paint p = Paint()..color = active ? accent : accent.withValues(alpha: 0.6);
    for (int i = -1; i <= 1; i++) {
      final Offset o = horiz ? Offset(center.dx + i * 4, center.dy) : Offset(center.dx, center.dy + i * 4);
      canvas.drawCircle(o, 2, p);
    }
  }

  @override
  bool shouldRepaint(_HvCanvasPainter old) =>
      old.rects != rects || old.hoveredZone != hoveredZone || old.draggingDiv != draggingDiv;
}

// ============================================================
// Freestyle Canvas
// ============================================================

enum _DragMode { none, move, resize }

enum _ResizeDir { nw, n, ne, e, se, s, sw, w }

class _FHandle {
  const _FHandle({required this.dir, required this.cx, required this.cy});
  final _ResizeDir dir;
  final double cx;
  final double cy;
}

class _SnapGuide {
  const _SnapGuide({required this.pos, required this.isX});
  final double pos; // 0..1 fraction
  final bool isX; // true = vertical guide line (x=pos), false = horizontal (y=pos)
}

class _FHit {
  const _FHit({required this.idx, required this.dir});
  final int idx;
  final _ResizeDir? dir; // null = interior (move)
}

class _ZoneFreestyleCanvas extends StatefulWidget {
  const _ZoneFreestyleCanvas({
    required this.zone,
    required this.accent,
    required this.selectedZone,
    required this.onUpdated,
    required this.onSelectionChanged,
  });

  final QuickGrid zone;
  final Color accent;
  final int? selectedZone;
  final void Function(List<QuickGridRect>) onUpdated;
  final void Function(int?) onSelectionChanged;

  @override
  State<_ZoneFreestyleCanvas> createState() => _ZoneFreestyleCanvasState();
}

class _ZoneFreestyleCanvasState extends State<_ZoneFreestyleCanvas> {
  static const double kHandlePx = 7.0;
  static const double kSnapThr = 0.01;
  static const double kMinSize = 0.06;

  int? _hoveredZone;
  int? _dragZone;
  _DragMode _dragMode = _DragMode.none;
  _ResizeDir? _resizeDir;
  Offset? _dragStartFrac;
  QuickGridRect? _dragStartRect;
  MouseCursor _cursor = SystemMouseCursors.basic;
  List<_SnapGuide> _guides = <_SnapGuide>[];
  Size _canvasSize = Size.zero;
  Offset? _lastTapDown;

  List<QuickGridRect> get _rects => widget.zone.zones;

  Offset _toFrac(Offset local) => Offset(local.dx / _canvasSize.width, local.dy / _canvasSize.height);

  // ── Snap helpers ───────────────────────────────────────────

  List<double> _xCands(int excl) {
    final List<double> t = <double>[0.0, 1.0];
    for (int i = 0; i < _rects.length; i++) {
      if (i == excl) continue;
      t.add(_rects[i].left);
      t.add(_rects[i].right);
    }
    return t;
  }

  List<double> _yCands(int excl) {
    final List<double> t = <double>[0.0, 1.0];
    for (int i = 0; i < _rects.length; i++) {
      if (i == excl) continue;
      t.add(_rects[i].top);
      t.add(_rects[i].bottom);
    }
    return t;
  }

  double _sx(double v, int excl, List<_SnapGuide> guides) {
    for (final double t in _xCands(excl)) {
      if ((v - t).abs() < kSnapThr) {
        guides.add(_SnapGuide(pos: t, isX: true));
        return t;
      }
    }
    return v;
  }

  double _sy(double v, int excl, List<_SnapGuide> guides) {
    for (final double t in _yCands(excl)) {
      if ((v - t).abs() < kSnapThr) {
        guides.add(_SnapGuide(pos: t, isX: false));
        return t;
      }
    }
    return v;
  }

  // ── Handle positions ────────────────────────────────────────

  List<_FHandle> _handles(QuickGridRect r) {
    final double mx = (r.left + r.right) / 2;
    final double my = (r.top + r.bottom) / 2;
    return <_FHandle>[
      _FHandle(dir: _ResizeDir.nw, cx: r.left, cy: r.top),
      _FHandle(dir: _ResizeDir.n, cx: mx, cy: r.top),
      _FHandle(dir: _ResizeDir.ne, cx: r.right, cy: r.top),
      _FHandle(dir: _ResizeDir.e, cx: r.right, cy: my),
      _FHandle(dir: _ResizeDir.se, cx: r.right, cy: r.bottom),
      _FHandle(dir: _ResizeDir.s, cx: mx, cy: r.bottom),
      _FHandle(dir: _ResizeDir.sw, cx: r.left, cy: r.bottom),
      _FHandle(dir: _ResizeDir.w, cx: r.left, cy: my),
    ];
  }

  // ── Hit test ────────────────────────────────────────────────

  _FHit? _hitTest(Offset frac) {
    final double hw = kHandlePx / _canvasSize.width;
    final double hh = kHandlePx / _canvasSize.height;
    // Handles on selected zone take priority
    final int? sel = widget.selectedZone;
    if (sel != null && sel < _rects.length) {
      for (final _FHandle h in _handles(_rects[sel])) {
        if ((frac.dx - h.cx).abs() <= hw && (frac.dy - h.cy).abs() <= hh) {
          return _FHit(idx: sel, dir: h.dir);
        }
      }
    }
    // Zone interiors (topmost = last index wins)
    for (int i = _rects.length - 1; i >= 0; i--) {
      final QuickGridRect r = _rects[i];
      if (frac.dx >= r.left && frac.dx <= r.right && frac.dy >= r.top && frac.dy <= r.bottom) {
        return _FHit(idx: i, dir: null);
      }
    }
    return null;
  }

  MouseCursor _cursorForHit(_FHit? hit) {
    if (hit == null) return SystemMouseCursors.basic;
    if (hit.dir == null) return SystemMouseCursors.move;
    return switch (hit.dir!) {
      _ResizeDir.n || _ResizeDir.s => SystemMouseCursors.resizeUpDown,
      _ResizeDir.e || _ResizeDir.w => SystemMouseCursors.resizeLeftRight,
      _ResizeDir.nw || _ResizeDir.se => SystemMouseCursors.resizeUpLeftDownRight,
      _ResizeDir.ne || _ResizeDir.sw => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }

  // ── Drag logic ──────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    if (_canvasSize == Size.zero) return;
    final Offset frac = _toFrac(d.localPosition);
    final _FHit? hit = _hitTest(frac);
    if (hit == null) {
      widget.onSelectionChanged(null);
      return;
    }
    widget.onSelectionChanged(hit.idx);
    setState(() {
      _dragZone = hit.idx;
      _dragMode = hit.dir == null ? _DragMode.move : _DragMode.resize;
      _resizeDir = hit.dir;
      _dragStartFrac = frac;
      _dragStartRect = _rects[hit.idx].copyWith();
      _guides = <_SnapGuide>[];
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_dragZone == null || _dragStartFrac == null || _dragStartRect == null) return;
    final Offset frac = _toFrac(d.localPosition);
    final Offset delta = frac - _dragStartFrac!;
    final QuickGridRect s = _dragStartRect!;
    final int idx = _dragZone!;
    final List<_SnapGuide> guides = <_SnapGuide>[];
    final List<QuickGridRect> updated = _rects.map((QuickGridRect r) => r.copyWith()).toList();

    if (_dragMode == _DragMode.move) {
      final double w = s.right - s.left;
      final double h = s.bottom - s.top;
      double nl = (s.left + delta.dx).clamp(0.0, 1.0 - w);
      double nt = (s.top + delta.dy).clamp(0.0, 1.0 - h);

      // Try snapping each edge
      final double sl = _sx(nl, idx, guides);
      final double sr = _sx(nl + w, idx, guides);
      if (sl != nl) {
        nl = sl;
      } else if (sr != nl + w) {
        nl = sr - w;
      }
      final double st = _sy(nt, idx, guides);
      final double sb = _sy(nt + h, idx, guides);
      if (st != nt) {
        nt = st;
      } else if (sb != nt + h) {
        nt = sb - h;
      }

      nl = nl.clamp(0.0, 1.0 - w);
      nt = nt.clamp(0.0, 1.0 - h);
      updated[idx] = QuickGridRect(left: nl, top: nt, right: nl + w, bottom: nt + h);
    } else {
      double l = s.left, t = s.top, r = s.right, b = s.bottom;
      switch (_resizeDir!) {
        case _ResizeDir.nw:
          l = _sx((s.left + delta.dx).clamp(0, r - kMinSize), idx, guides);
          t = _sy((s.top + delta.dy).clamp(0, b - kMinSize), idx, guides);
        case _ResizeDir.n:
          t = _sy((s.top + delta.dy).clamp(0, b - kMinSize), idx, guides);
        case _ResizeDir.ne:
          r = _sx((s.right + delta.dx).clamp(l + kMinSize, 1), idx, guides);
          t = _sy((s.top + delta.dy).clamp(0, b - kMinSize), idx, guides);
        case _ResizeDir.e:
          r = _sx((s.right + delta.dx).clamp(l + kMinSize, 1), idx, guides);
        case _ResizeDir.se:
          r = _sx((s.right + delta.dx).clamp(l + kMinSize, 1), idx, guides);
          b = _sy((s.bottom + delta.dy).clamp(t + kMinSize, 1), idx, guides);
        case _ResizeDir.s:
          b = _sy((s.bottom + delta.dy).clamp(t + kMinSize, 1), idx, guides);
        case _ResizeDir.sw:
          l = _sx((s.left + delta.dx).clamp(0, r - kMinSize), idx, guides);
          b = _sy((s.bottom + delta.dy).clamp(t + kMinSize, 1), idx, guides);
        case _ResizeDir.w:
          l = _sx((s.left + delta.dx).clamp(0, r - kMinSize), idx, guides);
      }
      updated[idx] = QuickGridRect(left: l, top: t, right: r, bottom: b);
    }

    setState(() => _guides = guides);
    widget.onUpdated(updated);
  }

  void _onPanEnd(DragEndDetails _) {
    setState(() {
      _dragZone = null;
      _dragMode = _DragMode.none;
      _resizeDir = null;
      _dragStartFrac = null;
      _dragStartRect = null;
      _guides = <_SnapGuide>[];
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return LayoutBuilder(
      builder: (BuildContext ctx, BoxConstraints constraints) {
        _canvasSize = Size(constraints.maxWidth, constraints.maxHeight);

        return MouseRegion(
          cursor: _cursor,
          onHover: (PointerEvent e) {
            final Offset frac = _toFrac(e.localPosition);
            final _FHit? hit = _hitTest(frac);
            final MouseCursor nc = _cursorForHit(hit);
            int? hov;
            for (int i = _rects.length - 1; i >= 0; i--) {
              final QuickGridRect r = _rects[i];
              if (frac.dx >= r.left && frac.dx <= r.right && frac.dy >= r.top && frac.dy <= r.bottom) {
                hov = i;
                break;
              }
            }
            if (nc != _cursor || hov != _hoveredZone) {
              setState(() {
                _cursor = nc;
                _hoveredZone = hov;
              });
            }
          },
          onExit: (_) => setState(() {
            _cursor = SystemMouseCursors.basic;
            _hoveredZone = null;
          }),
          child: GestureDetector(
            onTapDown: (TapDownDetails d) => _lastTapDown = d.localPosition,
            onTap: () {
              if (_lastTapDown == null) return;
              final Offset frac = _toFrac(_lastTapDown!);
              widget.onSelectionChanged(_hitTest(frac)?.idx);
              _lastTapDown = null;
            },
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                size: _canvasSize,
                painter: _FreestylePainter(
                  rects: _rects,
                  accent: accent,
                  onSurface: onSurface,
                  selectedZone: widget.selectedZone,
                  hoveredZone: _hoveredZone,
                  handlePx: kHandlePx,
                  guides: _guides,
                  canvasSize: _canvasSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FreestylePainter extends CustomPainter {
  _FreestylePainter({
    required this.rects,
    required this.accent,
    required this.onSurface,
    required this.selectedZone,
    required this.hoveredZone,
    required this.handlePx,
    required this.guides,
    required this.canvasSize,
  });

  final List<QuickGridRect> rects;
  final Color accent;
  final Color onSurface;
  final int? selectedZone;
  final int? hoveredZone;
  final double handlePx;
  final List<_SnapGuide> guides;
  final Size canvasSize;

  @override
  void paint(Canvas canvas, Size size) {
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)),
      Paint()..color = onSurface.withValues(alpha: 0.05),
    );

    // Subtle grid reference dots
    const int gridLines = 4;
    final Paint dotPaint = Paint()..color = onSurface.withValues(alpha: 0.08);
    for (int gx = 1; gx < gridLines; gx++) {
      for (int gy = 1; gy < gridLines; gy++) {
        canvas.drawCircle(Offset(size.width * gx / gridLines, size.height * gy / gridLines), 1.5, dotPaint);
      }
    }

    // Draw zones: non-selected first, then selected on top
    final List<int> order = <int>[
      for (int i = 0; i < rects.length; i++)
        if (i != selectedZone) i,
      if (selectedZone != null && selectedZone! < rects.length) selectedZone!,
    ];

    for (final int i in order) {
      final QuickGridRect r = rects[i];
      final bool isSel = i == selectedZone;
      final bool isHov = i == hoveredZone && !isSel;
      final Rect rect =
          Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height);
      final RRect rr = RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(8));

      // Shadow for selected
      if (isSel) {
        canvas.drawRRect(
          rr.inflate(3),
          Paint()
            ..color = accent.withValues(alpha: 0.20)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }

      // Fill
      canvas.drawRRect(
          rr,
          Paint()
            ..color = isSel
                ? accent.withValues(alpha: 0.22)
                : isHov
                    ? accent.withValues(alpha: 0.15)
                    : accent.withValues(alpha: 0.09));

      // Border
      canvas.drawRRect(
          rr,
          Paint()
            ..color = isSel
                ? accent.withValues(alpha: 0.80)
                : isHov
                    ? accent.withValues(alpha: 0.50)
                    : accent.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isSel ? 1.8 : 1.0);

      // Zone number
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: accent.withValues(alpha: isSel ? 0.95 : 0.55)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));

      // Resize handles for selected zone
      if (isSel) {
        _drawHandles(canvas, r, size);
      }
    }

    // Snap guide lines
    for (final _SnapGuide g in guides) {
      // Skip border lines (0 and 1) to reduce noise
      if (g.pos < 0.001 || g.pos > 0.999) continue;
      final Paint gPaint = Paint()
        ..color = accent.withValues(alpha: 0.75)
        ..strokeWidth = 1.0;
      if (g.isX) {
        canvas.drawLine(Offset(g.pos * size.width, 0), Offset(g.pos * size.width, size.height), gPaint);
      } else {
        canvas.drawLine(Offset(0, g.pos * size.height), Offset(size.width, g.pos * size.height), gPaint);
      }
      // Small diamond at the snap point
      final double px = g.isX ? g.pos * size.width : size.width / 2;
      final double py = g.isX ? size.height / 2 : g.pos * size.height;
      _drawDiamond(canvas, Offset(px, py), accent);
    }
  }

  void _drawHandles(Canvas canvas, QuickGridRect r, Size size) {
    final double mx = (r.left + r.right) / 2;
    final double my = (r.top + r.bottom) / 2;
    final List<Offset> positions = <Offset>[
      Offset(r.left * size.width, r.top * size.height),
      Offset(mx * size.width, r.top * size.height),
      Offset(r.right * size.width, r.top * size.height),
      Offset(r.right * size.width, my * size.height),
      Offset(r.right * size.width, r.bottom * size.height),
      Offset(mx * size.width, r.bottom * size.height),
      Offset(r.left * size.width, r.bottom * size.height),
      Offset(r.left * size.width, my * size.height),
    ];
    for (final Offset pos in positions) {
      final Rect hRect = Rect.fromCenter(center: pos, width: handlePx * 2, height: handlePx * 2);
      canvas.drawRRect(RRect.fromRectAndRadius(hRect, const Radius.circular(3)), Paint()..color = accent);
      canvas.drawRRect(
          RRect.fromRectAndRadius(hRect, const Radius.circular(3)),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void _drawDiamond(Canvas canvas, Offset center, Color color) {
    final Path path = Path()
      ..moveTo(center.dx, center.dy - 5)
      ..lineTo(center.dx + 5, center.dy)
      ..lineTo(center.dx, center.dy + 5)
      ..lineTo(center.dx - 5, center.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.85));
  }

  @override
  bool shouldRepaint(_FreestylePainter old) =>
      old.rects != rects ||
      old.selectedZone != selectedZone ||
      old.hoveredZone != hoveredZone ||
      old.guides.length != guides.length;
}

// ============================================================
// Manual Zone Editor
// ============================================================

class _ManualZoneEditor extends StatelessWidget {
  const _ManualZoneEditor({
    super.key,
    required this.zoneIndex,
    required this.rect,
    required this.allRects,
    required this.gap,
    required this.totalZones,
    required this.accent,
    required this.onChanged,
    required this.onDelete,
  });

  final int zoneIndex;
  final QuickGridRect rect;
  final List<QuickGridRect> allRects;
  final int gap;
  final int totalZones;
  final Color accent;
  final void Function(QuickGridRect) onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    final double lPct = rect.left * 100;
    final double tPct = rect.top * 100;
    final double wPct = (rect.right - rect.left) * 100;
    final double hPct = (rect.bottom - rect.top) * 100;
    final double rPct = rect.right * 100;
    final double bPct = rect.bottom * 100;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Header row
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.layers_rounded, size: 12, color: accent),
                    const SizedBox(width: 5),
                    Text('Zone ${zoneIndex + 1}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                  ],
                ),
              ),
              const Spacer(),
              if (totalZones > 1)
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.delete_outline_rounded, size: 14, color: theme.colorScheme.error),
                        const SizedBox(width: 4),
                        Text('Delete', style: TextStyle(fontSize: 11, color: theme.colorScheme.error)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Position + size fields
          Row(
            children: <Widget>[
              _PctField(
                key: ValueKey<String>('L-$zoneIndex'),
                label: 'Left',
                value: lPct,
                onChanged: (double v) => onChanged(rect.copyWith(left: (v / 100).clamp(0.0, rect.right - 0.06))),
              ),
              const SizedBox(width: 8),
              _PctField(
                key: ValueKey<String>('T-$zoneIndex'),
                label: 'Top',
                value: tPct,
                onChanged: (double v) => onChanged(rect.copyWith(top: (v / 100).clamp(0.0, rect.bottom - 0.06))),
              ),
              const SizedBox(width: 8),
              _PctField(
                key: ValueKey<String>('W-$zoneIndex'),
                label: 'Width',
                value: wPct,
                onChanged: (double v) =>
                    onChanged(rect.copyWith(right: (rect.left + v / 100).clamp(rect.left + 0.06, 1.0))),
              ),
              const SizedBox(width: 8),
              _PctField(
                key: ValueKey<String>('H-$zoneIndex'),
                label: 'Height',
                value: hPct,
                onChanged: (double v) =>
                    onChanged(rect.copyWith(bottom: (rect.top + v / 100).clamp(rect.top + 0.06, 1.0))),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Right / Bottom info row (selectable for gap comparison) ────
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _InfoChip(
                label: 'Right edge',
                value: '${rPct.toStringAsFixed(1)}%',
                icon: Icons.align_horizontal_right_rounded,
                accent: accent,
              ),
              _InfoChip(
                label: 'Bottom edge',
                value: '${bPct.toStringAsFixed(1)}%',
                icon: Icons.align_vertical_bottom_rounded,
                accent: accent,
              ),
              if (gap > 0)
                _InfoChip(
                  label: 'Gap applied',
                  value: '${gap}px / side',
                  icon: Icons.space_bar_rounded,
                  accent: accent,
                  faint: true,
                ),
              // Neighbour comparisons
              for (int i = 0; i < allRects.length; i++) ...<Widget>[
                if (i != zoneIndex) ...<Widget>[
                  if ((allRects[i].left - rect.right).abs() < 0.15)
                    _InfoChip(
                      label: 'Gap → Z${i + 1}',
                      value: '${((allRects[i].left - rect.right) * 100).toStringAsFixed(1)}%',
                      icon: Icons.swap_horiz_rounded,
                      accent: accent,
                      faint: true,
                    ),
                  if ((allRects[i].top - rect.bottom).abs() < 0.15)
                    _InfoChip(
                      label: 'Gap ↓ Z${i + 1}',
                      value: '${((allRects[i].top - rect.bottom) * 100).toStringAsFixed(1)}%',
                      icon: Icons.swap_vert_rounded,
                      accent: accent,
                      faint: true,
                    ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Summary text
          SelectableText(
            'L:${lPct.toStringAsFixed(1)}%  T:${tPct.toStringAsFixed(1)}%  R:${rPct.toStringAsFixed(1)}%  B:${bPct.toStringAsFixed(1)}%  W:${wPct.toStringAsFixed(1)}%  H:${hPct.toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5), fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Percentage field
// ============================================================

class _PctField extends StatefulWidget {
  const _PctField({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final double value; // 0–100
  final void Function(double) onChanged;

  @override
  State<_PctField> createState() => _PctFieldState();
}

class _PctFieldState extends State<_PctField> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_PctField old) {
    super.didUpdateWidget(old);
    if (!_focused) {
      final double? parsed = double.tryParse(_ctrl.text);
      if (parsed == null || (parsed - widget.value).abs() > 0.01) {
        _ctrl.text = _fmt(widget.value);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) => v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: Focus(
              onFocusChange: (bool f) => setState(() => _focused = f),
              child: TextField(
                controller: _ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}\.?\d{0,1}')),
                ],
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  suffixText: '%',
                  suffixStyle: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.5)),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
                onChanged: (String v) {
                  final double? d = double.tryParse(v);
                  if (d != null) widget.onChanged(d.clamp(0.0, 100.0));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Gap Spinner
// ============================================================

class _GapSpinner extends StatefulWidget {
  const _GapSpinner({required this.value, required this.onChanged, required this.accent});
  final int value;
  final void Function(int) onChanged;
  final Color accent;

  @override
  State<_GapSpinner> createState() => _GapSpinnerState();
}

class _GapSpinnerState extends State<_GapSpinner> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(_GapSpinner old) {
    super.didUpdateWidget(old);
    if (!_focused) {
      final int? parsed = int.tryParse(_ctrl.text);
      if (parsed != widget.value) {
        _ctrl.text = widget.value.toString();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 30,
      child: Row(
        children: <Widget>[
          _SpinBtn(
            icon: Icons.remove_rounded,
            onTap: widget.value > 0 ? () => widget.onChanged(widget.value - 1) : null,
            accent: globalSettings.themeColors.accentColor,
          ),
          Expanded(
            child: Focus(
              onFocusChange: (bool f) => setState(() => _focused = f),
              child: TextField(
                controller: _ctrl,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: globalSettings.themeColors.accentColor, width: 1.5),
                  ),
                ),
                onChanged: (String v) {
                  final int? d = int.tryParse(v);
                  if (d != null) widget.onChanged(d.clamp(0, 200));
                },
              ),
            ),
          ),
          _SpinBtn(
            icon: Icons.add_rounded,
            onTap: widget.value < 200 ? () => widget.onChanged(widget.value + 1) : null,
            accent: globalSettings.themeColors.accentColor,
          ),
        ],
      ),
    );
  }
}

class _SpinBtn extends StatelessWidget {
  const _SpinBtn({required this.icon, required this.onTap, required this.accent});
  final IconData icon;
  final VoidCallback? onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 22,
        height: 30,
        child: Icon(icon,
            size: 14, color: onTap == null ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25) : accent),
      ),
    );
  }
}

// ============================================================
// Info Chip (selectable)
// ============================================================

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    this.faint = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return CustomTooltip(
      message: 'Click to select text and copy',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: faint ? onSurface.withValues(alpha: 0.05) : accent.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: faint ? onSurface.withValues(alpha: 0.10) : accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 11, color: faint ? onSurface.withValues(alpha: 0.45) : accent.withValues(alpha: 0.8)),
            const SizedBox(width: 4),
            Text('$label: ', style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: faint ? 0.45 : 0.65))),
            SelectableText(
              value,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: faint ? onSurface.withValues(alpha: 0.65) : accent),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Zone Index List
// ============================================================

class _ZoneIndexList extends StatelessWidget {
  const _ZoneIndexList({required this.zone, required this.accent});
  final QuickGrid zone;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Zone summary',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: onSurface.withValues(alpha: 0.65))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              for (int i = 0; i < zone.zones.length; i++) _ZoneChip(index: i, rect: zone.zones[i], accent: accent),
            ],
          ),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.index, required this.rect, required this.accent});
  final int index;
  final QuickGridRect rect;
  final Color accent;

  String _p(double v) => '${(v * 100).toStringAsFixed(1)}%';

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: SelectableText.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: 'Z${index + 1}  ',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent),
            ),
            TextSpan(
              text: 'L:${_p(rect.left)}  T:${_p(rect.top)}  '
                  'R:${_p(rect.right)}  B:${_p(rect.bottom)}  '
                  'W:${_p(rect.right - rect.left)}  H:${_p(rect.bottom - rect.top)}',
              style: TextStyle(fontSize: 10, color: onSurface.withValues(alpha: 0.70)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Empty State
// ============================================================

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(Icons.view_quilt_rounded, color: accent, size: 28),
          ),
          const SizedBox(height: 12),
          Text('No zone presets yet',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            'Create a preset to define screen zones.\nThen snap any window into a zone from the QuickMenu.',
            style: theme.textTheme.bodySmall?.copyWith(color: onSurface.withValues(alpha: 0.65)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create First Preset'),
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _GridSettingsTile extends StatelessWidget {
  const _GridSettingsTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 80,
                height: 50,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Icon(Icons.grid_4x4_rounded, color: accent, size: 24)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Grid Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(height: 3),
                    Text('Configure subdivisions, density and scroll scaling',
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.6))),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: accent.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}
