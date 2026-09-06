import 'package:flutter/material.dart';

import '../settings.dart';

/// QuickMenu's console presentation uses its own active design colors.
abstract final class QuickMenuTuiTheme {
  static Color get background => user.themeColors.background;
  static Color get foreground => user.themeColors.text;
  static Color get accent => user.themeColors.accent;
  static Color get dim => Color.alphaBlend(foreground.withValues(alpha: 0.7), background);
  static Color get border => Color.alphaBlend(foreground.withValues(alpha: 0.4), background);
  static TextStyle text({Color? color, double? size}) => TextStyle(
        fontFamily: 'Consolas',
        fontFamilyFallback: const <String>['Lucida Console', 'monospace'],
        fontSize: size ?? Design.baseFontSize + 4,
        fontWeight: FontWeight.w400,
        color: color ?? foreground,
        height: 1.125,
        letterSpacing: 0,
      );

  static ThemeData theme(ThemeData base) => base.copyWith(
        colorScheme: base.colorScheme.copyWith(surface: background, onSurface: foreground, primary: accent),
        scaffoldBackgroundColor: background,
        splashFactory: NoSplash.splashFactory,
        hoverColor: foreground.withValues(alpha: 0.12),
        highlightColor: foreground.withValues(alpha: 0.18),
        textTheme: base.textTheme.apply(
            fontFamily: 'Consolas',
            fontFamilyFallback: const <String>['Lucida Console', 'monospace'],
            bodyColor: foreground,
            displayColor: foreground),
        iconTheme: IconThemeData(color: foreground, size: 16),
        textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
                foregroundColor: foreground, textStyle: text(), shape: const RoundedRectangleBorder())),
        tooltipTheme: TooltipThemeData(
            textStyle: text(size: 12), decoration: BoxDecoration(color: background, border: Border.all(color: border))),
      );
}
