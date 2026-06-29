import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../models/util/color_format_controller.dart';
import '../../models/util/color_picker_controller.dart';
import '../../models/win32/win_utils.dart';
import 'color_editor_view.dart';
import 'color_format_settings_view.dart';
import 'custom_tooltip.dart';
import 'panel_header.dart';
import 'windows_scroll.dart';

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
  final ColorFormatController _formatController = ColorFormatController.instance;

  ColorPickerCapture? _lastCapture;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  bool _settingsMode = false;
  bool _editMode = false;
  ColorGridSample? _editedSample;
  String? _copiedMessage;
  Timer? _copiedTimer;
  final ScrollController _formatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.loadCapture());
    unawaited(_formatController.ensureLoaded());
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
    final Color accent = Design.accent;

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _formatController]),
      builder: (BuildContext context, _) {
        final ColorPickerCapture? capture = _controller.capture;
        _syncSelection(capture);
        final ColorGridSample? sample = _selectedSample(capture);
        final ColorOutputEntry? selectedFormat = _formatController.selectedFormat;
        final String? formattedValue =
            sample == null || selectedFormat == null ? null : _formatController.formatSample(sample, selectedFormat);
        _formatController.syncColorName(sample);

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
                    title: _editMode ? "Edit Color" : (_settingsMode ? "Color Formats" : "Color Picker"),
                    icon:
                        _editMode ? Icons.edit_rounded : (_settingsMode ? Icons.tune_rounded : Icons.palette_outlined),
                    extraActions: <Widget>[
                      if (!widget.isStandalone)
                        CustomTooltip(
                          message: _settingsMode ? "Picker" : "Format settings",
                          child: IconButton(
                            onPressed: () => setState(() {
                              _settingsMode = !_settingsMode;
                              _editMode = false;
                            }),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                            iconSize: 14,
                            icon: Icon(
                              _settingsMode ? Icons.palette_outlined : Icons.tune_rounded,
                              color: accent,
                            ),
                          ),
                        ),
                      if (!widget.isStandalone)
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _editMode
                        ? _buildColorEditorPage()
                        : (_settingsMode ? _buildSettingsPage(sample) : _buildPickerView(capture, sample, formattedValue)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.grid_view_rounded, size: 28, color: accent.withAlpha(200)),
          const SizedBox(height: 8),
          Text(
            "Pick any pixel on screen",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 2.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "The external picker samples the center color and the surrounding grid. When it closes, the grid loads here so you can inspect each cell.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: Design.baseFontSize + 0.5,
              color: onSurface.withAlpha(150),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerView(ColorPickerCapture? capture, ColorGridSample? sample, String? formattedValue) {
    return WindowsScrollView(
      key: const ValueKey<String>('colorPickerView'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: widget.onPickRequested ??
                () {
                  WinUtils.startTabame(closeCurrent: false, arguments: "-colorPicker");
                  QuickMenuFunctions.hideQuickMenu();
                },
            icon: const Icon(Icons.colorize_rounded, size: 14),
            label: const Text("Pick color"),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              visualDensity: VisualDensity.compact,
              textStyle: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          if (capture == null)
            _buildEmptyState()
          else ...<Widget>[
            _buildFormatSelector(),
            const SizedBox(height: 8),
            _buildPreviewCard(capture, sample, formattedValue),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: sample == null
                  ? null
                  : () {
                      setState(() {
                        _editedSample = sample;
                        _editMode = true;
                      });
                    },
              icon: const Icon(Icons.edit_rounded, size: 13),
              label: const Text("Edit color"),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                visualDensity: VisualDensity.compact,
                textStyle: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            _buildGridCard(capture),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewCard(ColorPickerCapture capture, ColorGridSample? sample, String? formattedValue) {
    final ColorGridSample selectedSample = sample ?? capture.center;
    final Color swatch = selectedSample.color;
    final bool hasEnabledFormats = _formatController.enabledFormats.isNotEmpty;
    final String displayValue = formattedValue ?? (hasEnabledFormats ? selectedSample.hex : 'No enabled format');
    final String colorNameText =
        _formatController.isFetchingColorName ? 'Searching ...' : (_formatController.selectedColorName ?? 'Unknown color');

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
                  if (!hasEnabledFormats) ...<Widget>[
                    Text(
                      "Enable at least one format in settings to copy its output.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1.5,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
                          _formatController.isFetchingColorName ? Icons.hourglass_top_rounded : Icons.badge_outlined,
                          size: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.64),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _copiedMessage ?? colorNameText,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 1.5,
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
                          overrideRow: _editedSample != null ? _selectedRow : null,
                          overrideColumn: _editedSample != null ? _selectedColumn : null,
                          overrideColor: _editedSample?.color,
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
              fontSize: Design.baseFontSize + 1,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.66),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatSelector() {
    final List<ColorOutputEntry> formats = _formatController.enabledFormats;
    if (formats.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.16)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.visibility_off_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "No formats enabled. Open settings to turn one back on.",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1.5,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _settingsMode = true),
              child: const Text('Settings'),
            ),
          ],
        ),
      );
    }

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
          itemCount: formats.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (BuildContext context, int index) {
            final ColorOutputEntry format = formats[index];
            final bool selected = _formatController.selectedFormatId == format.id;
            return ChoiceChip(
              label: Text(format.name),
              selected: selected,
              onSelected: (_) => _formatController.selectFormat(format.id),
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                fontSize: Design.baseFontSize + 1.5,
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

  // ── Color Editor ──────────────────────────────────────────────────────────

  Widget _buildColorEditorPage() {
    final ColorGridSample? base = _editedSample;
    if (base == null) {
      return const SizedBox.shrink();
    }
    return ColorEditorView(
      key: ValueKey<String>(base.hex),
      initial: base,
      onBack: () => setState(() {
        _editMode = false;
        _editedSample = null;
      }),
      onApply: (ColorGridSample updated) {
        setState(() {
          _editedSample = updated;
          _editMode = false;
        });
        final ColorOutputEntry? fmt = _formatController.selectedFormat;
        if (fmt != null) {
          unawaited(_copyOutput(_formatController.formatSample(updated, fmt)));
        }
      },
    );
  }

  Widget _buildSettingsPage(ColorGridSample? sample) {
    return ColorFormatSettingsView(
      key: const ValueKey<String>('colorPickerFormatSettings'),
      controller: _formatController,
      previewSample: sample ?? const ColorGridSample(r: 150, g: 100, b: 60, hex: "96643c"),
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
      // Clear any pending edit override so the new cell shows its real color.
      _editedSample = null;
    });
  }

  ColorGridSample? _selectedSample(ColorPickerCapture? capture) {
    if (capture == null || capture.grid.isEmpty) return null;
    // If the user applied an edit to the currently-selected cell, return that
    // instead of the original captured value so the preview card and format
    // output both reflect the modified color.
    if (_editedSample != null) return _editedSample;
    final int row = _selectedRow.clamp(0, capture.rowCount - 1);
    final int column = _selectedColumn.clamp(0, capture.columnCount - 1);
    return capture.grid[row][column];
  }
}

class _ColorGridPainter extends CustomPainter {
  const _ColorGridPainter({
    required this.capture,
    required this.selectedRow,
    required this.selectedColumn,
    required this.accent,
    required this.outline,
    this.overrideRow,
    this.overrideColumn,
    this.overrideColor,
  });

  final ColorPickerCapture capture;
  final int selectedRow;
  final int selectedColumn;
  final Color accent;
  final Color outline;
  final int? overrideRow;
  final int? overrideColumn;
  final Color? overrideColor;

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
        final bool isOverride = overrideColor != null && row == overrideRow && column == overrideColumn;
        final Color cellColor = isOverride ? overrideColor! : sample.color;
        final Rect rect = Rect.fromLTWH(
          column * cellWidth,
          row * cellHeight,
          cellWidth,
          cellHeight,
        );
        canvas.drawRect(rect, Paint()..color = cellColor);
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
        oldDelegate.outline != outline ||
        oldDelegate.overrideRow != overrideRow ||
        oldDelegate.overrideColumn != overrideColumn ||
        oldDelegate.overrideColor != overrideColor;
  }
}
