import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import 'package:window_manager/window_manager.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/globals.dart';
import '../widgets/quickmenu/bottom_bar.dart';
import '../widgets/quickmenu/task_bar.dart';
import '../widgets/quickmenu/top_bar.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({Key? key}) : super(key: key);
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

Future<int> quickMenuWindowSetup() async {
  Globals.lastPage = Globals.currentPage;
  Globals.currentPage = Pages.quickmenu;
  // ! For Release Build
  print("p1");
  if (kReleaseMode && Globals.justStarted) {
    print("p11");
    Globals.justStarted = false;
    final Point mousePos = WinUtils.getMousePos();
    await WindowManager.instance.setPosition(Offset(mousePos.X.toDouble(), mousePos.Y.toDouble()));
    return 1;
  }
  // ! ^^^^^^^^^^^

  print("p2");
  if (Globals.lastPage != Pages.quickmenu) {
    print("p9");
    await WindowManager.instance.setMinimumSize(const Size(300, 150));
    print("p3");
    await WindowManager.instance.setSize(const Size(300, 300));
    print("p3");
    await WindowManager.instance.setSkipTaskbar(true);
    print("p3");
    await WindowManager.instance.setResizable(false);
    print("p3");
    await WindowManager.instance.setAlwaysOnTop(true);
    print("p3");
    await WindowManager.instance.setAspectRatio(0);
    print("p3");
    final Point mousePos = WinUtils.getMousePos();
    print("p3");
    await WindowManager.instance.setPosition(Offset(mousePos.X.toDouble(), mousePos.Y.toDouble()));
  }
  print("p3");
  return 1;
}

class QuickMenuState extends State<QuickMenu> {
  @override
  void initState() {
    super.initState();
    Globals.changingPages = false;
    // init();
  }

  final Future<int> quickMenuWindow = quickMenuWindowSetup();

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Globals.changingPages) return const SizedBox(width: 10);
    return FutureBuilder<int>(
      future: quickMenuWindow,
      builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 10);
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: MouseRegion(
            onEnter: (PointerEnterEvent event) => Globals.isWindowActive = true,
            onExit: (PointerExitEvent event) => Globals.isWindowActive = false,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              physics: const NeverScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(10) + const EdgeInsets.only(top: 20),
                child: Container(
                  color: Colors.black,
                  child: Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).backgroundColor,
                        gradient: LinearGradient(
                          colors: <Color>[
                            Theme.of(context).backgroundColor,
                            Theme.of(context).backgroundColor.withAlpha(200),
                            Theme.of(context).backgroundColor,
                          ],
                          stops: <double>[0, 0.4, 1],
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: <BoxShadow>[
                          const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                        ]),
                    child: FutureBuilder<Object>(
                        future: Future<bool>.delayed(const Duration(milliseconds: 50), () async {
                          return true;
                        }),
                        builder: (BuildContext context, AsyncSnapshot<Object> snapshot) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              //3 Items
                              const TopBar(),
                              const TaskBar(),
                              const Divider(
                                thickness: 1,
                                height: 1,
                              ),
                              const BottomBar(),
                            ],
                          );
                        }),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
