// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import 'models/globals.dart';
import 'models/settings.dart';
import 'models/win32/win32.dart';
import 'pages/interface.dart';
import 'pages/quickmenu.dart';

final ValueNotifier<bool> fullLoaded = ValueNotifier<bool>(false);
Future<void> main(List<String> arguments) async {
  List<String> auxArgs = <String>[...arguments];
  if (auxArgs.length == 1 && auxArgs[0].contains('-interface')) {
    auxArgs = <String>['"${auxArgs[0].replaceAll(' -interface', '')}\\', '-interface'];
  }

  // auxArgs.add("-strudel");
  globalSettings.args = <String>[...auxArgs];
  // WinUtils.msgBox(globalSettings.args.join(' '), "");
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await registerAll();

  /// ? Window
  late WindowOptions windowOptions;
  if (globalSettings.args.contains("-interface")) {
    windowOptions = WindowOptions(
      size: Size(700, 400),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      alwaysOnTop: false,
      title: globalSettings.args.contains("-wizardly") ? "Tabame - Wizardly" : "Tabame - Interface",
    );
  } else {
    windowOptions = const WindowOptions(
      size: Size(300, 520),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: "Tabame",
    );
  }
  windowManager.setMinimizable(false);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await Win32.fetchMainWindowHandle();
    fullLoaded.value = true;
  });

  await setWindowAsTransparent();
  if (globalSettings.runAsAdministrator && !WinUtils.isAdministrator() && globalSettings.args.join(' ').contains('-strudel')) {
    globalSettings.args.remove('-strudel');
    WinUtils.run(Platform.resolvedExecutable, arguments: globalSettings.args.join(' '));
    Timer(const Duration(seconds: 5), () => exit(0));
  }
  runApp(const Tabame());
}

final ValueNotifier<bool> themeChangeNotifier = ValueNotifier<bool>(false);
PageController mainPageViewController = PageController();

class Tabame extends StatefulWidget {
  const Tabame({Key? key}) : super(key: key);

  @override
  State<Tabame> createState() => _TabameState();
}

class _TabameState extends State<Tabame> {
  @override
  void dispose() {
    themeChangeNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: fullLoaded,
        builder: (BuildContext context, bool value, __) {
          if (value == false) return Container();
          return ValueListenableBuilder<bool>(
            valueListenable: themeChangeNotifier,
            builder: (_, bool refreshed, __) {
              ThemeMode scheduled = ThemeMode.system;
              ThemeType themeType = globalSettings.themeType;
              if (themeType.index == 3) {
                scheduled = globalSettings.themeTypeMode == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;
              }
              ThemeMode themeMode = <ThemeMode>[ThemeMode.system, ThemeMode.light, ThemeMode.dark, scheduled][themeType.index];

              return MaterialApp(
                scrollBehavior: MyCustomScrollBehavior(),
                debugShowCheckedModeBanner: false,
                title: 'Tabame - Taskbar Menu',
                theme: ThemeData.light().copyWith(
                  splashColor: Color.fromARGB(225, 0, 0, 0),
                  backgroundColor: Color(globalSettings.lightTheme.background),
                  dialogBackgroundColor: Color(globalSettings.lightTheme.background),
                  cardColor: Color(globalSettings.lightTheme.background),
                  errorColor: Color(globalSettings.lightTheme.accentColor),
                  iconTheme: ThemeData.light().iconTheme.copyWith(color: Color(globalSettings.lightTheme.textColor)),
                  textTheme: ThemeData.light().textTheme.apply(
                      bodyColor: Color(globalSettings.lightTheme.textColor),
                      displayColor: Color(globalSettings.lightTheme.textColor),
                      decorationColor: Color(globalSettings.lightTheme.textColor)),
                  toggleableActiveColor: Color(globalSettings.lightTheme.accentColor),
                  checkboxTheme: ThemeData.light()
                      .checkboxTheme
                      .copyWith(visualDensity: VisualDensity.compact, checkColor: MaterialStateProperty.all(Color(globalSettings.lightTheme.background))),
                  tooltipTheme: ThemeData.light().tooltipTheme.copyWith(
                        verticalOffset: 10,
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        height: 0,
                        margin: EdgeInsets.all(0),
                        textStyle: TextStyle(color: Color(globalSettings.lightTheme.textColor), fontSize: 12, height: 0),
                        decoration: BoxDecoration(color: Color(globalSettings.lightTheme.background)),
                        preferBelow: false,
                      ),
                  colorScheme: ThemeData.light().colorScheme.copyWith(
                        primary: Color(globalSettings.lightTheme.accentColor),
                        secondary: Color(globalSettings.lightTheme.accentColor),
                      ),
                ),
                darkTheme: ThemeData.dark().copyWith(
                  splashColor: Color.fromARGB(225, 0, 0, 0),
                  backgroundColor: Color(globalSettings.darkTheme.background),
                  dialogBackgroundColor: Color(globalSettings.darkTheme.background),
                  cardColor: Color(globalSettings.darkTheme.background),
                  errorColor: Color(globalSettings.darkTheme.accentColor),
                  iconTheme: ThemeData.dark().iconTheme.copyWith(color: Color(globalSettings.darkTheme.textColor)),
                  textTheme: ThemeData.dark().textTheme.apply(
                        bodyColor: Color(globalSettings.darkTheme.textColor),
                        displayColor: Color(globalSettings.darkTheme.textColor),
                        decorationColor: Color(globalSettings.darkTheme.textColor),
                      ),
                  toggleableActiveColor: Color(globalSettings.darkTheme.accentColor),
                  checkboxTheme: ThemeData.dark()
                      .checkboxTheme
                      .copyWith(visualDensity: VisualDensity.compact, checkColor: MaterialStateProperty.all(Color(globalSettings.darkTheme.background))),
                  tooltipTheme: ThemeData.dark().tooltipTheme.copyWith(
                        verticalOffset: 10,
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        height: 0,
                        margin: EdgeInsets.all(0),
                        textStyle: TextStyle(color: Color(globalSettings.darkTheme.textColor), fontSize: 12, height: 0),
                        decoration: BoxDecoration(color: Color(globalSettings.darkTheme.background)),
                        preferBelow: false,
                      ),
                  colorScheme: ThemeData.dark().colorScheme.copyWith(
                        primary: Color(globalSettings.darkTheme.accentColor),
                        secondary: Color(globalSettings.darkTheme.accentColor),
                        tertiary: Color(globalSettings.darkTheme.textColor),
                      ),
                ),
                themeMode: themeMode,
                // home: QuickMenu()
                home: PageView.builder(
                  controller: mainPageViewController,
                  allowImplicitScrolling: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (BuildContext context, int index) {
                    if (globalSettings.args.contains("-interface")) {
                      return const Interface();

                      // return FutureBuilder<int>(
                      //   future: Future<int>.delayed(Duration(milliseconds: 300), () => 1),
                      //   builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
                      //     if (!snapshot.hasData) return Container();
                      //     return const Interface();
                      //   },
                      // );
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
