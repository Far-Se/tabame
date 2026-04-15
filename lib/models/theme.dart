import 'package:flutter/material.dart';
import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) {
    return ThemeData.dark().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: Color(globalSettings.darkTheme.background),
      iconTheme: ThemeData.dark().iconTheme.copyWith(color: Color(globalSettings.darkTheme.textColor)),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: Color(globalSettings.darkTheme.textColor),
            displayColor: Color(globalSettings.darkTheme.textColor),
            decorationColor: Color(globalSettings.darkTheme.textColor),
          ),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(Color(globalSettings.darkTheme.accentColor)),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(Color(globalSettings.darkTheme.background)),
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
            textStyle: TextStyle(color: Color(globalSettings.darkTheme.textColor), fontSize: 12, height: 0),
            decoration: BoxDecoration(color: Color(globalSettings.darkTheme.background)),
            preferBelow: false,
          ),
      buttonTheme: ThemeData.dark().buttonTheme.copyWith(
            textTheme: ButtonTextTheme.primary,
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: Theme.of(context).colorScheme.primary),
          ),
      checkboxTheme: ThemeData.dark()
          .checkboxTheme
          .copyWith(visualDensity: VisualDensity.compact, checkColor: WidgetStateProperty.all(Color(globalSettings.darkTheme.background)))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return Color(globalSettings.darkTheme.accentColor);
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
            return Color(globalSettings.darkTheme.accentColor);
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
            return Color(globalSettings.darkTheme.accentColor);
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return Color(globalSettings.darkTheme.accentColor).withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.dark()
          .colorScheme
          .copyWith(
            primary: Color(globalSettings.darkTheme.accentColor),
            secondary: Color(globalSettings.darkTheme.accentColor),
            tertiary: Color(globalSettings.darkTheme.textColor),
            surfaceContainerLow: Color(globalSettings.darkTheme.background).lighten(3),
            surfaceContainerHigh: Color(globalSettings.darkTheme.background).lighten(5),
            surfaceContainer: Color(globalSettings.darkTheme.background).lighten(7),
            primaryContainer: Color(globalSettings.darkTheme.background).lighten(10),
          )
          .copyWith(surface: Color(globalSettings.darkTheme.background))
          .copyWith(error: Color(globalSettings.darkTheme.accentColor)),
      hoverColor: Color(globalSettings.darkTheme.accentColor).withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: Color(globalSettings.darkTheme.background)),
    );
  }

  static ThemeData getLightThemeData() {
    return ThemeData.light().copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: Color(globalSettings.lightTheme.background),
      iconTheme: ThemeData.light().iconTheme.copyWith(color: Color(globalSettings.lightTheme.textColor)),
      textTheme: ThemeData.light().textTheme.apply(
          bodyColor: Color(globalSettings.lightTheme.textColor),
          displayColor: Color(globalSettings.lightTheme.textColor),
          decorationColor: Color(globalSettings.lightTheme.textColor)),
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(Color(globalSettings.lightTheme.accentColor)),
        elevation: WidgetStateProperty.all(0),
        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        foregroundColor: WidgetStateProperty.all(Color(globalSettings.lightTheme.background)),
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
            textStyle: TextStyle(color: Color(globalSettings.lightTheme.textColor), fontSize: 12, height: 0),
            decoration: BoxDecoration(color: Color(globalSettings.lightTheme.background)),
            preferBelow: false,
          ),
      checkboxTheme: ThemeData.light()
          .checkboxTheme
          .copyWith(visualDensity: VisualDensity.compact, checkColor: WidgetStateProperty.all(Color(globalSettings.lightTheme.background)))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return Color(globalSettings.lightTheme.accentColor);
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
            return Color(globalSettings.lightTheme.accentColor);
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
            return Color(globalSettings.lightTheme.accentColor);
          }
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) {
            return null;
          }
          if (states.contains(WidgetState.selected)) {
            return Color(globalSettings.lightTheme.accentColor).withValues(alpha: 0.5);
          }
          return null;
        }),
      ),
      colorScheme: ThemeData.light()
          .colorScheme
          .copyWith(
            primary: Color(globalSettings.lightTheme.accentColor),
            secondary: Color(globalSettings.lightTheme.accentColor),
            tertiary: Color(globalSettings.lightTheme.textColor),
            surfaceContainerLow: Color(globalSettings.lightTheme.background).darken(3),
            surfaceContainerHigh: Color(globalSettings.lightTheme.background).darken(5),
            surfaceContainer: Color(globalSettings.lightTheme.background).darken(7),
            primaryContainer: Color(globalSettings.lightTheme.accentColor).withValues(alpha: 0.1),
          )
          .copyWith(surface: Color(globalSettings.lightTheme.background))
          .copyWith(error: Color(globalSettings.lightTheme.accentColor)),
      hoverColor: Color(globalSettings.lightTheme.accentColor).withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: Color(globalSettings.lightTheme.background)),
    );
  }
}
