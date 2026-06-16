import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'classes/boxes.dart';
import 'classes/saved_maps.dart';
import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) => getThemeData(context, isDark: true);
  static ThemeData getLightThemeData(BuildContext context) => getThemeData(context, isDark: false);

  static ThemeData getThemeData(BuildContext context, {required bool isDark}) {
    final ThemeColors theme = isDark ? user.darkTheme : user.lightTheme;
    final ThemeData base = isDark ? ThemeData.dark() : ThemeData.light();

    late TextTheme uiFont;
    try {
      uiFont = GoogleFonts.getTextTheme(theme.uiFontFamily, base.textTheme);
    } catch (_) {
      theme.uiFontFamily = "Roboto";
      uiFont = GoogleFonts.getTextTheme(theme.uiFontFamily, base.textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    late TextTheme entryFont;
    try {
      entryFont = GoogleFonts.getTextTheme(theme.entryFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      theme.entryFontFamily = "Roboto";
      entryFont = GoogleFonts.getTextTheme(theme.entryFontFamily, ThemeData.dark().textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }

    return base.copyWith(
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: theme.background,
      iconTheme: IconThemeData(color: theme.text),
      textTheme: uiFont,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(theme.accent),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          foregroundColor: WidgetStateProperty.all(theme.background),
          textStyle: WidgetStateProperty.all(entryFont.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.black.withAlpha(isDark ? 40 : 20);
            }
            if (states.contains(WidgetState.pressed)) return Colors.black.withAlpha(isDark ? 20 : 10);
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Design.background,
          backgroundColor: Design.accent,
          textStyle: entryFont.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      tooltipTheme: base.tooltipTheme.copyWith(
        constraints: const BoxConstraints(minHeight: 0),
        verticalOffset: 10,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        margin: const EdgeInsets.all(0),
        textStyle: TextStyle(color: theme.text, fontSize: Design.baseFontSize + 2, height: 0),
        decoration: BoxDecoration(color: theme.background),
        preferBelow: false,
      ),
      buttonTheme: isDark
          ? base.buttonTheme.copyWith(
              textTheme: ButtonTextTheme.primary,
              colorScheme: Theme.of(context).colorScheme.copyWith(primary: Theme.of(context).colorScheme.primary),
            )
          : null,
      checkboxTheme: base.checkboxTheme
          .copyWith(visualDensity: VisualDensity.compact, checkColor: WidgetStateProperty.all(theme.background))
          .copyWith(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.selected)) return theme.accent;
          return null;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.selected)) return theme.accent;
          return null;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.selected)) return theme.accent;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
          if (states.contains(WidgetState.disabled)) return null;
          if (states.contains(WidgetState.selected)) return theme.accent.withValues(alpha: 0.5);
          return null;
        }),
      ),
      colorScheme: base.colorScheme
          .copyWith(
            primary: theme.accent,
            secondary: theme.accent,
            tertiary: theme.text,
            surfaceContainerLow: isDark ? theme.background.lighten(3) : theme.background.darken(3),
            surfaceContainerHigh: isDark ? theme.background.lighten(5) : theme.background.darken(5),
            surfaceContainer: isDark ? theme.background.lighten(7) : theme.background.darken(7),
            primaryContainer: isDark ? theme.background.lighten(10) : theme.accent.withValues(alpha: 0.1),
          )
          .copyWith(surface: theme.background)
          .copyWith(error: theme.accent),
      hoverColor: theme.accent.withAlpha(60),
      dialogTheme: DialogThemeData(backgroundColor: theme.background),
      appBarTheme: AppBarTheme(
        backgroundColor: theme.background,
        foregroundColor: theme.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: theme.accent.withAlpha(isDark ? 40 : 30),
        iconTheme: IconThemeData(color: theme.text),
        actionsIconTheme: IconThemeData(color: theme.text),
        titleTextStyle: uiFont.titleLarge?.copyWith(
          color: theme.text,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      // inputDecorationTheme: InputDecorationTheme(
      //   filled: true,
      //   fillColor: isDark ? theme.background.lighten(5) : theme.background.darken(3),
      //   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      //   border: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: theme.text.withAlpha(isDark ? 40 : 50)),
      //   ),
      //   enabledBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: theme.text.withAlpha(isDark ? 40 : 50)),
      //   ),
      //   focusedBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: theme.accent, width: 1.5),
      //   ),
      //   errorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: theme.accent.withAlpha(180)),
      //   ),
      //   focusedErrorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: theme.accent, width: 1.5),
      //   ),
      //   labelStyle: TextStyle(color: theme.text.withAlpha(isDark ? 180 : 160)),
      //   hintStyle: TextStyle(color: theme.text.withAlpha(100)),
      //   prefixIconColor: theme.text.withAlpha(isDark ? 160 : 140),
      //   suffixIconColor: theme.text.withAlpha(isDark ? 160 : 140),
      //   floatingLabelStyle: TextStyle(color: theme.accent),
      // ),
      tabBarTheme: TabBarThemeData(
        labelColor: theme.accent,
        unselectedLabelColor: theme.text.withAlpha(140),
        indicatorColor: theme.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: theme.text.withAlpha(30),
        overlayColor: WidgetStateProperty.all(theme.accent.withAlpha(isDark ? 30 : 25)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: theme.background,
        selectedItemColor: theme.accent,
        unselectedItemColor: theme.text.withAlpha(120),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: theme.background,
        selectedIconTheme: IconThemeData(color: theme.accent),
        unselectedIconTheme: IconThemeData(color: theme.text.withAlpha(120)),
        selectedLabelTextStyle: TextStyle(color: theme.accent, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: theme.text.withAlpha(120)),
        indicatorColor: theme.accent.withAlpha(isDark ? 40 : 35),
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: theme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        scrimColor: Colors.black.withAlpha(isDark ? 140 : 100),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: theme.accent.withAlpha(isDark ? 40 : 30),
        selectedColor: theme.accent,
        iconColor: theme.text.withAlpha(isDark ? 180 : 160),
        textColor: theme.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
      dividerTheme: DividerThemeData(
        color: theme.text.withAlpha(30),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? theme.background.lighten(10) : theme.background.darken(10),
        contentTextStyle: TextStyle(color: theme.text),
        actionTextColor: theme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: theme.accent,
        linearTrackColor: theme.accent.withAlpha(40),
        circularTrackColor: theme.accent.withAlpha(40),
        linearMinHeight: 3,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? theme.background.lighten(7) : theme.background.darken(3),
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(color: theme.text, fontSize: Design.baseFontSize),
        labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.focused) || states.contains(WidgetState.hovered)) {
            return TextStyle(color: theme.accent, fontSize: Design.baseFontSize);
          }
          return TextStyle(color: theme.text, fontSize: Design.baseFontSize);
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
            return theme.accent.withAlpha(isDark ? 180 : 200);
          }
          return theme.text.withAlpha(isDark ? 60 : 70);
        }),
        trackColor: WidgetStateProperty.all(Colors.transparent),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) return 6.0;
          return 4.0;
        }),
        interactive: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? theme.background.lighten(7) : theme.background.darken(5),
        selectedColor: theme.accent.withAlpha(isDark ? 60 : 50),
        secondarySelectedColor: theme.background,
        deleteIconColor: theme.text.withAlpha(160),
        labelStyle: TextStyle(color: theme.text),
        secondaryLabelStyle: TextStyle(color: theme.accent),
        side: BorderSide(color: theme.text.withAlpha(40)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        // visualDensity: VisualDensity.compact,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: theme.accent,
        textColor: theme.background,
        smallSize: 8,
        largeSize: 16,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: theme.accent,
        collapsedIconColor: theme.text.withAlpha(160),
        textColor: theme.accent,
        collapsedTextColor: theme.text,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        childrenPadding: const EdgeInsets.only(left: 16),
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }

  static FontWeight getFontWeight(int value) {
    if (value < 100 || value > 900) {
      return FontWeight.w400;
    }

    return FontWeight.values[(value ~/ 100) - 1];
  }
}
