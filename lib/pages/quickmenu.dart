import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/util/hotkey_handler.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../widgets/itzy/quickmenu/widget_audio.dart';
import 'quickactions.dart';
import 'quickrun.dart';
import 'package:window_manager/window_manager.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/globals.dart';
import '../widgets/quickmenu/bottom_bar.dart';
import '../widgets/quickmenu/list_pinned_tray.dart';
import '../widgets/quickmenu/task_bar.dart';
import '../widgets/quickmenu/top_bar.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({Key? key}) : super(key: key);
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

Future<int> quickMenuWindowSetup() async {
  Globals.currentPage = Pages.quickmenu;

  if (Globals.lastPage != Pages.quickmenu) {
    await WindowManager.instance.setMinimumSize(const Size(300, 150));
    await WindowManager.instance.setSize(const Size(300, 540));
    await WindowManager.instance.setSkipTaskbar(true);
    await WindowManager.instance.setResizable(false);
    await WindowManager.instance.setAlwaysOnTop(true);
    await WindowManager.instance.setAspectRatio(0);
    await Win32.setMainWindowToMousePos();
  } else {
    await Win32.setMainWindowToMousePos();
  }
  Debug.add("QuickMenu: setup");
  return 1;
}

enum QuickMenuTypes {
  quickMenu,
  quickRun,
  audioBox,
  quickActions,
}

class QuickMenuState extends State<QuickMenu> with TabameListener, QuickMenuTriggers, WindowListener {
  double lastHeight = 0;
  Timer? changeHeightTimer;
  final Future<int> quickMenuWindow = quickMenuWindowSetup();
  final FocusNode focusNode = FocusNode();
  int trktivityIdleState = 0;
  QuickRun theQuickRun = QuickRun(key: UniqueKey());
  @override
  void initState() {
    super.initState();
    NativeHooks.unHook();
    NativeHooks.addListener(this);
    QuickMenuFunctions.addListener(this);
    WindowManager.instance.addListener(this);
    WinHotkeys.update();
    if (globalSettings.trktivityEnabled) enableTrcktivity(globalSettings.trktivityEnabled);
    Globals.changingPages = false;
    if (globalSettings.trktivityEnabled) {
      Timer.periodic(const Duration(seconds: 15), (Timer timer) {
        if (trktivityIdleState == 0) {
          trktivityIdleState = 1;
        } else if (trktivityIdleState == 1) {
          trk.add(TrktivityType.idle, "");
          trktivityIdleState = 2;
        }
      });
    }
    Debug.add("QuickMenu: init");
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    if (!kDebugMode) changeHeightTimer?.cancel();
    NativeHooks.removeListener(this);
    QuickMenuFunctions.removeListener(this);
    focusNode.dispose();
    super.dispose();
  }

  @override
  void refreshQuickMenu() {
    if (mounted) setState(() {});
  }

  QuickMenuTypes typeShown = QuickMenuTypes.quickMenu;
  @override
  Future<void> onQuickMenuToggled(bool visible, int type) async {
    globalSettings.quickRunState = 0;
    globalSettings.quickRunText = "";
    typeShown = QuickMenuTypes.values.elementAt(type);
    if (visible) {
      FocusScope.of(context).requestFocus(focusNode);
      //? QuickMenu
      if (typeShown == QuickMenuTypes.quickMenu || typeShown == QuickMenuTypes.quickActions) {
        if (typeShown == QuickMenuTypes.quickMenu) {
          Globals.quickMenuPage = QuickMenuPage.quickMenu;
        } else {
          Globals.quickMenuPage = QuickMenuPage.quickActions;
        }
        print("wtf");
        setState(() {});
      } else if (typeShown == QuickMenuTypes.quickRun) {
        //? QuickRun
        globalSettings.quickRunState = 1;
        globalSettings.quickRunText = "";
        setState(() {});
      } else if (typeShown == QuickMenuTypes.audioBox) {
        //? AudioBox
        Globals.audioBoxVisible = true;
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 280),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse) {
                      if (event.buttons == kSecondaryMouseButton) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: AudioBox(),
                  ),
                ),
              ),
            );
          },
        ).whenComplete(() {
          Globals.audioBoxVisible = false;
        });
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      FocusScope.of(context).unfocus();
      tryPop = true;

      globalSettings.quickRunState = 0;
      globalSettings.quickRunText = "";
      setState(() {});
    }
    return;
  }

  bool tryPop = false;
  @override
  Future<void> onQuickMenuShown(int type) async {
    tryPop = false;
    Win32.activateWindow(Win32.hWnd);
    // Win32.focusWindow(Win32.hWnd);

    // SendMessage(Win32.hWnd, WM_ACTIVATE, 0, 0);
  }

  @override
  void onWindowFocus() {
    setState(() {});
  }

  @override
  void onWindowBlur() async {}

  double previousVolume = 0.0;
  @override
  void onForegroundWindowChanged(int hWnd) {
    if (globalSettings.hookedWins.containsKey(hWnd)) {
      for (int win in globalSettings.hookedWins[hWnd]!) {
        if (Win32.winExists(win)) {
          Win32.surfaceWindow(win);
        }
      }
    }
    if (!kReleaseMode && !Globals.debugHotkeys) return;
    bool setting = false;
    if (Boxes.defaultVolume.isNotEmpty) {
      final int wW = WindowWatcher.list.indexWhere((Window element) => element.hWnd == hWnd);
      for (DefaultVolume def in Boxes.defaultVolume) {
        if (def.type == "exe") {
          String stringCheck = "";
          switch (def.type) {
            case "exe":
              stringCheck = wW > -1 ? WindowWatcher.list.elementAt(wW).process.exe : Win32.getWindowExePath(hWnd);
              break;
            case "class":
              stringCheck = wW > -1 ? WindowWatcher.list.elementAt(wW).process.className : Win32.getClass(hWnd);
              break;
            case "title":
              stringCheck = wW > -1 ? WindowWatcher.list.elementAt(wW).title : Win32.getTitle(hWnd);
              break;
          }
          if (RegExp(def.match, caseSensitive: false).hasMatch(stringCheck)) {
            if (globalSettings.volumeSetBack) {
              Audio.getVolume(AudioDeviceType.output).then((double value) {
                previousVolume = value;
                Audio.setVolume(def.volume / 100, AudioDeviceType.output);
              });
            } else {
              Audio.setVolume(def.volume / 100, AudioDeviceType.output);
            }
            break;
          }
        }
      }
      if (setting == false && previousVolume != 0.0) {
        Audio.setVolume(previousVolume, AudioDeviceType.output);
        previousVolume = 0.0;
      }
    }
    if (globalSettings.hideTabameOnUnfocus && QuickMenuFunctions.isQuickMenuVisible && globalSettings.quickRunState == 0) {
      QuickMenuFunctions.toggleQuickMenu(visible: false);
      Future<void>.delayed(const Duration(milliseconds: 100), () => QuickMenuFunctions.toggleQuickMenu(visible: false));
    }
  }

  ///
  ///! Hotkeys
  ///
  final HotkeyHandler handler = HotkeyHandler();
  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    handler.handle(hotkeyInfo);
  }

  final Trktivity trk = Trktivity();
  @override
  void onTricktivityEvent(String action, String info) {
    if (trktivityIdleState == 2) {
      trk.add(lastTrkType, lasthWnd.toString());
    }
    trktivityIdleState = 0;
    if (action == "Keys") {
      trk.add(TrktivityType.keys, info);
    } else if (action == "Movement") {
      trk.add(TrktivityType.mouse, info);
    }
  }

  String lastTitle = "emptytitlehere";
  TrktivityType lastTrkType = TrktivityType.window;
  int lasthWnd = 0;
  @override
  void onWinEventReceived(int hWnd, WinEventType type) {
    if (type == WinEventType.nameChange) {
      final String title = Win32.getTitle(hWnd);
      if (title.replaceFirst(lastTitle, "").length < 3 || lastTitle.replaceFirst(title, "").length < 3) {
        lastTitle = title;
        return;
      }
      lastTitle = title;
      trk.add(TrktivityType.title, hWnd.toString());
      lasthWnd = hWnd;
      lastTrkType = TrktivityType.title;
    } else if (type == WinEventType.foreground) {
      trk.add(TrktivityType.window, hWnd.toString());
      lasthWnd = hWnd;
      lastTrkType = TrktivityType.window;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!globalSettings.keepPopupsOpen && tryPop && Navigator.of(context).canPop()) Navigator.of(context).pop();
    tryPop = false;
    if (typeShown == QuickMenuTypes.quickActions) {
      Globals.quickMenuPage = QuickMenuPage.quickActions;
    } else if (typeShown == QuickMenuTypes.quickRun) {
      Globals.quickMenuPage = QuickMenuPage.quickRun;
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
    }
    if (Globals.changingPages) {
      return const SizedBox(width: 10);
    }
    if (kReleaseMode) {
      return FutureBuilder<int>(
        future: quickMenuWindow,
        builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
          if (!snapshot.hasData) return const SizedBox(width: 10);
          return mainWidget(context);
        },
      );
    }
    return FutureBuilder<int>(
      future: quickMenuWindow,
      builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 10);
        return FutureBuilder<int>(
          future: Future<int>.delayed(const Duration(seconds: 1), () => 1),
          builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
            if (!snapshot.hasData) return const SizedBox(width: 10);
            return mainWidget(context);
          },
        );
      },
    );
  }

  RawKeyboardListener mainWidget(BuildContext context) {
    return RawKeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKey: (RawKeyEvent keyEvent) async {
        if (globalSettings.noopKeyListener) return;
        PhysicalKeyboardKey currentKey = keyEvent.physicalKey;
        if (currentKey == PhysicalKeyboardKey.escape) {
          if (keyEvent is RawKeyUpEvent) {
            Globals.quickMenuPage = QuickMenuPage.quickMenu;
            if (typeShown == QuickMenuTypes.quickActions) {
              typeShown = QuickMenuTypes.quickMenu;
              setState(() {});
            } else if (globalSettings.quickRunState != 0) {
              globalSettings.quickRunState = 0;
              globalSettings.quickRunText = "";
              setState(() {});
            } else {
              QuickMenuFunctions.toggleQuickMenu(visible: false);
            }
          }
        } else if (typeShown != QuickMenuTypes.quickActions && globalSettings.quickRunState != 2 && keyEvent.logicalKey.keyId.isBetween(0, 255)) {
          if (keyEvent.isAltPressed || keyEvent.isControlPressed || keyEvent.isMetaPressed || keyEvent.isShiftPressed) return;
          globalSettings.quickRunState = 1;
          globalSettings.quickRunText += String.fromCharCode(keyEvent.logicalKey.keyId);
          theQuickRun = QuickRun(key: UniqueKey());
          Globals.quickMenuPage = QuickMenuPage.quickRun;
          setState(() {});
        }
      },
      child: GestureDetector(
        onTap: () {
          if (globalSettings.hideTabameOnUnfocus && QuickMenuFunctions.isQuickMenuVisible) {
            QuickMenuFunctions.toggleQuickMenu(visible: false);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: MouseRegion(
            onEnter: (PointerEnterEvent event) async {
              Globals.isWindowActive = true;
              await WindowManager.instance.focus();
            },
            onExit: (PointerExitEvent event) => Globals.isWindowActive = false,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              physics: const NeverScrollableScrollPhysics(),
              child: Stack(
                children: <Widget>[
                  if (globalSettings.customSpash != "") Positioned(child: Image.file(File(globalSettings.customSpash), height: 30), left: 10),
                  Padding(
                    padding: const EdgeInsets.all(10) + const EdgeInsets.only(top: 20),
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        key: Globals.quickMenu,
                        color: globalSettings.themeTypeMode == ThemeType.dark ? Colors.white : Colors.black,
                        child: Container(
                          decoration: BoxDecoration(
                              color: Theme.of(context).backgroundColor,
                              gradient: LinearGradient(
                                colors: <Color>[
                                  Theme.of(context).backgroundColor,
                                  Theme.of(context).backgroundColor.withAlpha(globalSettings.themeColors.gradientAlpha),
                                  Theme.of(context).backgroundColor,
                                ],
                                stops: <double>[0, 0.4, 1],
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: <BoxShadow>[
                                const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                              ]),
                          child: globalSettings.quickRunState != 0
                              ? theQuickRun
                              : typeShown == QuickMenuTypes.quickActions
                                  ? QuickActionWidget(key: UniqueKey())
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        const TopBar(),
                                        const TaskBar(),
                                        const Divider(thickness: 1, height: 1),
                                        if (globalSettings.quickMenuPinnedWithTrayAtBottom) const PinnedAndTrayList(),
                                        const BottomBar(),
                                      ],
                                    ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
