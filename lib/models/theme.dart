import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'classes/boxes.dart';
import 'settings.dart';

class AppTheme {
  static ThemeData getDarkThemeData(BuildContext context) {
    late TextTheme uiFont;
    try {
      uiFont = GoogleFonts.getTextTheme(userSettings.darkTheme.uiFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.darkTheme.uiFontFamily = "Roboto";
      uiFont = GoogleFonts.getTextTheme(userSettings.darkTheme.uiFontFamily, ThemeData.dark().textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    late TextTheme entryFont;
    try {
      entryFont = GoogleFonts.getTextTheme(userSettings.darkTheme.entryFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.darkTheme.entryFontFamily = "Roboto";
      entryFont = GoogleFonts.getTextTheme(userSettings.darkTheme.entryFontFamily, ThemeData.dark().textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    return ThemeData(
      brightness: Brightness.dark,
      splashColor: const Color.fromARGB(225, 0, 0, 0),
      cardColor: userSettings.darkTheme.background,
      iconTheme: IconThemeData(color: userSettings.darkTheme.text),
      textTheme: uiFont,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(userSettings.darkTheme.accent),
          elevation: WidgetStateProperty.all(0),
          shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          foregroundColor: WidgetStateProperty.all(userSettings.darkTheme.background),
          textStyle: WidgetStateProperty.all(entryFont.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) {
              return Colors.black.withAlpha(40);
            }
            if (states.contains(WidgetState.pressed)) return Colors.black.withAlpha(20);
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
      tooltipTheme: ThemeData.dark().tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 0),
            verticalOffset: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.all(0),
            textStyle: TextStyle(color: userSettings.darkTheme.text, fontSize: Design.baseFontSize + 2, height: 0),
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
      appBarTheme: AppBarTheme(
        backgroundColor: userSettings.darkTheme.background,
        foregroundColor: userSettings.darkTheme.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: userSettings.darkTheme.accent.withAlpha(40),
        iconTheme: IconThemeData(color: userSettings.darkTheme.text),
        actionsIconTheme: IconThemeData(color: userSettings.darkTheme.text),
        titleTextStyle: uiFont.titleLarge?.copyWith(
          color: userSettings.darkTheme.text,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      // inputDecorationTheme: InputDecorationTheme(
      //   filled: true,
      //   fillColor: userSettings.darkTheme.background.lighten(5),
      //   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      //   border: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.darkTheme.text.withAlpha(40)),
      //   ),
      //   enabledBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.darkTheme.text.withAlpha(40)),
      //   ),
      //   focusedBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.darkTheme.accent, width: 1.5),
      //   ),
      //   errorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.darkTheme.accent.withAlpha(180)),
      //   ),
      //   focusedErrorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.darkTheme.accent, width: 1.5),
      //   ),
      //   labelStyle: TextStyle(color: userSettings.darkTheme.text.withAlpha(180)),
      //   hintStyle: TextStyle(color: userSettings.darkTheme.text.withAlpha(100)),
      //   prefixIconColor: userSettings.darkTheme.text.withAlpha(160),
      //   suffixIconColor: userSettings.darkTheme.text.withAlpha(160),
      //   floatingLabelStyle: TextStyle(color: userSettings.darkTheme.accent),
      // ),
      tabBarTheme: TabBarThemeData(
        labelColor: userSettings.darkTheme.accent,
        unselectedLabelColor: userSettings.darkTheme.text.withAlpha(140),
        indicatorColor: userSettings.darkTheme.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: userSettings.darkTheme.text.withAlpha(30),
        overlayColor: WidgetStateProperty.all(userSettings.darkTheme.accent.withAlpha(30)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: userSettings.darkTheme.background,
        selectedItemColor: userSettings.darkTheme.accent,
        unselectedItemColor: userSettings.darkTheme.text.withAlpha(120),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: userSettings.darkTheme.background,
        selectedIconTheme: IconThemeData(color: userSettings.darkTheme.accent),
        unselectedIconTheme: IconThemeData(color: userSettings.darkTheme.text.withAlpha(120)),
        selectedLabelTextStyle: TextStyle(color: userSettings.darkTheme.accent, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: userSettings.darkTheme.text.withAlpha(120)),
        indicatorColor: userSettings.darkTheme.accent.withAlpha(40),
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: userSettings.darkTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        scrimColor: Colors.black.withAlpha(140),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: userSettings.darkTheme.accent.withAlpha(40),
        selectedColor: userSettings.darkTheme.accent,
        iconColor: userSettings.darkTheme.text.withAlpha(180),
        textColor: userSettings.darkTheme.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
      dividerTheme: DividerThemeData(
        color: userSettings.darkTheme.text.withAlpha(30),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: userSettings.darkTheme.background.lighten(10),
        contentTextStyle: TextStyle(color: userSettings.darkTheme.text),
        actionTextColor: userSettings.darkTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: userSettings.darkTheme.accent,
        linearTrackColor: userSettings.darkTheme.accent.withAlpha(40),
        circularTrackColor: userSettings.darkTheme.accent.withAlpha(40),
        linearMinHeight: 3,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: userSettings.darkTheme.background.lighten(7),
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(color: userSettings.darkTheme.text, fontSize: Design.baseFontSize),
        labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.focused) || states.contains(WidgetState.hovered)) {
            return TextStyle(color: userSettings.darkTheme.accent, fontSize: Design.baseFontSize);
          }
          return TextStyle(color: userSettings.darkTheme.text, fontSize: Design.baseFontSize);
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
            return userSettings.darkTheme.accent.withAlpha(180);
          }
          return userSettings.darkTheme.text.withAlpha(60);
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
        backgroundColor: userSettings.darkTheme.background.lighten(7),
        selectedColor: userSettings.darkTheme.accent.withAlpha(60),
        secondarySelectedColor: userSettings.darkTheme.accent,
        deleteIconColor: userSettings.darkTheme.text.withAlpha(160),
        labelStyle: TextStyle(color: userSettings.darkTheme.text),
        secondaryLabelStyle: TextStyle(color: userSettings.darkTheme.accent),
        side: BorderSide(color: userSettings.darkTheme.text.withAlpha(40)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        // visualDensity: VisualDensity.compact,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: userSettings.darkTheme.accent,
        textColor: userSettings.darkTheme.background,
        smallSize: 8,
        largeSize: 16,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: userSettings.darkTheme.accent,
        collapsedIconColor: userSettings.darkTheme.text.withAlpha(160),
        textColor: userSettings.darkTheme.accent,
        collapsedTextColor: userSettings.darkTheme.text,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        childrenPadding: const EdgeInsets.only(left: 16),
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }

  static ThemeData getLightThemeData(BuildContext context) {
    final ThemeData base = ThemeData.light();
    late TextTheme font;
    try {
      font = GoogleFonts.getTextTheme(userSettings.lightTheme.uiFontFamily, base.textTheme);
    } catch (_) {
      userSettings.lightTheme.uiFontFamily = "Roboto";
      font = GoogleFonts.getTextTheme(userSettings.lightTheme.uiFontFamily, base.textTheme);
      Boxes.saveActiveQuickMenuThemes();
    }
    late TextTheme entryFont;
    try {
      entryFont = GoogleFonts.getTextTheme(userSettings.lightTheme.entryFontFamily, ThemeData.dark().textTheme);
    } catch (_) {
      userSettings.lightTheme.entryFontFamily = "Roboto";
      entryFont = GoogleFonts.getTextTheme(userSettings.lightTheme.entryFontFamily, ThemeData.dark().textTheme);
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
          textStyle: WidgetStateProperty.all(entryFont.labelLarge?.copyWith(fontWeight: FontWeight.bold)),
          foregroundColor: WidgetStateProperty.all(userSettings.lightTheme.background),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
            if (states.contains(WidgetState.hovered)) return Colors.black.withAlpha(20);
            if (states.contains(WidgetState.pressed)) return Colors.black.withAlpha(10);
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          foregroundColor: Design.background, // text + icon color
          backgroundColor: Design.accent,
          textStyle: entryFont.labelLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      tooltipTheme: ThemeData.light().tooltipTheme.copyWith(
            constraints: const BoxConstraints(minHeight: 0),
            verticalOffset: 10,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            margin: const EdgeInsets.all(0),
            textStyle: TextStyle(color: userSettings.lightTheme.text, fontSize: Design.baseFontSize + 2, height: 0),
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
      appBarTheme: AppBarTheme(
        backgroundColor: userSettings.lightTheme.background,
        foregroundColor: userSettings.lightTheme.text,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: userSettings.lightTheme.accent.withAlpha(30),
        iconTheme: IconThemeData(color: userSettings.lightTheme.text),
        actionsIconTheme: IconThemeData(color: userSettings.lightTheme.text),
        titleTextStyle: font.titleLarge?.copyWith(
          color: userSettings.lightTheme.text,
          fontWeight: FontWeight.w600,
        ),
        surfaceTintColor: Colors.transparent,
      ),
      // inputDecorationTheme: InputDecorationTheme(
      //   filled: true,
      //   fillColor: userSettings.lightTheme.background.darken(3),
      //   contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      //   border: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.lightTheme.text.withAlpha(50)),
      //   ),
      //   enabledBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.lightTheme.text.withAlpha(50)),
      //   ),
      //   focusedBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.lightTheme.accent, width: 1.5),
      //   ),
      //   errorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.lightTheme.accent.withAlpha(180)),
      //   ),
      //   focusedErrorBorder: OutlineInputBorder(
      //     borderRadius: BorderRadius.circular(8),
      //     borderSide: BorderSide(color: userSettings.lightTheme.accent, width: 1.5),
      //   ),
      //   labelStyle: TextStyle(color: userSettings.lightTheme.text.withAlpha(160)),
      //   hintStyle: TextStyle(color: userSettings.lightTheme.text.withAlpha(100)),
      //   prefixIconColor: userSettings.lightTheme.text.withAlpha(140),
      //   suffixIconColor: userSettings.lightTheme.text.withAlpha(140),
      //   floatingLabelStyle: TextStyle(color: userSettings.lightTheme.accent),
      // ),
      tabBarTheme: TabBarThemeData(
        labelColor: userSettings.lightTheme.accent,
        unselectedLabelColor: userSettings.lightTheme.text.withAlpha(140),
        indicatorColor: userSettings.lightTheme.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: userSettings.lightTheme.text.withAlpha(30),
        overlayColor: WidgetStateProperty.all(userSettings.lightTheme.accent.withAlpha(25)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: userSettings.lightTheme.background,
        selectedItemColor: userSettings.lightTheme.accent,
        unselectedItemColor: userSettings.lightTheme.text.withAlpha(120),
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: userSettings.lightTheme.background,
        selectedIconTheme: IconThemeData(color: userSettings.lightTheme.accent),
        unselectedIconTheme: IconThemeData(color: userSettings.lightTheme.text.withAlpha(120)),
        selectedLabelTextStyle: TextStyle(color: userSettings.lightTheme.accent, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: TextStyle(color: userSettings.lightTheme.text.withAlpha(120)),
        indicatorColor: userSettings.lightTheme.accent.withAlpha(35),
        elevation: 0,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: userSettings.lightTheme.background,
        surfaceTintColor: Colors.transparent,
        elevation: 2,
        scrimColor: Colors.black.withAlpha(100),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: userSettings.lightTheme.accent.withAlpha(30),
        selectedColor: userSettings.lightTheme.accent,
        iconColor: userSettings.lightTheme.text.withAlpha(160),
        textColor: userSettings.lightTheme.text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        visualDensity: VisualDensity.compact,
      ),
      dividerTheme: DividerThemeData(
        color: userSettings.lightTheme.text.withAlpha(30),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: userSettings.lightTheme.background.darken(10),
        contentTextStyle: TextStyle(color: userSettings.lightTheme.text),
        actionTextColor: userSettings.lightTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: userSettings.lightTheme.accent,
        linearTrackColor: userSettings.lightTheme.accent.withAlpha(40),
        circularTrackColor: userSettings.lightTheme.accent.withAlpha(40),
        linearMinHeight: 3,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: userSettings.lightTheme.background.darken(3),
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: TextStyle(color: userSettings.lightTheme.text, fontSize: Design.baseFontSize),
        labelTextStyle: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.focused) || states.contains(WidgetState.hovered)) {
            return TextStyle(color: userSettings.lightTheme.accent, fontSize: Design.baseFontSize);
          }
          return TextStyle(color: userSettings.lightTheme.text, fontSize: Design.baseFontSize);
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((Set<WidgetState> states) {
          if (states.contains(WidgetState.hovered) || states.contains(WidgetState.dragged)) {
            return userSettings.lightTheme.accent.withAlpha(200);
          }
          return userSettings.lightTheme.text.withAlpha(70);
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
        backgroundColor: userSettings.lightTheme.background.darken(5),
        selectedColor: userSettings.lightTheme.accent.withAlpha(50),
        secondarySelectedColor: userSettings.lightTheme.accent,
        deleteIconColor: userSettings.lightTheme.text.withAlpha(160),
        labelStyle: TextStyle(color: userSettings.lightTheme.text),
        secondaryLabelStyle: TextStyle(color: userSettings.lightTheme.accent),
        side: BorderSide(color: userSettings.lightTheme.text.withAlpha(40)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        // visualDensity: VisualDensity.compact,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: userSettings.lightTheme.accent,
        textColor: userSettings.lightTheme.background,
        smallSize: 8,
        largeSize: 16,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        iconColor: userSettings.lightTheme.accent,
        collapsedIconColor: userSettings.lightTheme.text.withAlpha(160),
        textColor: userSettings.lightTheme.accent,
        collapsedTextColor: userSettings.lightTheme.text,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        childrenPadding: const EdgeInsets.only(left: 16),
        shape: const Border(),
        collapsedShape: const Border(),
      ),
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
