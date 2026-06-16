import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import 'inkwell_button.dart';

class PanelOpacityGradientEditor extends StatefulWidget {
  final String begin;
  final String end;
  final List<double> points;
  final ValueChanged<List<double>> onChanged;
  final ValueChanged<String> onBeginChanged;
  final ValueChanged<String> onEndChanged;

  const PanelOpacityGradientEditor({
    super.key,
    required this.points,
    required this.begin,
    required this.end,
    required this.onChanged,
    required this.onBeginChanged,
    required this.onEndChanged,
  });

  @override
  State<PanelOpacityGradientEditor> createState() => _PanelOpacityGradientEditorState();
}

class _PanelOpacityGradientEditorState extends State<PanelOpacityGradientEditor> {
  late List<_OpacityPoint> _workingPoints;

  @override
  void initState() {
    super.initState();
    _loadPoints();
  }

  @override
  void didUpdateWidget(PanelOpacityGradientEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(widget.points, oldWidget.points)) {
      _loadPoints();
    }
  }

  void _loadPoints() {
    _workingPoints = <_OpacityPoint>[];
    for (int i = 0; i < widget.points.length; i += 2) {
      if (i + 1 < widget.points.length) {
        _workingPoints.add(_OpacityPoint(stop: widget.points[i], opacity: widget.points[i + 1]));
      }
    }
    _workingPoints.sort((_OpacityPoint a, _OpacityPoint b) => a.stop.compareTo(b.stop));
  }

  void _notify() {
    final List<double> flat = <double>[];
    _workingPoints.sort((_OpacityPoint a, _OpacityPoint b) => a.stop.compareTo(b.stop));
    for (final _OpacityPoint p in _workingPoints) {
      flat.add(p.stop);
      flat.add(p.opacity);
    }
    widget.onChanged(flat);
  }

  void _addPoint() {
    setState(() {
      _workingPoints.add(_OpacityPoint(stop: 0.5, opacity: 1.0));
      _notify();
    });
  }

  void _removePoint(int index) {
    if (_workingPoints.length <= 2) return;
    setState(() {
      _workingPoints.removeAt(index);
      _notify();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Preview Bar
        Container(
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: onSurface.withAlpha(20)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Stack(
              children: <Widget>[
                // Checkerboard background for transparency preview
                Container(
                  color: onSurface.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: panelAlignmentMap[widget.begin] ?? Alignment.topCenter,
                      end: panelAlignmentMap[widget.end] ?? Alignment.bottomCenter,
                      colors: _workingPoints
                          .map(
                              (_OpacityPoint p) => onSurface.withValues(alpha: (p.opacity * 1.5 - 0.5).clamp(0.0, 1.0)))
                          .toList(),
                      stops: _workingPoints.map((_OpacityPoint p) => p.stop).toList(),
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Points List
        ..._workingPoints.asMap().entries.map((MapEntry<int, _OpacityPoint> entry) {
          final int idx = entry.key;
          final _OpacityPoint point = entry.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  flex: 2,
                  child: _MiniSlider(
                    label: "Stop",
                    value: point.stop,
                    accent: accent,
                    onChanged: (double val) {
                      setState(() {
                        point.stop = val;
                        _notify();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _MiniSlider(
                    label: "Opacity",
                    value: point.opacity,
                    min: 0.5,
                    max: 1.0,
                    accent: accent,
                    onChanged: (double val) {
                      setState(() {
                        point.opacity = val;
                        _notify();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _workingPoints.length > 2 ? () => _removePoint(idx) : null,
                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                  color: Colors.red.withAlpha(200),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        InkWellButton(
          onTap: _addPoint,
          label: "Add Transparency Point",
          icon: Icons.add_rounded,
          color: accent,
          mainAxisSize: MainAxisSize.max,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        ),
        const SizedBox(height: 12),
        // Alignment Selectors
        Row(
          children: <Widget>[
            Expanded(
              child: _AlignmentSelector(
                label: "Begin",
                value: widget.begin,
                accent: accent,
                onChanged: widget.onBeginChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AlignmentSelector(
                label: "End",
                value: widget.end,
                accent: accent,
                onChanged: widget.onEndChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OpacityPoint {
  double stop;
  double opacity;
  _OpacityPoint({required this.stop, required this.opacity});
}

class _MiniSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color accent;
  final ValueChanged<double> onChanged;

  const _MiniSlider({
    required this.label,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(150), fontWeight: FontWeight.w600)),
            Text("${(value * 100).toInt()}%",
                style: TextStyle(fontSize: Design.baseFontSize, color: accent, fontWeight: FontWeight.bold)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: accent.withAlpha(200),
            inactiveTrackColor: onSurface.withAlpha(20),
            thumbColor: accent,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _AlignmentSelector extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;

  const _AlignmentSelector({
    required this.label,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label,
            style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: onSurface.withValues(alpha: 0.1)),
          ),
          child: PopupMenuButton<String>(
            initialValue: value,
            tooltip: "Select Alignment",
            onSelected: onChanged,
            offset: const Offset(0, 30),
            padding: EdgeInsets.zero,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.zero),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.9)),
                    ),
                  ),
                  Icon(Icons.unfold_more_rounded, size: 14, color: accent.withValues(alpha: 0.7)),
                ],
              ),
            ),
            itemBuilder: (BuildContext context) {
              return panelAlignmentMap.keys.map((String key) {
                return PopupMenuItem<String>(
                  value: key,
                  child: Text(
                    key,
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: key == value ? FontWeight.w700 : FontWeight.w500,
                      color: key == value ? accent : onSurface,
                    ),
                  ),
                );
              }).toList();
            },
          ),
        ),
      ],
    );
  }
}
