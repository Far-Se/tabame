// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'pages/views.dart';
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
  if (File("${WinUtils.getTabameSettingsFolder()}\\enable_debug.txt").existsSync()) {
    Debug.register(clean: false);
  }
  if (File("${WinUtils.getTabameSettingsFolder()}\\disable_audio.txt").existsSync()) {
    Audio.alreadySet = true;
    Audio.canRunAudioModule = false;
  }

  Debug.add("===");
  Debug.add("Started");
  WidgetsFlutterBinding.ensureInitialized();
  Debug.add("Register WindowManager");
  await windowManager.ensureInitialized();

  if (kReleaseMode) {
    FlutterError.onError = handleErrors;
    PlatformDispatcher.instance.onError = handlePlatformErrors;
  }
  List<String> arguments = <String>[...arguments2];
  if (arguments.isNotEmpty) {
    if (arguments[0].endsWith('"') && !arguments[0].startsWith('"')) arguments[0] = '"${arguments[0]}';
    String argString = arguments.join(" ");
    globalSettings.args = <String>[...arguments];
    if (argString.contains("interface")) {
      globalSettings.page = TPage.interface;
    } else if (argString.contains("views")) {
      globalSettings.page = TPage.views;
    }
  }
  Debug.add("Parsed arguments ${globalSettings.page}");

  await registerAll();

  if (File("${WinUtils.getTabameSettingsFolder()}\\enable_debug.txt").existsSync()) {
    Debug.methodDebug(clean: false);
  }
  Debug.add("Registered All");

  if (kReleaseMode && globalSettings.runAsAdministrator && !WinUtils.isAdministrator() && !globalSettings.args.join(' ').contains('-tryadmin')) {
    Debug.add("Trying Admin");
    globalSettings.args.add('-tryadmin');
    WinUtils.closeAllTabameExProcesses();
    Debug.add("Closed all tabame processed");
    WinUtils.run(Platform.resolvedExecutable, arguments: '"${globalSettings.args.join('" "')}"');
    Debug.add("Started New");
    Timer(const Duration(seconds: 1), () {
      Debug.add("Started Close Current");
      exit(0);
    });
    runApp(EmptyWidget());
    return;
  }
  if (kReleaseMode && globalSettings.views && !globalSettings.args.contains('-views') && !globalSettings.args.contains("-interface")) {
    Debug.add("Starting Views");
    Future<void>.delayed(Duration(seconds: 3), () => WinUtils.startTabame(closeCurrent: false, arguments: "-views"));
  }

  if (Globals.debugHooks || kReleaseMode) {
    Debug.add("Registering Hooks");
    await NativeHooks.registerCallHandler();
    //!hook
  }

  /// ? Window
  late WindowOptions windowOptions;
  if (arguments.contains('-views')) {
    windowOptions = WindowOptions(
      size: Size(300, 300),
      center: false,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      alwaysOnTop: true,
      title: "Tabame Views",
    );
  } else if (globalSettings.args.contains("-interface") || Boxes.remap.isEmpty) {
    windowOptions = WindowOptions(
      size: Size(700, 600),
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
  Debug.add("Setting windowOptions");
  windowManager.setMinimizable(false);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await Win32.fetchMainWindowHandle();
    fullLoaded.value = true;
    Debug.add("Set windowOptions");
  });

  Debug.add("Setting transparency");
  await setWindowAsTransparent();
  Debug.add("Set transparency");
  runApp(Tabame());
  // if (arguments.contains('-views')) {
  //   return runApp(ViewsScreen());
  // }
  // runApp(const Tabame());
  // runZonedGuarded(() => runApp(Tabame()), (Object error, StackTrace stackTrace) async {
  //   String stack = stackTrace.toString();
  //   final List<String> stackArr = stack.split("\n");
  //   if (stackArr.length > 11) {
  //     stack = stackArr.take(10).join("\n");
  //   }
  //   stack = "$stack\n===============\n===============\n";
  //   File("${WinUtils.getTabameSettingsFolder()}\\errors.log").writeAsStringSync("${error.toString()}\n$stack", mode: FileMode.append);
  // });
}

void handleErrors(FlutterErrorDetails details) async {
  final String error = "(${details.library ?? "unknownLib"}) ${details.exceptionAsString()}";
  String stack = details.stack.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack = "$stack\n${details.context?.toDescription()}\n${details.summary.toString()}\n${details.context.toString()}\n===============\n";
  File("${WinUtils.getTabameSettingsFolder()}\\errors.log").writeAsStringSync("$error\n$stack", mode: FileMode.append);
}

bool handlePlatformErrors(Object error, StackTrace stack2) {
  String stack = stack2.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack = "$stack\n===============\n";
  File("${WinUtils.getTabameSettingsFolder()}\\errors.log").writeAsStringSync("${error.toString()}\n$stack", mode: FileMode.append);
  return true;
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
    super.initState();
    Debug.add("Tabame: init");
    ThemeType theme = globalSettings.themeTypeMode;
    Timer.periodic(Duration(minutes: 1), (Timer timer) {
      if (theme != globalSettings.themeTypeMode) {
        theme = globalSettings.themeTypeMode;
        themeChangeNotifier.value = !themeChangeNotifier.value;
        if (mounted) setState(() {});
      }
    });

    final SingletonFlutterWindow window = WidgetsBinding.instance.window;
    window.onPlatformBrightnessChanged = () {
      theme = globalSettings.themeTypeMode;
      themeChangeNotifier.value = !themeChangeNotifier.value;
      if (mounted) setState(() {});
    };
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: fullLoaded,
        builder: (BuildContext context, bool value, __) {
          Debug.add("Tabame: fullLoaded");
          if (value == false) return Container();
          return ValueListenableBuilder<bool>(
            valueListenable: themeChangeNotifier,
            builder: (_, bool refreshed, __) {
              Debug.add("Tabame: Theme");
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
                    Debug.add("Tabame: $index ${globalSettings.args.join(':')}");
                    if (globalSettings.args.contains('-views')) {
                      return const ViewsScreen();
                    }
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
