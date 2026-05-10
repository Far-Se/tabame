import 'package:flutter/material.dart';

import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) {
    return ThemeData.dark().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: userSettings.darkTheme.background,
      iconTheme: ThemeData.dark().iconTheme.copyWith(color: userSettings.darkTheme.textColor),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: userSettings.darkTheme.textColor,
            displayColor: userSettings.darkTheme.textColor,
            decorationColor: userSettings.darkTheme.textColor,
            fontFamily: userSettings.darkTheme.uiFontFamily,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(userSettings.darkTheme.accentColor),
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
            textStyle: TextStyle(color: userSettings.darkTheme.textColor, fontSize: 12, height: 0),
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
            return userSettings.darkTheme.accentColor;
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
            return userSettings.darkTheme.accentColor;
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
            return userSettings.darkTheme.accentColor;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.darkTheme.accentColor.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.dark()
          .colorScheme
          .copyWith(
            primary: userSettings.darkTheme.accentColor,
            secondary: userSettings.darkTheme.accentColor,
            tertiary: userSettings.darkTheme.textColor,
            surfaceContainerLow: userSettings.darkTheme.background.lighten(3),
            surfaceContainerHigh: userSettings.darkTheme.background.lighten(5),
            surfaceContainer: userSettings.darkTheme.background.lighten(7),
            primaryContainer: userSettings.darkTheme.background.lighten(10),
          )
          .copyWith(surface: userSettings.darkTheme.background)
          .copyWith(error: userSettings.darkTheme.accentColor),
      hoverColor: userSettings.darkTheme.accentColor.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: userSettings.darkTheme.background),
    );
  }

  static ThemeData getLightThemeData() {
    return ThemeData.light().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: userSettings.lightTheme.background,
      iconTheme: ThemeData.light().iconTheme.copyWith(color: userSettings.lightTheme.textColor),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: userSettings.lightTheme.textColor,
            displayColor: userSettings.lightTheme.textColor,
            decorationColor: userSettings.lightTheme.textColor,
            fontFamily: userSettings.lightTheme.uiFontFamily,
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(userSettings.lightTheme.accentColor),
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
            textStyle: TextStyle(color: userSettings.lightTheme.textColor, fontSize: 12, height: 0),
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
            return userSettings.lightTheme.accentColor;
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
            return userSettings.lightTheme.accentColor;
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
            return userSettings.lightTheme.accentColor;
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return userSettings.lightTheme.accentColor.withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.light()
          .colorScheme
          .copyWith(
            primary: userSettings.lightTheme.accentColor,
            secondary: userSettings.lightTheme.accentColor,
            tertiary: userSettings.lightTheme.textColor,
            surfaceContainerLow: userSettings.lightTheme.background.darken(3),
            surfaceContainerHigh: userSettings.lightTheme.background.darken(5),
            surfaceContainer: userSettings.lightTheme.background.darken(7),
            primaryContainer: userSettings.lightTheme.accentColor.withValues(alpha: 0.1),
          )
          .copyWith(surface: userSettings.lightTheme.background)
          .copyWith(error: userSettings.lightTheme.accentColor),
      hoverColor: userSettings.lightTheme.accentColor.withAlpha(60),
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
