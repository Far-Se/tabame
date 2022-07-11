import 'dart:async';

import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import '../widgets/quickmenu/bottom_bar.dart';
import '../widgets/quickmenu/top_bar.dart';
import '../widgets/quickmenu/task_bar.dart';
import '../models/globals.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({Key? key}) : super(key: key);
  @override
  State<QuickMenu> createState() => _QuickMenuState();
}

class _QuickMenuState extends State<QuickMenu> {
  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    // Timer.periodic(Duration(seconds: 3), (timer) {
    //   setState(() {});
    // });
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
      body: MouseRegion(
        onEnter: (PointerEnterEvent event) => Globals.isWindowActive = true,
        onExit: (PointerExitEvent event) => Globals.isWindowActive = false,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
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
    );
  }
}
