import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/quick_menu_panel.dart';

class CustomCharsButton extends StatelessWidget {
  const CustomCharsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Custom Chars", icon: const Icon(Icons.format_quote), child: () => const CustomCharsPanel());
  }
}

final Map<String, List<String>> customChars = <String, List<String>>{
  "Currency": <String>[
    '฿',
    'в',
    '¢',
    '₡',
    'č',
    '₫',
    '€',
    'ƒ',
    '₴',
    '₭',
    'ł',
    'л',
    '₼',
    '£',
    '₽',
    '₹',
    '៛',
    '﷼',
    r'$',
    '₪',
    '₮',
    '₺',
    '₩',
    '¥',
    'z'
  ],
  "Math": <String>[
    '₀',
    '⁰',
    '₁',
    '¹',
    '₂',
    '²',
    '₃',
    '³',
    '₄',
    '⁴',
    '₅',
    '⁵',
    '₆',
    '⁶',
    '₇',
    '⁷',
    '₈',
    '⁸',
    '₉',
    '⁹',
    'π',
    'ú',
    '≤',
    '≥',
    '≠',
    '≈',
    '≙',
    '±',
    '₊',
    '⁺'
  ],
  "French": <String>[
    'à',
    'â',
    'á',
    'ä',
    'ã',
    'æ',
    'ç',
    'é',
    'è',
    'ê',
    'ë',
    '€',
    'î',
    'ï',
    'í',
    'ì',
    'ô',
    'ö',
    'ó',
    'ò',
    'õ',
    'œ',
    'û',
    'ù',
    'ü',
    'ú',
    'ÿ',
    'ý'
  ],
  "Iceland": <String>['á', 'æ', 'ð', 'é', 'ó', 'ö', 'ú', 'ý', 'þ'],
  "Spain": <String>['á', 'é', '€', 'í', 'ñ', 'ó', 'ú', 'ü', '¿', '?'],
  "Maori": <String>['ā', 'ē', 'ī', 'ō', r'$', 'ū'],
  "Pinyin": <String>[
    'ā',
    'á',
    'ǎ',
    'à',
    'a',
    'ē',
    'é',
    'ě',
    'è',
    'e',
    'ī',
    'í',
    'ǐ',
    'ì',
    'i',
    'ō',
    'ó',
    'ǒ',
    'ò',
    'o',
    'ū',
    'ú',
    'ǔ',
    'ù',
    'u',
    'ǖ',
    'ǘ',
    'ǚ',
    'ǜ',
    'ü'
  ],
  "Turkish": <String>['â', 'ç', 'ë', '€', 'ğ', 'ı', 'İ', 'î', 'ö', 'ô', 'ş', '₺', 'ü', 'û'],
  "Polish": <String>['ą', 'ć', 'ę', '€', 'ł', 'ń', 'ó', 'ś', 'ż', 'ź'],
  "Portuguese": <String>['á', 'à', 'â', 'ã', 'ç', 'é', 'ê', '€', 'í', 'ô', 'ó', 'õ'],
  "Slovak": <String>['á', 'ä', 'č', 'ď', 'é', '€', 'í', 'ľ', 'ĺ', 'ň', 'ó', 'ô', 'ŕ', 'š', 'ť', 'ú', 'ý', 'ž'],
  "Czech": <String>['á', 'č', 'ď', 'ě', 'é', 'í', 'ň', 'ó', 'ř', 'š', 'ť', 'ů', 'ú', 'ý', 'ž'],
  "German": <String>['ä', '€', 'ö', 'ß', 'ü'],
  "Hungarian": <String>['á', 'é', 'í', 'ó', 'ő', 'ö', 'ú', 'ű', 'ü'],
  "Romanian": <String>['ă', 'â', 'î', 'ș', 'ț'],
  "Italian": <String>['à', 'è', 'é', '€', 'ì', 'í', 'ò', 'ó', 'ù', 'ú'],
  "Arrows": <String>[
    '←',
    '↑',
    '→',
    '↓',
    '↔',
    '↕',
    '↖',
    '↗',
    '↘',
    '↙',
    '↩',
    '↪',
    '⤴',
    '⤵',
    '➔',
    '➜',
    '➞',
    '➟',
    '➠',
    '➡',
    '➢',
    '➣',
    '➤',
    '➥',
    '₢'
  ],
  "Greek": <String>[
    'α',
    'β',
    'γ',
    'δ',
    'ε',
    'ζ',
    'η',
    'θ',
    'ι',
    'κ',
    'λ',
    'μ',
    'ν',
    'ξ',
    'ο',
    'π',
    'ρ',
    'σ',
    'ς',
    'τ',
    'υ',
    'φ',
    'χ',
    'ψ',
    'ω',
    'Α',
    'Β',
    'Γ',
    'Δ',
    'Ε',
    'Ζ',
    'Η',
    'Θ',
    'Ι',
    'Κ',
    'Λ',
    'Μ',
    'Ν',
    'Ξ',
    'Ο',
    'Π',
    'Ρ',
    'Σ',
    'Τ',
    'Υ',
    'Φ',
    'Χ',
    'Ψ',
    'Ω'
  ],
  "Shapes": <String>[
    '■',
    '□',
    '▲',
    '△',
    '▼',
    '▽',
    '◆',
    '◇',
    '○',
    '◎',
    '●',
    '◯',
    '★',
    '☆',
    '✦',
    '✧',
    '✨',
    '✔',
    '✘',
    '☐',
    '☑',
    '☒'
  ],
  "Punctuation": <String>[
    '«',
    '»',
    '„',
    '“',
    '”',
    '‘',
    '’',
    '—',
    '–',
    '…',
    '¿',
    '¡',
    '•',
    '‣',
    '◦',
    '※',
    '¶',
    '§',
    '†',
    '‡'
  ],
};

class CustomCharsPanel extends StatefulWidget {
  const CustomCharsPanel({super.key});

  @override
  State<CustomCharsPanel> createState() => _CustomCharsPanelState();
}

class _CustomCharsPanelState extends State<CustomCharsPanel> {
  final TextEditingController textField = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<String> savedChars = <String>[];
  List<String> disabledSets = <String>[];
  final Set<String> expandedSets = <String>{};

  @override
  void initState() {
    super.initState();
    savedChars = Boxes.pref.getStringList("savedChars") ?? <String>[];
    disabledSets = Boxes.pref.getStringList("disabledSets") ?? <String>[];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).requestFocus(_focusNode);
    });
  }

  @override
  void dispose() {
    textField.dispose();
    _focusNode.dispose();
    searchController.dispose();
    super.dispose();
  }

  bool _resembles(String char, String search) {
    if (search.isEmpty) return false;
    final String c = char.toLowerCase();
    final String s = search.toLowerCase();
    if (c == s) return true;

    const Map<String, String> map = <String, String>{
      'a': 'àâáäãæāǎ',
      'e': 'éèêëēě€',
      'i': 'ιΙîïíìīǐ',
      'o': 'οΟôöóòõōǒ',
      'u': 'ûùüúūǔǖǘǚǜ',
      'c': 'çćč¢₡',
      'n': 'ñńň',
      's': 'σΣςśšşș§₪',
      'z': 'ζΖżźž',
      'l': 'λΛłľĺ',
      'd': 'δΔďð₫',
      't': 'θΘτΤťț₮₺',
      'y': 'ÿýψΨ',
      'r': 'ŕřρΡ',
      'g': 'γΓğ',
      'b': '฿βΒ',
      'p': 'πΠφΦ',
      'k': '₭κΚ',
      'w': '₩ωΩ',
      'x': 'χΧ',
      'f': 'φΦ',
      'm': 'μΜ',
      'v': 'νΝ',
    };
    return map[s]?.contains(c) ?? false;
  }

  void _copyAndClose(String char) {
    Clipboard.setData(ClipboardData(text: char));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Copied $char"),
        behavior: SnackBarBehavior.floating,
        width: 140,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  void _saveChar() {
    if (textField.text.isEmpty) return;
    setState(() {
      savedChars.add(textField.text);
      Boxes.pref.setStringList("savedChars", savedChars);
      textField.clear();
      // Auto expand saved if it was folded
      expandedSets.add("Saved");
    });
  }

  String _getCategoryFor(String char) {
    final List<String> sources = <String>[];
    if (savedChars.contains(char)) sources.add("Saved");
    for (final MapEntry<String, List<String>> entry in customChars.entries) {
      if (entry.value.contains(char)) sources.add(entry.key);
    }
    return sources.isEmpty ? "Unknown" : sources.join(", ");
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return QuickMenuPanel(
      title: "Characters",
      accent: accent,
      icon: Icons.format_quote,
      scrollable: true,
      bodyPadding: const EdgeInsets.symmetric(vertical: 12),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildSearchSection(accent, onSurface),
          if (searchController.text.isEmpty) ...<Widget>[
            _buildInputSection(accent, onSurface),
            if (savedChars.isNotEmpty) ...<Widget>[
              _buildSectionHeader(
                "Saved",
                accent,
                canExpand: true,
                isExpanded: expandedSets.contains("Saved"),
                onExpand: () => setState(() {
                  if (!expandedSets.add("Saved")) expandedSets.remove("Saved");
                }),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: expandedSets.contains("Saved")
                    ? _buildGrid(savedChars, accent, onSurface, isSaved: true)
                    : const SizedBox(width: double.infinity),
              ),
            ],
            ...customChars.entries
                .where((MapEntry<String, List<String>> entry) => !disabledSets.contains(entry.key))
                .map(
              (MapEntry<String, List<String>> entry) {
                final bool isExpanded = expandedSets.contains(entry.key);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildSectionHeader(
                      entry.key,
                      accent,
                      canExpand: true,
                      isExpanded: isExpanded,
                      onExpand: () => setState(() {
                        if (!expandedSets.add(entry.key)) expandedSets.remove(entry.key);
                      }),
                      onToggle: () {
                        setState(() {
                          disabledSets.add(entry.key);
                          Boxes.pref.setStringList("disabledSets", disabledSets);
                        });
                      },
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      alignment: Alignment.topCenter,
                      child: isExpanded
                          ? _buildGrid(entry.value, accent, onSurface)
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                );
              },
            ),
          ] else ...<Widget>[
            if (searchController.text.length == 1)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildSectionHeader("Related Characters", accent),
                  Builder(
                    builder: (BuildContext context) {
                      final List<String> results = <String>{
                        ...savedChars.where((String c) => _resembles(c, searchController.text)),
                        ...customChars.values
                            .expand((List<String> l) => l)
                            .where((String c) => _resembles(c, searchController.text)),
                      }.toList();
                      return _buildGrid(
                        results,
                        accent,
                        onSurface,
                        tooltips: results.map((String c) => _getCategoryFor(c)).toList(),
                      );
                    },
                  ),
                ],
              )
            else
              ...customChars.entries
                  .where((MapEntry<String, List<String>> entry) =>
                      entry.key.toLowerCase().contains(searchController.text.toLowerCase()))
                  .map(
                    (MapEntry<String, List<String>> entry) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildSectionHeader(entry.key, accent),
                        _buildGrid(entry.value, accent, onSurface),
                      ],
                    ),
                  ),
          ],
          if (disabledSets.isNotEmpty) ...<Widget>[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Divider(height: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                "Hidden Sets",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: FontWeight.bold,
                  color: onSurface.withAlpha(100),
                ),
              ),
            ),
            Wrap(
              spacing: 4,
              children: disabledSets.map((String name) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ActionChip(
                    labelPadding: EdgeInsets.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    label: Text(name, style: TextStyle(fontSize: Design.baseFontSize)),
                    onPressed: () {
                      setState(() {
                        disabledSets.remove(name);
                        Boxes.pref.setStringList("disabledSets", disabledSets);
                      });
                    },
                    backgroundColor: onSurface.withAlpha(10),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchSection(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: accent.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withAlpha(40)),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 8),
            Icon(Icons.search_rounded, size: 16, color: accent),
            Expanded(
              child: TextField(
                controller: searchController,
                style: TextStyle(fontSize: Design.baseFontSize + 2),
                autofocus: true,
                focusNode: _focusNode,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: "Search categories or characters...",
                  hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: accent.withAlpha(120)),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            if (searchController.text.isNotEmpty)
              IconButton(
                onPressed: () => setState(() => searchController.clear()),
                icon: Icon(Icons.close_rounded, size: 16, color: accent),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputSection(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: onSurface.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 8),
            Icon(Icons.add_rounded, size: 16, color: onSurface.withAlpha(150)),
            Expanded(
              child: TextField(
                controller: textField,
                style: TextStyle(fontSize: Design.baseFontSize + 2),
                decoration: InputDecoration(
                  hintText: "New char...",
                  hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(80)),
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onSubmitted: (_) => _saveChar(),
              ),
            ),
            IconButton(
              onPressed: _saveChar,
              icon: Icon(Icons.check_rounded, size: 16, color: accent),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    Color accent, {
    VoidCallback? onToggle,
    bool canExpand = false,
    bool isExpanded = false,
    VoidCallback? onExpand,
  }) {
    return InkWell(
      onTap: canExpand ? onExpand : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
        child: Row(
          children: <Widget>[
            if (canExpand)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: AnimatedRotation(
                  turns: isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.chevron_right_rounded, size: 14, color: accent),
                ),
              ),
            Text(
              title,
              style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (onToggle != null)
              IconButton(
                onPressed: onToggle,
                icon: const Icon(Icons.visibility_off_outlined, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: "Hide set",
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<String> chars, Color accent, Color onSurface, {bool isSaved = false, List<String>? tooltips}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: chars.asMap().entries.map((MapEntry<int, String> entry) {
          final int index = entry.key;
          final String char = entry.value;
          return _CharTile(
            char: char,
            accent: accent,
            tooltip: tooltips != null && index < tooltips.length ? tooltips[index] : null,
            onSurface: onSurface,
            onTap: () => _copyAndClose(char),
            onSecondaryTap: isSaved
                ? () {
                    setState(() {
                      savedChars.removeAt(index);
                      Boxes.pref.setStringList("savedChars", savedChars);
                    });
                  }
                : null,
          );
        }).toList(),
      ),
    );
  }
}

class _CharTile extends StatefulWidget {
  const _CharTile({
    required this.char,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    this.tooltip,
    this.onSecondaryTap,
  });

  final String char;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final String? tooltip;
  final VoidCallback? onSecondaryTap;

  @override
  State<_CharTile> createState() => _CharTileState();
}

class _CharTileState extends State<_CharTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Listener(
        onPointerDown: (PointerDownEvent event) {
          if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
            widget.onSecondaryTap?.call();
          }
        },
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _isHovering ? Design.accent.withAlpha(35) : Design.accent.withAlpha(12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _isHovering ? Design.accent.withAlpha(80) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Text(
              widget.char,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _isHovering ? Design.accent : widget.onSurface,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      tile = CustomTooltip(
        message: widget.tooltip!,
        child: tile,
      );
    }

    return tile;
  }
}
