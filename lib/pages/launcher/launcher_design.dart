import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/settings.dart';

/// Shared visual tokens for the Terminal (CLI) launcher design.
///
/// The Terminal design overrides the active theme with a forced console palette
/// so it always reads as a command prompt — regardless of the user's chosen
/// launcher colors. Two curated palettes adapt to the active brightness: a
/// near-black screen with light phosphor text in dark mode, and a soft "paper
/// console" with dark ink in light mode. The accent stays user-driven (prompt,
/// cursor, selection).
abstract final class TerminalTokens {
  // Dark — near-black screen (Windows Terminal default).
  static const Color _bgDark = Color(0xFF0C0C0C);
  static const Color _chromeDark = Color(0xFF161616);
  static const Color _fgDark = Color(0xFFCCCCCC);
  static const Color _dimDark = Color(0xFF7A7A7A);

  // Light — "paper console": off-white screen, dark ink.
  static const Color _bgLight = Color(0xFFF4F4F1);
  static const Color _chromeLight = Color(0xFFE7E7E2);
  static const Color _fgLight = Color(0xFF2A2A2A);
  static const Color _dimLight = Color(0xFF6C6C6C);

  /// Console "screen" background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Slightly raised chrome (title bar / status bar).
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;

  /// Primary foreground.
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Dimmed/secondary foreground.
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

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

/// Shared visual tokens for the Blueprint (drafting sheet) launcher design.
///
/// Like [TerminalTokens]/[ZenTokens] this forces its own palette so the
/// launcher always reads as an engineering drawing — a cyanotype blueprint
/// (deep prussian-blue sheet, pale ink) in dark mode, and white drafting paper
/// with navy ink in light mode. Every line on the sheet — grid, borders,
/// dimension lines, balloons — is drawn in "ink" (the forced accent).
abstract final class BlueprintTokens {
  // Dark — cyanotype: deep prussian-blue sheet, pale ink.
  static const Color _bgDark = Color(0xFF0C2841);
  static const Color _fgDark = Color(0xFFD9EAF8);
  static const Color _dimDark = Color(0xFF7E9FBD);
  static const Color _accentDark = Color(0xFF7FB8E6);

  // Light — drafting paper: cool white sheet, navy ink.
  static const Color _bgLight = Color(0xFFD9D8FF);
  static const Color _fgLight = Color(0xFF1F4467);
  static const Color _dimLight = Color(0xFF6F8CA6);
  static const Color _accentLight = Color(0xFF2E6DA4);

  /// Sheet background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Primary ink (titles, values, sheet border).
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Dimmed ink (labels, subtitles, minor grid).
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  /// Bright drafting ink — the forced accent (selection, dimension lines).
  static Color accent(bool isDark) => isDark ? _accentDark : _accentLight;

  /// Squared technical lettering — the drafting-stencil voice of the sheet.
  static TextStyle tech({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.chakraPetch(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Shared visual tokens for the Transit (metro map) launcher design.
///
/// Like [TerminalTokens] this forces its own palette so the launcher always
/// reads as wayfinding signage — a night-service dark board or a clean white
/// station sign in light mode. The user accent stays in charge as "your line
/// color": the route line, roundels, bands and zone markers are all drawn in
/// it, so every accent choice becomes a different metro line.
abstract final class TransitTokens {
  // Dark — night network board.
  static const Color _bgDark = Color(0xFF15181D);
  static const Color _chromeDark = Color(0xFF1C2026);
  static const Color _fgDark = Color(0xFFE9EDF2);
  static const Color _dimDark = Color(0xFF8C96A3);

  // Light — enamel station sign.
  static const Color _bgLight = Color(0xFFF7F7F4);
  static const Color _chromeLight = Color(0xFFECECE7);
  static const Color _fgLight = Color(0xFF17191C);
  static const Color _dimLight = Color(0xFF70767E);

  /// Sign background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Slightly raised chrome (platform strip / footer).
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;

  /// Primary lettering.
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Dimmed lettering (connections, captions).
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  /// Signage lettering — Overpass, digitised from US highway-sign alphabets.
  static TextStyle sign({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.overpass(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Shared visual tokens for the Fluent (Windows 11) launcher design.
///
/// Like [TerminalTokens] this forces its own palette — the Windows 11 "Mica"
/// neutrals: the smoky #202020 sheet in dark mode, the frosted #F3F3F3 one in
/// light. The user accent stays in charge (selection pill, focus underline),
/// exactly like the system accent color in Windows. Typography is Segoe UI
/// Variable with a plain Segoe UI fallback — the native voice of the OS, no
/// bundled font needed.
abstract final class FluentTokens {
  // Dark — mica dark.
  static const Color _bgDark = Color(0xFF202020);
  static const Color _chromeDark = Color(0xFF1B1B1B);
  static const Color _fgDark = Color(0xFFFFFFFF);
  static const Color _dimDark = Color(0xFF9D9D9D);

  // Light — mica light.
  static const Color _bgLight = Color(0xFFF3F3F3);
  static const Color _chromeLight = Color(0xFFEBEBEB);
  static const Color _fgLight = Color(0xFF1B1B1B);
  static const Color _dimLight = Color(0xFF5D5D5D);

  /// Mica window background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Slightly shifted chrome (footer strip), like the Start menu's bottom bar.
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;

  /// Primary foreground.
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Secondary foreground (subtitles, captions).
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  /// Hairline control stroke (WinUI "ControlStrokeColorDefault").
  static Color stroke(bool isDark) => isDark ? const Color(0x17FFFFFF) : const Color(0x12000000);

  /// Faint layer fill a WinUI text box / list item sits on.
  static Color fill(bool isDark) => isDark ? const Color(0x0FFFFFFF) : const Color(0xB3FFFFFF);

  /// Segoe UI Variable (Win11) with the classic Segoe UI as fallback (Win10).
  static TextStyle segoe({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Shared palette and typography for the Manifesto editorial launcher.
abstract final class ManifestoTokens {
  static const Color _bgLight = Color(0xFFF2EEDB);
  static const Color _fgLight = Color(0xFF171713);
  static const Color _dimLight = Color(0xFF6C685C);
  static const Color _accentLight = Color(0xFFE13A27);

  static const Color _bgDark = Color(0xFF171713);
  static const Color _fgDark = Color(0xFFF2EEDB);
  static const Color _dimDark = Color(0xFFA7A28F);
  static const Color _accentDark = Color(0xFFF0D83A);

  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;
  static Color accent(bool isDark) => isDark ? _accentDark : _accentLight;

  static TextStyle display({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Bahnschrift Condensed',
      fontFamilyFallback: const <String>['Bahnschrift', 'Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  static TextStyle body({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }
}

/// Shared visual tokens for the Orbit (spacecraft guidance HUD) launcher design.
///
/// Like [TerminalTokens] this forces its own palette so the launcher always
/// reads as a guidance computer — a deep-space scope in dark mode, a daylight
/// instrument panel in light mode. The user accent stays in charge as the
/// "lock" color: reticle brackets, the radar sweep, track markers and telemetry
/// readouts are all drawn in it.
abstract final class OrbitTokens {
  // Dark — deep-space scope.
  static const Color _bgDark = Color(0xFF04090E);
  static const Color _chromeDark = Color(0xFF0A121A);
  static const Color _fgDark = Color(0xFFD9E8E4);
  static const Color _dimDark = Color(0xFF64787F);

  // Light — daylight instrument panel.
  static const Color _bgLight = Color(0xFFEEF3EF);
  static const Color _chromeLight = Color(0xFFE0E9E3);
  static const Color _fgLight = Color(0xFF1C2A28);
  static const Color _dimLight = Color(0xFF5E706B);

  /// Scope background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Slightly raised chrome (telemetry strip).
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;

  /// Primary phosphor foreground.
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Dimmed foreground (captions, minor ticks).
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  /// Display voice — Space Grotesk, the geometric-technical face of flight
  /// instrumentation labels.
  static TextStyle disp({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Telemetry voice — IBM Plex Mono for readouts, micro labels and kbd hints.
  static TextStyle tele({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.ibmPlexMono(
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
  bool get isBlueprint => design == LauncherDesign.blueprint;
  bool get isTransit => design == LauncherDesign.transit;
  bool get isFluent => design == LauncherDesign.fluent;
  bool get isManifesto => design == LauncherDesign.manifesto;
  bool get isOrbit => design == LauncherDesign.orbit;

  /// Leading glyph in the search bar — a chevron prompt for the Command/Terminal
  /// consoles, a leaf for Zen, a drafting compass for Blueprint, a radar scope
  /// for Orbit, a magnifier otherwise.
  IconData get searchIcon => switch (design) {
        LauncherDesign.command => Icons.chevron_right_rounded,
        LauncherDesign.terminal => Icons.chevron_right_rounded,
        LauncherDesign.zen => Icons.eco_rounded,
        LauncherDesign.serene => Icons.search_rounded,
        LauncherDesign.glass => Icons.search_rounded,
        LauncherDesign.classic => Icons.search_rounded,
        LauncherDesign.blueprint => Icons.architecture_rounded,
        LauncherDesign.transit => Icons.near_me_rounded,
        LauncherDesign.fluent => Icons.search_rounded,
        LauncherDesign.manifesto => Icons.arrow_forward,
        LauncherDesign.orbit => Icons.radar,
      };

  double get searchIconSize => switch (design) {
        LauncherDesign.serene => 22.0,
        LauncherDesign.command => 22.0,
        LauncherDesign.terminal => 20.0,
        LauncherDesign.zen => 20.0,
        LauncherDesign.glass => 20.0,
        LauncherDesign.classic => 20.0,
        LauncherDesign.blueprint => 20.0,
        LauncherDesign.transit => 16.0,
        LauncherDesign.fluent => 18.0,
        LauncherDesign.manifesto => 18.0,
        LauncherDesign.orbit => 19.0,
      };

  bool get searchIconUsesOnSurface => isSerene || isGlass || isFluent;

  double get searchFontSize => switch (design) {
        LauncherDesign.serene => 16.0,
        LauncherDesign.command => 15.0,
        LauncherDesign.terminal => 14.0,
        LauncherDesign.zen => 15.0,
        LauncherDesign.glass => 16.0,
        LauncherDesign.classic => 15.0,
        LauncherDesign.blueprint => 15.0,
        LauncherDesign.transit => 15.0,
        LauncherDesign.fluent => 15.0,
        LauncherDesign.manifesto => 17.0,
        LauncherDesign.orbit => 15.0,
      };
  FontWeight? get searchFontWeight => switch (design) {
        LauncherDesign.serene => FontWeight.w400,
        LauncherDesign.command => FontWeight.w500,
        LauncherDesign.terminal => FontWeight.w500,
        LauncherDesign.zen => FontWeight.w500,
        LauncherDesign.glass => FontWeight.w500,
        LauncherDesign.classic => null,
        LauncherDesign.blueprint => FontWeight.w500,
        LauncherDesign.transit => FontWeight.w600,
        LauncherDesign.fluent => FontWeight.w400,
        LauncherDesign.manifesto => FontWeight.w600,
        LauncherDesign.orbit => FontWeight.w500,
      };

  double get frameRadius => switch (design) {
        LauncherDesign.serene => 14.0,
        LauncherDesign.command => 12.0,
        LauncherDesign.terminal => 6.0,
        LauncherDesign.zen => 26.0,
        LauncherDesign.glass => 28.0,
        LauncherDesign.classic => 18.0,
        LauncherDesign.blueprint => 3.0,
        LauncherDesign.transit => 16.0,
        LauncherDesign.fluent => 8.0,
        LauncherDesign.manifesto => 0.0,
        LauncherDesign.orbit => 10.0,
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
