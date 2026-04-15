// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../widgets/interface/audio_interface.dart';
import '../widgets/interface/changelog.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/interface/first_run.dart';
import '../widgets/interface/home.dart';
import '../widgets/interface/hotkeys_interface.dart';
import '../widgets/interface/interface_settings.dart';
import '../widgets/interface/bookmarks.dart';
import '../widgets/interface/quickmenu_settings.dart';
import '../widgets/interface/tasks.dart';
import '../widgets/interface/theme_setup.dart';
import '../widgets/interface/trktivity.dart';
import '../widgets/interface/wizardly.dart';
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
  Monitor.fetchMonitor();
  Globals.currentPage = Pages.interface;
  Win32.setCenter(useMouse: true, hwnd: Win32.hWnd);
  final Square monitor = Monitor.monitorSizes[Win32.getWindowMonitor(Win32.hWnd)]!;
  await WindowManager.instance.setMinimumSize(const Size(700, 600));
  // await WindowManager.instance.setMaximumSize(Size(monitor.width.toDouble(), monitor.height.toDouble()));
  await WindowManager.instance.setSkipTaskbar(false);
  await WindowManager.instance.setResizable(true);
  await WindowManager.instance.setAlwaysOnTop(false);
  await WindowManager.instance.setAspectRatio(1);
  if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Interface");
  await WindowManager.instance.setSize(Size(monitor.width / 2.2, monitor.height / 1.4));
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
    PageClass(title: 'Audio', icon: Icons.speaker, widget: const AudioInterface()),
    PageClass(title: 'Colors', icon: Icons.theater_comedy, widget: const ThemeSetup()),
    PageClass(title: 'QuickMenu', icon: Icons.apps, widget: const QuickmenuSettings()),
    // PageClass(title: 'QuickRun', icon: Icons.drag_handle, widget: const RunSettings()),
    PageClass(title: 'Hotkeys', icon: Icons.keyboard, widget: const HotkeysInterface()),
    PageClass(title: 'Bookmarks', icon: Icons.folder_copy, widget: const BookmarksPage()),
    PageClass(title: 'Reminders', icon: Icons.schedule_rounded, widget: const TasksPage()),
    PageClass(title: 'Trktivity', icon: Icons.scatter_plot, widget: const TrktivityPage()),
    PageClass(title: 'Wizardly', icon: Icons.auto_fix_high, widget: const Wizardly()),
    PageClass(title: 'Fancyshot', icon: Icons.center_focus_strong_rounded, widget: const Fancyshot()),
    PageClass(title: 'Changelog', icon: Icons.newspaper, widget: const Changelog()),
    PageClass(title: 'FirstRun', icon: Icons.newspaper, widget: const FirstRun()),
  ];
  final List<String> disableScroll = <String>["Colors", "Wizardly", "Reminders", "Fancyshot", "FirstRun"];
  final Future<int> interfaceWindow = interfaceWindowSetup();
  int hoveredPage = -1;

  bool bmaCoffeHovered = false;
  File? sponsorImageLight;
  File? sponsorImageDark;
  int sizeIncrement = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) async {
      await Future<void>.delayed(const Duration(milliseconds: 100), () {
        windowManager.getSize().then((Size value) {
          windowManager.setSize(Size(value.width + sizeIncrement, value.height + sizeIncrement));
          sizeIncrement = sizeIncrement == 1 ? -1 : 1;
        });
      });
    });
    if (globalSettings.args.contains("-wizardly")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Wizardly");
    } else if (globalSettings.args.contains("-fancyshot")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Fancyshot");
    } else if (globalSettings.args.contains("-changelog")) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "Changelog");
    } else if (Boxes.remap.isEmpty) {
      currentPage = pages.indexWhere((PageClass element) => element.title == "FirstRun");
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

  @override
  Widget build(BuildContext context) {
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
            builder: (BuildContext context) => AlertDialog(
              content: Container(
                height: 160,
                width: 320,
                child: const Markdown(
                  data: """
# Thanks for using Tabame!
## If you find this app useful please consider a donation, it will be appreciated ☺
""",
                  shrinkWrap: true,
                ),
              ),
              actionsAlignment: MainAxisAlignment.spaceEvenly,
              actions: <Widget>[
                OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Boxes.pref.setBool("bmacPopup", true);
                    },
                    child: const Text("Never show again")),
                ElevatedButton(
                    onPressed: () {
                      WinUtils.open("https://www.buymeacoffee.com/far.se");
                      Boxes.pref.setBool("bmacPopup", true);
                      Navigator.of(context).pop();
                    },
                    child: const Text("☕ Buy me a Coffee")),
              ],
            ),
          );
        },
      );
    }
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
                            color: Theme.of(context).colorScheme.surface,
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
                                        child: const Padding(
                                            padding: EdgeInsets.all(5), child: Icon(Icons.minimize, size: 15)),
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
                                            } else if (globalSettings.args.contains('-fancyshot')) {
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
                                            Globals.mainPageViewController.jumpToPage(Pages.quickmenu.index);
                                          }
                                        },
                                        child: const Padding(
                                            padding: EdgeInsets.all(5), child: Icon(Icons.close, size: 15)),
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
                                color: Theme.of(context).colorScheme.surface,
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Theme.of(context).colorScheme.surface,
                                    Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                                    Theme.of(context).colorScheme.surface
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
                                  // if (!globalSettings.args.contains("-wizardly")) //2 commented this
                                  //1 Sidebar
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
                                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                                      physics: const ClampingScrollPhysics(),
                                                      itemBuilder: (BuildContext context, int index) {
                                                        final PageClass pageItem = pages[index];
                                                        if (pageItem.title == "FirstRun") return const SizedBox();
                                                        final bool isActive = currentPage == index;
                                                        return Container(
                                                          margin: const EdgeInsets.symmetric(vertical: 2),
                                                          child: InkWell(
                                                            onTap: () {
                                                              setState(() => currentPage = index);
                                                            },
                                                            borderRadius: BorderRadius.circular(8),
                                                            child: AnimatedContainer(
                                                              duration: const Duration(milliseconds: 200),
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
                                                                mainAxisAlignment: MainAxisAlignment.start,
                                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: <Widget>[
                                                                  Icon(
                                                                    pageItem.icon,
                                                                    size: 20,
                                                                    color: isActive
                                                                        ? Theme.of(context).colorScheme.primary
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
                                                                      fontWeight:
                                                                          isActive ? FontWeight.w600 : FontWeight.w400,
                                                                      color: isActive
                                                                          ? Theme.of(context).colorScheme.primary
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
                                                                        color: Theme.of(context).colorScheme.primary,
                                                                        borderRadius: BorderRadius.circular(2),
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
                                                              fontSize: 10,
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
                                                              globalSettings.themeType == ThemeType.light
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
                                                            onPressed: () => Navigator.of(context).pop(),
                                                            child: const Text("Cancel"),
                                                          ),
                                                          ElevatedButton(
                                                            onPressed: () {
                                                              WinUtils.closeAllTabameExProcesses();
                                                              exit(0);
                                                            },
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor:
                                                                  Theme.of(context).colorScheme.errorContainer,
                                                              foregroundColor:
                                                                  Theme.of(context).colorScheme.onErrorContainer,
                                                            ),
                                                            child: const Text("Full Exit"),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  },
                                                  borderRadius: BorderRadius.circular(8),
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                                                    decoration: BoxDecoration(
                                                      border: Border.all(
                                                          color: Theme.of(context).colorScheme.error.withAlpha(50)),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Row(
                                                      children: <Widget>[
                                                        Icon(Icons.power_settings_new_rounded,
                                                            size: 18, color: Theme.of(context).colorScheme.error),
                                                        const SizedBox(width: 12),
                                                        Text(
                                                          "Exit",
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
                                                Padding(
                                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                                  child: Text(
                                                    "Coded by Far Se",
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
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
                                          final bool scrollDisabled = disableScroll.contains(pages[currentPage].title);
                                          final Widget pageWidget = Material(
                                              type: MaterialType.transparency, child: pages[currentPage].widget);
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
