import 'dart:async';

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
  final bool editMode;
  const QuickMenu({Key? key, this.editMode = false}) : super(key: key);
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

class QuickMenuState extends State<QuickMenu> {
  @override
  void initState() {
    super.initState();
    Globals.opacity = true;
    if (!widget.editMode) {
      init();
    }
    //WindowManager.instance.setAlwaysOnTop(true);
    //WindowManager.instance.setSkipTaskbar(true);
    // Future<void>.delayed(const Duration(milliseconds: 100), () {
    //   WindowManager.instance.setResizable(false);
    //   WindowManager.instance.setAlwaysOnTop(true);
    //   WindowManager.instance.setSkipTaskbar(true);
    //   // WindowManager.instance.setSize(const Size(300, 150));
    // });
    // Timer.periodic(Duration(seconds: 3), (timer) {
    //   setState(() {});
    // });
  }

  void init() async {
    // await WindowManager.instance.setSize(Size(monitor.width / 2, monitor.height / 1.25));
    await WindowManager.instance.setMinimumSize(const Size(300, 150));
    // await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
    await WindowManager.instance.setSkipTaskbar(true);
    await WindowManager.instance.setResizable(false);
    await WindowManager.instance.setAlwaysOnTop(true);
    final Point mousePos = WinUtils.getMousePos();
    await WindowManager.instance.setPosition(Offset(mousePos.X.toDouble(), mousePos.Y.toDouble()));
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedOpacity(
        opacity: Globals.opacity ? 1.0 : 0,
        duration: const Duration(milliseconds: 100),
        child: MouseRegion(
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
                            TopBar(),
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
      ),
    );
  }
}
