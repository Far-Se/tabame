import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/saved_maps.dart';
import 'package:tabame/models/design_settings.dart';
import 'package:tabame/pages/quickmenu_designs/void_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appends Void so saved QuickMenu indexes stay put', () {
    expect(QuickMenuDesigns.values.last, QuickMenuDesigns.voidDesign);
    expect(QuickMenuDesigns.voidDesign.displayName, 'Void');
  });

  test('registers a readable Void palette', () {
    final Map<String, QMDesignThemeSet> themes = DesignSettings.createDefaultQuickMenuDesignThemes();
    final QMDesignThemeSet theme = themes[QuickMenuDesigns.voidDesign.displayName]!;

    expect(theme.lightTheme.text.computeLuminance(), lessThan(theme.lightTheme.background.computeLuminance()));
    expect(theme.darkTheme.text.computeLuminance(), greaterThan(theme.darkTheme.background.computeLuminance()));
  });

  test('shelves stay fainter than the rules that close them', () {
    const Color ink = Color(0xFFDCE1E3);
    expect(voidShelf(ink, dark: true).a, lessThan(voidRule(ink, dark: true).a));
    expect(voidShelf(ink, dark: false).a, lessThan(voidRule(ink, dark: false).a));
  });

  testWidgets('surface fills its box', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 420,
            child: VoidSurface(
              ground: Color(0xFF1D2126),
              dark: true,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(VoidSurface)), const Size(360, 420));
  });
}
