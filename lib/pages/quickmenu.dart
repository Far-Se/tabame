import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/util/hotkey_handler.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
// import '../widgets/itzy/quickmenu/button_quickactions.dart';
import 'file_search.dart';
import 'package:window_manager/window_manager.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/globals.dart';
import 'quickmenu_designs/designs.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({super.key});
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

Future<int> quickMenuWindowSetup() async {
  if (Globals.lastPage != Pages.quickmenu) {
    await WindowManager.instance.setMinimumSize(const Size(299, 540));
    await WindowManager.instance.setSize(const Size(299, 540));
    await WindowManager.instance.setMaximumSize(const Size(1200, 539));
    await WindowManager.instance.setSkipTaskbar(true);
    await WindowManager.instance.setResizable(true);
    await WindowManager.instance.setAlwaysOnTop(true);
    if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Debug");
    // await WindowManager.instance.setAspectRatio(1);
    await Win32.setMainWindowToMousePos();
  } else {
    await Win32.setMainWindowToMousePos();
  }
  Globals.currentPage = Pages.quickmenu;
  Debug.add("QuickMenu: setup");
  return 1;
}

class QuickMenuState extends State<QuickMenu> with TabameListener, WindowListener, QuickMenuTriggers {
  double lastHeight = 0;
  Timer? changeHeightTimer;
  final Future<int> quickMenuWindow = quickMenuWindowSetup();
  final FocusNode focusNode = FocusNode();
  int trktivityIdleState = 0;
  // QuickRun removed

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
    if (kDebugMode) {
      Timer(const Duration(milliseconds: 2000), () async {
        final Size size = await windowManager.getSize();
        if (size.width > 400) {
          List<double> size = Boxes.quickMenuSize;
          if (size.length != 2) size = <double>[299, 539];
          await WindowManager.instance.setMinimumSize(const Size(299, 540));
          await WindowManager.instance.setMaximumSize(const Size(1200, 539));
          await WindowManager.instance.setSize(Size(size[0], size[1]));
          await WindowManager.instance.setSkipTaskbar(true);
          await WindowManager.instance.setResizable(true);
          await WindowManager.instance.setAlwaysOnTop(true);
          if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Debug");
          // await WindowManager.instance.setAspectRatio(1);
          await Win32.setMainWindowToMousePos();
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

  int unixVisible = 0;
  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    globalSettings.textFileSearch = "";
    Globals.clearQuickMenuSearchInput();
    unixVisible = DateTime.now().millisecondsSinceEpoch;
    Globals.quickMenuPage = type;
    QuickMenuFunctions.resetKeyboardSelection();
    if (visible) {
      PaintingBinding.instance.imageCache.clear();
      FocusScope.of(context).requestFocus(focusNode);
      //? QuickMenu
      if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
        Globals.quickMenuPage = QuickMenuPage.quickActions;
        QuickMenuFunctions.triggerQuickAction("QuickActions");
        setState(() {});
      } else if (Globals.quickMenuPage == QuickMenuPage.fileSearch) {
        globalSettings.textFileSearch = "";
        setState(() {});
      } else if (Globals.quickMenuPage == QuickMenuPage.audioBox) {
        await QuickMenuFunctions.toggleQuickMenu(visible: true);
        await Future<void>.delayed(const Duration(milliseconds: 260));
        QuickMenuFunctions.triggerQuickAction("AudioControl");
      }
    } else {
      Globals.quickMenuPage = QuickMenuPage.quickMenu;
      FocusScope.of(context).unfocus();
      tryPop = true;
      globalSettings.textFileSearch = "";
      Globals.clearQuickMenuSearchInput();
      setState(() {});
    }
    return;
  }

  bool tryPop = false;
  @override
  Future<void> onQuickMenuShown(QuickMenuPage type) async {
    tryPop = false;
    Win32.activateWindow(Win32.hWnd);
    // Win32.focusWindow(Win32.hWnd);

    // SendMessage(Win32.hWnd, WM_ACTIVATE, 0, 0);
  }

  @override
  void onWindowFocus() {
    FocusScope.of(context).requestFocus(focusNode);
    setState(() {});
  }

  @override
  void onWindowResized() async {
    // save the new size to settings
    final Size size = await windowManager.getSize();
    Boxes.quickMenuSize = <double>[size.width, size.height];
    Boxes.updateSettings("quickMenuSize", jsonEncode(Boxes.quickMenuSize));
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "refreshQuickMenu") {
      if (mounted) setState(() {});
    }
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
    if (globalSettings.hideTabameOnUnfocus &&
        QuickMenuFunctions.isQuickMenuVisible &&
        Globals.quickMenuPage == QuickMenuPage.quickMenu &&
        !QuickMenuFunctions.keepOpen) {
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

  int lastCheck = 0;
  @override
  Widget build(BuildContext context) {
    if (!globalSettings.keepPopupsOpen && tryPop && Navigator.of(context).canPop()) Navigator.of(context).pop();
    tryPop = false;
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

  Widget mainWidget(BuildContext context) {
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent keyEvent) {
        final String? searchKey = _searchCharacterFromKeyEvent(keyEvent);
        if (Globals.quickMenuPage == QuickMenuPage.fileSearch) {
          if (searchKey != null) {
            Globals.queueQuickMenuSearchInput(searchKey);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        PhysicalKeyboardKey currentKey = keyEvent.physicalKey;
        if (currentKey == PhysicalKeyboardKey.escape) {
          if (keyEvent is KeyUpEvent) {
            Globals.quickMenuPage = QuickMenuPage.quickMenu;
            if (Globals.quickMenuPage == QuickMenuPage.quickActions) {
              setState(() {});
            } else if (Globals.quickMenuPage == QuickMenuPage.fileSearch) {
              Globals.quickMenuPage = QuickMenuPage.quickMenu;
              globalSettings.textFileSearch = "";
              Globals.quickMenuPage = QuickMenuPage.quickMenu;
              setState(() {});
            } else {
              QuickMenuFunctions.toggleQuickMenu(visible: false);
            }
            FocusScope.of(context).requestFocus(focusNode);
          }
          return KeyEventResult.handled;
        } else if (Globals.quickMenuPage == QuickMenuPage.quickMenu && searchKey != null) {
          // if (DateTime.now().millisecondsSinceEpoch - unixVisible < 100) return KeyEventResult.ignored;
          Globals.quickMenuPage = QuickMenuPage.fileSearch;
          Globals.queueQuickMenuSearchInput(searchKey);
          setState(() {});
          return KeyEventResult.handled;
        } else if (keyEvent is KeyDownEvent && Globals.quickMenuPage == QuickMenuPage.quickMenu) {
          if (currentKey == PhysicalKeyboardKey.arrowUp) {
            QuickMenuFunctions.onVerticalArrow(true);
            setState(() {});
            return KeyEventResult.handled;
          } else if (currentKey == PhysicalKeyboardKey.arrowDown) {
            QuickMenuFunctions.onVerticalArrow(false);
            setState(() {});
            return KeyEventResult.handled;
          } else if (currentKey == PhysicalKeyboardKey.enter) {
            QuickMenuFunctions.onEnter();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
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
            onHover: (PointerHoverEvent event) {
              final int now = DateTime.timestamp().millisecondsSinceEpoch;
              if (lastCheck == 0) {
                lastCheck = now;
                return;
              }
              if (now - lastCheck > 400) {
                lastCheck = now;
                final int hWnd = GetForegroundWindow();
                if (hWnd != Win32.hWnd) {
                  WindowManager.instance.show();
                  WindowManager.instance.focus();
                }
              }
            },
            onExit: (PointerExitEvent event) {
              Globals.isWindowActive = false;
              lastCheck = 0;
            },
            child: Align(
              alignment: Alignment.topLeft,
              child: Stack(
                children: <Widget>[
                  if (globalSettings.customSpash != "")
                    Positioned(child: Image.file(File(globalSettings.customSpash), height: 30), left: 10),
                  Padding(
                    padding: const EdgeInsets.all(10) + const EdgeInsets.only(top: 20),
                    child: DragToResizeArea(
                      resizeEdgeSize: 5,
                      enableResizeEdges: <ResizeEdge>[ResizeEdge.left, ResizeEdge.right],
                      child: GestureDetector(
                        onTap: () {},
                        child: Container(
                          key: Globals.quickMenu,
                          color: Colors.transparent,
                          child: Globals.quickMenuPage == QuickMenuPage.fileSearch
                              ? const FileSearch()
                              : const LoadQuickMenuDesign(),
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

  String? _searchCharacterFromKeyEvent(KeyEvent keyEvent) {
    if (keyEvent is! KeyDownEvent) return null;
    if (HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return null;
    }
    final String? character = keyEvent.character;
    if (character == null || character.isEmpty) return null;
    if (!RegExp(r'^[\w\-. \?\>\/]+$', caseSensitive: false).hasMatch(character)) {
      return null;
    }
    return character;
  }
}
