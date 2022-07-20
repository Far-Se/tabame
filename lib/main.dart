// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import 'models/globals.dart';
import 'models/utils.dart';
import 'models/win32/win32.dart';
import 'pages/interface.dart';
import 'pages/quickmenu.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await registerAll();

  /// ? Window
  WindowOptions windowOptions = const WindowOptions(
    size: Size(300, 520),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    // minimumSize: Size(300, 150),
    title: "Tabame",
  );
  windowManager.setMinimizable(false);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    Win32.fetchMainWindowHandle();
  });

  await setWindowAsTransparent();
  runApp(const Tabame());
}

final Color kInitialColor = Color.fromRGBO(59, 65, 77, 1);
final Color kTintColor = Color(0xFF373C47);

final Color kLightBackground = Color(0xffFFFFFF);
final Color kLightTint = Color(0xff4DCF72);
final Color kLightText = Color.fromRGBO(169, 69, 138, 1);

// final Color kDarkBackground = Color.fromRGBO(55, 47, 98, 1);
final Color kDarkBackground = Color.fromRGBO(59, 65, 77, 1);
final Color kDarkTint = Color.fromRGBO(250, 249, 248, 1);
final Color kDarkText = Color.fromRGBO(250, 249, 248, 1);

final ValueNotifier<bool> darkThemeNotifier = ValueNotifier<bool>(true);
PageController mainPageViewController = PageController();

class Tabame extends StatefulWidget {
  const Tabame({Key? key}) : super(key: key);

  @override
  State<Tabame> createState() => _TabameState();
}

class _TabameState extends State<Tabame> {
  @override
  void dispose() {
    // mainPageViewController.dispose();
    darkThemeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkThemeNotifier,
      builder: (_, bool mode, __) => MaterialApp(
        scrollBehavior: MyCustomScrollBehavior(),
        debugShowCheckedModeBanner: false,
        title: 'Tabame - Taskbar Menu',
        theme: ThemeData(
          splashColor: Color.fromARGB(40, 0, 0, 0),
          backgroundColor: kLightBackground,
          dividerColor: Color.alphaBlend(Colors.black.withOpacity(0.2), kLightBackground), // Color(darkerColor(kBackground.value, darkenBy: 0x44) as int),
          cardColor: kLightBackground,
          errorColor: kLightTint,
          iconTheme: Theme.of(context).iconTheme.copyWith(color: kLightText),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: kLightText, displayColor: kLightText, decorationColor: kLightText),
          tooltipTheme: Theme.of(context).tooltipTheme.copyWith(
                verticalOffset: 10,
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                height: 0,
                margin: EdgeInsets.all(0),
                textStyle: TextStyle(color: kLightText, fontSize: 12, height: 0),
                decoration: BoxDecoration(color: Theme.of(context).backgroundColor),
              ),
        ),
        darkTheme: ThemeData(
          splashColor: Color.fromARGB(40, 0, 0, 0),
          backgroundColor: kDarkBackground,
          dividerColor: Color.alphaBlend(Colors.black.withOpacity(0.2), kDarkBackground), // Color(darkerColor(kBackground.value, darkenBy: 0x44) as int),
          cardColor: kDarkBackground,
          errorColor: kDarkTint,
          iconTheme: Theme.of(context).iconTheme.copyWith(color: kDarkText),
          textTheme: Theme.of(context).textTheme.apply(bodyColor: kDarkText, displayColor: kDarkText, decorationColor: kDarkText),
          tooltipTheme: Theme.of(context).tooltipTheme.copyWith(
                verticalOffset: 10,
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                height: 0,
                margin: EdgeInsets.all(0),
                textStyle: TextStyle(color: kDarkText, fontSize: 12, height: 0),
                decoration: BoxDecoration(color: Theme.of(context).backgroundColor),
              ),
        ),
        themeMode: mode ? ThemeMode.dark : ThemeMode.light,
        // home: QuickMenu()
        home: PageView.builder(
          controller: mainPageViewController,
          allowImplicitScrolling: false,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (BuildContext context, int index) {
            if (index == Pages.quickmenu.index) {
              return const QuickMenu();
            } else if (index == Pages.interface.index) {
              return const Interface();
            }
            return const QuickMenu();
          },
        ),
      ),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{PointerDeviceKind.touch, PointerDeviceKind.mouse};
}
