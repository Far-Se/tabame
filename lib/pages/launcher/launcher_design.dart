import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/classes/saved_maps.dart';
import '../../models/design_settings.dart';
import '../../models/settings.dart';

part 'launcher_design_config.dart';
part 'launcher_palette.dart';

/// Paper, indigo and a small vermilion seal, with user palette overrides intact.
abstract final class UkiyoeTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.74), background);
  static Color get border => Color.alphaBlend(accent.withValues(alpha: 0.35), background);
  static Color get vermilion => isDark ? const Color(0xFFD18A70) : const Color(0xFFAD4737);

  static TextStyle font({double size = 14, Color? color, FontWeight weight = FontWeight.w500, double spacing = 0}) =>
      launcherTextStyle(GoogleFonts.zenKakuGothicNew(
        fontSize: size,
        color: color ?? foreground,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.3,
      ));

  static TextStyle title() => launcherTextStyle(GoogleFonts.shipporiMincho(
        fontSize: 23,
        fontWeight: FontWeight.w600,
        color: foreground,
        height: 1.15,
        letterSpacing: 0.5,
      ));
}

/// Electric light on a midnight canvas. Both default modes use the reference's
/// dark palette; custom launcher colors and fonts still apply.
abstract final class RadiantTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => accent.withValues(alpha: 0.35);

  static TextStyle font({double size = 14, Color? color, FontWeight weight = FontWeight.w500, double spacing = 0}) =>
      launcherTextStyle(GoogleFonts.mulish(
        fontSize: size,
        color: color ?? foreground,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.3,
      ));
}

/// Botanical ink on warm paper; launcher color and font overrides stay active.
abstract final class NouveauTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => Color.alphaBlend(accent.withValues(alpha: 0.32), background);
  static Color get brass => isDark ? const Color(0xFFC9A36B) : const Color(0xFFA1763D);

  static TextStyle font({double size = 14, Color? color, FontWeight weight = FontWeight.w400, double spacing = 0}) =>
      launcherTextStyle(GoogleFonts.commissioner(
        fontSize: size,
        color: color ?? foreground,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.3,
      ));
}

/// Matte, low-chroma materials; user palette and font overrides remain active.
abstract final class SatinTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.72), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: 0.16), background);

  static TextStyle font({double size = 14, Color? color, FontWeight weight = FontWeight.w500, double spacing = 0}) =>
      launcherTextStyle(GoogleFonts.barlow(
        fontSize: size,
        color: color ?? foreground,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.3,
      ));

  static TextStyle label() => launcherTextStyle(GoogleFonts.archivo(
        fontSize: 10,
        color: dim,
        fontWeight: FontWeight.w500,
        letterSpacing: 1.8,
      ));
}

abstract final class ThermalTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  // Thermal's heat response is intentionally a subdued version of the user
  // accent so focus stays visible without becoming the brightest surface.
  static Color get accent => Color.alphaBlend(user.launcherThemeColors.accent.withValues(alpha: 0.5), background);
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.8 : 0.64), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.18 : 0.2), background);
  static Color get rust => isDark ? const Color(0xFF653725) : const Color(0xFFA8542C);

  static TextStyle font({
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double spacing = 0,
  }) =>
      launcherTextStyle(GoogleFonts.hankenGrotesk(
        fontSize: size,
        color: color ?? foreground,
        fontWeight: weight,
        letterSpacing: spacing,
        height: 1.3,
      ));

  static TextStyle label() => launcherTextStyle(GoogleFonts.archivo(
        fontSize: 10,
        color: dim,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ));
}

@immutable
class CapillaryTokens {
  const CapillaryTokens._({
    required this.background,
    required this.foreground,
    required this.accent,
    required this.dim,
    required this.border,
  });

  static const CapillaryTokens light = CapillaryTokens._(
    background: Color(0xFFF3F0E6),
    foreground: Color(0xFF252C3C),
    accent: Color(0xFF354B82),
    dim: Color(0xFF5E6574),
    border: Color(0xFFC9C8C1),
  );
  static const CapillaryTokens dark = CapillaryTokens._(
    background: Color(0xFF191C24),
    foreground: Color(0xFFE8E6DE),
    accent: Color(0xFF94A6D9),
    dim: Color(0xFFA2A7B4),
    border: Color(0xFF3A404F),
  );

  static CapillaryTokens resolve(bool isDark) => isDark ? dark : light;
  static CapillaryTokens of(BuildContext context) => resolve(Theme.of(context).brightness == Brightness.dark);

  final Color background;
  final Color foreground;
  final Color accent;
  final Color dim;
  final Color border;

  TextStyle font({
    double size = 14,
    Color? color,
    double spacing = 0,
    FontWeight weight = FontWeight.w500,
  }) =>
      launcherTextStyle(GoogleFonts.commissioner(
        fontSize: size,
        color: color ?? foreground,
        letterSpacing: spacing,
        fontWeight: weight,
        height: 1.3,
      ));

  TextStyle title() => launcherTextStyle(GoogleFonts.literata(
        fontSize: 17,
        color: foreground,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ));
}

abstract final class OpticalGlassTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.65 : 0.72), background);
  static Color get border => accent.withAlpha(isDark ? 120 : 128);

  static TextStyle font({double size = 14, Color? color, double spacing = 0, FontWeight weight = FontWeight.w500}) =>
      launcherTextStyle(GoogleFonts.mulish(
          fontSize: size, color: color ?? foreground, letterSpacing: spacing, fontWeight: weight, height: 1.3));
}

abstract final class LiquidMetalTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.68 : 0.58), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.22 : 0.28), background);

  static TextStyle font({double size = 14, Color? color, double spacing = 0, FontWeight weight = FontWeight.w500}) =>
      launcherTextStyle(GoogleFonts.barlow(
          fontSize: size, color: color ?? foreground, letterSpacing: spacing, fontWeight: weight, height: 1.25));
}

TextStyle launcherTextStyle(TextStyle designStyle) {
  if (!Design.useCustomFont) return designStyle;

  try {
    return GoogleFonts.getFont(
      Design.uiFontFamily,
      textStyle: designStyle.copyWith(
        fontWeight: FontWeight(Design.uiFontWeight),
        fontStyle: Design.uiFontItalic ? FontStyle.italic : FontStyle.normal,
      ),
    );
  } catch (_) {
    return designStyle;
  }
}

TextTheme launcherTextTheme(TextTheme designTextTheme) {
  if (!Design.useCustomFont) return designTextTheme;

  try {
    return GoogleFonts.getTextTheme(Design.uiFontFamily, designTextTheme);
  } catch (_) {
    return designTextTheme;
  }
}

/// Terminal colors derived from the active Launcher Design Colors.
/// Read launcher settings directly so action dialogs use the same palette.
abstract final class OmarchyTokens {
  static Color get bg => user.launcherThemeColors.background;
  static Color get fg => user.launcherThemeColors.text;
  static Color get dim => Color.alphaBlend(fg.withValues(alpha: 0.72), bg);
  static Color get accent => user.launcherThemeColors.accent;
  static Color get selected => Color.alphaBlend(accent.withValues(alpha: 0.18), bg);
  static Color get border => Color.alphaBlend(fg.withValues(alpha: 0.42), bg);

  static TextStyle mono(
          {double? fontSize, FontWeight? fontWeight, Color? color, double? letterSpacing, double? height}) =>
      launcherTextStyle(GoogleFonts.inconsolata(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      ));
}

/// Native console lettering and user-configured console colors.
abstract final class TuiTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: 0.4), background);
  static double get fontSize => Design.baseFontSize + 6;

  static TextStyle mono(
          {double? fontSize, FontWeight? fontWeight, Color? color, double? letterSpacing, double? height}) =>
      launcherTextStyle(TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: const <String>['Lucida Console', 'monospace'],
        fontSize: fontSize ?? TuiTokens.fontSize,
        fontWeight: fontWeight ?? FontWeight.w400,
        color: color ?? foreground,
        letterSpacing: letterSpacing ?? 0,
        height: height ?? 1.125,
      ));
}

/// Shared visual tokens for the original Terminal launcher design.
abstract final class TerminalTokens {
  static const Color _bgDark = Color(0xFF0C0C0C);
  static const Color _chromeDark = Color(0xFF161616);
  static const Color _fgDark = Color(0xFFCCCCCC);
  static const Color _dimDark = Color(0xFF7A7A7A);

  static const Color _bgLight = Color(0xFFF4F4F1);
  static const Color _chromeLight = Color(0xFFE7E7E2);
  static const Color _fgLight = Color(0xFF2A2A2A);
  static const Color _dimLight = Color(0xFF6C6C6C);

  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Shared visual tokens for the Terminal2 (TUI) launcher design.
///
/// The Terminal design overrides the active theme with a forced console palette
/// so it always reads as a command prompt — regardless of the user's chosen
/// launcher colors. Two curated palettes adapt to the active brightness: a
/// near-black screen with light phosphor text in dark mode, and a soft "paper
/// console" with dark ink in light mode. The accent stays user-driven (prompt,
/// cursor, selection).
abstract final class Terminal2Tokens {
  // Dark — near-black screen (Windows Terminal default).
  static const Color _bgDark = Color(0xFF10130F);
  static const Color _chromeDark = Color(0xFF171B15);
  static const Color _raisedDark = Color(0xFF20261D);
  static const Color _fgDark = Color(0xFFE4E7D5);
  static const Color _dimDark = Color(0xFF89917D);
  static const Color _amberDark = Color(0xFFE8B86A);

  // Light — "paper console": off-white screen, dark ink.
  static const Color _bgLight = Color(0xFFF2F1E8);
  static const Color _chromeLight = Color(0xFFE7E6D9);
  static const Color _raisedLight = Color(0xFFDCDDCF);
  static const Color _fgLight = Color(0xFF242A20);
  static const Color _dimLight = Color(0xFF6D7566);
  static const Color _amberLight = Color(0xFF9A5D16);

  /// Console "screen" background.
  static Color bg(bool isDark) => isDark ? _bgDark : _bgLight;

  /// Slightly raised chrome (title bar / status bar).
  static Color chrome(bool isDark) => isDark ? _chromeDark : _chromeLight;

  /// Active-line surface used for hover and keyboard selection.
  static Color raised(bool isDark) => isDark ? _raisedDark : _raisedLight;

  /// Primary foreground.
  static Color fg(bool isDark) => isDark ? _fgDark : _fgLight;

  /// Dimmed/secondary foreground.
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  /// Secondary semantic color for modes, counts, and state.
  static Color amber(bool isDark) => isDark ? _amberDark : _amberLight;

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.fragmentMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  static TextStyle label({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.azeretMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(GoogleFonts.quicksand(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(GoogleFonts.chakraPetch(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(GoogleFonts.overpass(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Windows XP Luna palette and Tahoma typography.
/// Blue Luna chrome with launcher colors for dark surfaces.
abstract final class WindowsXpTokens {
  static bool get _isDark =>
      ThemeData.estimateBrightnessForColor(user.launcherThemeColors.background) == Brightness.dark;
  static Color get surface => _isDark ? user.launcherThemeColors.background : const Color(0xFFECE9D8);
  static Color get paper => _isDark
      ? Color.alphaBlend(user.launcherThemeColors.text.withAlpha(10), user.launcherThemeColors.background)
      : const Color(0xFFFFFEF5);
  static const Color blueDark = Color(0xFF003399);
  static const Color blue = Color(0xFF245EDC);
  static const Color blueLight = Color(0xFF5A8CF0);
  static const Color blueHighlight = Color(0xFF7AA5F7);
  static const Color selection = Color(0xFF316AC5);
  static Color get foreground => _isDark ? user.launcherThemeColors.text : const Color(0xFF000000);
  static Color get dim => _isDark ? user.launcherThemeColors.text.withAlpha(170) : const Color(0xFF5D5D5D);
  static const Color controlShadow = Color(0xFF716F64);
  static Color get controlLight => _isDark
      ? Color.alphaBlend(user.launcherThemeColors.text.withAlpha(12), user.launcherThemeColors.background)
      : const Color(0xFFFFFFFF);
  static const Color orange = Color(0xFFFF8C00);
  static const Color green = Color(0xFF4BAE31);

  static TextStyle tahoma({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'Tahoma',
      fontFamilyFallback: const <String>['Verdana', 'Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Windows 98 shell palette, beveled control colors and bitmap-era type.
abstract final class Windows98Tokens {
  static bool get _isDark =>
      ThemeData.estimateBrightnessForColor(user.launcherThemeColors.background) == Brightness.dark;
  static Color get face => _isDark ? user.launcherThemeColors.background : const Color(0xFFC0C0C0);
  static Color get field => _isDark
      ? Color.alphaBlend(user.launcherThemeColors.text.withAlpha(12), user.launcherThemeColors.background)
      : const Color(0xFFFFFFFF);
  static Color get light => _isDark ? user.launcherThemeColors.text.withAlpha(220) : const Color(0xFFFFFFFF);
  static Color get highlight => _isDark ? user.launcherThemeColors.text.withAlpha(150) : const Color(0xFFDFDFDF);
  static Color get shadow => _isDark ? user.launcherThemeColors.text.withAlpha(80) : const Color(0xFF808080);
  static Color get dark => _isDark ? user.launcherThemeColors.text.withAlpha(45) : const Color(0xFF000000);
  static const Color title = Color(0xFF000080);
  static const Color titleLight = Color(0xFF1084D0);
  static const Color selection = Color(0xFF000080);
  static Color get foreground => _isDark ? user.launcherThemeColors.text : const Color(0xFF000000);
  static Color get dim => _isDark ? user.launcherThemeColors.text.withAlpha(170) : const Color(0xFF5A5A5A);

  static TextStyle system({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'MS Sans Serif',
      fontFamilyFallback: const <String>['Tahoma', 'Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Notion-inspired workspace surfaces and typography.
abstract final class NotionTokens {
  static Color canvas(bool isDark) => isDark ? const Color(0xFF202020) : const Color(0xFFFFFFFF);
  static Color sidebar(bool isDark) => isDark ? const Color(0xFF191919) : const Color(0xFFF7F6F3);
  static Color foreground(bool isDark) => isDark ? const Color(0xFFE6E6E6) : const Color(0xFF37352F);
  static Color dim(bool isDark) => isDark ? const Color(0xFF9B9B9B) : const Color(0xFF787774);
  static Color blue(bool isDark) => isDark ? const Color(0xFF529CCA) : const Color(0xFF2383E2);
  static Color selection(bool isDark) => foreground(isDark).withAlpha(isDark ? 18 : 14);
  static Color border(bool isDark) => foreground(isDark).withAlpha(isDark ? 24 : 18);

  static TextStyle ui({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Operations-desk palette and typography for the Switchboard launcher.
///
/// Switchboard treats the launcher as a compact workstation rather than a
/// themed list. Its tinted neutral surfaces create hierarchy without relying
/// on blur or heavy shadows; the user's accent is reserved for live controls.
abstract final class SwitchboardTokens {
  static Color canvas(bool isDark) => isDark ? const Color(0xFF141816) : const Color(0xFFEDF0EB);
  static Color panel(bool isDark) => isDark ? const Color(0xFF1B211E) : const Color(0xFFF8F9F5);
  static Color raised(bool isDark) => isDark ? const Color(0xFF242C28) : const Color(0xFFE2E8E1);
  static Color foreground(bool isDark) => isDark ? const Color(0xFFE8EEE9) : const Color(0xFF1C251F);
  static Color dim(bool isDark) => isDark ? const Color(0xFF93A198) : const Color(0xFF66746B);
  static Color border(bool isDark) => isDark ? const Color(0xFF35413B) : const Color(0xFFCBD3CC);

  static TextStyle body({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.publicSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  static TextStyle label({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.barlowCondensed(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(TextStyle(
      fontFamily: 'Bahnschrift Condensed',
      fontFamilyFallback: const <String>['Bahnschrift', 'Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  static TextStyle body({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
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
    return launcherTextStyle(GoogleFonts.spaceGrotesk(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  /// Telemetry voice — IBM Plex Mono for readouts, micro labels and kbd hints.
  static TextStyle tele({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.ibmPlexMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Shared palette and typography for the Relay communications backplane.
///
/// Relay keeps the user's accent as its live signal color and subtly folds it
/// into otherwise quiet graphite/porcelain surfaces. Encode Sans carries the
/// readable command content while Teko gives channel labels the narrow voice
/// of stamped equipment legends without falling back to generic monospace.
abstract final class RelayTokens {
  static const Color _canvasDark = Color(0xFF18181D);
  static const Color _panelDark = Color(0xFF202027);
  static const Color _raisedDark = Color(0xFF292933);
  static const Color _foregroundDark = Color(0xFFECEAF0);
  static const Color _dimDark = Color(0xFF97939F);

  static const Color _canvasLight = Color(0xFFF2F0E9);
  static const Color _panelLight = Color(0xFFFAF8F2);
  static const Color _raisedLight = Color(0xFFE7E3DA);
  static const Color _foregroundLight = Color(0xFF25232A);
  static const Color _dimLight = Color(0xFF716D77);

  static Color _tint(Color base, Color accent, int alpha) => Color.alphaBlend(accent.withAlpha(alpha), base);

  static Color canvas(bool isDark, Color accent) => _tint(isDark ? _canvasDark : _canvasLight, accent, isDark ? 9 : 6);

  static Color panel(bool isDark, Color accent) => _tint(isDark ? _panelDark : _panelLight, accent, isDark ? 12 : 7);

  static Color raised(bool isDark, Color accent) =>
      _tint(isDark ? _raisedDark : _raisedLight, accent, isDark ? 16 : 10);

  static Color foreground(bool isDark) => isDark ? _foregroundDark : _foregroundLight;

  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  static Color border(bool isDark, Color accent) =>
      Color.alphaBlend(accent.withAlpha(isDark ? 48 : 34), isDark ? const Color(0xFF34323B) : const Color(0xFFD2CEC4));

  static TextStyle body({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.encodeSans(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  static TextStyle channel({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.teko(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

/// Raycast-inspired command-palette tokens.
///
/// This design intentionally owns its neutral palette instead of inheriting
/// the user's launcher colors. The palette follows the host brightness so the
/// shell remains legible in both light and dark mode. Result icons still keep
/// their source colors; the shell reserves color for legibility, selection and
/// depth.
abstract final class RaycastTokens {
  static const Color _surfaceDark = Color(0xFF1C1C1E);
  static const Color _deepSurfaceDark = Color(0xFF151517);
  static const Color _selectedDark = Color(0xFF3A3A3C);
  static const Color _dividerDark = Color(0xFF2A2A2C);
  static const Color _badgeDark = Color(0xFF2C2C2E);
  static const Color _primaryDark = Color(0xFFF2F2F7);
  static const Color _secondaryDark = Color(0xFFD1D1D6);
  static const Color _mutedDark = Color(0xFF8E8E93);
  static const Color _dimDark = Color(0xFF6E6E73);

  static const Color _surfaceLight = Color(0xFFF7F7F8);
  static const Color _deepSurfaceLight = Color(0xFFF0F0F2);
  static const Color _selectedLight = Color(0xFFE4E4E7);
  static const Color _dividerLight = Color(0xFFD9D9DD);
  static const Color _badgeLight = Color(0xFFEAEAED);
  static const Color _primaryLight = Color(0xFF1C1C1E);
  static const Color _secondaryLight = Color(0xFF48484A);
  static const Color _mutedLight = Color(0xFF636366);
  static const Color _dimLight = Color(0xFF8E8E93);

  static Color surface(bool isDark) => isDark ? _surfaceDark : _surfaceLight;
  static Color deepSurface(bool isDark) => isDark ? _deepSurfaceDark : _deepSurfaceLight;
  static Color selected(bool isDark) => isDark ? _selectedDark : _selectedLight;
  static Color divider(bool isDark) => isDark ? _dividerDark : _dividerLight;
  static Color badge(bool isDark) => isDark ? _badgeDark : _badgeLight;
  static Color primary(bool isDark) => isDark ? _primaryDark : _primaryLight;
  static Color secondary(bool isDark) => isDark ? _secondaryDark : _secondaryLight;
  static Color muted(bool isDark) => isDark ? _mutedDark : _mutedLight;
  static Color dim(bool isDark) => isDark ? _dimDark : _dimLight;

  static TextStyle ui({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'Segoe UI Variable Text',
      fontFamilyFallback: const <String>['Segoe UI', 'Arial'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }

  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return launcherTextStyle(TextStyle(
      fontFamily: 'Cascadia Mono',
      fontFamilyFallback: const <String>['Consolas', 'Segoe UI'],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    ));
  }
}

@immutable
class LauncherThemeData {
  const LauncherThemeData({required this.design});

  final LauncherDesign design;

  LauncherDesignConfig get config => LauncherDesignConfig.forDesign(design);

  bool get isSerene => design == LauncherDesign.serene;
  bool get isClassic => design == LauncherDesign.classic;
  bool get isCommand => design == LauncherDesign.command;
  bool get isTerminal => design == LauncherDesign.terminal;
  bool get isTerminal2 => design == LauncherDesign.terminal2;
  bool get isZen => design == LauncherDesign.zen;
  bool get isGlass => design == LauncherDesign.glass;
  bool get isBlueprint => design == LauncherDesign.blueprint;
  bool get isTransit => design == LauncherDesign.transit;
  bool get isFluent => design == LauncherDesign.fluent;
  bool get isManifesto => design == LauncherDesign.manifesto;
  bool get isOrbit => design == LauncherDesign.orbit;
  bool get isAnime => design == LauncherDesign.anime;
  bool get isWindowsXp => design == LauncherDesign.windowsXp;
  bool get isWindows98 => design == LauncherDesign.windows98;
  bool get isNotion => design == LauncherDesign.notion;
  bool get isSwitchboard => design == LauncherDesign.switchboard;
  bool get isRelay => design == LauncherDesign.relay;
  bool get isRaycast => design == LauncherDesign.newCast;
  bool get isRetro => design == LauncherDesign.retro;
  bool get isToon => design == LauncherDesign.toon;
  bool get isQuickMenuInspired => config.isQuickMenuInspired;

  /// Leading glyph in the search bar — a chevron prompt for the Command/Terminal
  /// consoles, a leaf for Zen, a drafting compass for Blueprint, a radar scope
  /// for Orbit, a magnifier otherwise.
  IconData get searchIcon => config.searchIcon;

  double get searchIconSize => config.searchIconSize;

  bool get searchIconUsesOnSurface => config.searchIconUsesOnSurface;

  double get searchFontSize => config.searchFontSize;
  FontWeight? get searchFontWeight => config.searchFontWeight;

  String? get searchHint => config.searchHint;

  double get frameRadius => config.frameRadius;

  EdgeInsets get resultsListPadding => config.resultsListPadding;

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
    required this.palette,
    required super.child,
  });

  final LauncherThemeData data;

  final LauncherPalette palette;

  static LauncherPalette? maybePaletteOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LauncherTheme>()?.palette;

  static Color accentOf(BuildContext context) =>
      maybePaletteOf(context)?.accent ?? Theme.of(context).colorScheme.primary;

  static LauncherThemeData of(BuildContext context) {
    final LauncherTheme? theme = context.dependOnInheritedWidgetOfExactType<LauncherTheme>();
    assert(theme != null, 'No LauncherTheme found in context');
    return theme!.data;
  }

  static LauncherThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LauncherTheme>()?.data;

  @override
  bool updateShouldNotify(LauncherTheme oldWidget) => data != oldWidget.data || palette != oldWidget.palette;
}

/// Reference palette for the Aurora night landscape design.
abstract final class AuroraTokens {
  static const Color background = Color(0xFF031722);
  static const Color panel = Color(0xD9081B27);
  static const Color accent = Color(0xFF00E5F5);
  static const Color foreground = Color(0xFFE4F5FF);
  static const Color dim = Color(0xFF8BBAD7);
  static const Color border = Color(0xFF16556A);
  static TextStyle font({double size = 13, Color color = foreground, double? spacing}) =>
      launcherTextStyle(TextStyle(fontFamily: 'Segoe UI', fontSize: size, color: color, letterSpacing: spacing));
}

/// Slate surfaces and cyan outlines from the Strata reference.
abstract final class StrataTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get panel => isDark
      ? Color.alphaBlend(foreground.withAlpha(6), background)
      : Color.alphaBlend(Colors.white.withAlpha(108), background);
  static Color get accent => user.launcherThemeColors.accent;
  static Color get foreground => user.launcherThemeColors.text;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.69 : 0.68), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.095 : 0.22), background);
  static TextStyle font({double size = 13, Color? color, double? spacing}) => launcherTextStyle(
      TextStyle(fontFamily: 'Segoe UI', fontSize: size, color: color ?? foreground, letterSpacing: spacing));
}

/// The green console palette from the Phosphor reference.
abstract final class PhosphorTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get panel => isDark
      ? Color.alphaBlend(foreground.withAlpha(4), background)
      : Color.alphaBlend(Colors.white.withAlpha(110), background);
  static Color get accent => user.launcherThemeColors.accent;
  static Color get foreground => user.launcherThemeColors.text;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.58 : 0.65), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: isDark ? 0.18 : 0.22), background);
  static Color get cyan => isDark ? const Color(0xFF51BCD5) : const Color(0xFF247B91);
  static Color get yellow => isDark ? const Color(0xFFE6C85C) : const Color(0xFF956C12);
  static TextStyle font({double size = 13, Color? color, double? spacing}) => launcherTextStyle(TextStyle(
      fontFamily: 'Consolas',
      fontFamilyFallback: const <String>['Cascadia Mono', 'monospace'],
      fontSize: size,
      color: color ?? foreground,
      letterSpacing: spacing,
      height: 1.3));
}

/// CRT colors follow the active Launcher Colors, including derived chrome.
abstract final class CrtTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => Color.alphaBlend(accent.withValues(alpha: 0.38), background);
  static Color get bezel => Color.alphaBlend(accent.withValues(alpha: 0.12), background);
  static Color get selected => Color.alphaBlend(accent.withValues(alpha: 0.16), background);
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static TextStyle font({double size = 13, Color? color, double? spacing}) =>
      PhosphorTokens.font(size: size, color: color ?? foreground, spacing: spacing);
}

/// Warm paper, ink, and signal colors for the comic-book Toon launcher.
/// The shader applies the final posterization and outline pass to the live UI.
abstract final class ToonTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
  static Color get panel =>
      Color.alphaBlend((isDark ? foreground : Colors.black).withAlpha(isDark ? 18 : 14), background);
  static Color get dim => Color.alphaBlend(foreground.withAlpha(isDark ? 210 : 165), background);
  static Color get border => Color.alphaBlend(orange.withAlpha(155), background);
  static Color get selected => Color.alphaBlend(orange.withAlpha(65), background);

  static const Color ink = Color(0xFF121519);
  static Color get orange => accent;
  static Color get cream => isDark ? const Color(0xFFFFF3D6) : foreground;
  static Color get red => isDark ? const Color(0xFFFF7961) : const Color(0xFFB84D3F);
  static Color get blue => isDark ? const Color(0xFF83ACD4) : const Color(0xFF3D7594);

  static TextStyle font({
    double size = 13,
    Color? color,
    double? spacing,
    FontWeight weight = FontWeight.w600,
    double? height,
  }) =>
      launcherTextStyle(GoogleFonts.barlowCondensed(
        fontSize: size,
        color: color ?? foreground,
        letterSpacing: spacing,
        fontWeight: weight,
        height: height ?? 1.12,
      ));
}

/// Arcade cabinet tokens and pixel-era typography for the Retro launcher.
///
/// The three base colors follow the active Launcher Design settings. The
/// remaining tones are derived from them so custom palettes stay coherent.
/// VT323 keeps result rows readable at a compact size; Press Start 2P is
/// reserved for the short labels that should feel printed on a game cabinet.
abstract final class RetroTokens {
  static Color get background => user.launcherThemeColors.background;
  static Color get foreground => user.launcherThemeColors.text;
  static Color get accent => user.launcherThemeColors.accent;
  static Color get panel => Color.alphaBlend(foreground.withValues(alpha: 0.06), background);
  static Color get bezel => Color.alphaBlend(accent.withValues(alpha: 0.12), background);
  static Color get cyan => isDark ? Color.lerp(accent, foreground, 0.45)! : const Color(0xFF2E7B93);
  static Color get yellow => isDark ? Color.lerp(accent, foreground, 0.72)! : const Color(0xFF986A16);
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => Color.alphaBlend(accent.withValues(alpha: 0.38), background);
  static Color get selected => Color.alphaBlend(accent.withValues(alpha: 0.16), background);
  static bool get isDark => ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

  static double get resultTitleSize => Design.baseFontSize + 5;

  static double get resultSubtitleSize => Design.baseFontSize + 2;

  static TextTheme resultTextTheme(TextTheme baseTextTheme) {
    final TextTheme textTheme = GoogleFonts.vt323TextTheme(baseTextTheme).apply(
      bodyColor: foreground,
      displayColor: foreground,
    );
    return textTheme.copyWith(
      bodyMedium: textTheme.bodyMedium?.copyWith(fontSize: resultTitleSize),
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: resultSubtitleSize),
    );
  }

  static TextStyle pixel({
    double size = 18,
    Color? color,
    double? spacing,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.vt323(
      fontSize: size,
      color: color ?? foreground,
      letterSpacing: spacing,
      fontWeight: weight,
      height: height ?? 1.05,
    ));
  }

  static TextStyle label({
    double size = 9,
    Color? color,
    double? spacing,
    FontWeight weight = FontWeight.w400,
    double? height,
  }) {
    return launcherTextStyle(GoogleFonts.pressStart2p(
      fontSize: size,
      color: color ?? foreground,
      letterSpacing: spacing,
      fontWeight: weight,
      height: height ?? 1.35,
    ));
  }
}
