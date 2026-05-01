import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/fontweights_map.dart';

/// A wrapper class that contains details about each font in the [FontPicker].
///
/// Returned from the [onFontChanged] method of the [FontPicker].
///
/// Use the [toTextStyle] method to style any [Text] with the particular font.
class PickerFont {
  final String fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  bool isRecent;

  PickerFont({
    required this.fontFamily,
    this.fontWeight = FontWeight.w400,
    this.fontStyle = FontStyle.normal,
    this.isRecent = false,
  });

  /// Constructs a [PickerFont] from a font spec description (a shorthand string that can describe a font), e.g. "Roboto:700i".
  factory PickerFont.fromFontSpec(String fontSpec) {
    final List<String> fontSpecSplit = fontSpec.split(":");

    return fontSpecSplit.length == 1
        ? PickerFont(fontFamily: fontSpecSplit[0])
        : PickerFont(
            fontFamily: fontSpecSplit[0],
            fontWeight: fontWeightValues[fontSpecSplit[1].replaceAll("i", "")] ?? FontWeight.w400,
            fontStyle: fontSpecSplit[1].contains("i") ? FontStyle.italic : FontStyle.normal,
          );
  }

  /// Converts a [PickerFont] to a font spec description, a shorthand string that can describe a font.
  /// Examples of font specs: "Roboto:400", "Merriweather:700i", "Archivo Narrow:200i".
  String toFontSpec() {
    String fontWeightString = fontWeight.toString();
    String fontSpec = "$fontFamily:${fontWeightString.substring(fontWeightString.length - 3)}";

    return fontStyle == FontStyle.italic ? "${fontSpec}i" : fontSpec;
  }

  /// Provides a [TextStyle] object that can be used to style any [Text] with the selected Google font.
  TextStyle toTextStyle() {
    return GoogleFonts.getFont(
      fontFamily,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
    );
  }
}
