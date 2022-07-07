// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'models/registration.dart';
import 'pages/quickmenu.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await registerAll();

  /// ? Window
  WindowOptions windowOptions = const WindowOptions(
    size: Size(300, 150),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    alwaysOnTop: true,
    minimumSize: Size(300, 150),
    title: "Tabame",
  );
  windowManager.setMinimizable(false);
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
  });

  await setWindowAsTransparent();
  runApp(const Tabame());
}

final kColor = Color(0xff3B414D);

class Tabame extends StatelessWidget {
  const Tabame({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scrollBehavior: MyCustomScrollBehavior(),
      debugShowCheckedModeBanner: false,
      title: 'Tabame',
      theme: ThemeData(
        splashColor: Color.fromARGB(40, 0, 0, 0),
        primarySwatch: Colors.red,
        backgroundColor: Color(0xff3B414D),
        iconTheme: Theme.of(context).iconTheme.copyWith(color: Colors.white),
        dividerColor: Color.fromARGB(255, 51, 54, 61),
        cardColor: Color(0xff3B414D),
        textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
      ),
      home: const QuickMenu(),
    );
  }
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {PointerDeviceKind.touch, PointerDeviceKind.mouse};
}
