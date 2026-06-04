import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/boxes_base.dart';
import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/util/color_picker_controller.dart';
import '../../models/win32/win_utils.dart';
import 'custom_tooltip.dart';
import 'mini_switch.dart';
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
  static const String _formatsSettingsKey = 'colorPickerOutputFormats';

  final ColorPickerController _controller = ColorPickerController.instance;
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customOutputController = TextEditingController();

  ColorPickerCapture? _lastCapture;
  int _selectedRow = 0;
  int _selectedColumn = 0;
  List<_ColorOutputEntry> _formats = _defaultColorOutputEntries();
  String? _selectedFormatId = _defaultColorOutputEntries().first.id;
  bool _settingsMode = false;
  _FormatSettingsPage _settingsPage = _FormatSettingsPage.library;
  String? _copiedMessage;
  Timer? _copiedTimer;
  final ScrollController _formatScrollController = ScrollController();
  final Map<String, String> _colorNameCache = <String, String>{};
  String? _selectedColorName;
  String? _selectedColorHexForName;
  bool _isFetchingColorName = false;
  String? _formatSettingsMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.loadCapture());
    unawaited(_loadFormats());
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _formatScrollController.dispose();
    _customNameController.dispose();
    _customOutputController.dispose();
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
        final _ColorOutputEntry? selectedFormat = _selectedFormat;
        final String? formattedValue =
            sample == null || selectedFormat == null ? null : _formatSample(sample, selectedFormat);
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
                    title: _settingsMode ? "Color Formats" : "Color Picker",
                    accent: accent,
                    icon: _settingsMode ? Icons.tune_rounded : Icons.palette_outlined,
                    extraActions: <Widget>[
                      if (!widget.isStandalone)
                        CustomTooltip(
                          message: _settingsMode ? "Picker" : "Format settings",
                          child: IconButton(
                            onPressed: () => setState(() {
                              _settingsMode = !_settingsMode;
                              if (_settingsMode == false) {
                                _settingsPage = _FormatSettingsPage.library;
                              }
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
                    child: _settingsMode
                        ? _buildSettingsPage(accent, const ColorGridSample(r: 150, g: 100, b: 60, hex: "96643c"))
                        : _buildPickerView(capture, sample, formattedValue),
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
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "The external picker samples the center color and the surrounding grid. When it closes, the grid loads here so you can inspect each cell.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
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
              textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          if (capture == null)
            _buildEmptyState()
          else ...<Widget>[
            _buildFormatSelector(),
            const SizedBox(height: 8),
            _buildPreviewCard(capture, sample, formattedValue),
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
    final bool hasEnabledFormats = _enabledFormats.isNotEmpty;
    final String displayValue = formattedValue ?? (hasEnabledFormats ? selectedSample.hex : 'No enabled format');
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
                  if (!hasEnabledFormats) ...<Widget>[
                    Text(
                      "Enable at least one format in settings to copy its output.",
                      style: TextStyle(
                        fontSize: 11.5,
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
    final List<_ColorOutputEntry> formats = _enabledFormats;
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
                  fontSize: 11.5,
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
            final _ColorOutputEntry format = formats[index];
            final bool selected = _selectedFormatId == format.id;
            return ChoiceChip(
              label: Text(format.name),
              selected: selected,
              onSelected: (_) {
                Boxes.pref.setString("preferedColorFormat", format.id);
                if (!mounted) return;
                setState(() => _selectedFormatId = format.id);
              },
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

  Widget _buildSettingsPage(Color accent, ColorGridSample? sample) {
    return switch (_settingsPage) {
      _FormatSettingsPage.library => _buildFormatSettingsView(accent, sample),
      _FormatSettingsPage.info => _buildFormatInfoView(accent),
    };
  }

  Widget _buildFormatSettingsView(Color accent, ColorGridSample? sample) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final String draftOutput = _customOutputController.text.trim();
    final _TemplateParseResult templateState = _parseCustomFormatTemplate(draftOutput);
    final bool canPreviewDraft = sample != null && draftOutput.isNotEmpty && templateState.validTokenCount > 0;
    final String? draftPreview = canPreviewDraft ? _renderCustomFormat(sample, draftOutput) : null;

    return WindowsScrollView(
      key: const ValueKey<String>('colorPickerSettingsView'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              color: onSurface.withAlpha(7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: onSurface.withAlpha(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        "Format library",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                    ),
                    _buildMetaChip(
                      "${_enabledFormats.length}/${_formats.length} enabled",
                      accent,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Built-ins can be toggled on or off. Custom formats use placeholder tokens like %RX or %Hu and appear in the picker selector when enabled.",
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: onSurface.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildFormatDraftCard(accent, onSurface, sample, draftPreview, templateState),
          if (_formatSettingsMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            _buildInfoStrip(_formatSettingsMessage!, accent, onSurface),
          ],
          const SizedBox(height: 10),
          ..._formats.map((_ColorOutputEntry format) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFormatRow(format, accent, onSurface, sample),
              )),
        ],
      ),
    );
  }

  Widget _buildFormatDraftCard(
    Color accent,
    Color onSurface,
    ColorGridSample? sample,
    String? draftPreview,
    _TemplateParseResult templateState,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            "Create custom format",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customNameController,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            decoration: _formatInputDecoration(
              hint: "Name",
              icon: Icons.badge_outlined,
              accent: accent,
              onSurface: onSurface,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customOutputController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            decoration: _formatInputDecoration(
              hint: "Output template, e.g: new Color(%Rb, %Gb, %Bb)",
              icon: Icons.code_rounded,
              accent: accent,
              onSurface: onSurface,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_customOutputController.text.trim().isNotEmpty) _buildTemplateState(templateState, accent, onSurface),
          if (sample != null && draftPreview != null) ...<Widget>[
            const SizedBox(height: 8),
            _buildPreviewStrip("Preview", draftPreview, accent, onSurface),
          ] else if (sample == null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              "Pick a color to preview custom format output.",
              style: TextStyle(
                fontSize: 10.5,
                color: onSurface.withAlpha(150),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => setState(() => _settingsPage = _FormatSettingsPage.info),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.menu_book_rounded, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          "Format Info",
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _addCustomFormat,
                  icon: const Icon(Icons.add_rounded, size: 14),
                  label: const Text("Add format"),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormatInfoView(Color accent) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              color: onSurface.withAlpha(7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: onSurface.withAlpha(16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        "Available Tokens",
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                    ),
                    _buildTextAction(
                      "Back",
                      Icons.arrow_back_rounded,
                      accent,
                      () => setState(() => _settingsPage = _FormatSettingsPage.library),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _customOutputController,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        decoration: _formatInputDecoration(
                          hint: "Build your format template here...",
                          icon: Icons.code_rounded,
                          accent: accent,
                          onSurface: onSurface,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildIconButton(
                      Icons.copy_rounded,
                      accent,
                      () => _copyOutput(_customOutputController.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: WindowsScrollView(
            key: const ValueKey<String>('colorPickerFormatInfoView'),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(children: <Widget>[
              ..._tokenReferenceEntries.map(
                (_TokenReferenceEntry entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      final String currentText = _customOutputController.text;
                      _customOutputController.text = "$currentText${entry.token}";
                      setState(() {});
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: onSurface.withAlpha(7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: onSurface.withAlpha(16)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildMetaChip(entry.token, accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  entry.description,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: onSurface,
                                  ),
                                ),
                                if (entry.modifiers != null) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    "Modifiers: ${entry.modifiers}",
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      height: 1.25,
                                      color: onSurface.withAlpha(150),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                decoration: BoxDecoration(
                  color: onSurface.withAlpha(7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: onSurface.withAlpha(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Modifier Reference",
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "These apply to %R, %G, %B, and %Al.",
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ..._modifierReferenceEntries.map(
                      (_ModifierReferenceEntry entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildMetaChip(entry.modifier, accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.description,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Example: ${entry.example}",
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      height: 1.25,
                                      color: onSurface.withAlpha(150),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTemplateState(_TemplateParseResult result, Color accent, Color onSurface) {
    final bool ok = result.invalidTokens.isEmpty && result.validTokenCount > 0;
    final Color tone = ok ? accent : Colors.orangeAccent;
    final String message = ok
        ? "${result.validTokenCount} token${result.validTokenCount == 1 ? '' : 's'} detected."
        : "Unknown token${result.invalidTokens.length == 1 ? '' : 's'}: ${result.invalidTokens.join(', ')}";
    return _buildInfoStrip(message, tone, onSurface);
  }

  Widget _buildFormatRow(_ColorOutputEntry format, Color accent, Color onSurface, ColorGridSample? sample) {
    final String? preview = sample == null ? null : _formatSample(sample, format);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: format.enabled ? accent.withAlpha(10) : onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: format.enabled ? accent.withAlpha(30) : onSurface.withAlpha(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            format.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMetaChip(
                          format.isBuiltIn ? 'Built-in' : 'Custom',
                          format.isBuiltIn ? accent : onSurface,
                        ),
                      ],
                    ),
                    if (format.template != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        format.template!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.25,
                          color: onSurface.withAlpha(150),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MiniToggleSwitch(
                value: format.enabled,
                onChanged: (bool value) => _setFormatEnabled(format.id, value),
              ),
              if (!format.isBuiltIn) ...<Widget>[
                const SizedBox(width: 4),
                _buildIconButton(
                  Icons.delete_outline_rounded,
                  onSurface.withAlpha(150),
                  () => _deleteCustomFormat(format.id),
                ),
              ],
            ],
          ),
          if (preview != null) ...<Widget>[
            const SizedBox(height: 10),
            _buildPreviewStrip("Preview", preview, accent, onSurface),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewStrip(String label, String value, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: onSurface.withAlpha(12)),
      ),
      child: Row(
        children: <Widget>[
          _buildMetaChip(label, accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: onSurface.withAlpha(180),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStrip(String message, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withAlpha(20)),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: onSurface.withAlpha(200),
        ),
      ),
    );
  }

  InputDecoration _formatInputDecoration({
    required String hint,
    required IconData icon,
    required Color accent,
    required Color onSurface,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 11.5, color: onSurface.withAlpha(100)),
      prefixIcon: Icon(icon, size: 14, color: accent),
      filled: true,
      fillColor: onSurface.withAlpha(7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: onSurface.withAlpha(16)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: onSurface.withAlpha(16)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: accent.withAlpha(60)),
      ),
    );
  }

  Widget _buildMetaChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  Widget _buildTextAction(String label, IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
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

  Future<void> _loadFormats() async {
    try {
      final String raw = Boxes.pref.getString(_formatsSettingsKey) ?? '';
      if (raw.trim().isEmpty) {
        await _saveFormats();
        return;
      }

      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final List<_ColorOutputEntry> loaded = decoded
          .map((dynamic item) => _ColorOutputEntry.fromMap(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
      final List<_ColorOutputEntry> merged = _mergeWithDefaultFormats(loaded);
      final String? format = Boxes.pref.getString("preferedColorFormat");
      if (format != null && merged.any((_ColorOutputEntry element) => element.id == format)) {
        _selectedFormatId = format;
        //move selectedformatId format to first in merged
        final _ColorOutputEntry selectedFormat = merged.firstWhere((_ColorOutputEntry entry) => entry.id == format);
        merged.removeWhere((_ColorOutputEntry entry) => entry.id == format);
        merged.insert(0, selectedFormat);
        _selectedFormatId = merged.first.id;
      } else {
        _selectedFormatId = merged.first.id;
        Boxes.pref.setString("preferedColorFormat", _selectedFormatId!);
      }
      if (!mounted) return;
      setState(() {
        _formats = merged;
        _ensureSelectedFormat();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _formats = _defaultColorOutputEntries();
        _ensureSelectedFormat();
      });
      await _saveFormats();
    }
  }

  Future<void> _saveFormats() async {
    await Boxes.updateSettings(
      _formatsSettingsKey,
      jsonEncode(_formats.map((_ColorOutputEntry format) => format.toMap()).toList()),
    );
  }

  void _ensureSelectedFormat() {
    final List<_ColorOutputEntry> enabledFormats = _enabledFormats;
    if (enabledFormats.isEmpty) {
      _selectedFormatId = null;
      return;
    }
    if (_selectedFormatId != null && enabledFormats.any((_ColorOutputEntry entry) => entry.id == _selectedFormatId)) {
      return;
    }
    _selectedFormatId = enabledFormats.first.id;
  }

  Future<void> _setFormatEnabled(String id, bool enabled) async {
    setState(() {
      _formats = _formats
          .map((_ColorOutputEntry entry) => entry.id == id ? entry.copyWith(enabled: enabled) : entry)
          .toList(growable: false);
      _ensureSelectedFormat();
      _formatSettingsMessage = null;
    });
    await _saveFormats();
  }

  Future<void> _deleteCustomFormat(String id) async {
    setState(() {
      _formats = _formats.where((_ColorOutputEntry entry) => entry.id != id).toList(growable: false);
      _ensureSelectedFormat();
      _formatSettingsMessage = "Custom format deleted.";
    });
    await _saveFormats();
  }

  Future<void> _addCustomFormat() async {
    final String name = _customNameController.text.trim();
    final String output = _customOutputController.text.trim();
    final _TemplateParseResult templateState = _parseCustomFormatTemplate(output);

    if (name.isEmpty) {
      setState(() => _formatSettingsMessage = "Give the custom format a name.");
      return;
    }
    if (output.isEmpty) {
      setState(() => _formatSettingsMessage = "Enter the output string for the format.");
      return;
    }
    if (_formats.any((_ColorOutputEntry entry) => entry.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _formatSettingsMessage = "A format named \"$name\" already exists.");
      return;
    }
    if (templateState.validTokenCount == 0) {
      setState(() => _formatSettingsMessage = "Use at least one token like %Rb, %RX, %Hu, or %Na.");
      return;
    }
    if (templateState.invalidTokens.isNotEmpty) {
      setState(() => _formatSettingsMessage = "Unknown token(s): ${templateState.invalidTokens.join(', ')}");
      return;
    }

    final _ColorOutputEntry entry = _ColorOutputEntry.custom(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      template: output,
      enabled: true,
    );

    setState(() {
      _formats = <_ColorOutputEntry>[..._formats, entry];
      _selectedFormatId = entry.id;
      _formatSettingsMessage = "Added \"$name\".";
      _customNameController.clear();
      _customOutputController.clear();
    });
    await _saveFormats();
  }

  String _formatSample(ColorGridSample sample, _ColorOutputEntry format) {
    if (format.kind == _ColorOutputKind.custom && format.template != null) {
      return _renderCustomFormat(sample, format.template!);
    }

    switch (format.id) {
      case 'hex':
        return sample.hex.toUpperCase();
      case 'rgb':
        return "rgb(${sample.r}, ${sample.g}, ${sample.b})";
      case 'hsl':
        final HSLColor hsl = HSLColor.fromColor(sample.color);
        return "hsl(${_fixed(hsl.hue)}, ${_fixed(hsl.saturation * 100)}%, ${_fixed(hsl.lightness * 100)}%)";
      case 'cmyk':
        return _formatCmyk(sample);
      case 'oklch':
        return _formatOklch(sample);
      default:
        return sample.hex.toUpperCase();
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

  List<_ColorOutputEntry> get _enabledFormats =>
      _formats.where((_ColorOutputEntry entry) => entry.enabled).toList(growable: false);

  _ColorOutputEntry? get _selectedFormat {
    final String? id = _selectedFormatId;
    if (id == null) return null;
    for (final _ColorOutputEntry entry in _formats) {
      if (entry.id == id && entry.enabled) return entry;
    }
    return null;
  }

  String _renderCustomFormat(ColorGridSample sample, String template) {
    final _ColorTokenBundle values = _ColorTokenBundle.fromSample(sample, colorName: _selectedColorName);
    return _parseCustomFormatTemplate(template, values: values).rendered;
  }

  _TemplateParseResult _parseCustomFormatTemplate(String template, {_ColorTokenBundle? values}) {
    if (template.isEmpty) {
      return const _TemplateParseResult(rendered: '', validTokenCount: 0, invalidTokens: <String>[]);
    }

    final StringBuffer buffer = StringBuffer();
    final List<String> invalidTokens = <String>[];
    int validTokenCount = 0;
    int index = 0;

    while (index < template.length) {
      final String current = template[index];
      if (current != '%') {
        buffer.write(current);
        index++;
        continue;
      }

      String? matchedToken;
      for (final String candidate in _orderedCustomTokens) {
        if (template.startsWith(candidate, index + 1)) {
          matchedToken = candidate;
          break;
        }
      }

      if (matchedToken == null) {
        invalidTokens.add(_tokenSnippet(template, index));
        buffer.write('%');
        index++;
        continue;
      }

      index += 1 + matchedToken.length;
      final Set<String> allowedModifiers = _tokenAllowedModifiers[matchedToken] ?? const <String>{''};
      String modifier = '';
      if (index < template.length && _isAsciiLetter(template[index]) && allowedModifiers.contains(template[index])) {
        modifier = template[index];
        index++;
      }

      validTokenCount++;
      buffer.write(values == null ? '%$matchedToken$modifier' : values.formatToken(matchedToken, modifier));
    }

    return _TemplateParseResult(
      rendered: buffer.toString(),
      validTokenCount: validTokenCount,
      invalidTokens: invalidTokens.toSet().toList(growable: false),
    );
  }

  String _tokenSnippet(String source, int start) {
    final int end = math.min(source.length, start + 4);
    return source.substring(start, end);
  }

  bool _isAsciiLetter(String value) {
    if (value.isEmpty) return false;
    final int codeUnit = value.codeUnitAt(0);
    return (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);
  }
}

enum _FormatSettingsPage { library, info }

enum _ColorOutputKind { builtIn, custom }

class _ColorOutputEntry {
  const _ColorOutputEntry({
    required this.id,
    required this.name,
    required this.enabled,
    required this.kind,
    this.template,
  });

  const _ColorOutputEntry.builtIn({
    required this.id,
    required this.name,
    required this.enabled,
  })  : kind = _ColorOutputKind.builtIn,
        template = null;

  const _ColorOutputEntry.custom({
    required this.id,
    required this.name,
    required this.template,
    required this.enabled,
  }) : kind = _ColorOutputKind.custom;

  final String id;
  final String name;
  final bool enabled;
  final _ColorOutputKind kind;
  final String? template;

  bool get isBuiltIn => kind == _ColorOutputKind.builtIn;

  _ColorOutputEntry copyWith({
    String? id,
    String? name,
    bool? enabled,
    _ColorOutputKind? kind,
    String? template,
  }) {
    return _ColorOutputEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      kind: kind ?? this.kind,
      template: template ?? this.template,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'enabled': enabled,
      'kind': kind.name,
      'template': template,
    };
  }

  factory _ColorOutputEntry.fromMap(Map<String, dynamic> map) {
    final String kindName = (map['kind'] as String?) ?? 'builtIn';
    final _ColorOutputKind kind =
        kindName == _ColorOutputKind.custom.name ? _ColorOutputKind.custom : _ColorOutputKind.builtIn;
    return _ColorOutputEntry(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Format',
      enabled: (map['enabled'] as bool?) ?? true,
      kind: kind,
      template: map['template'] as String?,
    );
  }
}

List<_ColorOutputEntry> _defaultColorOutputEntries() {
  return const <_ColorOutputEntry>[
    _ColorOutputEntry.builtIn(id: 'hex', name: 'HEX', enabled: true),
    _ColorOutputEntry.builtIn(id: 'rgb', name: 'RGB', enabled: true),
    _ColorOutputEntry.builtIn(id: 'hsl', name: 'HSL', enabled: true),
    _ColorOutputEntry.builtIn(id: 'cmyk', name: 'CMYK', enabled: true),
    _ColorOutputEntry.builtIn(id: 'oklch', name: 'OKLCH', enabled: true),
  ];
}

List<_ColorOutputEntry> _mergeWithDefaultFormats(List<_ColorOutputEntry> loaded) {
  final List<_ColorOutputEntry> defaults = _defaultColorOutputEntries();
  final Map<String, _ColorOutputEntry> loadedBuiltIns = <String, _ColorOutputEntry>{
    for (final _ColorOutputEntry entry in loaded.where((_ColorOutputEntry entry) => entry.isBuiltIn)) entry.id: entry,
  };

  final List<_ColorOutputEntry> mergedDefaults = defaults.map((_ColorOutputEntry entry) {
    final _ColorOutputEntry? saved = loadedBuiltIns[entry.id];
    return saved == null ? entry : entry.copyWith(enabled: saved.enabled, name: saved.name);
  }).toList(growable: false);

  final List<_ColorOutputEntry> custom = loaded
      .where(
          (_ColorOutputEntry entry) => !entry.isBuiltIn && entry.id.isNotEmpty && (entry.template?.isNotEmpty ?? false))
      .toList(growable: false);

  return <_ColorOutputEntry>[...mergedDefaults, ...custom];
}

class _TemplateParseResult {
  const _TemplateParseResult({
    required this.rendered,
    required this.validTokenCount,
    required this.invalidTokens,
  });

  final String rendered;
  final int validTokenCount;
  final List<String> invalidTokens;
}

class _ColorTokenBundle {
  _ColorTokenBundle({
    required this.r,
    required this.g,
    required this.b,
    required this.alpha,
    required this.cyan,
    required this.magenta,
    required this.yellow,
    required this.black,
    required this.hue,
    required this.hsiSaturation,
    required this.hslSaturation,
    required this.hsbSaturation,
    required this.brightness,
    required this.intensity,
    required this.value,
    required this.lightness,
    required this.labLightness,
    required this.whiteness,
    required this.blackness,
    required this.labB,
    required this.labA,
    required this.x,
    required this.y,
    required this.z,
    required this.oklabL,
    required this.oklabB,
    required this.oklabA,
    required this.oklchChroma,
    required this.oklchHue,
    required this.decimalBgr,
    required this.decimalRgb,
    required this.colorName,
  });

  factory _ColorTokenBundle.fromSample(ColorGridSample sample, {String? colorName}) {
    final double red = sample.r / 255;
    final double green = sample.g / 255;
    final double blue = sample.b / 255;
    final HSLColor hsl = HSLColor.fromColor(sample.color);
    final HSVColor hsv = HSVColor.fromColor(sample.color);

    final double maxChannel = math.max(red, math.max(green, blue));
    final double minChannel = math.min(red, math.min(green, blue));
    final double key = 1 - maxChannel;

    final double cyan = key >= 0.9999 ? 0 : ((1 - red - key) / (1 - key)) * 100;
    final double magenta = key >= 0.9999 ? 0 : ((1 - green - key) / (1 - key)) * 100;
    final double yellow = key >= 0.9999 ? 0 : ((1 - blue - key) / (1 - key)) * 100;
    final double black = key >= 0.9999 ? 100 : key * 100;

    final double intensityNormal = (red + green + blue) / 3;
    final double hsiSaturation = intensityNormal == 0 ? 0 : (1 - (minChannel / intensityNormal)) * 100;

    final double linearR = _srgbToLinearStatic(red);
    final double linearG = _srgbToLinearStatic(green);
    final double linearB = _srgbToLinearStatic(blue);

    final double x = (linearR * 0.4124564 + linearG * 0.3575761 + linearB * 0.1804375) * 100;
    final double y = (linearR * 0.2126729 + linearG * 0.7151522 + linearB * 0.072175) * 100;
    final double z = (linearR * 0.0193339 + linearG * 0.119192 + linearB * 0.9503041) * 100;

    final _LabColor lab = _xyzToLab(x, y, z);

    final double l = 0.4122214708 * linearR + 0.5363325363 * linearG + 0.0514459929 * linearB;
    final double m = 0.2119034982 * linearR + 0.6806995451 * linearG + 0.1073969566 * linearB;
    final double s = 0.0883024619 * linearR + 0.2817188376 * linearG + 0.6299787005 * linearB;

    final double lPrime = _cbrtStatic(l);
    final double mPrime = _cbrtStatic(m);
    final double sPrime = _cbrtStatic(s);

    final double oklabL = 0.2104542553 * lPrime + 0.793617785 * mPrime - 0.0040720468 * sPrime;
    final double oklabA = 1.9779984951 * lPrime - 2.428592205 * mPrime + 0.4505937099 * sPrime;
    final double oklabB = 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.808675766 * sPrime;
    final double oklchChroma = math.sqrt(oklabA * oklabA + oklabB * oklabB);
    double oklchHue = math.atan2(oklabB, oklabA) * 180 / math.pi;
    if (oklchHue < 0) oklchHue += 360;
    final String resolvedColorName = (colorName ?? '').trim();

    return _ColorTokenBundle(
      r: sample.r,
      g: sample.g,
      b: sample.b,
      alpha: 255,
      cyan: cyan.clamp(0, 100).toDouble(),
      magenta: magenta.clamp(0, 100).toDouble(),
      yellow: yellow.clamp(0, 100).toDouble(),
      black: black.clamp(0, 100).toDouble(),
      hue: hsl.hue,
      hsiSaturation: hsiSaturation.clamp(0, 100).toDouble(),
      hslSaturation: hsl.saturation * 100,
      hsbSaturation: hsv.saturation * 100,
      brightness: hsv.value * 100,
      intensity: intensityNormal * 100,
      value: hsv.value * 100,
      lightness: hsl.lightness * 100,
      labLightness: lab.l,
      whiteness: minChannel * 100,
      blackness: (1 - maxChannel) * 100,
      labB: lab.b,
      labA: lab.a,
      x: x,
      y: y,
      z: z,
      oklabL: oklabL,
      oklabB: oklabB,
      oklabA: oklabA,
      oklchChroma: oklchChroma,
      oklchHue: oklchHue,
      decimalBgr: sample.b * 65536 + sample.g * 256 + sample.r,
      decimalRgb: sample.r * 65536 + sample.g * 256 + sample.b,
      colorName: (resolvedColorName.isEmpty ? 'unknown color' : resolvedColorName).toLowerCase(),
    );
  }

  final int r;
  final int g;
  final int b;
  final int alpha;
  final double cyan;
  final double magenta;
  final double yellow;
  final double black;
  final double hue;
  final double hsiSaturation;
  final double hslSaturation;
  final double hsbSaturation;
  final double brightness;
  final double intensity;
  final double value;
  final double lightness;
  final double labLightness;
  final double whiteness;
  final double blackness;
  final double labB;
  final double labA;
  final double x;
  final double y;
  final double z;
  final double oklabL;
  final double oklabB;
  final double oklabA;
  final double oklchChroma;
  final double oklchHue;
  final int decimalBgr;
  final int decimalRgb;
  final String colorName;

  String formatToken(String token, String modifier) {
    switch (token) {
      case 'R':
        return _formatRgbLike(r, modifier);
      case 'G':
        return _formatRgbLike(g, modifier);
      case 'B':
        return _formatRgbLike(b, modifier);
      case 'Al':
        return _formatRgbLike(alpha, modifier);
      case 'Cy':
        return _formatMetric(cyan, digits: 0);
      case 'Ma':
        return _formatMetric(magenta, digits: 0);
      case 'Ye':
        return _formatMetric(yellow, digits: 0);
      case 'Bk':
        return _formatMetric(black, digits: 0);
      case 'Hu':
        return _formatMetric(hue, digits: 1);
      case 'Si':
        return _formatMetric(hsiSaturation, digits: 1);
      case 'Sl':
        return _formatMetric(hslSaturation, digits: 1);
      case 'Sb':
        return _formatMetric(hsbSaturation, digits: 1);
      case 'Br':
        return _formatMetric(brightness, digits: 1);
      case 'In':
        return _formatMetric(intensity, digits: 1);
      case 'Va':
        return _formatMetric(value, digits: 1);
      case 'Li':
        return _formatMetric(lightness, digits: 1);
      case 'Lc':
        return modifier == 'i' ? labLightness.round().toString() : _formatMetric(labLightness, digits: 2);
      case 'Wh':
        return _formatMetric(whiteness, digits: 1);
      case 'Bn':
        return _formatMetric(blackness, digits: 1);
      case 'Cb':
        return modifier == 'i' ? labB.round().toString() : _formatMetric(labB, digits: 2);
      case 'Ca':
        return modifier == 'i' ? labA.round().toString() : _formatMetric(labA, digits: 2);
      case 'Xv':
        return _formatMetric(x, digits: 3);
      case 'Yv':
        return _formatMetric(y, digits: 3);
      case 'Zv':
        return _formatMetric(z, digits: 3);
      case 'Ol':
        return _formatMetric(oklabL, digits: 4);
      case 'Ob':
        return _formatMetric(oklabB, digits: 4);
      case 'Oa':
        return _formatMetric(oklabA, digits: 4);
      case 'Oc':
        return _formatMetric(oklchChroma, digits: 4);
      case 'Oh':
        return _formatMetric(oklchHue, digits: 1);
      case 'Dv':
        return decimalBgr.toString();
      case 'Dr':
        return decimalRgb.toString();
      case 'Na':
        return colorName;
      default:
        return '%$token$modifier';
    }
  }

  String _formatRgbLike(int value, String modifier) {
    switch (modifier) {
      case '':
      case 'b':
        return value.toString();
      case 'h':
        return _singleHex(value).toLowerCase();
      case 'H':
        return _singleHex(value).toUpperCase();
      case 'x':
        return value.toRadixString(16).padLeft(2, '0').toLowerCase();
      case 'X':
        return value.toRadixString(16).padLeft(2, '0').toUpperCase();
      case 'f':
        return (value / 255).toStringAsFixed(2);
      case 'F':
        final String text = (value / 255).toStringAsFixed(2);
        return text.startsWith('0.') ? text.substring(1) : text;
      default:
        return value.toString();
    }
  }

  String _singleHex(int value) {
    final int nibble = (value / 17).round().clamp(0, 15);
    return nibble.toRadixString(16);
  }

  String _formatMetric(double value, {required int digits}) {
    final String fixed = value.toStringAsFixed(digits);
    if (!fixed.contains('.')) return fixed;
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _LabColor {
  const _LabColor(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

_LabColor _xyzToLab(double x, double y, double z) {
  const double refX = 95.047;
  const double refY = 100;
  const double refZ = 108.883;

  double transform(double value) {
    return value > 0.008856 ? math.pow(value, 1 / 3).toDouble() : (7.787 * value) + (16 / 116);
  }

  final double fx = transform(x / refX);
  final double fy = transform(y / refY);
  final double fz = transform(z / refZ);

  return _LabColor(
    (116 * fy) - 16,
    500 * (fx - fy),
    200 * (fy - fz),
  );
}

double _srgbToLinearStatic(double value) {
  if (value <= 0.04045) return value / 12.92;
  return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

double _cbrtStatic(double value) {
  if (value == 0) return 0;
  return math.pow(value, 1 / 3).toDouble();
}

const List<String> _orderedCustomTokens = <String>[
  'Al',
  'Cy',
  'Ma',
  'Ye',
  'Bk',
  'Hu',
  'Si',
  'Sl',
  'Sb',
  'Br',
  'In',
  'Va',
  'Li',
  'Lc',
  'Wh',
  'Bn',
  'Cb',
  'Ca',
  'Xv',
  'Yv',
  'Zv',
  'Ol',
  'Ob',
  'Oa',
  'Oc',
  'Oh',
  'Dv',
  'Dr',
  'Na',
  'R',
  'G',
  'B',
];

const Map<String, Set<String>> _tokenAllowedModifiers = <String, Set<String>>{
  'R': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'G': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'B': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'Al': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'Lc': <String>{'', 'i'},
  'Ca': <String>{'', 'i'},
  'Cb': <String>{'', 'i'},
};

class _TokenReferenceEntry {
  const _TokenReferenceEntry(this.token, this.description, {this.modifiers});

  final String token;
  final String description;
  final String? modifiers;
}

class _ModifierReferenceEntry {
  const _ModifierReferenceEntry(this.modifier, this.description, this.example);

  final String modifier;
  final String description;
  final String example;
}

const List<_TokenReferenceEntry> _tokenReferenceEntries = <_TokenReferenceEntry>[
  _TokenReferenceEntry('%R', 'red', modifiers: 'b, h, H, x, X, f, F'),
  _TokenReferenceEntry('%G', 'green', modifiers: 'b, h, H, x, X, f, F'),
  _TokenReferenceEntry('%B', 'blue', modifiers: 'b, h, H, x, X, f, F'),
  _TokenReferenceEntry('%Al', 'alpha', modifiers: 'b, h, H, x, X, f, F'),
  _TokenReferenceEntry('%Cy', 'cyan'),
  _TokenReferenceEntry('%Ma', 'magenta'),
  _TokenReferenceEntry('%Ye', 'yellow'),
  _TokenReferenceEntry('%Bk', 'black key (CMYK)'),
  _TokenReferenceEntry('%Hu', 'hue'),
  _TokenReferenceEntry('%Si', 'saturation (HSI)'),
  _TokenReferenceEntry('%Sl', 'saturation (HSL)'),
  _TokenReferenceEntry('%Sb', 'saturation (HSB)'),
  _TokenReferenceEntry('%Br', 'brightness'),
  _TokenReferenceEntry('%In', 'intensity'),
  _TokenReferenceEntry('%Va', 'value'),
  _TokenReferenceEntry('%Li', 'lightness (natural)'),
  _TokenReferenceEntry('%Lc', 'lightness (CIE)', modifiers: 'i'),
  _TokenReferenceEntry('%Wh', 'whiteness'),
  _TokenReferenceEntry('%Bn', 'blackness'),
  _TokenReferenceEntry('%Cb', 'chromaticity B (CIE Lab)', modifiers: 'i'),
  _TokenReferenceEntry('%Ca', 'chromaticity A (CIE Lab)', modifiers: 'i'),
  _TokenReferenceEntry('%Xv', 'X value'),
  _TokenReferenceEntry('%Yv', 'Y value'),
  _TokenReferenceEntry('%Zv', 'Z value'),
  _TokenReferenceEntry('%Ol', 'lightness (Oklab/Oklch)'),
  _TokenReferenceEntry('%Ob', 'chroma B (Oklab/Oklch)'),
  _TokenReferenceEntry('%Oa', 'chroma A (Oklab/Oklch)'),
  _TokenReferenceEntry('%Oc', 'chroma (Oklch)'),
  _TokenReferenceEntry('%Oh', 'hue (Oklch)'),
  _TokenReferenceEntry('%Dv', 'decimal value (BGR)'),
  _TokenReferenceEntry('%Dr', 'decimal value (RGB)'),
  _TokenReferenceEntry('%Na', 'color name'),
];

const List<_ModifierReferenceEntry> _modifierReferenceEntries = <_ModifierReferenceEntry>[
  _ModifierReferenceEntry('b', 'byte value, or the default integer form', '255'),
  _ModifierReferenceEntry('h', 'lowercase hex, 1 digit', 'f'),
  _ModifierReferenceEntry('H', 'uppercase hex, 1 digit', 'F'),
  _ModifierReferenceEntry('x', 'lowercase hex, 2 digits', '0f'),
  _ModifierReferenceEntry('X', 'uppercase hex, 2 digits', '0F'),
  _ModifierReferenceEntry('f', 'float with leading zero', '0.25'),
  _ModifierReferenceEntry('F', 'float without leading zero', '.25'),
];

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
