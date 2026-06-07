import 'package:flutter/material.dart';

import '../../../../models/settings.dart';
import '../constants/translations.dart';

class FontLanguage extends StatefulWidget {
  final ValueChanged<String?> onFontLanguageSelected;
  final String selectedFontLanguage;
  const FontLanguage({
    super.key,
    required this.selectedFontLanguage,
    required this.onFontLanguageSelected,
  });

  @override
  State<FontLanguage> createState() => _FontLanguageState();
}

class _FontLanguageState extends State<FontLanguage> {
  final List<String> googleFontLanguages = <String>[
    'all',
    'arabic',
    'bengali',
    'chinese-hongkong',
    'chinese-simplified',
    'chinese-traditional',
    'cyrillic',
    'cyrillic-ext',
    'devanagari',
    'greek',
    'greek-ext',
    'gujarati',
    'gurmukhi',
    'hebrew',
    'japanese',
    'kannada',
    'khmer',
    'korean',
    'latin',
    'latin-ext',
    'malayalam',
    'myanmar',
    'oriya',
    'sinhala',
    'tamil',
    'telugu',
    'thai',
    'tibetan',
    'vietnamese',
  ];
  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: widget.selectedFontLanguage,
        isDense: true,
        style: TextStyle(
          fontSize: Design.baseFontSize + 2.0,
          color: DefaultTextStyle.of(context).style.color,
        ),
        icon: const Icon(Icons.arrow_drop_down_sharp),
        onChanged: widget.onFontLanguageSelected,
        items: googleFontLanguages.map<DropdownMenuItem<String>>((String value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(translations.d[value]!),
          );
        }).toList(),
      ),
    );
  }
}
