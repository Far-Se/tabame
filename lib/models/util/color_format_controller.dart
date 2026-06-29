import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../classes/boxes/boxes_base.dart';
import 'color_picker_controller.dart';

enum ColorOutputKind { builtIn, custom }

class ColorOutputEntry {
  const ColorOutputEntry({
    required this.id,
    required this.name,
    required this.enabled,
    required this.kind,
    this.template,
  });

  const ColorOutputEntry.builtIn({
    required this.id,
    required this.name,
    required this.enabled,
  })  : kind = ColorOutputKind.builtIn,
        template = null;

  const ColorOutputEntry.custom({
    required this.id,
    required this.name,
    required this.template,
    required this.enabled,
  }) : kind = ColorOutputKind.custom;

  final String id;
  final String name;
  final bool enabled;
  final ColorOutputKind kind;
  final String? template;

  bool get isBuiltIn => kind == ColorOutputKind.builtIn;

  ColorOutputEntry copyWith({
    String? id,
    String? name,
    bool? enabled,
    ColorOutputKind? kind,
    String? template,
  }) {
    return ColorOutputEntry(
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

  factory ColorOutputEntry.fromMap(Map<String, dynamic> map) {
    final String kindName = (map['kind'] as String?) ?? 'builtIn';
    final ColorOutputKind kind =
        kindName == ColorOutputKind.custom.name ? ColorOutputKind.custom : ColorOutputKind.builtIn;
    return ColorOutputEntry(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Format',
      enabled: (map['enabled'] as bool?) ?? true,
      kind: kind,
      template: map['template'] as String?,
    );
  }
}

List<ColorOutputEntry> defaultColorOutputEntries() {
  return const <ColorOutputEntry>[
    ColorOutputEntry.builtIn(id: 'hex', name: 'HEX', enabled: true),
    ColorOutputEntry.builtIn(id: 'rgb', name: 'RGB', enabled: true),
    ColorOutputEntry.builtIn(id: 'hsl', name: 'HSL', enabled: true),
    ColorOutputEntry.builtIn(id: 'cmyk', name: 'CMYK', enabled: true),
    ColorOutputEntry.builtIn(id: 'oklch', name: 'OKLCH', enabled: true),
  ];
}

List<ColorOutputEntry> mergeWithDefaultFormats(List<ColorOutputEntry> loaded) {
  final List<ColorOutputEntry> defaults = defaultColorOutputEntries();
  final Map<String, ColorOutputEntry> loadedBuiltIns = <String, ColorOutputEntry>{
    for (final ColorOutputEntry entry in loaded.where((ColorOutputEntry entry) => entry.isBuiltIn)) entry.id: entry,
  };

  final List<ColorOutputEntry> mergedDefaults = defaults.map((ColorOutputEntry entry) {
    final ColorOutputEntry? saved = loadedBuiltIns[entry.id];
    return saved == null ? entry : entry.copyWith(enabled: saved.enabled, name: saved.name);
  }).toList(growable: false);

  final List<ColorOutputEntry> custom = loaded
      .where(
          (ColorOutputEntry entry) => !entry.isBuiltIn && entry.id.isNotEmpty && (entry.template?.isNotEmpty ?? false))
      .toList(growable: false);

  return <ColorOutputEntry>[...mergedDefaults, ...custom];
}

class TemplateParseResult {
  const TemplateParseResult({
    required this.rendered,
    required this.validTokenCount,
    required this.invalidTokens,
  });

  final String rendered;
  final int validTokenCount;
  final List<String> invalidTokens;
}

class TokenReferenceEntry {
  const TokenReferenceEntry(this.token, this.description, {this.modifiers});

  final String token;
  final String description;
  final String? modifiers;
}

class ModifierReferenceEntry {
  const ModifierReferenceEntry(this.modifier, this.description, this.example);

  final String modifier;
  final String description;
  final String example;
}

const List<String> orderedCustomTokens = <String>[
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

const Map<String, Set<String>> tokenAllowedModifiers = <String, Set<String>>{
  'R': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'G': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'B': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'Al': <String>{'', 'b', 'h', 'H', 'x', 'X', 'f', 'F'},
  'Lc': <String>{'', 'i'},
  'Ca': <String>{'', 'i'},
  'Cb': <String>{'', 'i'},
};

const List<TokenReferenceEntry> tokenReferenceEntries = <TokenReferenceEntry>[
  TokenReferenceEntry('%R', 'red', modifiers: 'b, h, H, x, X, f, F'),
  TokenReferenceEntry('%G', 'green', modifiers: 'b, h, H, x, X, f, F'),
  TokenReferenceEntry('%B', 'blue', modifiers: 'b, h, H, x, X, f, F'),
  TokenReferenceEntry('%Al', 'alpha', modifiers: 'b, h, H, x, X, f, F'),
  TokenReferenceEntry('%Cy', 'cyan'),
  TokenReferenceEntry('%Ma', 'magenta'),
  TokenReferenceEntry('%Ye', 'yellow'),
  TokenReferenceEntry('%Bk', 'black key (CMYK)'),
  TokenReferenceEntry('%Hu', 'hue'),
  TokenReferenceEntry('%Si', 'saturation (HSI)'),
  TokenReferenceEntry('%Sl', 'saturation (HSL)'),
  TokenReferenceEntry('%Sb', 'saturation (HSB)'),
  TokenReferenceEntry('%Br', 'brightness'),
  TokenReferenceEntry('%In', 'intensity'),
  TokenReferenceEntry('%Va', 'value'),
  TokenReferenceEntry('%Li', 'lightness (natural)'),
  TokenReferenceEntry('%Lc', 'lightness (CIE)', modifiers: 'i'),
  TokenReferenceEntry('%Wh', 'whiteness'),
  TokenReferenceEntry('%Bn', 'blackness'),
  TokenReferenceEntry('%Cb', 'chromaticity B (CIE Lab)', modifiers: 'i'),
  TokenReferenceEntry('%Ca', 'chromaticity A (CIE Lab)', modifiers: 'i'),
  TokenReferenceEntry('%Xv', 'X value'),
  TokenReferenceEntry('%Yv', 'Y value'),
  TokenReferenceEntry('%Zv', 'Z value'),
  TokenReferenceEntry('%Ol', 'lightness (Oklab/Oklch)'),
  TokenReferenceEntry('%Ob', 'chroma B (Oklab/Oklch)'),
  TokenReferenceEntry('%Oa', 'chroma A (Oklab/Oklch)'),
  TokenReferenceEntry('%Oc', 'chroma (Oklch)'),
  TokenReferenceEntry('%Oh', 'hue (Oklch)'),
  TokenReferenceEntry('%Dv', 'decimal value (BGR)'),
  TokenReferenceEntry('%Dr', 'decimal value (RGB)'),
  TokenReferenceEntry('%Na', 'color name'),
];

const List<ModifierReferenceEntry> modifierReferenceEntries = <ModifierReferenceEntry>[
  ModifierReferenceEntry('b', 'byte value, or the default integer form', '255'),
  ModifierReferenceEntry('h', 'lowercase hex, 1 digit', 'f'),
  ModifierReferenceEntry('H', 'uppercase hex, 1 digit', 'F'),
  ModifierReferenceEntry('x', 'lowercase hex, 2 digits', '0f'),
  ModifierReferenceEntry('X', 'uppercase hex, 2 digits', '0F'),
  ModifierReferenceEntry('f', 'float with leading zero', '0.25'),
  ModifierReferenceEntry('F', 'float without leading zero', '.25'),
];

bool _isAsciiLetter(String value) {
  if (value.isEmpty) return false;
  final int codeUnit = value.codeUnitAt(0);
  return (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);
}

String _tokenSnippet(String source, int start) {
  final int end = math.min(source.length, start + 4);
  return source.substring(start, end);
}

TemplateParseResult parseCustomFormatTemplate(String template, {ColorTokenBundle? values}) {
  if (template.isEmpty) {
    return const TemplateParseResult(rendered: '', validTokenCount: 0, invalidTokens: <String>[]);
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
    for (final String candidate in orderedCustomTokens) {
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
    final Set<String> allowedModifiers = tokenAllowedModifiers[matchedToken] ?? const <String>{''};
    String modifier = '';
    if (index < template.length && _isAsciiLetter(template[index]) && allowedModifiers.contains(template[index])) {
      modifier = template[index];
      index++;
    }

    validTokenCount++;
    buffer.write(values == null ? '%$matchedToken$modifier' : values.formatToken(matchedToken, modifier));
  }

  return TemplateParseResult(
    rendered: buffer.toString(),
    validTokenCount: validTokenCount,
    invalidTokens: invalidTokens.toSet().toList(growable: false),
  );
}

String renderCustomFormat(ColorGridSample sample, String template, {String? colorName}) {
  final ColorTokenBundle values = ColorTokenBundle.fromSample(sample, colorName: colorName);
  return parseCustomFormatTemplate(template, values: values).rendered;
}

String formatColorSample(ColorGridSample sample, ColorOutputEntry format, {String? colorName}) {
  if (format.kind == ColorOutputKind.custom && format.template != null) {
    return renderCustomFormat(sample, format.template!, colorName: colorName);
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
  final double red = srgbToLinear(sample.r / 255);
  final double green = srgbToLinear(sample.g / 255);
  final double blue = srgbToLinear(sample.b / 255);

  final double l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue;
  final double m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue;
  final double s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue;

  final double lPrime = cbrtRoot(l);
  final double mPrime = cbrtRoot(m);
  final double sPrime = cbrtRoot(s);

  final double lightness = 0.2104542553 * lPrime + 0.793617785 * mPrime - 0.0040720468 * sPrime;
  final double a = 1.9779984951 * lPrime - 2.428592205 * mPrime + 0.4505937099 * sPrime;
  final double b = 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.808675766 * sPrime;

  final double chroma = math.sqrt(a * a + b * b);
  double hue = math.atan2(b, a) * 180 / math.pi;
  if (hue < 0) hue += 360;

  return "oklch(${_fixed(lightness * 100)}% ${chroma.toStringAsFixed(3)} ${_fixed(hue)})";
}

double srgbToLinear(double value) {
  if (value <= 0.04045) {
    return value / 12.92;
  }
  return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

double cbrtRoot(double value) {
  if (value == 0) return 0;
  return math.pow(value, 1 / 3).toDouble();
}

String _fixed(double value) {
  final String fixed = value.toStringAsFixed(1);
  return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
}

ColorGridSample sampleFromRgb(int r, int g, int b) {
  final int ri = r.round().clamp(0, 255);
  final int gi = g.round().clamp(0, 255);
  final int bi = b.round().clamp(0, 255);
  final String hex =
      '${ri.toRadixString(16).padLeft(2, '0')}${gi.toRadixString(16).padLeft(2, '0')}${bi.toRadixString(16).padLeft(2, '0')}';
  return ColorGridSample(r: ri, g: gi, b: bi, hex: hex);
}

ColorGridSample sampleFromHsl(double h, double s, double l) {
  final Color color = HSLColor.fromAHSL(1, h.clamp(0, 360), s.clamp(0, 1), l.clamp(0, 1)).toColor();
  return sampleFromRgb((color.r * 255).round(), (color.g * 255).round(), (color.b * 255).round());
}

ColorGridSample sampleFromCmyk(double c, double m, double y, double k) {
  final double cc = c.clamp(0.0, 1.0);
  final double mm = m.clamp(0.0, 1.0);
  final double yy = y.clamp(0.0, 1.0);
  final double kk = k.clamp(0.0, 1.0);
  return sampleFromRgb(
    (255 * (1 - cc) * (1 - kk)).round(),
    (255 * (1 - mm) * (1 - kk)).round(),
    (255 * (1 - yy) * (1 - kk)).round(),
  );
}

ColorGridSample sampleFromOklch(double l, double c, double h) {
  final double lCc = l.clamp(0.0, 1.0);
  final double cCc = c.clamp(0.0, 0.4);
  final double rad = h * math.pi / 180;
  final double a = cCc * math.cos(rad);
  final double b = cCc * math.sin(rad);

  // Oklab -> LMS
  final double lp = lCc + 0.3963377774 * a + 0.2158037573 * b;
  final double mp = lCc - 0.1055613458 * a - 0.0638541728 * b;
  final double sp = lCc - 0.0894841775 * a - 1.2914855480 * b;

  final double lms = lp * lp * lp;
  final double mms = mp * mp * mp;
  final double sms = sp * sp * sp;

  // LMS -> linear sRGB
  final double linR = 4.0767416621 * lms - 3.3077115913 * mms + 0.2309699292 * sms;
  final double linG = -1.2684380046 * lms + 2.6097574011 * mms - 0.3413193965 * sms;
  final double linB = -0.0041960863 * lms - 0.7034186147 * mms + 1.7076147010 * sms;

  double toSrgb(double v) {
    final double clamped = v.clamp(0.0, 1.0);
    if (clamped <= 0.0031308) return clamped * 12.92;
    return 1.055 * math.pow(clamped, 1 / 2.4) - 0.055;
  }

  return sampleFromRgb(
    (toSrgb(linR) * 255).round(),
    (toSrgb(linG) * 255).round(),
    (toSrgb(linB) * 255).round(),
  );
}

/// Parses a color from free-form text in any of the formats this app emits:
/// hex (`#fff`, `ffffff`), `rgb()`/`rgba()`, `hsl()`/`hsla()`, `cmyk()`, or
/// `oklch()`. Returns null if the text doesn't match a recognized format.
ColorGridSample? parseColorString(String input) {
  final String text = input.trim();
  if (text.isEmpty) return null;
  return _tryParseHex(text) ?? _tryParseRgb(text) ?? _tryParseHsl(text) ?? _tryParseCmyk(text) ?? _tryParseOklch(text);
}

ColorGridSample? _tryParseHex(String text) {
  final RegExpMatch? match =
      RegExp(r'^(?:0x|#)?([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(text);
  if (match == null) return null;
  String hex = match.group(1)!;
  hex = hex.length <= 4 ? hex.substring(0, 3).split('').map((String c) => '$c$c').join() : hex.substring(0, 6);
  final int? r = int.tryParse(hex.substring(0, 2), radix: 16);
  final int? g = int.tryParse(hex.substring(2, 4), radix: 16);
  final int? b = int.tryParse(hex.substring(4, 6), radix: 16);
  if (r == null || g == null || b == null) return null;
  return sampleFromRgb(r, g, b);
}

ColorGridSample? _tryParseRgb(String text) {
  final RegExpMatch? match = RegExp(
    r'^rgba?\(\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*(?:[,/]\s*[\d.]+%?\s*)?\)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  double? channel(String raw) {
    final bool pct = raw.endsWith('%');
    final double? value = double.tryParse(pct ? raw.substring(0, raw.length - 1) : raw);
    if (value == null) return null;
    return pct ? value / 100 * 255 : value;
  }

  final double? r = channel(match.group(1)!);
  final double? g = channel(match.group(2)!);
  final double? b = channel(match.group(3)!);
  if (r == null || g == null || b == null) return null;
  return sampleFromRgb(r.round(), g.round(), b.round());
}

ColorGridSample? _tryParseHsl(String text) {
  final RegExpMatch? match = RegExp(
    r'^hsla?\(\s*([\d.]+)(?:deg|°)?\s*[, ]\s*([\d.]+)%?\s*[, ]\s*([\d.]+)%?\s*(?:[,/]\s*[\d.]+%?\s*)?\)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final double? h = double.tryParse(match.group(1)!);
  final double? s = double.tryParse(match.group(2)!);
  final double? l = double.tryParse(match.group(3)!);
  if (h == null || s == null || l == null) return null;
  return sampleFromHsl(h, s / 100, l / 100);
}

ColorGridSample? _tryParseCmyk(String text) {
  final RegExpMatch? match = RegExp(
    r'^cmyk\(\s*([\d.]+)%?\s*[, ]\s*([\d.]+)%?\s*[, ]\s*([\d.]+)%?\s*[, ]\s*([\d.]+)%?\s*\)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final double? c = double.tryParse(match.group(1)!);
  final double? m = double.tryParse(match.group(2)!);
  final double? y = double.tryParse(match.group(3)!);
  final double? k = double.tryParse(match.group(4)!);
  if (c == null || m == null || y == null || k == null) return null;
  return sampleFromCmyk(c / 100, m / 100, y / 100, k / 100);
}

ColorGridSample? _tryParseOklch(String text) {
  final RegExpMatch? match = RegExp(
    r'^oklch\(\s*([\d.]+)%?\s*[, ]\s*([\d.]+)\s*[, ]\s*([\d.]+)(?:deg|°)?\s*\)$',
    caseSensitive: false,
  ).firstMatch(text);
  if (match == null) return null;
  final double? l = double.tryParse(match.group(1)!);
  final double? c = double.tryParse(match.group(2)!);
  final double? h = double.tryParse(match.group(3)!);
  if (l == null || c == null || h == null) return null;
  return sampleFromOklch(l / 100, c, h);
}

class LabColor {
  const LabColor(this.l, this.a, this.b);

  final double l;
  final double a;
  final double b;
}

LabColor xyzToLab(double x, double y, double z) {
  const double refX = 95.047;
  const double refY = 100;
  const double refZ = 108.883;

  double transform(double value) {
    return value > 0.008856 ? math.pow(value, 1 / 3).toDouble() : (7.787 * value) + (16 / 116);
  }

  final double fx = transform(x / refX);
  final double fy = transform(y / refY);
  final double fz = transform(z / refZ);

  return LabColor(
    (116 * fy) - 16,
    500 * (fx - fy),
    200 * (fy - fz),
  );
}

class ColorTokenBundle {
  ColorTokenBundle({
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

  factory ColorTokenBundle.fromSample(ColorGridSample sample, {String? colorName}) {
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

    final double linearR = srgbToLinear(red);
    final double linearG = srgbToLinear(green);
    final double linearB = srgbToLinear(blue);

    final double x = (linearR * 0.4124564 + linearG * 0.3575761 + linearB * 0.1804375) * 100;
    final double y = (linearR * 0.2126729 + linearG * 0.7151522 + linearB * 0.072175) * 100;
    final double z = (linearR * 0.0193339 + linearG * 0.119192 + linearB * 0.9503041) * 100;

    final LabColor lab = xyzToLab(x, y, z);

    final double l = 0.4122214708 * linearR + 0.5363325363 * linearG + 0.0514459929 * linearB;
    final double m = 0.2119034982 * linearR + 0.6806995451 * linearG + 0.1073969566 * linearB;
    final double s = 0.0883024619 * linearR + 0.2817188376 * linearG + 0.6299787005 * linearB;

    final double lPrime = cbrtRoot(l);
    final double mPrime = cbrtRoot(m);
    final double sPrime = cbrtRoot(s);

    final double oklabL = 0.2104542553 * lPrime + 0.793617785 * mPrime - 0.0040720468 * sPrime;
    final double oklabA = 1.9779984951 * lPrime - 2.428592205 * mPrime + 0.4505937099 * sPrime;
    final double oklabB = 0.0259040371 * lPrime + 0.7827717662 * mPrime - 0.808675766 * sPrime;
    final double oklchChroma = math.sqrt(oklabA * oklabA + oklabB * oklabB);
    double oklchHue = math.atan2(oklabB, oklabA) * 180 / math.pi;
    if (oklchHue < 0) oklchHue += 360;
    final String resolvedColorName = (colorName ?? '').trim();

    return ColorTokenBundle(
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

/// Owns the persisted list of color output formats (built-in + custom),
/// the currently selected format, and the async color-name lookup used by
/// the `%Na` token. Shared as a singleton so the picker panel and any other
/// surface (e.g. a standalone color editor) stay in sync.
class ColorFormatController extends ChangeNotifier {
  ColorFormatController._();

  static final ColorFormatController instance = ColorFormatController._();

  static const String _formatsSettingsKey = 'colorPickerOutputFormats';

  List<ColorOutputEntry> formats = defaultColorOutputEntries();
  String? selectedFormatId = defaultColorOutputEntries().first.id;

  String? selectedColorName;
  bool isFetchingColorName = false;
  String? _selectedColorHexForName;
  final Map<String, String> _colorNameCache = <String, String>{};

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await loadFormats();
  }

  Future<void> loadFormats() async {
    try {
      final String raw = Boxes.pref.getString(_formatsSettingsKey) ?? '';
      if (raw.trim().isEmpty) {
        await saveFormats();
        return;
      }

      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      final List<ColorOutputEntry> loaded = decoded
          .map((dynamic item) => ColorOutputEntry.fromMap(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList();
      final List<ColorOutputEntry> merged = mergeWithDefaultFormats(loaded);
      final String? format = Boxes.pref.getString("preferedColorFormat");
      if (format != null && merged.any((ColorOutputEntry element) => element.id == format)) {
        final ColorOutputEntry selectedEntry = merged.firstWhere((ColorOutputEntry entry) => entry.id == format);
        merged.removeWhere((ColorOutputEntry entry) => entry.id == format);
        merged.insert(0, selectedEntry);
        selectedFormatId = merged.first.id;
      } else {
        selectedFormatId = merged.first.id;
        Boxes.pref.setString("preferedColorFormat", selectedFormatId!);
      }
      formats = merged;
      ensureSelectedFormat();
      notifyListeners();
    } catch (_) {
      formats = defaultColorOutputEntries();
      ensureSelectedFormat();
      notifyListeners();
      await saveFormats();
    }
  }

  Future<void> saveFormats() async {
    await Boxes.updateSettings(
      _formatsSettingsKey,
      jsonEncode(formats.map((ColorOutputEntry format) => format.toMap()).toList()),
    );
  }

  void ensureSelectedFormat() {
    final List<ColorOutputEntry> enabled = enabledFormats;
    if (enabled.isEmpty) {
      selectedFormatId = null;
      return;
    }
    if (selectedFormatId != null && enabled.any((ColorOutputEntry entry) => entry.id == selectedFormatId)) {
      return;
    }
    selectedFormatId = enabled.first.id;
  }

  Future<void> setFormatEnabled(String id, bool enabled) async {
    formats = formats
        .map((ColorOutputEntry entry) => entry.id == id ? entry.copyWith(enabled: enabled) : entry)
        .toList(growable: false);
    ensureSelectedFormat();
    notifyListeners();
    await saveFormats();
  }

  Future<void> deleteCustomFormat(String id) async {
    formats = formats.where((ColorOutputEntry entry) => entry.id != id).toList(growable: false);
    ensureSelectedFormat();
    notifyListeners();
    await saveFormats();
  }

  /// Returns an error message on failure, or null on success.
  Future<String?> addCustomFormat({required String name, required String template}) async {
    final TemplateParseResult templateState = parseCustomFormatTemplate(template);

    if (name.isEmpty) return "Give the custom format a name.";
    if (template.isEmpty) return "Enter the output string for the format.";
    if (formats.any((ColorOutputEntry entry) => entry.name.toLowerCase() == name.toLowerCase())) {
      return "A format named \"$name\" already exists.";
    }
    if (templateState.validTokenCount == 0) {
      return "Use at least one token like %Rb, %RX, %Hu, or %Na.";
    }
    if (templateState.invalidTokens.isNotEmpty) {
      return "Unknown token(s): ${templateState.invalidTokens.join(', ')}";
    }

    final ColorOutputEntry entry = ColorOutputEntry.custom(
      id: 'custom_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      template: template,
      enabled: true,
    );

    formats = <ColorOutputEntry>[...formats, entry];
    selectedFormatId = entry.id;
    notifyListeners();
    await saveFormats();
    return null;
  }

  void selectFormat(String id) {
    selectedFormatId = id;
    Boxes.pref.setString("preferedColorFormat", id);
    notifyListeners();
  }

  List<ColorOutputEntry> get enabledFormats =>
      formats.where((ColorOutputEntry entry) => entry.enabled).toList(growable: false);

  ColorOutputEntry? get selectedFormat {
    final String? id = selectedFormatId;
    if (id == null) return null;
    for (final ColorOutputEntry entry in formats) {
      if (entry.id == id && entry.enabled) return entry;
    }
    return null;
  }

  void syncColorName(ColorGridSample? sample) {
    if (sample == null) return;

    final String hex = sample.hex.replaceAll('#', '').toLowerCase();
    if (_selectedColorHexForName == hex) return;

    _selectedColorHexForName = hex;
    selectedColorName = _colorNameCache[hex];
    isFetchingColorName = selectedColorName == null;

    if (selectedColorName != null) return;

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
      if (_selectedColorHexForName != hex) return;
      selectedColorName = resolvedName;
      isFetchingColorName = false;
      notifyListeners();
    } catch (_) {
      if (_selectedColorHexForName != hex) return;
      selectedColorName = 'Unknown color';
      isFetchingColorName = false;
      notifyListeners();
    }
  }

  String formatSample(ColorGridSample sample, ColorOutputEntry format) {
    return formatColorSample(sample, format, colorName: selectedColorName);
  }
}
