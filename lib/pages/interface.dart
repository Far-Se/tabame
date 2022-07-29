// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../widgets/interface/home.dart';
import '../widgets/interface/projects.dart';
import '../widgets/interface/quickmenu.dart';
import '../widgets/interface/run_settings.dart';
import '../widgets/interface/settings.dart';
import '../widgets/interface/tasks.dart';
import '../widgets/interface/theme_setup.dart';
import '../widgets/interface/wizardly.dart';

class PageClass {
  String? title;
  IconData? icon;
  Widget widget;
  PageClass({
    this.title,
    this.icon,
    required this.widget,
  });
}

Future<int> interfaceWindowSetup() async {
  Globals.currentPage = Pages.interface;
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  final Square monitor = Monitor.monitorSizes[Win32.getWindowMonitor(Win32.hWnd)]!;
  await WindowManager.instance.setMinimumSize(const Size(700, 400));
  // await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
  await WindowManager.instance.setSkipTaskbar(false);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(false);
  await WindowManager.instance.setSize(Size(monitor.width / 2.2, monitor.height / 1.65));
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  return 1;
}

bool mainScrollEnabled = true;
BoxConstraints? interfaceConstraints;

class NotImplemeneted extends StatelessWidget {
  const NotImplemeneted({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(child: const Center(child: Text("Not implementedd")));
  }
}

class Interface extends StatefulWidget {
  const Interface({Key? key}) : super(key: key);
  @override
  InterfaceState createState() => InterfaceState();
}

class InterfaceState extends State<Interface> {
  int currentPage = 0;
  PageController page = PageController();
  final List<PageClass> pages = <PageClass>[
    PageClass(title: 'Home', icon: Icons.home, widget: const Home()),
    PageClass(title: 'Settings', icon: Icons.settings, widget: const SettingsPage()),
    PageClass(title: 'Colors', icon: Icons.theater_comedy, widget: const ThemeSetup()),
    PageClass(title: 'QuickMenu', icon: Icons.apps, widget: const QuickmenuSettings()),
    PageClass(title: 'Run Window', icon: Icons.drag_handle, widget: const RunSettings()),
    PageClass(title: 'Remap Keys', icon: Icons.keyboard, widget: const NotImplemeneted()),
    PageClass(title: 'Views', icon: Icons.view_agenda, widget: const NotImplemeneted()),
    PageClass(title: 'Projects', icon: Icons.folder_copy, widget: const ProjectsPage()),
    PageClass(title: 'Trktivity', icon: Icons.celebration, widget: const NotImplemeneted()),
    PageClass(title: 'Tasks', icon: Icons.task_alt, widget: const TasksPage()),
    PageClass(title: 'Wizardly', icon: Icons.auto_fix_high, widget: const Wizardly()),
    PageClass(title: 'Info', icon: Icons.info, widget: const NotImplemeneted()),
  ];
  final List<String> disableScroll = <String>["Wizardly"];
  final Future<int> interfaceWindow = interfaceWindowSetup();
  @override
  void initState() {
    if (globalSettings.args.contains("-wizardly")) {
      currentPage = 10;
    }
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
        return DragToResizeArea(
          // resizeEdgeSize: 5,
          child: Padding(
            padding: const EdgeInsets.all(3) - const EdgeInsets.only(top: 3),
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
                        child: Container(
                          height: 30,
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
                                child: InkWell(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 5),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.translucent,
                                        onPanStart: (DragStartDetails details) {
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
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: <Widget>[
                                            Image(image: AssetImage(globalSettings.logo), width: 15),
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
                                    //! go to quickmenu
                                    SizedBox(
                                      width: 25,
                                      child: InkWell(
                                        onTap: () async {
                                          Globals.changingPages = true;
                                          setState(() {});
                                          if (kReleaseMode) {
                                            if (globalSettings.args.contains('-wizardly')) {
                                              exit(0);
                                            }
                                            if (WinUtils.isAdministrator()) {
                                              WinUtils.run(Platform.resolvedExecutable);
                                              Future<void>.delayed(const Duration(milliseconds: 400), () => exit(0));
                                            } else {
                                              WinUtils.open(Platform.resolvedExecutable);
                                              Future<void>.delayed(const Duration(milliseconds: 400), () => exit(0));
                                            }
                                          } else {
                                            mainPageViewController.jumpToPage(Pages.quickmenu.index);
                                          }
                                        },
                                        child: const Padding(padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 15)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      //1 Body
                      body: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints mainConstraints) {
                          interfaceConstraints = mainConstraints;
                          return DecoratedBox(
                            decoration: BoxDecoration(
                                color: Theme.of(context).backgroundColor,
                                gradient: LinearGradient(
                                  colors: <Color>[Theme.of(context).backgroundColor, Theme.of(context).backgroundColor.withAlpha(180), Theme.of(context).backgroundColor],
                                  stops: <double>[0, 0.4, 1],
                                  end: Alignment.bottomRight,
                                )),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 1080),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: Caa.stretch,
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
                                                  return DecoratedBox(
                                                    decoration: BoxDecoration(
                                                        color: currentPage == index ? Color(globalSettings.theme.textColor).withOpacity(0.1) : Colors.transparent),
                                                    child: GestureDetector(
                                                      onTap: () {
                                                        currentPage = index;
                                                        if (mounted) setState(() {});
                                                      },
                                                      child: MouseRegion(
                                                        cursor: SystemMouseCursors.click,
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
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
                                              children: <Widget>[],
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
                                    child: ClipRect(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                                        child: Listener(
                                          onPointerSignal: (PointerSignalEvent pointerSignal) {
                                            if (pointerSignal is PointerScrollEvent) {
                                              if (pointerSignal.scrollDelta.dy < 0) {
                                              } else {}
                                            }
                                          },
                                          child: SingleChildScrollView(
                                            controller: AdjustableScrollController(40),
                                            physics: mainScrollEnabled ? const BouncingScrollPhysics(parent: PageScrollPhysics()) : const NeverScrollableScrollPhysics(),
                                            child: Material(type: MaterialType.transparency, child: pages[currentPage].widget),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  //#e
                                ],
                              ),
                            ),
                          );
                        },
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
