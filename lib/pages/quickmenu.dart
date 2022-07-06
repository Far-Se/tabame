import 'package:flutter/material.dart';
import '../widgets/containers/two_sides.dart';
import '../widgets/itzy/time_weather_widget.dart';
import '../widgets/traybar.dart';
import '../widgets/containers/top_bar.dart';
import '../widgets/taskbar.dart';
import 'package:window_manager/window_manager.dart';

class QuickMenu extends StatelessWidget with WindowListener {
  const QuickMenu({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kWindowCaptionHeight),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (details) {
              windowManager.startDragging();
            },
            child: Container(
              margin: const EdgeInsets.all(0) + EdgeInsets.only(left: 10),
              width: double.infinity,
              height: 15,
              color: Colors.transparent,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Image(image: AssetImage("resources/logo.png")),
              ),
            ),
          )),
      //#h white
      //1 Body
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
                      TopBar(),
                      Taskbar(),
                      TwoSides(left: TimeWeatherWidget(), right: Traybar()),
                      // BarWithButtons(children: [Traybar()], withScroll: false),
                      /* BarWithButtons(
                        children: [
                          SimulateKeyButton(icon: Icons.desktop_windows, simulateKeys: "{#WIN}D", color: Theme.of(context).iconTheme.color!),
                          InkWell(
                            onTap: () {
                              WinUtils.getTaskbarPinnedApps().then((e) => print(e));
                            },
                            child: Icon(Icons.run_circle_sharp),
                          ),
                          WindowsAppButton(path: "C:\\Windows\\explorer.exe"),
                        ],
                      )
                       */ // Buttonbar(children: const [TimeWidget(), WeatherWidget()]),
                    ],
                  );
                }),
          ),
        ),
      ),
      //#e
    );
  }
}
