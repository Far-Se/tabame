import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'classes/boxes.dart';
import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) {
    late TextTheme font;
    try {
      font = GoogleFonts.getTextTheme(userSettings.darkTheme.uiFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.darkTheme.uiFontFamily = "Roboto";
      font = GoogleFonts.getTextTheme(userSettings.darkTheme.uiFontFamily, ThemeData.dark().textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    try {
      GoogleFonts.getTextTheme(userSettings.darkTheme.entryFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.darkTheme.entryFontFamily = "Roboto";
      Boxes.saveActiveQuickMenuThemes();
    }
    return ThemeData(
      brightness: Brightness.dark,
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: userSettings.darkTheme.background,
      iconTheme: IconThemeData(color: userSettings.darkTheme.text),
      textTheme: font,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(userSettings.darkTheme.accent),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(userSettings.darkTheme.background),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered)) {
            return Colors.black.withAlpha(40);
          }
          if (states.contains(WidgetState.pressed)) return Colors.black.withAlpha(20);
          return null;
        }),
      )),
      tooltipTheme: ThemeData.dark().tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 0),
            verticalOffset: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.all(0),
            textStyle: TextStyle(color: userSettings.darkTheme.text, fontSize: 12, height: 0),
            decoration: BoxDecoration(color: userSettings.darkTheme.background),
            preferBelow: false,
          ),
      buttonTheme: ThemeData.dark().buttonTheme.copyWith(
            textTheme: ButtonTextTheme.primary,
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: Theme.of(context).colorScheme.primary),
          ),
      checkboxTheme: ThemeData.dark()
          .checkboxTheme
          .copyWith(
              visualDensity: VisualDensity.compact,
              checkColor: WidgetStateProperty.all(userSettings.darkTheme.background))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.darkTheme.accent;
          }
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.darkTheme.accent;
          }
          return null;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.darkTheme.accent;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.darkTheme.accent.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.dark()
          .colorScheme
          .copyWith(
            primary: userSettings.darkTheme.accent,
            secondary: userSettings.darkTheme.accent,
            tertiary: userSettings.darkTheme.text,
            surfaceContainerLow: userSettings.darkTheme.background.lighten(3),
            surfaceContainerHigh: userSettings.darkTheme.background.lighten(5),
            surfaceContainer: userSettings.darkTheme.background.lighten(7),
            primaryContainer: userSettings.darkTheme.background.lighten(10),
          )
          .copyWith(surface: userSettings.darkTheme.background)
          .copyWith(error: userSettings.darkTheme.accent),
      hoverColor: userSettings.darkTheme.accent.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: userSettings.darkTheme.background),
    );
  }

  static ThemeData getLightThemeData() {
    final ThemeData base = ThemeData.light();
    late TextTheme font;
    try {
      font = GoogleFonts.getTextTheme(userSettings.lightTheme.uiFontFamily, base.textTheme);
    } catch (_) {
      userSettings.lightTheme.uiFontFamily = "Roboto";
      font = GoogleFonts.getTextTheme(userSettings.lightTheme.uiFontFamily, base.textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    try {
      GoogleFonts.getTextTheme(userSettings.lightTheme.entryFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.lightTheme.entryFontFamily = "Roboto";
      Boxes.saveActiveQuickMenuThemes();
    }
    return base.copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: userSettings.lightTheme.background,
      iconTheme: IconThemeData(color: userSettings.lightTheme.text),
      textTheme: font,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(userSettings.lightTheme.accent),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(userSettings.lightTheme.background),
        overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered)) return Colors.black.withAlpha(20);
          if (states.contains(WidgetState.pressed)) return Colors.black.withAlpha(10);
          return null;
        }),
      )),
      tooltipTheme: ThemeData.light().tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 0),
            verticalOffset: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.all(0),
            textStyle: TextStyle(color: userSettings.lightTheme.text, fontSize: 12, height: 0),
            decoration: BoxDecoration(color: userSettings.lightTheme.background),
            preferBelow: false,
          ),
      checkboxTheme: ThemeData.light()
          .checkboxTheme
          .copyWith(
              visualDensity: VisualDensity.compact,
              checkColor: WidgetStateProperty.all(userSettings.lightTheme.background))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.lightTheme.accent;
          }
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.lightTheme.accent;
          }
          return null;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.lightTheme.accent;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.lightTheme.accent.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.light()
          .colorScheme
          .copyWith(
            primary: userSettings.lightTheme.accent,
            secondary: userSettings.lightTheme.accent,
            tertiary: userSettings.lightTheme.text,
            surfaceContainerLow: userSettings.lightTheme.background.darken(3),
            surfaceContainerHigh: userSettings.lightTheme.background.darken(5),
            surfaceContainer: userSettings.lightTheme.background.darken(7),
            primaryContainer: userSettings.lightTheme.accent.withValues(alpha: 0.1),
          )
          .copyWith(surface: userSettings.lightTheme.background)
          .copyWith(error: userSettings.lightTheme.accent),
      hoverColor: userSettings.lightTheme.accent.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: userSettings.lightTheme.background),
    );
  }

  static FontWeight getFontWeight(int value) {
    switch (value) {
      case 100:
        return FontWeight.w100;
      case 200:
        return FontWeight.w200;
      case 300:
        return FontWeight.w300;
      case 400:
        return FontWeight.w400;
      case 500:
        return FontWeight.w500;
      case 600:
        return FontWeight.w600;
      case 700:
        return FontWeight.w700;
      case 800:
        return FontWeight.w800;
      case 900:
        return FontWeight.w900;
      default:
        return FontWeight.w400;
    }
  }
}
