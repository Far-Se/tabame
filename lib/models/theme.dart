import 'package:flutter/material.dart';

import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) {
    return ThemeData.dark().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: globalSettings.darkTheme.background,
      iconTheme: ThemeData.dark().iconTheme.copyWith(color: globalSettings.darkTheme.textColor),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: globalSettings.darkTheme.textColor,
            displayColor: globalSettings.darkTheme.textColor,
            decorationColor: globalSettings.darkTheme.textColor,
            fontFamily: globalSettings.darkTheme.uiFontFamily,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(globalSettings.darkTheme.accentColor),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(globalSettings.darkTheme.background),
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
            textStyle: TextStyle(color: globalSettings.darkTheme.textColor, fontSize: 12, height: 0),
            decoration: BoxDecoration(color: globalSettings.darkTheme.background),
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
              checkColor: WidgetStateProperty.all(globalSettings.darkTheme.background))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return globalSettings.darkTheme.accentColor;
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
            return globalSettings.darkTheme.accentColor;
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
            return globalSettings.darkTheme.accentColor;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return globalSettings.darkTheme.accentColor.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.dark()
          .colorScheme
          .copyWith(
            primary: globalSettings.darkTheme.accentColor,
            secondary: globalSettings.darkTheme.accentColor,
            tertiary: globalSettings.darkTheme.textColor,
            surfaceContainerLow: globalSettings.darkTheme.background.lighten(3),
            surfaceContainerHigh: globalSettings.darkTheme.background.lighten(5),
            surfaceContainer: globalSettings.darkTheme.background.lighten(7),
            primaryContainer: globalSettings.darkTheme.background.lighten(10),
          )
          .copyWith(surface: globalSettings.darkTheme.background)
          .copyWith(error: globalSettings.darkTheme.accentColor),
      hoverColor: globalSettings.darkTheme.accentColor.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: globalSettings.darkTheme.background),
    );
  }

  static ThemeData getLightThemeData() {
    return ThemeData.light().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: globalSettings.lightTheme.background,
      iconTheme: ThemeData.light().iconTheme.copyWith(color: globalSettings.lightTheme.textColor),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: globalSettings.lightTheme.textColor,
            displayColor: globalSettings.lightTheme.textColor,
            decorationColor: globalSettings.lightTheme.textColor,
            fontFamily: globalSettings.lightTheme.uiFontFamily,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(globalSettings.lightTheme.accentColor),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(globalSettings.lightTheme.background),
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
            textStyle: TextStyle(color: globalSettings.lightTheme.textColor, fontSize: 12, height: 0),
            decoration: BoxDecoration(color: globalSettings.lightTheme.background),
            preferBelow: false,
          ),
      checkboxTheme: ThemeData.light()
          .checkboxTheme
          .copyWith(
              visualDensity: VisualDensity.compact,
              checkColor: WidgetStateProperty.all(globalSettings.lightTheme.background))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return globalSettings.lightTheme.accentColor;
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
            return globalSettings.lightTheme.accentColor;
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
            return globalSettings.lightTheme.accentColor;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return globalSettings.lightTheme.accentColor.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.light()
          .colorScheme
          .copyWith(
            primary: globalSettings.lightTheme.accentColor,
            secondary: globalSettings.lightTheme.accentColor,
            tertiary: globalSettings.lightTheme.textColor,
            surfaceContainerLow: globalSettings.lightTheme.background.darken(3),
            surfaceContainerHigh: globalSettings.lightTheme.background.darken(5),
            surfaceContainer: globalSettings.lightTheme.background.darken(7),
            primaryContainer: globalSettings.lightTheme.accentColor.withValues(alpha: 0.1),
          )
          .copyWith(surface: globalSettings.lightTheme.background)
          .copyWith(error: globalSettings.lightTheme.accentColor),
      hoverColor: globalSettings.lightTheme.accentColor.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: globalSettings.lightTheme.background),
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
