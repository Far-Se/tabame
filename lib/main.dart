// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';

import 'models/classes/boxes.dart';
import 'models/globals.dart';
import 'models/settings.dart';
import 'models/win32/win32.dart';
import 'pages/interface.dart';
import 'pages/quickmenu.dart';

final ValueNotifier<bool> fullLoaded = ValueNotifier<bool>(false);
Future<void> main(List<String> arguments2) async {
  // List<String> arguments = <String>[r"E:\Projects\Tabame", "-interface", "-wizardly"];
  List<String> arguments = arguments2;
  /*
  E:\Projects\Tabame
  -interface
  -wizardly
  */
  if (arguments.isNotEmpty) {
    String argString = arguments.join(" ");
    if (argString.indexOf('"') > 0 && argString.contains('"')) argString = '"$argString';
    List<String> auxArgs = argString.split(' ');
    globalSettings.args = <String>[...auxArgs];
    if (argString.contains("interface")) {
      globalSettings.page = TPage.interface;
    } else if (argString.contains("views")) {
      globalSettings.page = TPage.views;
    }
  }
  // WinUtils.msgBox(arguments.join("\n"), "tite");

  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  await registerAll();

  if (kReleaseMode && globalSettings.runAsAdministrator && !WinUtils.isAdministrator() && !globalSettings.args.join(' ').contains('-tryadmin')) {
    globalSettings.args.remove('-strudel');
    globalSettings.args.add('-tryadmin');
    WinUtils.run(Platform.resolvedExecutable, arguments: globalSettings.args.join(' '));
    Timer(const Duration(seconds: 1), () => exit(0));
    runApp(EmptyWidget());
    return;
    // WinUtils.run(Platform.resolvedExecutable, arguments: globalSettings.args.join(' '));
  }
  if (Globals.hotkeysEnabled || kReleaseMode) {
    await NativeHotkey.register();
    //!hook
    // Timer.periodic(Duration(minutes: 15), (Timer t) async {
    //   await NativeHotkey.unHook();
    //   await NativeHotkey.hook();
    // });
  }

  /// ? Window
  late WindowOptions windowOptions;
  if (globalSettings.args.contains("-interface") || Boxes.remap.isEmpty) {
    print("nomap");
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
      size: Size(300, 540),
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
  void initState() {
    ThemeType theme = globalSettings.themeTypeMode;
    Timer.periodic(Duration(minutes: 1), (Timer timer) {
      if (theme != globalSettings.themeTypeMode) {
        theme = globalSettings.themeTypeMode;
        themeChangeNotifier.value = !themeChangeNotifier.value;
        if (mounted) setState(() {});
      }
    });
    super.initState();
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
                  buttonTheme: ThemeData.dark().buttonTheme.copyWith(
                        textTheme: ButtonTextTheme.primary,
                        colorScheme: Theme.of(context).colorScheme.copyWith(primary: Theme.of(context).backgroundColor),
                      ),
                ),
                themeMode: themeMode,
                home: PageView.builder(
                  controller: mainPageViewController,
                  allowImplicitScrolling: false,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (BuildContext context, int index) {
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
  const EmptyWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tabame aux',
      home: Text("closing"),
    );
  }
}
