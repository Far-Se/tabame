import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/theme.dart';
import 'interface.dart';
import 'quickmenu.dart';

class Tabame extends StatefulWidget {
  const Tabame({super.key});

  @override
  State<Tabame> createState() => _TabameState();
}

class _TabameState extends State<Tabame> {
  @override
  void dispose() {
    Globals.themeChangeNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Debug.add("Tabame: init");
    ThemeType theme = globalSettings.themeTypeMode;
    Timer.periodic(const Duration(minutes: 1), (Timer timer) {
      if (theme != globalSettings.themeTypeMode) {
        theme = globalSettings.themeTypeMode;
        Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
        if (mounted) setState(() {});
      }
    });

    // ignore: deprecated_member_use
    final SingletonFlutterWindow window = WidgetsBinding.instance.window;
    window.onPlatformBrightnessChanged = () {
      theme = globalSettings.themeTypeMode;
      Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: Globals.fullLoaded,
        builder: (BuildContext context, bool value, __) {
          Debug.add("Tabame: fullLoaded");
          if (value == false) return const SizedBox.shrink();
          return ValueListenableBuilder<bool>(
            valueListenable: Globals.themeChangeNotifier,
            builder: (_, bool refreshed, __) {
              Debug.add("Tabame: Theme");
              ThemeMode scheduled = ThemeMode.system;
              ThemeType themeType = globalSettings.themeType;
              if (themeType.index == 3) {
                scheduled = globalSettings.themeTypeMode == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;
              }
              ThemeMode themeMode =
                  <ThemeMode>[ThemeMode.system, ThemeMode.light, ThemeMode.dark, scheduled][themeType.index];

              return MaterialApp(
                scrollBehavior: MyCustomScrollBehavior(),
                debugShowCheckedModeBanner: false,
                title: 'Tabame - Taskbar Menu',
                theme: AppTheme.getLightThemeData(),
                darkTheme: AppTheme.getDarkThemeData(context),
                themeMode: themeMode,
                home: PageView.builder(
                  controller: Globals.mainPageViewController,
                  allowImplicitScrolling: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (BuildContext context, int index) {
                    Debug.add("Tabame: $index ${globalSettings.args.join(':')}");
                    if (globalSettings.args.contains("-interface") || Boxes.remap.isEmpty) {
                      return const Interface();
                    }
                    if (index == Pages.quickmenu.index) {
                      return const QuickMenu();
                    } else if (index == Pages.interface.index) {
                      return const Interface();
                    }
                    return const QuickMenu();
                  },
                ),
              );
            },
          );
        });
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.mouse};
}

class EmptyWidget extends StatelessWidget {
  const EmptyWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Tabame aux',
      home: Text("closing"),
    );
  }
}
