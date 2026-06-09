// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../widgets/interface/changelog.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/interface/first_run.dart';
import '../widgets/interface/home.dart';
import '../widgets/interface/hotkeys_interface.dart';
import '../widgets/interface/interface_faq.dart';
import '../widgets/interface/interface_quickmenu.dart';
import '../widgets/interface/interface_settings.dart';
import '../widgets/interface/theme_setup.dart';
import '../widgets/interface/trktivity.dart';
import '../widgets/interface/wizardly.dart';
import '../widgets/widgets/bmac_dialog.dart';
import '../widgets/widgets/custom_tooltip.dart';
import '../widgets/widgets/mouse_scroll_widget.dart';
import '../widgets/widgets/windows_scroll.dart';

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
  Monitor.fetchMonitors();
  Globals.currentPage = Pages.interface;
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  final Square monitor = Monitor.monitorSizes[Win32.getWindowMonitor(Win32.hWnd)]!;
  await WindowManager.instance.setMinimumSize(const Size(1100, 600));
  await WindowManager.instance.setMaximumSize(const Size(3000, 3000));
  // await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
  await WindowManager.instance.setSkipTaskbar(false);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(false);
  await WindowManager.instance.setAspectRatio(0);
  if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Interface");
  await WindowManager.instance.setSize(Size(
      (monitor.width / 1.8).clamp(360, 1000).floorToDouble(), (monitor.height / 1.3).clamp(500, 760).floorToDouble()));
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  return 1;
}

bool mainScrollEnabled = true;
BoxConstraints? interfaceConstraints;

class NotImplemeneted extends StatelessWidget {
  const NotImplemeneted({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(child: const Center(child: Text("Not implementedd")));
  }
}

class Interface extends StatefulWidget {
  const Interface({super.key});
  @override
  InterfaceState createState() => InterfaceState();
}

class Sponsorship {
  bool enabled = false;
  String url = "";

  @override
  String toString() => '\nSponsorship(enabled: $enabled, url: $url)';
}

class InterfaceState extends State<Interface> with SingleTickerProviderStateMixin {
  int currentPage = 0;
  PageController page = PageController();
  final Sponsorship sponsor = Sponsorship();
  final List<PageClass> pages = <PageClass>[
    PageClass(title: 'Home', icon: Icons.home, widget: const Home()),
    PageClass(title: 'Settings', icon: Icons.settings, widget: const SettingsPage()),
    PageClass(title: 'Theme', icon: Icons.theater_comedy, widget: const ThemeSetup()),
    PageClass(title: 'QuickMenu', icon: Icons.apps, widget: const QMSettings()),
    // PageClass(title: 'QuickRun', icon: Icons.drag_handle, widget: const RunSettings()),
    PageClass(title: 'Hotkeys', icon: Icons.keyboard, widget: const HotkeysInterface()),
    PageClass(title: 'Trktivity', icon: Icons.scatter_plot, widget: const TrktivityPage()),
    PageClass(title: 'Fancyshot', icon: Icons.center_focus_strong_rounded, widget: const Fancyshot()),
    PageClass(title: 'Wizardly', icon: Icons.auto_fix_high, widget: const Wizardly()),
    PageClass(title: 'F.A.Q', icon: Icons.contact_support, widget: const FaqPage()),
    PageClass(title: 'Changelog', icon: Icons.newspaper, widget: const Changelog()),
    PageClass(title: 'FirstRun', icon: Icons.newspaper, widget: const FirstRun()),
  ];
  final List<String> disableScroll = <String>[
    "Theme",
    "Wizardly",
    "Fancyshot",
    "FirstRun",
    "QuickMenu",
    "Hotkeys",
  ];
  final Future<int> interfaceWindow = interfaceWindowSetup();
  int hoveredPage = -1;

  bool bmaCoffeHovered = false;
  File? sponsorImageLight;
  File? sponsorImageDark;
  bool hideSidebar = false;
  @override
  void initState() {
    super.initState();
    WinUtils.fixDrawBug();
    if (userSettings.args.contains("-wizardly")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Wizardly");
    } else if (userSettings.args.contains("-fancyshot")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Fancyshot");
    } else if (userSettings.args.contains("-changelog")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Changelog");
    } else if (Boxes.remap.isEmpty) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "FirstRun");
      hideSidebar = true;
    }
    if (currentPage == -1) currentPage = 0; // Default to Home if-1
    page = PageController(initialPage: currentPage);
    Globals.changingPages = false;
    final String? sp = Boxes.pref.getString("sponsorLink");
    if (sp != null) {
      sponsor.enabled = true;
      sponsor.url = sp;
      if (File("${WinUtils.getTabameAppDataFolder()}\\sponsorLight.png").existsSync()) {
        sponsorImageLight = File("${WinUtils.getTabameAppDataFolder()}\\sponsorLight.png");
        sponsorImageDark = File("${WinUtils.getTabameAppDataFolder()}\\sponsorDark.png");
      }
    }
    checkForSponsor();
    if (!Boxes.pref.containsKey("bmacPopup")) {
      final int? installDate = Boxes.pref.getInt("installDate");
      if (installDate == null) {
        Boxes.pref.setInt("installDate", DateTime.now().millisecondsSinceEpoch);
      } else {
        final Duration diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(installDate));
        if (diff.inDays >= 2) {
          showBuyMeACoffeePopup = true;
        }
      }
    }
  }

  bool showBuyMeACoffeePopup = false;
  @override
  void dispose() {
    page.dispose();
    super.dispose();
  }

  Future<void> checkForSponsor() async {
    if (File("${WinUtils.getTabameAppDataFolder()}\\sponsorLight.png").existsSync()) {
      sponsorImageLight = File("${WinUtils.getTabameAppDataFolder()}\\sponsorLight.png");
      sponsorImageDark = File("${WinUtils.getTabameAppDataFolder()}\\sponsorDark.png");
    }
    final http.Response response = await http.get(Uri.parse(
        "https://raw.githubusercontent.com/Far-Se/tabame/master/resources/sponsor.json?e=${DateTime.now().hour}"));
    if (response.statusCode == 200) {
      final Map<String, dynamic> json = jsonDecode(response.body);
      if (!json.containsKey("enabled")) return;
      sponsor
        ..enabled = json["enabled"]
        ..url = json["url"];
      json["name"] ??= "test";
      if (!sponsor.enabled) {
        await Boxes.pref.remove("sponsorName");
        await Boxes.pref.remove("sponsorLink");
        if (mounted) setState(() {});
        return;
      }
      if (((Boxes.pref.getString("sponsorName") ?? "") != json["name"]) || sponsorImageLight == null) {
        Boxes.pref.setString("sponsorName", json["name"]);
        Boxes.pref.setString("sponsorLink", json["url"]);
        sponsorImageLight = File("${WinUtils.getTabameAppDataFolder()}\\sponsorLight.png");
        final http.Response rsp = await http.get(Uri.parse(json["imageLight"]));
        if (rsp.statusCode == 200) sponsorImageLight!.writeAsBytesSync(rsp.bodyBytes);

        sponsorImageDark = File("${WinUtils.getTabameAppDataFolder()}\\sponsorDark.png");
        final http.Response rsp2 = await http.get(Uri.parse(json["imageDark"]));
        if (rsp2.statusCode == 200) sponsorImageDark!.writeAsBytesSync(rsp2.bodyBytes);
      }
      if (mounted) setState(() {});
    }
  }

  final math.Random random = math.Random();
  @override
  Widget build(BuildContext context) {
    final int randomWallpaper = random.nextInt(Globals.totalGradients);
    if (Globals.changingPages) {
      return const SizedBox(width: 10);
    }
    if (showBuyMeACoffeePopup) {
      showBuyMeACoffeePopup = false;
      Future<void>.delayed(
        const Duration(seconds: 1),
        () {
          showDialog(
            context: context,
            builder: (BuildContext context) => const BMACDialog(),
          );
        },
      );
    }
    bool closing = false;
    return FutureBuilder<int>(
      future: interfaceWindow,
      builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 10);
        return DragToResizeArea(
          resizeEdgeSize: 5,
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
                        preferredSize: const Size(double.infinity, 32),
                        child: Container(
                          height: 35,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: Theme.of(context).dividerColor.withAlpha(25),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Expanded(
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
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Row(
                                        children: <Widget>[
                                          Image(image: AssetImage(userSettings.logo), width: 16),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Tabame",
                                            style: TextStyle(
                                              fontSize: Design.baseFontSize + 2,
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (kDebugMode)
                                            Text(
                                              "Interface",
                                              style: TextStyle(
                                                fontSize: 9,
                                                letterSpacing: 1.5,
                                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                _WindowButton(
                                  icon: Icons.minimize_rounded,
                                  onTap: () => WindowManager.instance.minimize(),
                                ),
                                CustomTooltip(
                                  message: "Close without reloading",
                                  preferBelow: true,
                                  verticalOffset: 2,
                                  child: _WindowButton(
                                    icon: Icons.unfold_less_double,
                                    onTap: () async {
                                      if (kReleaseMode) {
                                        exit(0);
                                      }
                                    },
                                  ),
                                ),
                                _WindowButton(
                                  icon: Icons.close_rounded,
                                  isCloseButton: true,
                                  onTap: () async {
                                    if (kReleaseMode) {
                                      if (userSettings.args.contains('-wizardly')) {
                                        exit(0);
                                      } else if (userSettings.args.contains('-fancyshot')) {
                                        exit(0);
                                      } else if (userSettings.args.contains('-interface')) {
                                        WinUtils.reloadTabameQuickMenu();
                                        exit(0);
                                      }
                                      exit(0);
                                    } else {
                                      setState(() {
                                        closing = true;
                                      });
                                      Globals.currentPage = Pages.quickmenu;

                                      Timer(const Duration(milliseconds: 100), () async {
                                        await WindowManager.instance.setMinimumSize(
                                            Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
                                        await WindowManager.instance
                                            .setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
                                      });
                                      Globals.changingPages = true;
                                      Globals.mainPageViewController.jumpToPage(Pages.quickmenu.index);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      //1 Body
                      body: closing
                          ? Container()
                          : LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints mainConstraints) {
                                interfaceConstraints = mainConstraints;
                                return Stack(
                                  children: <Widget>[
                                    Positioned.fill(
                                      child: Container(
                                        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
                                        child: Opacity(
                                          opacity: 0.18,
                                          child: Image.asset(
                                            'resources/gradient/gradient$randomWallpaper.jpg',
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned.fill(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.75),
                                              gradient: LinearGradient(
                                                colors: <Color>[
                                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.78),
                                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.84),
                                                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.78)
                                                ],
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
                                                // if (!userSettings.args.contains("-wizardly")) //2 commented this
                                                //1 Sidebar
                                                if (!hideSidebar)
                                                  Material(
                                                    type: MaterialType.transparency,
                                                    child: Container(
                                                      width: 220,
                                                      height: double.infinity,
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context).colorScheme.surface.withAlpha(150),
                                                        border: Border(
                                                          right: BorderSide(
                                                            color: Theme.of(context).dividerColor.withAlpha(20),
                                                            width: 1,
                                                          ),
                                                        ),
                                                      ),
                                                      child: Column(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        mainAxisSize: MainAxisSize.max,
                                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                                        children: <Widget>[
                                                          const SizedBox(height: 15),
                                                          Flexible(
                                                            fit: FlexFit.tight,
                                                            child: MouseScrollWidget(
                                                              scrollDirection: Axis.vertical,
                                                              child: Column(
                                                                mainAxisAlignment: MainAxisAlignment.start,
                                                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                                                children: <Widget>[
                                                                  IgnorePointer(
                                                                    ignoring: Boxes.remap.isEmpty,
                                                                    child: ListView.builder(
                                                                      scrollDirection: Axis.vertical,
                                                                      itemCount: pages.length,
                                                                      shrinkWrap: true,
                                                                      padding:
                                                                          const EdgeInsets.symmetric(horizontal: 10),
                                                                      physics: const ClampingScrollPhysics(),
                                                                      itemBuilder: (BuildContext context, int index) {
                                                                        final PageClass pageItem = pages[index];
                                                                        if (pageItem.title == "FirstRun") {
                                                                          return const SizedBox();
                                                                        }
                                                                        final bool isActive = currentPage == index;
                                                                        return Container(
                                                                          margin:
                                                                              const EdgeInsets.symmetric(vertical: 2),
                                                                          child: InkWell(
                                                                            onTap: () {
                                                                              setState(() => currentPage = index);
                                                                            },
                                                                            borderRadius: BorderRadius.circular(8),
                                                                            child: AnimatedContainer(
                                                                              duration:
                                                                                  const Duration(milliseconds: 200),
                                                                              padding: const EdgeInsets.symmetric(
                                                                                  vertical: 10, horizontal: 12),
                                                                              decoration: BoxDecoration(
                                                                                color: isActive
                                                                                    ? Theme.of(context)
                                                                                        .colorScheme
                                                                                        .primary
                                                                                        .withAlpha(30)
                                                                                    : Colors.transparent,
                                                                                borderRadius: BorderRadius.circular(8),
                                                                              ),
                                                                              child: Row(
                                                                                mainAxisAlignment:
                                                                                    MainAxisAlignment.start,
                                                                                crossAxisAlignment:
                                                                                    CrossAxisAlignment.center,
                                                                                mainAxisSize: MainAxisSize.min,
                                                                                children: <Widget>[
                                                                                  Icon(
                                                                                    pageItem.icon,
                                                                                    size: 20,
                                                                                    color: isActive
                                                                                        ? Theme.of(context)
                                                                                            .colorScheme
                                                                                            .primary
                                                                                        : Theme.of(context)
                                                                                            .colorScheme
                                                                                            .onSurface
                                                                                            .withAlpha(180),
                                                                                  ),
                                                                                  const SizedBox(width: 12),
                                                                                  Text(
                                                                                    pageItem.title!,
                                                                                    style: TextStyle(
                                                                                      fontSize: 14,
                                                                                      fontWeight: isActive
                                                                                          ? FontWeight.w600
                                                                                          : FontWeight.w400,
                                                                                      color: isActive
                                                                                          ? Theme.of(context)
                                                                                              .colorScheme
                                                                                              .primary
                                                                                          : Theme.of(context)
                                                                                              .colorScheme
                                                                                              .onSurface
                                                                                              .withAlpha(180),
                                                                                    ),
                                                                                  ),
                                                                                  if (isActive) ...<Widget>[
                                                                                    const Spacer(),
                                                                                    Container(
                                                                                      width: 4,
                                                                                      height: 16,
                                                                                      decoration: BoxDecoration(
                                                                                        color: Theme.of(context)
                                                                                            .colorScheme
                                                                                            .primary,
                                                                                        borderRadius:
                                                                                            BorderRadius.circular(2),
                                                                                      ),
                                                                                    ),
                                                                                  ],
                                                                                ],
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          // Bottom Actions
                                                          Padding(
                                                            padding: const EdgeInsets.all(10),
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                                              children: <Widget>[
                                                                if (sponsor.enabled) ...<Widget>[
                                                                  InkWell(
                                                                    onTap: () => WinUtils.open(sponsor.url),
                                                                    borderRadius: BorderRadius.circular(8),
                                                                    child: Container(
                                                                      padding: const EdgeInsets.all(8),
                                                                      child: Column(
                                                                        children: <Widget>[
                                                                          Text(
                                                                            "Sponsored by",
                                                                            style: TextStyle(
                                                                              fontSize: Design.baseFontSize,
                                                                              fontStyle: FontStyle.italic,
                                                                              color: Theme.of(context)
                                                                                  .colorScheme
                                                                                  .onSurface
                                                                                  .withAlpha(100),
                                                                            ),
                                                                          ),
                                                                          const SizedBox(height: 4),
                                                                          if (sponsorImageLight != null)
                                                                            Image.file(
                                                                              userSettings.themeType == ThemeType.light
                                                                                  ? sponsorImageLight!
                                                                                  : sponsorImageDark!,
                                                                              height: 40,
                                                                              fit: BoxFit.contain,
                                                                            ),
                                                                        ],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 8),
                                                                ],
                                                                InkWell(
                                                                  onTap: () {
                                                                    showDialog(
                                                                      context: context,
                                                                      builder: (BuildContext context) => AlertDialog(
                                                                        title: const Text("Exit Tabame?"),
                                                                        content: const Text(
                                                                            "This will close the whole application. Continue?"),
                                                                        actions: <Widget>[
                                                                          TextButton(
                                                                            onPressed: () =>
                                                                                Navigator.of(context).pop(),
                                                                            child: const Text("Cancel"),
                                                                          ),
                                                                          ElevatedButton(
                                                                            onPressed: () {
                                                                              WinUtils.closeAllTabameExProcesses();
                                                                              exit(0);
                                                                            },
                                                                            style: ElevatedButton.styleFrom(
                                                                              backgroundColor: Theme.of(context)
                                                                                  .colorScheme
                                                                                  .errorContainer,
                                                                              foregroundColor: Theme.of(context)
                                                                                  .colorScheme
                                                                                  .onErrorContainer,
                                                                            ),
                                                                            child: const Text("Full Exit"),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    );
                                                                  },
                                                                  borderRadius: BorderRadius.circular(8),
                                                                  child: Container(
                                                                    padding: const EdgeInsets.symmetric(
                                                                        vertical: 10, horizontal: 12),
                                                                    decoration: BoxDecoration(
                                                                      border: Border.all(
                                                                          color: Theme.of(context)
                                                                              .colorScheme
                                                                              .error
                                                                              .withAlpha(50)),
                                                                      borderRadius: BorderRadius.circular(8),
                                                                    ),
                                                                    child: Row(
                                                                      children: <Widget>[
                                                                        Icon(Icons.power_settings_new_rounded,
                                                                            size: 18,
                                                                            color: Theme.of(context).colorScheme.error),
                                                                        const SizedBox(width: 12),
                                                                        Text(
                                                                          "Full Exit",
                                                                          style: TextStyle(
                                                                            fontSize: 14,
                                                                            color: Theme.of(context).colorScheme.error,
                                                                            fontWeight: FontWeight.w500,
                                                                          ),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 4),
                                                                const _BMACFooter(),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                //#e
                                                //1 Pages
                                                //#h white
                                                Expanded(
                                                  child: AnimatedSwitcher(
                                                    duration: const Duration(milliseconds: 200),
                                                    transitionBuilder: (Widget child, Animation<double> animation) {
                                                      return FadeTransition(opacity: animation, child: child);
                                                    },
                                                    child: SizedBox.expand(
                                                      key: ValueKey<int>(currentPage),
                                                      child: Builder(builder: (BuildContext context) {
                                                        final bool scrollDisabled =
                                                            disableScroll.contains(pages[currentPage].title);
                                                        final Widget pageWidget = Material(
                                                            type: MaterialType.transparency,
                                                            child: pages[currentPage].widget);
                                                        if (scrollDisabled) {
                                                          return pageWidget;
                                                        }
                                                        if (pages[currentPage].title == "Trktivity") {
                                                          return MouseScrollWidget(
                                                            child: pageWidget,
                                                            scrollDirection: Axis.vertical,
                                                            // physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                                            physics: const NeverScrollableScrollPhysics(),
                                                          );
                                                        }
                                                        return WindowsScrollView(
                                                          scrollDirection: Axis.vertical,
                                                          friction: 0.76,
                                                          scrollSpeed: 12,
                                                          // physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                                          child: pageWidget,
                                                        );
                                                      }),
                                                    ),
                                                  ),
                                                ),
                                                //#e
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
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

class _BMACFooter extends StatefulWidget {
  const _BMACFooter();

  @override
  State<_BMACFooter> createState() => _BMACFooterState();
}

class _BMACFooterState extends State<_BMACFooter> with SingleTickerProviderStateMixin {
  bool isHovered = false;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHover(bool hover) {
    setState(() {
      isHovered = hover;
    });
    if (hover) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _onHover(true),
      onExit: (_) => _onHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => WinUtils.open("https://www.buymeacoffee.com/far.se"),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) {
                  return Transform.translate(
                    offset: isHovered ? Offset(math.sin(_controller.value * math.pi * 5) * 1.2, 0) : Offset.zero,
                    child: Transform.scale(
                      scale: isHovered ? 1.4 : 1.0,
                      child: Icon(
                        Icons.coffee_rounded,
                        size: 14,
                        color: isHovered
                            ? userSettings.themeColors.accent
                            : Theme.of(context).colorScheme.onSurface.withAlpha(80),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 6),
              Text(
                "Made by Far Se",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.isCloseButton = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isCloseButton;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor:
          isCloseButton ? Colors.red.withValues(alpha: 0.8) : Theme.of(context).dividerColor.withValues(alpha: 0.1),
      child: SizedBox(
        width: 46,
        child: Center(
          child: Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
