import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/saved_maps.dart';
import '../models/keys.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../widgets/itzy/quickmenu/widget_audio.dart';
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
  return 1;
}

class QuickMenuState extends State<QuickMenu> with TabameListener, QuickMenuTriggers, WindowListener {
  double lastHeight = 0;
  Timer? changeHeightTimer;
  final Future<int> quickMenuWindow = quickMenuWindowSetup();
  final FocusNode focusNode = FocusNode();
  int trktivityIdleState = 0;
  QuickRun? theQuickRun;
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
    //!RELEASE MODE
    if (1 + 1 == 3 && !kDebugMode) {
      changeHeightTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) async {
        if (Globals.isWindowActive || globalSettings.quickRunState != 0) return;
        final double newHeight = Globals.heights.allSummed + 80;
        if (lastHeight != newHeight) {
          if (!mounted) return;
          await windowManager.setSize(Size(300, newHeight));
          lastHeight = newHeight;
        }
      });
    }
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
    // WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => FocusScope.of(context).requestFocus(focusNode));
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
  Future<void> onQuickMenuToggled(bool visible, int type) async {
    globalSettings.quickRunState = 0;
    globalSettings.quickRunText = "";
    if (visible) {
      FocusScope.of(context).requestFocus(focusNode);
      if (type == 0) {
        setState(() {});
      } else if (type == 1) {
        // if (lastHeight < 330) {
        //   Future<void>.delayed(const Duration(seconds: 1), () => windowManager.setSize(const Size(300, 330)));
        // }
        globalSettings.quickRunState = 1;
        globalSettings.quickRunText = "";
      } else if (type == 2) {
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
      FocusScope.of(context).unfocus();
      globalSettings.quickRunState = 0;
      globalSettings.quickRunText = "";
      setState(() {});
    }
    return;
  }

  @override
  Future<void> onQuickMenuShown(int type) async {
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
  Point<int> mouseSteps = const Point<int>(0, 0);
  int startMouseDir = 0;
  Map<String, int> hotkeyDoublePress = <String, int>{};
  Map<String, int> hotkeyMovement = <String, int>{};
  int currentVK = -1;
  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    if (!kReleaseMode && !Globals.debugHotkeys) return;
    final List<Hotkeys> hk = <Hotkeys>[...Boxes.remap.where((Hotkeys element) => element.hotkey == hotkeyInfo.hotkey).toList()];
    if (hk.isEmpty) return;
    final Hotkeys hotkey = hk[0];

    //* Keyboard listen to release
    if (hotkeyInfo.action == "pressedKbd") {
      //
      final int key = keyMap.containsKey("VK_${hotkey.key.toUpperCase()}") ? keyMap["VK_${hotkey.key.toUpperCase()}"]! : -1;
      if (key == -1) return;
      currentVK = key;

      if (hotkey.hasMouseMovementTriggers) {
        mouseSteps = hotkeyInfo.mouse.start;
      }
    }
    if (hotkeyInfo.action == "releaseKbd") {
      // NativeHotkey.free();
      if (hotkeyInfo.vk == currentVK) {
        currentVK = -1;
        NativeHooks.freeHotkeys();
        hotkeyInfo.action = "released";
        for (final TabameListener listener in NativeHooks.listeners) {
          if (!NativeHooks.listenersObv.contains(listener)) return;
          listener.onHotKeyEvent(hotkeyInfo);
        }
        return;
      }
    }

    ///
    if (hotkeyInfo.action == "pressed") {
      if (hotkey.hasMouseMovementTriggers) {
        mouseSteps = hotkeyInfo.mouse.start;
      }
    }
    if (hotkeyInfo.action == "moved") {
      if (hotkey.hasMouseMovementTriggers && startMouseDir == 0) {
        Point<int> diffAux = hotkeyInfo.mouse.end - mouseSteps;
        Point<int> diff = Point<int>(diffAux.x.abs(), diffAux.y.abs());
        if (diff.x + diff.y > 40) startMouseDir = diff.x > diff.y ? 1 : 2;
      }

      if (startMouseDir != 0) {
        final List<KeyMap> list = hotkey.getHotkeysWithMovementTriggers;
        if (list.isNotEmpty) {
          for (KeyMap key in list) {
            if (!key.isMouseInRegion) continue;
            Point<int> diffAux = hotkeyInfo.mouse.end - mouseSteps;
            if ((startMouseDir == 1 && key.triggerInfo[0] == 0 && diffAux.x < 0 && diffAux.x.abs() > key.triggerInfo[1]) ||
                ((startMouseDir == 1 && key.triggerInfo[0] == 1 && diffAux.x > 0 && diffAux.x.abs() > key.triggerInfo[1])) ||
                ((startMouseDir == 2 && key.triggerInfo[0] == 2 && diffAux.y < 0 && diffAux.y.abs() > key.triggerInfo[1])) ||
                ((startMouseDir == 2 && key.triggerInfo[0] == 3 && diffAux.y > 0 && diffAux.y.abs() > key.triggerInfo[1]))) {
              mouseSteps = hotkeyInfo.mouse.end;
              hotkeyMovement[hotkeyInfo.hotkey] = 1;
              key.applyActions();
            }
          }
        }
      }
    }

    if (hotkeyInfo.action == "released") {
      if (hotkeyMovement.containsKey(hotkeyInfo.hotkey)) {
        hotkeyMovement.remove(hotkeyInfo.hotkey);
        return;
      }
      startMouseDir = 0;
      final List<KeyMap> mouseDir = hotkey.getHotkeysWithMovement;
      mouseDir.sort((KeyMap a, KeyMap b) => a.boundToRegion
          ? -1
          : b.boundToRegion
              ? -1
              : 1);
      // ? Direction
      if (mouseDir.isNotEmpty) {
        final Point<int> diff = hotkeyInfo.mouse.diff;
        final int diffX = diff.x.abs();
        final int diffY = diff.y.abs();
        for (KeyMap key in mouseDir) {
          if (!key.isMouseInRegion) continue;
          // left right up down
          if ((key.triggerInfo[0] == 0 && diff.x < 0 && diffX.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2])) ||
              ((key.triggerInfo[0] == 1 && diff.x > 0 && diffX.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2]))) ||
              ((key.triggerInfo[0] == 2 && diff.y < 0 && diffY.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2]))) ||
              ((key.triggerInfo[0] == 3 && diff.y > 0 && diffY.isBetweenEqual(key.triggerInfo[1], key.triggerInfo[2])))) {
            key.applyActions();
            return;
          }
        }
      }
      // ? Duration
      List<KeyMap> keys = hotkey.getDurationKeys;
      mouseDir.sort((KeyMap a, KeyMap b) => a.boundToRegion
          ? -1
          : b.boundToRegion
              ? -1
              : 1);
      if (keys.isNotEmpty) {
        final int diff = hotkeyInfo.time.duration;
        for (KeyMap key in keys) {
          if (!key.isMouseInRegion) continue;
          if (diff.isBetweenEqual(key.triggerInfo[0], key.triggerInfo[1])) {
            key.applyActions();
            return;
          }
        }
      }
      // ?Region
      if (hotkeyDoublePress.containsKey(hotkey.hotkey) && hotkeyInfo.name.isNotEmpty) {
        keys = hotkey.keymaps.where((KeyMap element) => element.boundToRegion && element.triggerType == TriggerType.doublePress).toList();
        for (KeyMap key in keys) {
          if (key.isMouseInRegion) {
            if (hotkeyInfo.time.end - hotkeyDoublePress[hotkey.hotkey]! < 300) {
              key.applyActions();
              hotkeyDoublePress.remove(hotkey.hotkey);
              return;
            } else {
              hotkeyDoublePress.remove(hotkey.hotkey);
            }
          }
        }
      }
      keys = hotkey.keymaps.where((KeyMap element) => element.boundToRegion && element.triggerType == TriggerType.press).toList();
      if (hotkeyInfo.name.isNotEmpty) {
        for (KeyMap key in keys) {
          if (key.isMouseInRegion) {
            if (hotkey.hasDoublePress) {
              hotkeyDoublePress[hotkey.hotkey] = hotkeyInfo.time.end;
            }
            key.applyActions();
            return;
          }
        }
      }

      // ?Double press
      if (hotkeyDoublePress.containsKey(hotkey.hotkey)) {
        keys = hotkey.getDoublePress;
        for (KeyMap key in keys) {
          if (!key.isMouseInRegion) continue;
          if (hotkeyInfo.time.end - hotkeyDoublePress[hotkey.hotkey]! < 300) {
            key.applyActions();
            hotkeyDoublePress.remove(hotkey.hotkey);
            return;
          }
        }
        hotkeyDoublePress.remove(hotkey.hotkey);
      }
      // ?Normal
      keys = hotkey.getPress;
      for (KeyMap key in keys) {
        if (!key.isMouseInRegion) continue;
        if (hotkeyInfo.name.isNotEmpty && key.name != hotkeyInfo.name) continue;
        if (hotkey.hasDoublePress) {
          hotkeyDoublePress[hotkey.hotkey] = hotkeyInfo.time.end;
        }
        key.applyActions();
      }
    }
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
          globalSettings.quickRunState = 0;
          globalSettings.quickRunText = "";
          setState(() {});
        } else if (globalSettings.quickRunState != 2 && keyEvent.logicalKey.keyId.isBetween(0, 255)) {
          if (keyEvent.isAltPressed || keyEvent.isControlPressed || keyEvent.isMetaPressed || keyEvent.isShiftPressed) return;
          globalSettings.quickRunState = 1;
          globalSettings.quickRunText += String.fromCharCode(keyEvent.logicalKey.keyId);
          theQuickRun = QuickRun(key: UniqueKey());
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
              // if (!await WindowManager.instance.isFocused()) {}
              // await WindowManager.instance.focus();
              Globals.isWindowActive = true;
              // Win32.activateWindow(Win32.hWnd, forced: true);
              await WindowManager.instance.focus();
              // setState(() {});
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
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    //3 Items
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
