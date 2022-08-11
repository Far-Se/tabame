// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../main.dart';
import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../widgets/interface/changelog.dart';
import '../widgets/interface/first_run.dart';
import '../widgets/interface/home.dart';
import '../widgets/interface/projects.dart';
import '../widgets/interface/quickmenu_settings.dart';
import '../widgets/interface/quickrun_settings.dart';
import '../widgets/interface/interface_settings.dart';
import '../widgets/interface/hotkeys_interface.dart';
import '../widgets/interface/tasks.dart';
import '../widgets/interface/theme_setup.dart';
import '../widgets/interface/trktivity.dart';
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
  Monitor.fetchMonitor();
  Globals.currentPage = Pages.interface;
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  final Square monitor = Monitor.monitorSizes[Win32.getWindowMonitor(Win32.hWnd)]!;
  await WindowManager.instance.setMinimumSize(const Size(700, 400));
  // await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
  await WindowManager.instance.setSkipTaskbar(false);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(false);
  await WindowManager.instance.setSize(Size(monitor.width / 2.2, monitor.height / 1.55));
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

class InterfaceState extends State<Interface> with SingleTickerProviderStateMixin {
  int currentPage = 0;
  PageController page = PageController();
  final List<PageClass> pages = <PageClass>[
    PageClass(title: 'Home', icon: Icons.home, widget: const Home()),
    PageClass(title: 'Settings', icon: Icons.settings, widget: const SettingsPage()),
    PageClass(title: 'Colors', icon: Icons.theater_comedy, widget: const ThemeSetup()),
    PageClass(title: 'QuickMenu', icon: Icons.apps, widget: const QuickmenuSettings()),
    PageClass(title: 'QuickRun', icon: Icons.drag_handle, widget: const RunSettings()),
    PageClass(title: 'Hotkeys', icon: Icons.keyboard, widget: const HotkeysInterface()),
    // PageClass(title: 'Views', icon: Icons.view_agenda, widget: const ViewsInterface()),
    PageClass(title: 'Projects', icon: Icons.folder_copy, widget: const ProjectsPage()),
    PageClass(title: 'Trktivity', icon: Icons.scatter_plot, widget: const TrktivityPage()),
    PageClass(title: 'Tasks', icon: Icons.task_alt, widget: const TasksPage()),
    PageClass(title: 'Wizardly', icon: Icons.auto_fix_high, widget: const Wizardly()),
    PageClass(title: 'Changelog', icon: Icons.newspaper, widget: const Changelog()),
    PageClass(title: 'FirstRun', icon: Icons.newspaper, widget: const FirstRun()),
  ];
  final List<String> disableScroll = <String>["Wizardly"];
  final Future<int> interfaceWindow = interfaceWindowSetup();
  int hoveredPage = -1;

  bool bmaCoffeHovered = false;

  @override
  void initState() {
    if (globalSettings.args.contains("-wizardly")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Wizardly");
      if (currentPage == -1) currentPage = 1;
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
                                          if (kReleaseMode) {
                                            if (globalSettings.args.contains('-wizardly')) {
                                              exit(0);
                                            } else if (globalSettings.args.contains('-interface')) {
                                              await Boxes.pref.remove("previewThemeLight");
                                              await Boxes.pref.remove("previewThemeDark");
                                              WinUtils.reloadTabameQuickMenu();
                                              exit(0);
                                            }
                                          } else {
                                            Globals.changingPages = true;
                                            setState(() {});
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
                                  // if (!globalSettings.args.contains("-wizardly")) //2 commented this
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
                                              controller: ScrollController(),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.start,
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: <Widget>[
                                                  ListView.builder(
                                                    scrollDirection: Axis.vertical,
                                                    itemCount: pages.length,
                                                    shrinkWrap: true,
                                                    physics: const ClampingScrollPhysics(),
                                                    itemBuilder: (BuildContext context, int index) {
                                                      final PageClass pageItem = pages[index];
                                                      return DecoratedBox(
                                                        decoration: BoxDecoration(
                                                            color: currentPage == index ? Color(globalSettings.theme.textColor).withOpacity(0.1) : Colors.transparent),
                                                        child: InkWell(
                                                          radius: 0,
                                                          onTap: () {
                                                            setState(() => currentPage = index);
                                                          },
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
                                                      );
                                                    },
                                                  ),
                                                  //2 Exit
                                                  const Divider(height: 5, thickness: 1),
                                                  DecoratedBox(
                                                    decoration: BoxDecoration(
                                                        color: hoveredPage == 99 ? Color(globalSettings.theme.textColor).withOpacity(0.06) : Colors.transparent),
                                                    child: MouseRegion(
                                                      onEnter: (PointerEnterEvent v) => setState(() => hoveredPage = 99),
                                                      onExit: (PointerExitEvent v) => setState(() => hoveredPage = -1),
                                                      cursor: SystemMouseCursors.click,
                                                      child: InkWell(
                                                        radius: 0,
                                                        onTap: () => setState(() {
                                                          showDialog(
                                                              context: context,
                                                              builder: (BuildContext context) => AlertDialog(
                                                                    content: Container(
                                                                        height: 50,
                                                                        child: const Center(
                                                                            child: Text("This will close the whole app, not just Interface, continue?",
                                                                                style: TextStyle(fontSize: 20)))),
                                                                    actions: <Widget>[
                                                                      ElevatedButton(
                                                                          onPressed: () {
                                                                            WinUtils.closeMainTabame();
                                                                            exit(0);
                                                                          },
                                                                          child: Text("Full Exit", style: TextStyle(color: Theme.of(context).backgroundColor))),
                                                                      ElevatedButton(
                                                                          onPressed: () => Navigator.of(context).pop(),
                                                                          child: Text("Cancel", style: TextStyle(color: Theme.of(context).backgroundColor))),
                                                                    ],
                                                                  ));
                                                        }),
                                                        child: Padding(
                                                          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
                                                          child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.start,
                                                            crossAxisAlignment: CrossAxisAlignment.center,
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: <Widget>[
                                                              const SizedBox(width: 5),
                                                              const Icon(Icons.exit_to_app),
                                                              const SizedBox(width: 5),
                                                              const Text("Exit"),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              ),
                                            ),
                                          ),

                                          //2 Donation Box
                                          SizedBox(
                                            height: 200,
                                            child: Padding(
                                              padding: const EdgeInsets.fromLTRB(5, 0, 2, 5),
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.end,
                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                children: <Widget>[
                                                  const Center(
                                                      child: Text(
                                                    "Coded by Far Se",
                                                    style: TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w500),
                                                  )),
                                                  Column(
                                                    mainAxisAlignment: MainAxisAlignment.start,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: <Widget>[
                                                      const SizedBox(height: 5),
                                                      const Padding(
                                                        padding: EdgeInsets.only(left: 5.0),
                                                        child: Text(
                                                          "If you find this app useful consider a donation\nit will be appreciated ☺",
                                                          style: TextStyle(fontSize: 12),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 10),
                                                      TextButton(
                                                        onPressed: () {
                                                          WinUtils.open("https://www.buymeacoffee.com/far.se");
                                                        },
                                                        onHover: (bool value) {},
                                                        child: MouseRegion(
                                                          onEnter: (PointerEnterEvent e) => setState(() => bmaCoffeHovered = true),
                                                          onExit: (PointerExitEvent e) => setState(() => bmaCoffeHovered = false),
                                                          child: Container(
                                                            width: double.infinity,
                                                            height: 26,
                                                            padding: const EdgeInsets.symmetric(vertical: 5),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xffCE3F00).withOpacity(0.5),
                                                              borderRadius: BorderRadius.circular(20),
                                                            ),
                                                            child: ClipRRect(
                                                              child: Stack(
                                                                children: <Widget>[
                                                                  Center(
                                                                    child: TweenAnimationBuilder<double>(
                                                                      duration: const Duration(milliseconds: 400),
                                                                      tween: Tween<double>(begin: 1.0, end: bmaCoffeHovered ? -30 : 1),
                                                                      curve: Curves.fastLinearToSlowEaseIn,
                                                                      builder: (BuildContext context, double value, _) {
                                                                        return Transform.translate(
                                                                          offset: Offset(1, value),
                                                                          child: const Text(
                                                                            "Buy me a coffee",
                                                                            style: TextStyle(
                                                                              color: Colors.white,
                                                                              height: 1.001,
                                                                              fontSize: 14,
                                                                              fontWeight: FontWeight.bold,
                                                                            ),
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                  Center(
                                                                    child: TweenAnimationBuilder<double>(
                                                                      duration: const Duration(milliseconds: 400),
                                                                      tween: Tween<double>(begin: 30.0, end: bmaCoffeHovered ? 0 : 30),
                                                                      curve: Curves.fastLinearToSlowEaseIn,
                                                                      builder: (BuildContext context, double value, _) {
                                                                        return Transform.translate(
                                                                          offset: Offset(1, value),
                                                                          child: Transform.rotate(
                                                                            angle: value / 10,
                                                                            child: const Text(
                                                                              "☕",
                                                                              style: TextStyle(
                                                                                color: Colors.white,
                                                                                height: 1,
                                                                                fontSize: 17.5,
                                                                                fontWeight: FontWeight.bold,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                  )
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 5),
                                                    ],
                                                  )
                                                ],
                                              ),
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
