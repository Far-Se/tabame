import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/saved_maps.dart';
import 'package:tabame/models/design_settings.dart';
import 'package:tabame/pages/quickmenu_designs/lamp_surface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('appends Lamp so saved QuickMenu indexes stay put', () {
    expect(QuickMenuDesigns.values.last, QuickMenuDesigns.lamp);
    expect(QuickMenuDesigns.lamp.displayName, 'Lamp');
  });

  test('registers a readable Lamp palette', () {
    final Map<String, QMDesignThemeSet> themes = DesignSettings.createDefaultQuickMenuDesignThemes();
    final QMDesignThemeSet lamp = themes[QuickMenuDesigns.lamp.displayName]!;

    expect(lamp.lightTheme.text.computeLuminance(), lessThan(lamp.lightTheme.background.computeLuminance()));
    expect(lamp.darkTheme.text.computeLuminance(), greaterThan(lamp.darkTheme.background.computeLuminance()));
    expect(
      lampShadow(lamp.darkTheme.background, dark: true).computeLuminance(),
      lessThan(lamp.darkTheme.background.computeLuminance()),
    );
    expect(
      lampShadow(lamp.lightTheme.background, dark: false).computeLuminance(),
      lessThan(lamp.lightTheme.background.computeLuminance()),
    );
  });

  test('daylight peaks in the afternoon and rests at night', () {
    expect(lampDaylight(lampHour(DateTime(2026, 6, 1, 14))), closeTo(1, 0.001));
    expect(lampDaylight(lampHour(DateTime(2026, 6, 1, 2))), closeTo(0, 0.001));
    expect(lampDaylight(lampHour(DateTime(2026, 6, 1, 8))), closeTo(0.5, 0.02));
    expect(lampDaylight(lampHour(DateTime(2026, 6, 1, 20))), closeTo(0.5, 0.02));
  });

  test('lamp shader compiles', () async {
    final ui.FragmentProgram program = await ui.FragmentProgram.fromAsset('resources/shaders/lamp.frag');
    final ui.FragmentShader shader = program.fragmentShader();
    shader.dispose();
  });

  testWidgets('lamp surface paints a field', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 360,
            height: 420,
            child: LampSurface(
              pool: Color(0xFF241F1A),
              shadow: Color(0xFF100E0C),
              lip: Color(0xFF8A6232),
              dark: true,
              child: SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LampSurface), findsOneWidget);
    expect(tester.getSize(find.byType(LampSurface)), const Size(360, 420));
  });
}
