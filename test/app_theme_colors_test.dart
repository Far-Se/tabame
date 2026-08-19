import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/saved_maps.dart';
import 'package:tabame/models/settings.dart';

void main() {
  group('Settings.appThemeColors', () {
    test('registers the Rundown theme set', () {
      final Map<String, QMDesignThemeSet> themes = Settings.createDefaultQuickMenuDesignThemes();

      expect(themes[QuickMenuDesigns.rundown.displayName], isNotNull);
    });

    test('uses Classic themes for the XP and Windows 98 Interface process', () {
      final Settings settings = Settings()..page = TPage.interface;
      final QMDesignThemeSet classicThemes = settings.quickMenuDesignThemes[QuickMenuDesigns.classic.displayName]!;

      for (final QuickMenuDesigns design in <QuickMenuDesigns>[
        QuickMenuDesigns.windowsXp,
        QuickMenuDesigns.windows98,
      ]) {
        settings.quickMenuDesign = design.index;

        expect(settings.appThemeColors(isDark: false), classicThemes.lightTheme);
        expect(settings.appThemeColors(isDark: true), classicThemes.darkTheme);
      }
    });

    test('keeps the active themes outside the legacy Interface case', () {
      final Settings settings = Settings();

      for (final ({TPage page, QuickMenuDesigns design}) scenario in <({TPage page, QuickMenuDesigns design})>[
        (page: TPage.quickmenu, design: QuickMenuDesigns.windowsXp),
        (page: TPage.quickmenu, design: QuickMenuDesigns.windows98),
        (page: TPage.interface, design: QuickMenuDesigns.modern),
      ]) {
        settings
          ..page = scenario.page
          ..quickMenuDesign = scenario.design.index;

        expect(settings.appThemeColors(isDark: false), same(settings.lightTheme));
        expect(settings.appThemeColors(isDark: true), same(settings.darkTheme));
      }
    });
  });
}
