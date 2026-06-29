import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/settings.dart';
import '../../models/util/color_format_controller.dart';
import '../../models/util/color_picker_controller.dart';
import 'mini_switch.dart';
import 'windows_scroll.dart';

enum ColorFormatSettingsPage { library, info }

/// The "Format settings" surface from the color picker: a library of
/// built-in/custom output formats plus a token-reference page for building
/// custom templates. Shared between the color picker panel and any other
/// surface that needs the same format editing experience.
class ColorFormatSettingsView extends StatefulWidget {
  const ColorFormatSettingsView({
    super.key,
    required this.controller,
    this.previewSample,
  });

  final ColorFormatController controller;
  final ColorGridSample? previewSample;

  @override
  State<ColorFormatSettingsView> createState() => _ColorFormatSettingsViewState();
}

class _ColorFormatSettingsViewState extends State<ColorFormatSettingsView> {
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customOutputController = TextEditingController();
  ColorFormatSettingsPage _page = ColorFormatSettingsPage.library;
  String? _message;

  @override
  void dispose() {
    _customNameController.dispose();
    _customOutputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (BuildContext context, _) {
        return switch (_page) {
          ColorFormatSettingsPage.library => _buildLibraryView(),
          ColorFormatSettingsPage.info => _buildInfoView(),
        };
      },
    );
  }

  Widget _buildLibraryView() {
    final ColorGridSample? sample = widget.previewSample;
    final String draftOutput = _customOutputController.text.trim();
    final TemplateParseResult templateState = parseCustomFormatTemplate(draftOutput);
    final bool canPreviewDraft = sample != null && draftOutput.isNotEmpty && templateState.validTokenCount > 0;
    final String? draftPreview = canPreviewDraft ? renderCustomFormat(sample, draftOutput, colorName: widget.controller.selectedColorName) : null;

    return WindowsScrollView(
      key: const ValueKey<String>('colorFormatSettingsView'),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              color: Design.text.withAlpha(7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Design.text.withAlpha(16)),
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
                          fontSize: Design.baseFontSize + 2.5,
                          fontWeight: FontWeight.w700,
                          color: Design.text,
                        ),
                      ),
                    ),
                    _buildMetaChip(
                      "${widget.controller.enabledFormats.length}/${widget.controller.formats.length} enabled",
                      Design.accent,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "Built-ins can be toggled on or off. Custom formats use placeholder tokens like %RX or %Hu and appear in the picker selector when enabled.",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    height: 1.25,
                    color: Design.text.withAlpha(150),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildFormatDraftCard(sample, draftPreview, templateState),
          if (_message != null) ...<Widget>[
            const SizedBox(height: 10),
            _buildInfoStrip(_message!, Design.accent),
          ],
          const SizedBox(height: 10),
          ...widget.controller.formats.map((ColorOutputEntry format) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFormatRow(format, sample),
              )),
        ],
      ),
    );
  }

  Widget _buildFormatDraftCard(ColorGridSample? sample, String? draftPreview, TemplateParseResult templateState) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            "Create custom format",
            style: TextStyle(
              fontSize: Design.baseFontSize + 2.5,
              fontWeight: FontWeight.w700,
              color: Design.text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customNameController,
            style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w600),
            decoration: _formatInputDecoration(hint: "Name", icon: Icons.badge_outlined),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _customOutputController,
            minLines: 2,
            maxLines: 4,
            style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w600),
            decoration: _formatInputDecoration(
              hint: "Output template, e.g: new Color(%Rb, %Gb, %Bb)",
              icon: Icons.code_rounded,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          if (_customOutputController.text.trim().isNotEmpty) _buildTemplateState(templateState),
          if (sample != null && draftPreview != null) ...<Widget>[
            const SizedBox(height: 8),
            _buildPreviewStrip("Preview", draftPreview),
          ] else if (sample == null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              "Pick a color to preview custom format output.",
              style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(150)),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: () => setState(() => _page = ColorFormatSettingsPage.info),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.menu_book_rounded, size: 14, color: Design.accent),
                        const SizedBox(width: 6),
                        Text(
                          "Format Info",
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 1.5,
                            fontWeight: FontWeight.w600,
                            color: Design.accent,
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
                    textStyle: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
            decoration: BoxDecoration(
              color: Design.text.withAlpha(7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Design.text.withAlpha(16)),
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
                          fontSize: Design.baseFontSize + 2.5,
                          fontWeight: FontWeight.w700,
                          color: Design.text,
                        ),
                      ),
                    ),
                    _buildTextAction(
                      "Back",
                      Icons.arrow_back_rounded,
                      () => setState(() => _page = ColorFormatSettingsPage.library),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _customOutputController,
                        style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w600),
                        decoration: _formatInputDecoration(hint: "Build your format template here...", icon: Icons.code_rounded),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildIconButton(
                      Icons.copy_rounded,
                      Design.accent,
                      () => Clipboard.setData(ClipboardData(text: _customOutputController.text)),
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
            key: const ValueKey<String>('colorFormatInfoView'),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(children: <Widget>[
              ...tokenReferenceEntries.map(
                (TokenReferenceEntry entry) => Padding(
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
                        color: Design.text.withAlpha(7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Design.text.withAlpha(16)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _buildMetaChip(entry.token, Design.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  entry.description,
                                  style: TextStyle(
                                    fontSize: Design.baseFontSize + 2,
                                    fontWeight: FontWeight.w700,
                                    color: Design.text,
                                  ),
                                ),
                                if (entry.modifiers != null) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    "Modifiers: ${entry.modifiers}",
                                    style: TextStyle(
                                      fontSize: Design.baseFontSize + 0.5,
                                      height: 1.25,
                                      color: Design.text.withAlpha(150),
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
                  color: Design.text.withAlpha(7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Design.text.withAlpha(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Modifier Reference",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: Design.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "These apply to %R, %G, %B, and %Al.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        height: 1.25,
                        color: Design.text.withAlpha(150),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...modifierReferenceEntries.map(
                      (ModifierReferenceEntry entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _buildMetaChip(entry.modifier, Design.accent),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    entry.description,
                                    style: TextStyle(
                                      fontSize: Design.baseFontSize + 2,
                                      fontWeight: FontWeight.w700,
                                      color: Design.text,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    "Example: ${entry.example}",
                                    style: TextStyle(
                                      fontSize: Design.baseFontSize + 0.5,
                                      height: 1.25,
                                      color: Design.text.withAlpha(150),
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

  Widget _buildTemplateState(TemplateParseResult result) {
    final bool ok = result.invalidTokens.isEmpty && result.validTokenCount > 0;
    final Color tone = ok ? Design.accent : Colors.orangeAccent;
    final String message = ok
        ? "${result.validTokenCount} token${result.validTokenCount == 1 ? '' : 's'} detected."
        : "Unknown token${result.invalidTokens.length == 1 ? '' : 's'}: ${result.invalidTokens.join(', ')}";
    return _buildInfoStrip(message, tone);
  }

  Widget _buildFormatRow(ColorOutputEntry format, ColorGridSample? sample) {
    final String? preview = sample == null ? null : widget.controller.formatSample(sample, format);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: format.enabled ? Design.accent.withAlpha(10) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: format.enabled ? Design.accent.withAlpha(30) : Design.text.withAlpha(16),
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
                              fontSize: Design.baseFontSize + 2.5,
                              fontWeight: FontWeight.w700,
                              color: Design.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMetaChip(
                          format.isBuiltIn ? 'Built-in' : 'Custom',
                          format.isBuiltIn ? Design.accent : Design.text,
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
                          fontSize: Design.baseFontSize + 0.5,
                          height: 1.25,
                          color: Design.text.withAlpha(150),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              MiniToggleSwitch(
                value: format.enabled,
                onChanged: (bool value) => widget.controller.setFormatEnabled(format.id, value),
              ),
              if (!format.isBuiltIn) ...<Widget>[
                const SizedBox(width: 4),
                _buildIconButton(
                  Icons.delete_outline_rounded,
                  Design.text.withAlpha(150),
                  () => widget.controller.deleteCustomFormat(format.id),
                ),
              ],
            ],
          ),
          if (preview != null) ...<Widget>[
            const SizedBox(height: 10),
            _buildPreviewStrip("Preview", preview),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewStrip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Design.text.withAlpha(12)),
      ),
      child: Row(
        children: <Widget>[
          _buildMetaChip(label, Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize + 0.5,
                fontWeight: FontWeight.w600,
                color: Design.text.withAlpha(180),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStrip(String message, Color accent) {
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
          fontSize: Design.baseFontSize + 0.5,
          fontWeight: FontWeight.w600,
          color: Design.text.withAlpha(200),
        ),
      ),
    );
  }

  InputDecoration _formatInputDecoration({required String hint, required IconData icon}) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: Design.baseFontSize + 1.5, color: Design.text.withAlpha(100)),
      prefixIcon: Icon(icon, size: 14, color: Design.accent),
      filled: true,
      fillColor: Design.text.withAlpha(7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Design.text.withAlpha(16)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Design.text.withAlpha(16)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Design.accent.withAlpha(60)),
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
          fontSize: Design.baseFontSize + 0.5,
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

  Widget _buildTextAction(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: Design.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1.5,
                fontWeight: FontWeight.w700,
                color: Design.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCustomFormat() async {
    final String? error = await widget.controller.addCustomFormat(
      name: _customNameController.text.trim(),
      template: _customOutputController.text.trim(),
    );
    setState(() {
      _message = error ?? "Added \"${_customNameController.text.trim()}\".";
      if (error == null) {
        _customNameController.clear();
        _customOutputController.clear();
      }
    });
  }
}
