import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/containers/two_sides.dart';
import '../widgets/itzy/time_weather_widget.dart';
import '../widgets/traybar.dart';
import '../widgets/containers/top_bar.dart';
import '../widgets/taskbar.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({Key? key}) : super(key: key);
  @override
  State<QuickMenu> createState() => _QuickMenuState();
}

class _QuickMenuState extends State<QuickMenu> {
  @override
  void initState() {
    super.initState();
    // Timer.periodic(Duration(seconds: 3), (timer) {
    //   setState(() {});
    // });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: EdgeInsets.all(10) - EdgeInsets.only(top: 5),
          child: Container(
            color: Colors.transparent,
            // color: Theme.of(context).scaffoldBackgroundColor,
            child: FutureBuilder<Object>(
                future: Future.delayed(Duration(milliseconds: 50), () async {
                  return true;
                }),
                builder: (context, snapshot) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      //3 Items
                      TopBar(),
                      Taskbar(),
                      Divider(
                        thickness: 1,
                        height: 1,
                      ),
                      TwoSides(left: TimeWeatherWidget(), right: Traybar()),
                    ],
                  );
                }),
          ),
        ),
      ),
    );
  }
}
