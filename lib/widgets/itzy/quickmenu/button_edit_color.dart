import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../models/util/color_format_controller.dart';
import '../../../models/util/color_picker_controller.dart';
import '../../widgets/color_editor_view.dart';
import '../../widgets/color_format_settings_view.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class EditColorButton extends StatelessWidget {
  const EditColorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Edit Color",
      icon: const Icon(Icons.edit_rounded),
      heightFactor: 0.96,
      child: () => const EditColorPanel(),
    );
  }
}

/// A from-scratch color editor: drag RGB/CMYK/HSL/OKLCH sliders to build a
/// color, pick which output format to use, and copy the formatted result.
/// Shares its format library (built-ins + custom token templates) with the
/// Color Picker panel via [ColorFormatController].
class EditColorPanel extends StatefulWidget {
  const EditColorPanel({super.key});

  @override
  State<EditColorPanel> createState() => _EditColorPanelState();
}

class _EditColorPanelState extends State<EditColorPanel> {
  final ColorFormatController _formatController = ColorFormatController.instance;
  final ScrollController _formatScrollController = ScrollController();
  final TextEditingController _colorInputController = TextEditingController();
  final GlobalKey<ColorEditorViewState> _editorKey = GlobalKey<ColorEditorViewState>();

  ColorGridSample _sample = ColorPickerController.instance.latestSample ?? const ColorGridSample(r: 255, g: 255, b: 255, hex: "ffffff");
  bool _settingsMode = false;
  String? _copiedMessage;
  Timer? _copiedTimer;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    unawaited(_formatController.ensureLoaded());
    unawaited(_loadFromClipboard());
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    _formatScrollController.dispose();
    _colorInputController.dispose();
    super.dispose();
  }

  Future<void> _loadFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    final ColorGridSample? parsed = parseColorString(text);
    if (parsed == null || !mounted) return;
    setState(() {
      _sample = parsed;
      _colorInputController.text = text;
    });
    _editorKey.currentState?.setSample(parsed);
  }

  void _applyColorInput() {
    final ColorGridSample? parsed = parseColorString(_colorInputController.text);
    if (parsed == null) {
      setState(() => _inputError = "Couldn't recognize that color format.");
      return;
    }
    setState(() {
      _sample = parsed;
      _inputError = null;
    });
    _editorKey.currentState?.setSample(parsed);
  }

  Future<void> _copyOutput(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _copiedTimer?.cancel();
    setState(() => _copiedMessage = "Copied");
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _copiedMessage = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _formatController,
      builder: (BuildContext context, _) {
        _formatController.syncColorName(_sample);
        final ColorOutputEntry? selectedFormat = _formatController.selectedFormat;
        final String? formattedValue = selectedFormat == null ? null : _formatController.formatSample(_sample, selectedFormat);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PanelHeader(
              title: _settingsMode ? "Color Formats" : "Edit Color",
              icon: _settingsMode ? Icons.tune_rounded : Icons.edit_rounded,
              extraActions: <Widget>[
                CustomTooltip(
                  message: _settingsMode ? "Editor" : "Format settings",
                  child: IconButton(
                    onPressed: () => setState(() => _settingsMode = !_settingsMode),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    iconSize: 14,
                    icon: Icon(_settingsMode ? Icons.edit_rounded : Icons.tune_rounded, color: Design.accent),
                  ),
                ),
              ],
            ),
            Flexible(
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _settingsMode
                      ? ColorFormatSettingsView(
                          key: const ValueKey<String>('editColorFormatSettings'),
                          controller: _formatController,
                          previewSample: _sample,
                        )
                      : _buildEditorBody(formattedValue),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditorBody(String? formattedValue) {
    return Column(
      key: const ValueKey<String>('editColorEditorBody'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildColorInputField(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildFormatSelector(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildOutputCard(formattedValue),
        ),
        Flexible(
          child: ColorEditorView(
            key: _editorKey,
            initial: _sample,
            applyLabel: "Copy output",
            onChanged: (ColorGridSample updated) => setState(() => _sample = updated),
            onApply: (ColorGridSample updated) {
              setState(() => _sample = updated);
              final ColorOutputEntry? fmt = _formatController.selectedFormat;
              if (fmt != null) {
                unawaited(_copyOutput(_formatController.formatSample(updated, fmt)));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorInputField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _colorInputController,
                style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: "Paste or type: hex, rgb(), hsl(), cmyk(), oklch()",
                  hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(100)),
                  prefixIcon: Icon(Icons.colorize_rounded, size: 14, color: Design.accent),
                  filled: true,
                  fillColor: Design.text.withAlpha(7),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(16))),
                  enabledBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(16))),
                  focusedBorder:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.accent.withAlpha(60))),
                ),
                onSubmitted: (_) => _applyColorInput(),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: _applyColorInput,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(18),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Design.accent.withAlpha(50)),
                ),
                child: Icon(Icons.check_rounded, size: 14, color: Design.accent),
              ),
            ),
          ],
        ),
        if (_inputError != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(
            _inputError!,
            style: TextStyle(fontSize: Design.baseFontSize, color: Colors.orangeAccent, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }

  Widget _buildFormatSelector() {
    final List<ColorOutputEntry> formats = _formatController.enabledFormats;
    if (formats.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Design.text.withAlpha(16)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.visibility_off_rounded, size: 16, color: Design.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "No formats enabled. Open settings to turn one back on.",
                style: TextStyle(fontSize: Design.baseFontSize + 1.5, color: Design.text.withAlpha(200)),
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
                color: selected ? Design.accent : Design.text,
              ),
              labelPadding: const EdgeInsets.all(0),
              selectedColor: Design.accent.withAlpha(18),
              side: BorderSide(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(16)),
              backgroundColor: Design.text.withAlpha(8),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOutputCard(String? formattedValue) {
    final bool hasValue = formattedValue != null;
    return InkWell(
      onTap: hasValue ? () => _copyOutput(formattedValue) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Design.accent.withAlpha(30)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.content_copy_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _copiedMessage ?? (formattedValue ?? 'No enabled format'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: FontWeight.w700,
                  color: Design.text,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
