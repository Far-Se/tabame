import 'package:flutter/material.dart';

import '../constants/translations.dart';
import '../models/picker_font.dart';
import 'font_picker_ui.dart';

/// Creates a widget that lets the user select a Google font from a provided list.
///
/// Inside your [build] method, use a button that when pressed, will navigate to the font picker screen:
///
/// ```dart
/// PickerFont? _selectedFont;
/// ElevatedButton(
///   child: Text('Pick a font'),
///   onPressed: () {
///     Navigator.push(
///       context,
///       MaterialPageRoute(
///           builder: (context) => FontPicker(
///               onFontChanged: (PickerFont font) {
///                 _selectedFont = font;
///                 print("${font.fontFamily} with font weight ${font.fontWeight} and font style ${font.fontStyle}.}");
///               },
///           ),
///       ),
///     );
///   }),
/// ```
///
///  The [onFontChanged] function retrieves the font that the user selects with an object containing details like the font's name, weight, style, etc.
///
/// You can then use its [toTextStyle] method to style any text with the selected font:
///
/// ```dart
/// Text('This will be styled with the font: $_selectedFont.fontFamily',
///      style: selectedFont.toTextStyle()),
/// ```
///
/// Use the [showInDialog] property to set if it will be shown in a dialog or in its own separate route.
class FontPicker extends StatefulWidget {
  /// The callback that returns a [PickerFont] object with all the details and methods for the font that the user selected.
  final ValueChanged<PickerFont> onFontChanged;

  /// The font family to use initially in the font picker. Defaults to 'Roboto'.
  final String? initialFontFamily;

  /// Set whether to show font details (category, number of variants) next to each font tile in the list.
  final bool showFontInfo;

  /// Set whether to show font variants (weights and styles) in the font picker. If set to false, user will only be able to select the default variant of each font.
  final bool showFontVariants;

  /// Set to true if the font picker will be used in an [AlertDialog] (check examples for usage).
  final bool showInDialog;

  /// Fonts that the user selected before can be saved in [SharedPreferences] and shown at the start of the list. Sets how many you want saved as recents.
  final int recentsCount;

  /// The language in which to show the UI. Defaults to English.
  ///
  /// If you need a translation in another language: take a look at the dictionaries variable in constants.dart, and send me the translations for your language.
  final String lang;

  /// Creates a widget that lets the user select a Google font from a provided list.
  ///
  /// The [onFontChanged] function retrieves the font that the user selects with an object containing details like the font's name, weight, style, etc.
  ///
  /// You can then use its [toTextStyle] method to style any text with the selected font.
  const FontPicker({
    super.key,
    this.showFontInfo = true,
    this.showFontVariants = true,
    this.showInDialog = false,
    this.recentsCount = 3,
    required this.onFontChanged,
    this.initialFontFamily,
    this.lang = "en",
  });

  @override
  State<FontPicker> createState() => _FontPickerState();
}

class _FontPickerState extends State<FontPicker> {
  @override
  void initState() {
    super.initState();
    translations.language = widget.lang;
  }

  @override
  Widget build(BuildContext context) {
    return widget.showInDialog
        ? FontPickerUI(
            onFontChanged: widget.onFontChanged,
            showInDialog: widget.showInDialog,
            recentsCount: widget.recentsCount,
            initialFontFamily: widget.initialFontFamily ?? 'Roboto',
            lang: widget.lang,
            showFontVariants: widget.showFontVariants,
          )
        : Scaffold(
            appBar: AppBar(title: const Text("Pick a font:")),
            body: FontPickerUI(
              onFontChanged: widget.onFontChanged,
              showInDialog: widget.showInDialog,
              recentsCount: widget.recentsCount,
              initialFontFamily: widget.initialFontFamily ?? 'Roboto',
              lang: widget.lang,
              showFontVariants: widget.showFontVariants,
            ),
          );
  }
}
