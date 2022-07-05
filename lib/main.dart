// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'pages/quickmenu.dart';
import 'package:window_manager/window_manager.dart';
import 'models/utils.dart';
import 'models/boxes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final locale = Platform.localeName.substring(0, 2);
  print(locale);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);
  //
  await Boxes.registerBoxes();

  await Boxes.settings.getAt(0) ?? Boxes.settings.putAt(0, globalSettings);

  Settings settings = await Boxes.settings.getAt(0);
  settings.taskBarStyle = TaskBarAppsStyle.activeMonitorFirst;
  await Boxes.settings.putAt(0, settings);

  globalSettings = await Boxes.settings.getAt(0);

  globalSettings.weatherCity = "iasi";
  await Boxes.settings.putAt(0, globalSettings);
  // print((Boxes.settings.getAt(0) as Settings).taskBarAppsStyle);
  //
  // await Boxes.remapKeys.deleteAll(["pl"]);
  // await Boxes.remapKeys.put("pl", RemapKeys(from: "PIZDAM MATII", to: "BAGAMIAS PULA"));
  await Window.initialize();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(300, 150),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    // titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    minimumSize: Size(300, 150),
    title: "Tabame",
  );
  // await windowManager.setAsFrameless();
  // await windowManager.setHasShadow(false);
  windowManager.setMinimizable(false);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    // runApp(const MyApp());
  });
  await Window.setEffect(
    effect: WindowEffect.transparent,
    dark: false,
  );
  runApp(const Tabame());
}

class Main extends StatelessWidget {
  const Main({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}

class Tabame extends StatelessWidget {
  const Tabame({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyCustomScrollBehavior(),
      debugShowCheckedModeBanner: false,
      title: 'Tabame',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const QuickMenu(),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  // Override behavior methods and getters like dragDevices
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}
