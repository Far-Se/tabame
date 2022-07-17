// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart';
import '../models/globals.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../widgets/interface/home.dart';
import '../widgets/interface/quickmenu_settings.dart';

class Interface extends StatefulWidget {
  const Interface({Key? key}) : super(key: key);

  @override
  InterfaceState createState() => InterfaceState();
}

class PageClass {
  String? title;
  IconData? icon;
  PageClass({
    this.title,
    this.icon,
  });
}

// double maxHeight = 0;
Future<int> interfaceWindowSetup() async {
  Globals.lastPage = Globals.currentPage;
  Globals.currentPage = Pages.interface;
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  final Square monitor = Monitor.monitorSizes[Win32.getWindowMonitor(Win32.hWnd)]!;
  // maxHeight = monitor.height / 1.25;
  await WindowManager.instance.setMinimumSize(const Size(400, 400));
  await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
  await WindowManager.instance.setSize(Size(monitor.width / 2.5, monitor.height / 1.7));
  await WindowManager.instance.setSkipTaskbar(false);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(false);
  await WindowManager.instance.setAspectRatio(1.3);
  await WindowManager.instance.setSize(Size(monitor.width / 2.5, monitor.height / 1.7));
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  // sleep(const Duration(milliseconds: 200));
  return 1;
}

class InterfaceState extends State<Interface> {
  int currentPage = 0;
  PageController page = PageController();
  final List<PageClass> pages = <PageClass>[
    // PageClass(title: "Home", icon: Icons.home, page: Container(height: 20)),
    PageClass(title: 'Home', icon: Icons.home),
    PageClass(title: 'QuickMenu', icon: Icons.menu_outlined),
    PageClass(title: 'Run Window', icon: Icons.drag_handle),
    PageClass(title: 'Remap Keys', icon: Icons.keyboard),
    PageClass(title: 'Views', icon: Icons.view_agenda),
    PageClass(title: 'Trktivity', icon: Icons.celebration),
    PageClass(title: 'Tasks', icon: Icons.task_alt),
    PageClass(title: 'Wizardly', icon: Icons.auto_fix_high),
    PageClass(title: 'Settings', icon: Icons.settings),
  ];
  final List<Widget> pagesWidget = <Widget>[
    const Home(),
    const QuickmenuSettings(),
  ];
  final Future<int> interfaceWindow = interfaceWindowSetup();
  @override
  void initState() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    Globals.changingPages = false;
    super.initState();
  }

  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Globals.changingPages) {
      return const SizedBox(width: 10);
    }
    return FutureBuilder<int>(
      future: interfaceWindow,
      builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 10);
        return Padding(
          padding: const EdgeInsets.all(3) - const EdgeInsets.only(top: 3),
          child: DragToResizeArea(
            // color: Colors.black,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.transparent,
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                ],
              ),
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: Scaffold(
                      backgroundColor: Colors.transparent,
                      appBar: PreferredSize(
                        preferredSize: const Size(30, 30),
                        child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanStart: (DragStartDetails details) {
                              windowManager.startDragging();
                            },
                            child: Container(
                              height: 30,
                              // color: Theme.of(context).backgroundColor,
                              padding: const EdgeInsets.only(left: 5),
                              decoration: BoxDecoration(
                                boxShadow: <BoxShadow>[
                                  const BoxShadow(
                                    color: Colors.black,
                                    offset: Offset(0, 0),
                                    blurRadius: 0.1,
                                    blurStyle: BlurStyle.outer,
                                    spreadRadius: 0.5,
                                  )
                                ],
                                color: Theme.of(context).backgroundColor,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                mainAxisSize: MainAxisSize.max,
                                children: <Widget>[
                                  Flexible(
                                    fit: FlexFit.loose,
                                    // flex: 13,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.translucent,
                                      onPanStart: (DragStartDetails details) {
                                        windowManager.startDragging();
                                      },
                                      child: InkWell(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Row(
                                              // alignment: WrapAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              // textBaseline: TextBaseline.alphabetic,
                                              children: <Widget>[
                                                const Image(image: AssetImage("resources/logo.png"), width: 15),
                                                const SizedBox(width: 5),
                                                const Text("Tabame", style: TextStyle(fontSize: 20)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 50,
                                    child: Wrap(
                                      children: <Widget>[
                                        SizedBox(
                                          width: 25,
                                          child: InkWell(
                                            onTap: () {
                                              WindowManager.instance.minimize();
                                            },
                                            child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.minimize, size: 15)),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 25,
                                          child: InkWell(
                                            onTap: () async {
                                              final NavigatorState noc = Navigator.of(context);
                                              Globals.changingPages = true;
                                              setState(() {});
                                              mainPageViewController.jumpToPage(Pages.quickmenu.index);

                                              // noc.pushAndRemoveUntil(
                                              //   PageRouteBuilder<QuickMenu>(
                                              //     maintainState: false,
                                              //     pageBuilder: (BuildContext context, Animation<double> a1, Animation<double> a2) => const QuickMenu(),
                                              //     transitionDuration: Duration.zero,
                                              //     reverseTransitionDuration: Duration.zero,
                                              //   ),
                                              //   (Route<dynamic> route) => false,
                                              // );
                                            },
                                            child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 15)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ),
                      //1 Body
                      body: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) => DecoratedBox(
                          decoration: BoxDecoration(
                              color: Theme.of(context).backgroundColor,
                              gradient: LinearGradient(
                                colors: <Color>[Theme.of(context).backgroundColor, Theme.of(context).backgroundColor.withAlpha(225), Theme.of(context).backgroundColor],
                                stops: <double>[0, 0.4, 1],
                                end: Alignment.bottomRight,
                              )),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: constraints.maxWidth),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: <Widget>[
                                //1 Sidebar
                                //#h green
                                Material(
                                  type: MaterialType.transparency,
                                  child: Container(
                                    width: 150,
                                    height: double.infinity,
                                    color: Colors.black12.withOpacity(0.1),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        const SizedBox(height: 10),
                                        Flexible(
                                          fit: FlexFit.tight,
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.vertical,
                                            child: ListView.builder(
                                              scrollDirection: Axis.vertical,
                                              itemCount: pages.length,
                                              shrinkWrap: true,
                                              physics: const ClampingScrollPhysics(),
                                              itemBuilder: (BuildContext context, int index) {
                                                final PageClass pageItem = pages[index];
                                                // print(pageItem);
                                                return InkWell(
                                                  onTap: () {
                                                    page.jumpToPage(index);
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 5),
                                                    child: Row(
                                                      mainAxisAlignment: MainAxisAlignment.start,
                                                      crossAxisAlignment: CrossAxisAlignment.center,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: <Widget>[
                                                        const SizedBox(width: 5),
                                                        Icon(pageItem.icon),
                                                        const SizedBox(width: 5),
                                                        Text(pageItem.title!),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                        //2 Donation Box
                                        SizedBox(
                                          height: 200,
                                          child: Wrap(
                                            children: <Widget>[
                                              // const Text("pis pe mata"),
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  ),
                                ),
                                //#e
                                //1 Pages
                                //#h white
                                Expanded(
                                  child: PageView.builder(
                                    controller: page,
                                    allowImplicitScrolling: false,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: pages.length,
                                    itemBuilder: (BuildContext context, int index) {
                                      if (index < pagesWidget.length) {
                                        return pagesWidget[index];
                                      } else {
                                        return Container(
                                          child: const Center(child: Text("NOT IMPLEMENTED")),
                                        );
                                      }
                                    },
                                  ),
                                ),
                                //#e
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
