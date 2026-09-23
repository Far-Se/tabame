import 'dart:convert';

enum GlassEffect {
  none('None'),
  blur('Blur'),
  acrylic('Acrylic'),
  mica('Mica');

  const GlassEffect(this.label);

  final String label;

  static GlassEffect fromSetting(String? value) =>
      GlassEffect.values.where((GlassEffect effect) => effect.name == value).firstOrNull ?? GlassEffect.none;
}

/// Appearance preferences are kept separately for each backdrop mode.
class GlassEffectOptions {
  const GlassEffectOptions({
    this.panelOpacity = 0.62,
    this.customAcrylicTint = false,
    this.acrylicTintOpacity = 0.6,
    this.micaAlt = false,
  });

  final double panelOpacity;
  final bool customAcrylicTint;
  final double acrylicTintOpacity;
  final bool micaAlt;

  GlassEffectOptions copyWith({
    double? panelOpacity,
    bool? customAcrylicTint,
    double? acrylicTintOpacity,
    bool? micaAlt,
  }) =>
      GlassEffectOptions(
        panelOpacity: _opacity(panelOpacity, this.panelOpacity),
        customAcrylicTint: customAcrylicTint ?? this.customAcrylicTint,
        acrylicTintOpacity: _opacity(acrylicTintOpacity, this.acrylicTintOpacity, minimum: 0.01),
        micaAlt: micaAlt ?? this.micaAlt,
      );

  factory GlassEffectOptions.fromMap(Map<Object?, Object?> value) => GlassEffectOptions(
        panelOpacity: _opacity(value['panelOpacity'], 0.62),
        customAcrylicTint: value['customAcrylicTint'] == true,
        acrylicTintOpacity: _opacity(value['acrylicTintOpacity'], 0.6, minimum: 0.01),
        micaAlt: value['micaAlt'] == true,
      );

  Map<String, Object> toMap() => <String, Object>{
        'panelOpacity': panelOpacity,
        'customAcrylicTint': customAcrylicTint,
        'acrylicTintOpacity': acrylicTintOpacity,
        'micaAlt': micaAlt,
      };

  static double _opacity(Object? value, double fallback, {double minimum = 0}) =>
      value is num && value.isFinite ? value.toDouble().clamp(minimum, 1.0) : fallback;

  static Map<GlassEffect, GlassEffectOptions> decodeSettings(String? encoded) {
    if (encoded == null || encoded.isEmpty) return <GlassEffect, GlassEffectOptions>{};
    try {
      final Object? decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return <GlassEffect, GlassEffectOptions>{};
      return <GlassEffect, GlassEffectOptions>{
        for (final GlassEffect effect in GlassEffect.values)
          if (effect != GlassEffect.none && decoded[effect.name] is Map<String, dynamic>)
            effect: GlassEffectOptions.fromMap(decoded[effect.name] as Map<String, dynamic>),
      };
    } on FormatException {
      return <GlassEffect, GlassEffectOptions>{};
    }
  }
}
