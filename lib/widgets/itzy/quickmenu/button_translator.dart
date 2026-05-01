import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/google_translator.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class TranslatorButton extends StatelessWidget {
  const TranslatorButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Translator",
      icon: const Icon(Icons.translate_rounded),
      child: () => const TranslatorPanel(),
    );
  }
}

class TranslatorPanel extends StatefulWidget {
  const TranslatorPanel({super.key});

  @override
  State<TranslatorPanel> createState() => _TranslatorPanelState();
}

class _TranslatorPanelState extends State<TranslatorPanel> {
  static const String _targetsKey = "translatorTargetLanguages";
  static const List<String> _defaultTargets = <String>["en", "ro"];

  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _languageSearchController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final GoogleTranslator _translator = GoogleTranslator();

  final Map<String, _TranslationResult> _results = <String, _TranslationResult>{};
  List<String> _targetLanguages = <String>[];
  bool _settingsMode = false;
  bool _translating = false;
  int _requestToken = 0;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _targetLanguages = _loadTargets();
    _languageSearchController.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _translator.close();
    _inputController.dispose();
    _languageSearchController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  List<String> _loadTargets() {
    final List<String>? saved = Boxes.pref.getStringList(_targetsKey);
    final List<String> valid = (saved ?? _defaultTargets)
        .where((String code) => code != "auto" && GoogleTranslator.languages.containsKey(code))
        .toSet()
        .toList();
    return valid.isEmpty ? List<String>.from(_defaultTargets) : valid;
  }

  Future<void> _saveTargets() async {
    await Boxes.updateSettings(_targetsKey, _targetLanguages);
  }

  Future<void> _translate() async {
    final String text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() => _statusMessage = "Enter text to translate.");
      return;
    }
    if (_targetLanguages.isEmpty) {
      setState(() {
        _settingsMode = true;
        _statusMessage = "Choose at least one target language.";
      });
      return;
    }

    final int token = ++_requestToken;
    setState(() {
      _translating = true;
      _statusMessage = null;
      _results.clear();
    });

    for (final String language in _targetLanguages) {
      try {
        final GoogleTranslateResponse response = await _translator.translate(text, from: "auto", to: language);
        if (!mounted || token != _requestToken) return;
        setState(() {
          _results[language] = _TranslationResult(text: response.text, detectedLanguage: response.from.language.iso);
        });
      } catch (error) {
        if (!mounted || token != _requestToken) return;
        setState(() => _results[language] = _TranslationResult(error: error.toString()));
      }
    }

    if (!mounted || token != _requestToken) return;
    setState(() => _translating = false);
  }

  Future<void> _toggleTarget(String code) async {
    setState(() {
      if (_targetLanguages.contains(code)) {
        _targetLanguages.remove(code);
      } else {
        _targetLanguages.add(code);
      }
    });
    await _saveTargets();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _statusMessage = "Copied translation.");
  }

  KeyEventResult _handleInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final bool isEnter =
        event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (!isEnter) return KeyEventResult.ignored;

    if (HardwareKeyboard.instance.isControlPressed) {
      _insertInputNewline();
    } else if (!_translating) {
      unawaited(_translate());
    }
    return KeyEventResult.handled;
  }

  void _insertInputNewline() {
    final TextSelection selection = _inputController.selection;
    final String text = _inputController.text;
    final int start = selection.start < 0 ? text.length : selection.start;
    final int end = selection.end < 0 ? text.length : selection.end;
    final String nextText = text.replaceRange(start, end, "\n");
    final int nextOffset = start + 1;
    _inputController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _settingsMode ? "Translator Settings" : "Translator",
          accent: accent,
          icon: _settingsMode ? Icons.tune_rounded : Icons.translate_rounded,
          buttonIcon: _settingsMode ? Icons.translate_rounded : Icons.tune_rounded,
          buttonTooltip: _settingsMode ? "Translator" : "Settings",
          buttonPressed: () => setState(() => _settingsMode = !_settingsMode),
        ),
        if (_translating) LinearProgressIndicator(minHeight: 1.5, color: accent),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: _settingsMode ? _buildSettings(accent, onSurface) : _buildTranslator(accent, onSurface),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTranslator(Color accent, Color onSurface) {
    return SingleChildScrollView(
      key: const ValueKey<String>("translator"),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Focus(
            onKeyEvent: _handleInputKey,
            child: TextField(
              controller: _inputController,
              focusNode: _inputFocus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              decoration: _inputDecoration(
                hint: "Text to translate",
                icon: Icons.edit_note_rounded,
                accent: accent,
                onSurface: onSurface,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _TargetSummary(
                  targetLanguages: _targetLanguages,
                  accent: accent,
                  onSurface: onSurface,
                  onTap: () => setState(() => _settingsMode = true),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: ElevatedButton.icon(
                  onPressed: _translating ? null : _translate,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text("Translate"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
            ],
          ),
          if (_statusMessage != null) ...<Widget>[
            const SizedBox(height: 10),
            _InfoStrip(message: _statusMessage!, accent: accent, onSurface: onSurface),
          ],
          const SizedBox(height: 12),
          if (_results.isEmpty)
            _EmptyTranslationState(accent: accent, onSurface: onSurface)
          else
            ..._targetLanguages.where(_results.containsKey).map((String code) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TranslationCard(
                    code: code,
                    result: _results[code]!,
                    accent: accent,
                    onSurface: onSurface,
                    onCopy: () {
                      final String? text = _results[code]?.text;
                      if (text != null && text.isNotEmpty) unawaited(_copy(text));
                    },
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildSettings(Color accent, Color onSurface) {
    final String query = _languageSearchController.text.trim().toLowerCase();
    final List<MapEntry<String, String>> languages = GoogleTranslator.languages.entries
        .where((MapEntry<String, String> entry) => entry.key != "auto")
        .where(
          (MapEntry<String, String> entry) =>
              query.isEmpty || entry.key.toLowerCase().contains(query) || entry.value.toLowerCase().contains(query),
        )
        .take(80)
        .toList(growable: false);

    return Column(
      key: const ValueKey<String>("translatorSettings"),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _languageSearchController,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: _inputDecoration(
              hint: "Search languages",
              icon: Icons.search_rounded,
              accent: accent,
              onSurface: onSurface,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: _InfoStrip(
            message: "${_targetLanguages.length} target language${_targetLanguages.length == 1 ? '' : 's'} selected.",
            accent: accent,
            onSurface: onSurface,
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            itemCount: languages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (BuildContext context, int index) {
              final MapEntry<String, String> language = languages[index];
              final bool selected = _targetLanguages.contains(language.key);
              return _LanguageRow(
                code: language.key,
                name: language.value,
                selected: selected,
                accent: accent,
                onSurface: onSurface,
                onTap: () => unawaited(_toggleTarget(language.key)),
              );
            },
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    required Color accent,
    required Color onSurface,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(fontSize: 12, color: onSurface.withAlpha(110)),
      prefixIcon: Icon(icon, size: 16, color: accent),
      filled: true,
      fillColor: accent.withAlpha(10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: accent.withAlpha(90)),
      ),
    );
  }
}

class _TranslationResult {
  const _TranslationResult({this.text, this.detectedLanguage, this.error});

  final String? text;
  final String? detectedLanguage;
  final String? error;
}

class _TargetSummary extends StatelessWidget {
  const _TargetSummary({
    required this.targetLanguages,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final List<String> targetLanguages;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label =
        targetLanguages.map((String code) => GoogleTranslator.languages[code] ?? code.toUpperCase()).take(3).join(", ");
    final int extra = targetLanguages.length - 3;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: onSurface.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: onSurface.withAlpha(16)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.language_rounded, size: 16, color: accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                targetLanguages.isEmpty ? "Choose languages" : "$label${extra > 0 ? ' +$extra' : ''}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: onSurface.withAlpha(170)),
              ),
            ),
            Icon(Icons.tune_rounded, size: 14, color: accent),
          ],
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.code,
    required this.result,
    required this.accent,
    required this.onSurface,
    required this.onCopy,
  });

  final String code;
  final _TranslationResult result;
  final Color accent;
  final Color onSurface;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final String title = GoogleTranslator.languages[code] ?? code.toUpperCase();
    final bool hasError = result.error != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasError ? Colors.redAccent.withAlpha(14) : accent.withAlpha(10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasError ? Colors.redAccent.withAlpha(55) : accent.withAlpha(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(hasError ? Icons.error_outline_rounded : Icons.translate_rounded,
                  size: 15, color: hasError ? Colors.redAccent : accent),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  result.detectedLanguage == null || result.detectedLanguage!.isEmpty
                      ? title
                      : "$title · from ${result.detectedLanguage}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: onSurface.withAlpha(150)),
                ),
              ),
              if (!hasError)
                InkWell(
                  onTap: onCopy,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.copy_rounded, size: 14, color: accent),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            hasError ? result.error! : (result.text?.isEmpty == true ? "No translation returned." : result.text ?? ""),
            style: TextStyle(
              fontSize: 13,
              height: 1.28,
              fontWeight: FontWeight.w600,
              color: hasError ? Colors.redAccent.withAlpha(220) : onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.code,
    required this.name,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(18) : onSurface.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? accent.withAlpha(70) : onSurface.withAlpha(14)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 17,
              color: selected ? accent : onSurface.withAlpha(100),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: onSurface),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              code.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: onSurface.withAlpha(95)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.message, required this.accent, required this.onSurface});

  final String message;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onSurface.withAlpha(145)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTranslationState extends StatelessWidget {
  const _EmptyTranslationState({required this.accent, required this.onSurface});

  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(12)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.translate_rounded, size: 34, color: accent.withAlpha(170)),
          const SizedBox(height: 10),
          Text(
            "Translations will appear here",
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            "Auto-detect source language, then translate to your selected targets.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: onSurface.withAlpha(130), height: 1.25),
          ),
        ],
      ),
    );
  }
}
