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
    await WindowManager.instance.setSize(const Size(300, 350));
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

class QuickMenuState extends State<QuickMenu> with TabameListener, QuickMenuTriggers {
  double lastHeight = 0;
  Timer? changeHeightTimer;
  final Future<int> quickMenuWindow = quickMenuWindowSetup();
  final FocusNode focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    NativeHotkey.unHook();
    NativeHotkey.addListener(this);
    QuickMenuFunctions.addListener(this);
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
    // WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => FocusScope.of(context).requestFocus(focusNode));
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    if (!kDebugMode) changeHeightTimer?.cancel();
    NativeHotkey.removeListener(this);
    QuickMenuFunctions.removeListener(this);
    focusNode.dispose();
    super.dispose();
  }

  @override
  void onQuickMenuToggled(bool visible, int type) async {
    globalSettings.quickRunState = 0;
    globalSettings.quickRunText = "";
    if (visible) {
      FocusScope.of(context).requestFocus(focusNode);
      if (type == 0) {
        setState(() {});
      } else if (type == 1) {
        if (lastHeight < 330) {
          Future<void>.delayed(const Duration(seconds: 1), () => windowManager.setSize(const Size(300, 330)));
        }
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
      Future<void>.delayed(const Duration(milliseconds: 300), () async {
        // await WindowManager.instance.focus();
        Globals.isWindowActive = true;
        Win32.activateWindow(Win32.hWnd, forced: true);

        if (mounted) setState(() {});
      });
    } else {
      FocusScope.of(context).unfocus();
      globalSettings.quickRunState = 0;
      globalSettings.quickRunText = "";
      setState(() {});
      // Future<void>.delayed(const Duration(milliseconds: 300), () async {
      //   if (QuickMenuFunctions.isQuickMenuVisible) return;
      //   if (!mounted) return;
      //   final double newHeight = Globals.heights.allSummed + 80;
      //   if (lastHeight != newHeight) {
      //     if (!mounted || QuickMenuFunctions.isQuickMenuVisible) return;
      //     await windowManager.setSize(Size(300, newHeight));
      //     lastHeight = newHeight;
      //   }
      // });
    }
  }

  ///
  ///! Hotkeys
  ///
  Point<int> mouseSteps = const Point<int>(0, 0);
  int startMouseDir = 0;
  Map<String, int> hotkeyDoublePress = <String, int>{};
  Map<String, int> hotkeyMovement = <String, int>{};
  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    // print(hotkeyInfo);
    final List<Hotkeys> hk = <Hotkeys>[...Boxes.remap.where((Hotkeys element) => element.hotkey == hotkeyInfo.hotkey).toList()];
    if (hk.isEmpty) return;
    final Hotkeys hotkey = hk[0];
    // if (hotkey.noopScreenBusy) {
    //   final ScreenState state = WinUtils.checkUserScreenState();
    //   if (state == ScreenState.runningD3dFullScreen) return;
    // }
    if (hotkeyInfo.action == "pressed") {
      // print("Hotkey ${hotkeyInfo.hotkey} pressed!");
      if (hotkey.keymaps.any((KeyMap element) => element.windowUnderMouse)) {
        Win32.activeWindowUnderCursor();
      }
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
      // print("Hotkey ${hotkeyInfo.hotkey} released!");
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
            // print("Hotkey ${hotkeyInfo.hotkey} Direction ${key.name}!");
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
            // print("Hotkey ${hotkeyInfo.hotkey} Duration ${key.name}!");
            key.applyActions();
            return;
          }
        }
      }
      // ?Region
      keys = hotkey.keymaps.where((KeyMap element) => element.boundToRegion && element.triggerType == TriggerType.press).toList();
      for (KeyMap key in keys) {
        if (key.isMouseInRegion) {
          // print("Hotkey ${hotkeyInfo.hotkey} Region ${key.name}!");
          key.applyActions();
          return;
        }
      }
      if (hotkeyDoublePress.containsKey(hotkey.hotkey)) {
        keys = hotkey.getDoublePress;
        for (KeyMap key in keys) {
          if (!key.isMouseInRegion) continue;
          if (hotkeyInfo.time.end - hotkeyDoublePress[hotkey.hotkey]! < 300) {
            // print("Hotkey ${hotkeyInfo.hotkey} DoublePress ${key.name}!");
            key.applyActions();
            hotkeyDoublePress.remove(hotkey.hotkey);
            return;
          }
        }
        hotkeyDoublePress.remove(hotkey.hotkey);
      }
      keys = hotkey.getPress;
      for (KeyMap key in keys) {
        if (!key.isMouseInRegion) continue;
        if (hotkey.hasDoublePress) hotkeyDoublePress[hotkey.hotkey] = hotkeyInfo.time.end;
        // print("Hotkey ${hotkeyInfo.hotkey} Press ${key.name}!");
        key.applyActions();
      }
    }
  }

  @override
  void onForegroundWindowChanged(int hWnd) {
    if (globalSettings.hideTabameOnUnfocus && QuickMenuFunctions.isQuickMenuVisible) {
      QuickMenuFunctions.toggleQuickMenu(visible: false);
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
          if (lastHeight < 330) {
            await windowManager.setSize(const Size(300, 330));
          }
          globalSettings.quickRunState = 1;
          globalSettings.quickRunText += String.fromCharCode(keyEvent.logicalKey.keyId);
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
              if (!await WindowManager.instance.isFocused()) {}
              await WindowManager.instance.focus();
              Globals.isWindowActive = true;
              Win32.activateWindow(Win32.hWnd);
              setState(() {});
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
                              ? const QuickRun()
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
