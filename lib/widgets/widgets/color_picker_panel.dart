import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/util/color_picker_controller.dart';
import '../../models/win32/win_utils.dart';
import 'custom_tooltip.dart';
import 'panel_header.dart';
import 'windows_scroll.dart';

enum ColorOutputFormat {
  hex('HEX'),
  rgb('RGB'),
  hsl('HSL'),
  cmyk('CMYK'),
  oklch('OKLCH');

  const ColorOutputFormat(this.label);

  final String label;
}

class ColorPickerPanel extends StatefulWidget {
  const ColorPickerPanel({super.key, this.onPickRequested, this.onClose, this.isStandalone = false});

  final VoidCallback? onPickRequested;
  final bool isStandalone;
  final VoidCallback? onClose;

  @override
  State<ColorPickerPanel> createState() => _ColorPickerPanelState();
}

class _ColorPickerPanelState extends State<ColorPickerPanel> {
  final ColorPickerController _controller = ColorPickerController.instance;

  ColorPickerCapture? _lastCapture;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  ColorOutputFormat _selectedFormat = ColorOutputFormat.hex;
  String? _copiedMessage;
  Timer? _copiedTimer;
  final ScrollController _formatScrollController = ScrollController();
  final Map<String, String> _colorNameCache = <String, String>{};
  String? _selectedColorName;
  String? _selectedColorHexForName;
  bool _isFetchingColorName = false;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.loadCapture());
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _formatScrollController.dispose();
    super.dispose();
  }

  void _syncSelection(ColorPickerCapture? capture) {
    if (capture == null || identical(_lastCapture, capture)) return;
    _lastCapture = capture;
    _selectedRow = capture.centerRow;
    _selectedColumn = capture.centerColumn;
  }

  Future<void> _copyOutput(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _copiedTimer?.cancel();
    setState(() {
      _copiedMessage = "Copied";
    });
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _copiedMessage = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final ColorPickerCapture? capture = _controller.capture;
        _syncSelection(capture);
        final ColorGridSample? sample = _selectedSample(capture);
        final String? formattedValue = sample == null ? null : _formatSample(sample, _selectedFormat);
        _syncColorName(sample);

        return Material(
          color: Colors.transparent,
          child: DragToResizeArea(
            enableResizeEdges: widget.isStandalone
                ? <ResizeEdge>[
                    ResizeEdge.left,
                    ResizeEdge.right,
                    ResizeEdge.top,
                    ResizeEdge.bottom,
                    ResizeEdge.topLeft,
                    ResizeEdge.topRight,
                    ResizeEdge.bottomLeft,
                    ResizeEdge.bottomRight,
                  ]
                : <ResizeEdge>[],
            resizeEdgeSize: widget.isStandalone ? 10 : 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (DragStartDetails details) {
                    windowManager.startDragging();
                  },
                  child: PanelHeader(
                    title: "Color Picker",
                    accent: accent,
                    icon: Icons.palette_outlined,
                    extraActions: <Widget>[
                      CustomTooltip(
                        message: "Refresh",
                        child: IconButton(
                          onPressed: _controller.loadCapture,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          iconSize: 14,
                          icon: Icon(Icons.refresh_rounded, color: accent),
                        ),
                      ),
                    ],
                    buttonPressed: widget.onClose,
                    buttonIcon: Icons.close_rounded,
                    buttonTooltip: "Close",
                  ),
                ),
                Expanded(
                  child: WindowsScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FilledButton.icon(
                          onPressed: widget.onPickRequested ??
                              () {
                                WinUtils.startTabame(closeCurrent: false, arguments: "-colorPicker");
                                QuickMenuFunctions.toggleQuickMenu(visible: false);
                              },
                          icon: const Icon(Icons.colorize_rounded, size: 16),
                          label: const Text("Pick color"),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (capture == null)
                          _buildEmptyState()
                        else ...<Widget>[
                          _buildFormatSelector(),
                          const SizedBox(height: 10),
                          _buildPreviewCard(capture, sample, formattedValue),
                          const SizedBox(height: 10),
                          _buildGridCard(capture),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _syncColorName(ColorGridSample? sample) {
    if (sample == null) return;

    final String hex = sample.hex.replaceAll('#', '').toLowerCase();
    if (_selectedColorHexForName == hex) return;

    _selectedColorHexForName = hex;
    _selectedColorName = _colorNameCache[hex];
    _isFetchingColorName = _selectedColorName == null;

    if (_selectedColorName != null) return;

    unawaited(_fetchColorName(hex));
  }

  Future<void> _fetchColorName(String hex) async {
    try {
      final Uri uri = Uri.parse('https://www.thecolorapi.com/id?hex=$hex');
      final http.Response response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Color API returned ${response.statusCode}');
      }

      final Map<String, dynamic> json = (jsonDecode(response.body) as Map<dynamic, dynamic>).cast<String, dynamic>();
      final Map<String, dynamic> name =
          (json['name'] as Map<dynamic, dynamic>? ?? <dynamic, dynamic>{}).cast<String, dynamic>();
      final String fetchedName = ((name['value'] as String?) ?? '').trim();
      final String resolvedName = fetchedName.isEmpty ? 'Unknown color' : fetchedName;

      _colorNameCache[hex] = resolvedName;
      if (!mounted || _selectedColorHexForName != hex) return;
      setState(() {
        _selectedColorName = resolvedName;
        _isFetchingColorName = false;
      });
    } catch (_) {
      if (!mounted || _selectedColorHexForName != hex) return;
      setState(() {
        _selectedColorName = 'Unknown color';
        _isFetchingColorName = false;
      });
    }
  }

  Widget _buildEmptyState() {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.grid_view_rounded, size: 30, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85)),
          const SizedBox(height: 10),
          const Text(
            "Pick any pixel on screen",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            "The external picker samples the center color and the surrounding grid. When it closes, the grid loads here so you can inspect each cell.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: onSurface.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(ColorPickerCapture capture, ColorGridSample? sample, String? formattedValue) {
    final ColorGridSample selectedSample = sample ?? capture.center;
    final Color swatch = selectedSample.color;
    final String displayValue = formattedValue ?? selectedSample.hex;
    final String colorNameText = _isFetchingColorName ? 'Searching ...' : (_selectedColorName ?? 'Unknown color');

    return InkWell(
      onTap: formattedValue == null ? null : () => _copyOutput(formattedValue),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: swatch.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: swatch.withValues(alpha: 0.32)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: swatch.withValues(alpha: 0.16),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: swatch,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.55)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          displayValue,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.42),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.16),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          _isFetchingColorName ? Icons.hourglass_top_rounded : Icons.badge_outlined,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.64),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _copiedMessage ?? colorNameText,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridCard(ColorPickerCapture capture) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double squareSize = math.min(constraints.maxWidth, 250);
              return Center(
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTapDown: (TapDownDetails details) => _selectCell(details.localPosition, squareSize, capture),
                    child: SizedBox(
                      width: squareSize,
                      height: squareSize,
                      child: CustomPaint(
                        painter: _ColorGridPainter(
                          capture: capture,
                          selectedRow: _selectedRow,
                          selectedColumn: _selectedColumn,
                          accent: Theme.of(context).colorScheme.primary,
                          outline: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            "Tap any sampled square to inspect it. The accent outline marks the center pixel captured by the script.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.66),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    return SizedBox(
      height: 38,
      child: Listener(
        onPointerSignal: (PointerSignalEvent event) {
          if (event is! PointerScrollEvent || !_formatScrollController.hasClients) return;
          final double target = (_formatScrollController.offset + event.scrollDelta.dy + event.scrollDelta.dx).clamp(
            _formatScrollController.position.minScrollExtent,
            _formatScrollController.position.maxScrollExtent,
          );
          _formatScrollController.jumpTo(target);
        },
        child: ListView.separated(
          controller: _formatScrollController,
          scrollDirection: Axis.horizontal,
          primary: false,
          dragStartBehavior: DragStartBehavior.down,
          physics: const ClampingScrollPhysics(),
          itemCount: ColorOutputFormat.values.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (BuildContext context, int index) {
            final ColorOutputFormat format = ColorOutputFormat.values[index];
            final bool selected = _selectedFormat == format;
            return ChoiceChip(
              label: Text(format.label),
              selected: selected,
              onSelected: (_) => setState(() => _selectedFormat = format),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface,
              ),
              labelPadding: const EdgeInsets.all(0),
              selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
              side: BorderSide(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.16),
              ),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.08),
            );
          },
        ),
      ),
    );
  }

  void _selectCell(Offset position, double squareSize, ColorPickerCapture capture) {
    if (capture.rowCount == 0 || capture.columnCount == 0) return;

    final double cellWidth = squareSize / capture.columnCount;
    final double cellHeight = squareSize / capture.rowCount;
    final int tappedColumn = (position.dx / cellWidth).floor().clamp(0, capture.columnCount - 1);
    final int tappedRow = (position.dy / cellHeight).floor().clamp(0, capture.rowCount - 1);

    setState(() {
      _selectedColumn = tappedColumn;
      _selectedRow = tappedRow;
    });
  }

  ColorGridSample? _selectedSample(ColorPickerCapture? capture) {
    if (capture == null || capture.grid.isEmpty) return null;
    final int row = _selectedRow.clamp(0, capture.rowCount - 1);
    final int column = _selectedColumn.clamp(0, capture.columnCount - 1);
    return capture.grid[row][column];
  }

  String _formatSample(ColorGridSample sample, ColorOutputFormat format) {
    switch (format) {
      case ColorOutputFormat.hex:
        return sample.hex.toUpperCase();
      case ColorOutputFormat.rgb:
        return "rgb(${sample.r}, ${sample.g}, ${sample.b})";
      case ColorOutputFormat.hsl:
        final HSLColor hsl = HSLColor.fromColor(sample.color);
        return "hsl(${_fixed(hsl.hue)}, ${_fixed(hsl.saturation * 100)}%, ${_fixed(hsl.lightness * 100)}%)";
      case ColorOutputFormat.cmyk:
        return _formatCmyk(sample);
      case ColorOutputFormat.oklch:
        return _formatOklch(sample);
    }
  }

  String _formatCmyk(ColorGridSample sample) {
    final double red = sample.r / 255;
    final double green = sample.g / 255;
    final double blue = sample.b / 255;
    final double maxChannel = math.max(red, math.max(green, blue));
    final double key = 1 - maxChannel;

    if (key >= 0.9999) {
      return "cmyk(0, 0, 0, 100)";
    }

    final int cyan = (((1 - red - key) / (1 - key)) * 100).round();
    final int magenta = (((1 - green - key) / (1 - key)) * 100).round();
    final int yellow = (((1 - blue - key) / (1 - key)) * 100).round();
    final int black = (key * 100).round();
    return "cmyk($cyan, $magenta, $yellow, $black)";
  }

  String _formatOklch(ColorGridSample sample) {
    final double red = _srgbToLinear(sample.r / 255);
    final double green = _srgbToLinear(sample.g / 255);
    final double blue = _srgbToLinear(sample.b / 255);

    final double l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue;
    final double m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue;
    final double s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue;

    final double lPrime = _cbrt(l);
    final double mPrime = _cbrt(m);
    final double sPrime = _cbrt(s);

    final double lightness = 0.2104542553 * lPrime + 0.793617785 * mPrime - 0.0040720468 * sPrime;
    final double a = 1.9779984951 * lPrime - 2.428592205 * mPrime + 0.4505937099 * sPrime;
    final double b = 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.808675766 * sPrime;

    final double chroma = math.sqrt(a * a + b * b);
    double hue = math.atan2(b, a) * 180 / math.pi;
    if (hue < 0) hue += 360;

    return "oklch(${_fixed(lightness * 100)}% ${chroma.toStringAsFixed(3)} ${_fixed(hue)})";
  }

  double _srgbToLinear(double value) {
    if (value <= 0.04045) {
      return value / 12.92;
    }
    return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  double _cbrt(double value) {
    if (value == 0) return 0;
    return math.pow(value, 1 / 3).toDouble();
  }

  String _fixed(double value) {
    final String fixed = value.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }
}

class _ColorGridPainter extends CustomPainter {
  const _ColorGridPainter({
    required this.capture,
    required this.selectedRow,
    required this.selectedColumn,
    required this.accent,
    required this.outline,
  });

  final ColorPickerCapture capture;
  final int selectedRow;
  final int selectedColumn;
  final Color accent;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect clip = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16));
    final Paint basePaint = Paint()..color = Colors.black.withValues(alpha: 0.14);
    canvas.drawRRect(clip, basePaint);

    canvas.save();
    canvas.clipRRect(clip);

    final double cellWidth = size.width / capture.columnCount;
    final double cellHeight = size.height / capture.rowCount;

    for (int row = 0; row < capture.rowCount; row++) {
      for (int column = 0; column < capture.columnCount; column++) {
        final ColorGridSample sample = capture.grid[row][column];
        final Rect rect = Rect.fromLTWH(
          column * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        canvas.drawRect(rect, Paint()..color = sample.color);
      }
    }

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = outline.withValues(alpha: 0.14);

    for (int row = 0; row <= capture.rowCount; row++) {
      final double y = row * cellHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (int column = 0; column <= capture.columnCount; column++) {
      final double x = column * cellWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final Rect centerRect = Rect.fromLTWH(
      capture.centerColumn * cellWidth,
      capture.centerRow * cellHeight,
      cellWidth,
      cellHeight,
    );
    final Rect selectedRect = Rect.fromLTWH(
      selectedColumn * cellWidth,
      selectedRow * cellHeight,
      cellWidth,
      cellHeight,
    );

    if (selectedRow != capture.centerRow || selectedColumn != capture.centerColumn) {
      canvas.drawRect(
        centerRect.deflate(1.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent,
      );
    }

    canvas.drawRect(
      selectedRect.deflate(0.8),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.95),
    );
    canvas.drawRect(
      selectedRect.deflate(2.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = Colors.black.withValues(alpha: 0.78),
    );

    canvas.restore();
    canvas.drawRRect(
      clip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(covariant _ColorGridPainter oldDelegate) {
    return oldDelegate.capture != capture ||
        oldDelegate.selectedRow != selectedRow ||
        oldDelegate.selectedColumn != selectedColumn ||
        oldDelegate.accent != accent ||
        oldDelegate.outline != outline;
  }
}
