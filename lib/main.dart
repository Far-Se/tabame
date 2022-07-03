// ignore_for_file: unnecessary_import, prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:tabame/widgets/taskbar.dart';
import 'package:window_manager/window_manager.dart';
import 'models/utils.dart';
import 'models/boxes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print("startup");
  //
  await Boxes.registerBoxes();

  await Boxes.settings.getAt(0) ?? Boxes.settings.putAt(0, globalSettings);

  Settings settings = Boxes.settings.getAt(0);
  settings.taskBarStyle = TaskBarAppsStyle.activeMonitorFirst;
  Boxes.settings.putAt(0, settings);

  globalSettings = await Boxes.settings.getAt(0);
  print(globalSettings.taskBarAppsStyle);
  // print((Boxes.settings.getAt(0) as Settings).taskBarAppsStyle);
  //
  // await Boxes.remapKeys.deleteAll(["pl"]);
  // await Boxes.remapKeys.put("pl", RemapKeys(from: "PIZDAM MATII", to: "BAGAMIAS PULA"));
  // await Window.initialize();
  // await Window.setEffect(
  //   effect: WindowEffect.transparent,
  //   dark: false,
  // );
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(300, 300),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    title: "Tabame",
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tabame',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final textController = TextEditingController(text: "-");

  @override
  Widget build(BuildContext context) {
    final ButtonStyle style = ElevatedButton.styleFrom(textStyle: const TextStyle(fontSize: 20));
    // Settings settings = Boxes.settings.get("settings");
    RemapKeys remapKeys = Boxes.remapKeys.get("pl");
    // final x = Boxes.remapKeys;
    textController.text = remapKeys.from;
    return Scaffold(
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kWindowCaptionHeight),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) {
              windowManager.startDragging();
            },
            onDoubleTap: () async {
              bool isMaximized = await windowManager.isMaximized();
              if (!isMaximized) {
                windowManager.maximize();
              } else {
                windowManager.unmaximize();
              }
            },
            child: Container(
              margin: const EdgeInsets.all(0),
              width: double.infinity,
              height: 54,
              color: Colors.grey.withOpacity(0.3),
              child: const Center(
                child: Text('TABAME'),
              ),
            ),
          )),
      body: Container(
        color: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Taskbar(),
            true
                ? SizedBox(width: 10)
                // ignore: dead_code
                : Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Flexible(
                        child: TextField(
                          controller: textController,
                          style: const TextStyle(fontSize: 12.0, color: Color(0xFF000000), fontWeight: FontWeight.w200, fontFamily: "Roboto"),
                        ),
                      ),
                      ElevatedButton(
                          style: style,
                          onPressed: () {
                            windows.fetchWindows(debug: true);
                            // settings.language = textController.text;
                            // Boxes.settings.put("settings", settings);
                          },
                          child: const Text(
                            "Set",
                            style: TextStyle(fontSize: 12.0, color: Color(0xFF000000), fontWeight: FontWeight.w200, fontFamily: "Roboto"),
                          ))
                    ],
                  )
          ],
        ),
      ),
    );
  }
}
