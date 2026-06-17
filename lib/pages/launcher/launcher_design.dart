import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/settings.dart';

/// Shared visual tokens for the Terminal (CLI) launcher design.
///
/// The Terminal design intentionally overrides the active theme with a forced
/// console palette so it always reads as a command prompt — light phosphor text
/// on a near-black screen — regardless of the user's chosen launcher colors.
/// The accent stays user-driven (prompt, cursor, selection).
abstract final class TerminalTokens {
  /// Console "screen" background (Windows Terminal default black).
  static const Color bg = Color(0xFF0C0C0C);

  /// Slightly raised chrome (title bar / status bar).
  static const Color chrome = Color(0xFF161616);

  /// Primary foreground (Windows console default light gray).
  static const Color fg = Color(0xFFCCCCCC);

  /// Dimmed/secondary foreground.
  static const Color dim = Color(0xFF7A7A7A);

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Shared visual tokens for the Zen (nature) launcher design.
///
/// Like [TerminalTokens] this forces its own palette so the launcher always
/// reads as a calm, low-cortisol surface — soft sage and moss, warm paper light
/// or a moonlit-forest dark — regardless of the user's chosen colors. Two
/// curated palettes adapt to the active brightness.
abstract final class ZenTokens {
  // Light — "dawn garden".
  static const Color _bgLight = Color(0xFFEEF1E6);
  static const Color _bgLightTop = Color(0xFFF5F3EA);
  static const Color _fgLight = Color(0xFF3C463B);
  static const Color _dimLight = Color(0xFF818A78);
  static const Color _accentLight = Color(0xFF7B9A6B);

  // Dark — "moonlit forest".
  static const Color _bgDark = Color(0xFF171C18);
  static const Color _bgDarkTop = Color(0xFF1E251F);
  static const Color _fgDark = Color(0xFFD7DFCF);
  static const Color _dimDark = Color(0xFF8B9685);
  static const Color _accentDark = Color(0xFF93B281);

  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;
  static Color bgTop(bool isDark) => isDark ? _bgDarkTop : _bgLightTop;
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;
  static Color accent(bool isDark) => isDark ? _accentDark : _accentLight;

  static TextStyle soft({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.quicksand(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Typography for the Glass (iOS Liquid Glass) launcher design.
///
/// Unlike [TerminalTokens]/[ZenTokens], Glass does not force a palette — its
/// translucent surfaces pick up the active theme's colors so it works in both
/// light and dark. It only forces Inter, the closest free stand-in for the
/// San Francisco system font, to nail the iOS feel.
abstract final class GlassTokens {
  static TextStyle font({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

@immutable
class LauncherThemeData {
  const LauncherThemeData({required this.design});

  final LauncherDesign design;

  bool get isSerene => design == LauncherDesign.serene;
  bool get isClassic => design == LauncherDesign.classic;
  bool get isCommand => design == LauncherDesign.command;
  bool get isTerminal => design == LauncherDesign.terminal;
  bool get isZen => design == LauncherDesign.zen;
  bool get isGlass => design == LauncherDesign.glass;

  /// Leading glyph in the search bar — a chevron prompt for the Command/Terminal
  /// consoles, a leaf for Zen, a magnifier otherwise.
  IconData get searchIcon => switch (design) {
        LauncherDesign.command => Icons.chevron_right_rounded,
        LauncherDesign.terminal => Icons.chevron_right_rounded,
        LauncherDesign.zen => Icons.eco_rounded,
        LauncherDesign.serene => Icons.search_rounded,
        LauncherDesign.glass => Icons.search_rounded,
        LauncherDesign.classic => Icons.search_rounded,
      };

  double get searchIconSize => switch (design) {
        LauncherDesign.serene => 22.0,
        LauncherDesign.command => 22.0,
        LauncherDesign.terminal => 20.0,
        LauncherDesign.zen => 20.0,
        LauncherDesign.glass => 20.0,
        LauncherDesign.classic => 20.0,
      };

  bool get searchIconUsesOnSurface => isSerene || isGlass;

  double get searchFontSize => switch (design) {
        LauncherDesign.serene => 16.0,
        LauncherDesign.command => 15.0,
        LauncherDesign.terminal => 14.0,
        LauncherDesign.zen => 15.0,
        LauncherDesign.glass => 16.0,
        LauncherDesign.classic => 15.0,
      };
  FontWeight? get searchFontWeight => switch (design) {
        LauncherDesign.serene => FontWeight.w400,
        LauncherDesign.command => FontWeight.w500,
        LauncherDesign.terminal => FontWeight.w500,
        LauncherDesign.zen => FontWeight.w500,
        LauncherDesign.glass => FontWeight.w500,
        LauncherDesign.classic => null,
      };

  double get frameRadius => switch (design) {
        LauncherDesign.serene => 14.0,
        LauncherDesign.command => 12.0,
        LauncherDesign.terminal => 6.0,
        LauncherDesign.zen => 26.0,
        LauncherDesign.glass => 28.0,
        LauncherDesign.classic => 18.0,
      };

  EdgeInsets get resultsListPadding => const EdgeInsets.all(8.0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LauncherThemeData && runtimeType == other.runtimeType && design == other.design;

  @override
  int get hashCode => design.hashCode;
}

class LauncherTheme extends InheritedWidget {
  const LauncherTheme({
    super.key,
    required this.data,
    required super.child,
  });

  final LauncherThemeData data;

  static LauncherThemeData of(BuildContext context) {
    final LauncherTheme? theme = context.dependOnInheritedWidgetOfExactType<LauncherTheme>();
    assert(theme != null, 'No LauncherTheme found in context');
    return theme!.data;
  }

  static LauncherThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LauncherTheme>()?.data;

  @override
  bool updateShouldNotify(LauncherTheme oldWidget) => data != oldWidget.data;
}
