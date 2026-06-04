import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// import 'package:rich_clipboard/rich_clipboard.dart';
// ignore: implementation_imports
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/classes/saved_maps.dart';
import '../models/clipboard_history.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/util/hotkey_handler.dart';
import '../models/win32/imports.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../models/win32/window.dart';
import '../models/window_watcher.dart';
import '../services/file_indexer.dart';
import '../services/wallpaper_service.dart';
import 'emoji_page.dart';
// import '../widgets/itzy/quickmenu/button_quickactions.dart';
import 'launcher.dart';
import 'quickclick.dart';
import 'quickmenu_designs/designs.dart';
import 'quicksnap_overlay.dart';
import 'screen_capture.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({super.key});
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

Future<int> quickMenuWindowSetup() async {
  if (Globals.lastPage != Pages.quickmenu) {
    await WindowManager.instance.setMinimumSize(Size(Globals.quickMenuSize.width, 200));
    await WindowManager.instance.setSize(Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
    // await WindowManager.instance.setMaximumSize(const Size(1200, Globals.quickMenuSize.height));
    await windowManager.setMaximumSize(const Size(32767, 32767));
    await WindowManager.instance.setSkipTaskbar(true);
    await WindowManager.instance.setResizable(true);
    await WindowManager.instance.setAlwaysOnTop(true);
    if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Debug");
    // await WindowManager.instance.setAspectRatio(1);
    await Win32.setMainWindowToMousePos();
  } else {
    await Win32.setMainWindowToMousePos();
  }
  if (kReleaseMode) {
    final int exStyle = GetWindowLong(Win32.hWnd, GWL_EXSTYLE);
    SetWindowLongPtr(
      Win32.hWnd,
      GWL_EXSTYLE,
      (exStyle | WS_EX_TOOLWINDOW) & ~WS_EX_APPWINDOW,
    );
  }
  Globals.currentPage = Pages.quickmenu;
  Debug.add("QuickMenu: setup");
  return 1;
}

class QuickMenuState extends State<QuickMenu>
    with ClipboardEventListener, TabameListener, WindowListener, QuickMenuTriggers {
  // --------------------------------------------------------------------------
  // Variables
  // --------------------------------------------------------------------------
  final Future<int> quickMenuWindow = quickMenuWindowSetup();
  final FocusNode focusNode = FocusNode();
  final HotkeyHandler handler = HotkeyHandler();
  final Trktivity trk = Trktivity.instance;

  Timer? _quickMenuFocusRetryTimer;
  Size? _savedQuickMenuSize;

  double previousVolume = 0.0;

  int unixVisible = 0;
  int lastCheck = 0;

  bool didNotResizedOnLastState = false;
  bool tryPop = false;
  bool isresizing = false;

  String lastTitle = "emptytitlehere";
  TrktivityType lastTrkType = TrktivityType.window;

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _initState();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _build(context);
  }

  // --------------------------------------------------------------------------
  // Triggers / Listeners
  // --------------------------------------------------------------------------

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) => _onQuickMenuToggled(visible, type);

  @override
  Future<void> onQuickMenuMaybePop() => Navigator.of(context).maybePop();
  @override
  Future<void> onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) =>
      _onQuickMenuSwitchedPage(newType, oldType, visible);

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) => _onQuickMenuVisible(type, center);

  @override
  void onQuickActionExecute(String actionName) => _onQuickActionExecute(actionName);

  @override
  void requestQuickMenuFocus() => _requestQuickMenuFocus(focusWindow: true);

  @override
  void onWindowFocus() => _onWindowFocus();

  @override
  void onWindowMoved() => _onWindowMoved();

  @override
  void onWindowResize() => _onWindowResize();

  @override
  void onWindowResized() => _onWindowResized();

  @override
  void refreshQuickMenu() => _refreshQuickMenu();

  @override
  void onWindowBlur() => _onWindowBlur();

  @override
  void onForegroundWindowChanged(int hWnd) => _onForegroundWindowChanged(hWnd);

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) => _onHotKeyEvent(hotkeyInfo);

  @override
  void onTricktivityEvent(String action, String info) => trk.onTrktivityEvent(action, info);

  @override
  void onWinEventReceived(int hWnd, WinEventType type) => trk.onWinEventReceived(hWnd, type);
  @override
  void onViewsEvent(ViewsAction action, int hWnd) => _onViewsEvent(action, hWnd);

  // --------------------------------------------------------------------------
  // Private Implementations
  // --------------------------------------------------------------------------
  void _initState() {
    NativeHooks.unHook();
    NativeHooks.addListener(this);
    ClipboardHooks.addListener(this);
    ClipboardHooks.start();
    QuickMenuFunctions.addListener(this);
    WindowManager.instance.addListener(this);
    QuickMenuFunctions.randomizeBackdrop();

    WinHotkeys.update();
    ClipboardHistoryStore.clearCache();
    if (userSettings.trktivityEnabled) enableTrcktivity(userSettings.trktivityEnabled);
    Globals.changingPages = false;
    if (userSettings.trktivityEnabled) trk.startTimer();
    WallpaperService.instance.init();
    FileIndexer.instance.init();
    WinUtils.deleteOldFiles("${WinUtils.getTabameAppDataFolder()}/cache/icon_cache", days: 4);
    if (kDebugMode) {
      Timer(const Duration(milliseconds: 2000), () async {
        final Size size = await windowManager.getSize();
        if (size.width > 400) {
          final double width = Boxes.quickMenuWidth;
          await WindowManager.instance.setMinimumSize(Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
          await windowManager.setMaximumSize(const Size(32767, 32767));
          await WindowManager.instance.setSize(Size(width, Globals.quickMenuSize.height));
          await WindowManager.instance.setSkipTaskbar(true);
          await WindowManager.instance.setResizable(true);
          await WindowManager.instance.setAlwaysOnTop(true);
          if (kDebugMode) await WindowManager.instance.setTitle("Tabame - Debug");
          await Win32.setMainWindowToMousePos();
        }
      });
      Win32.setWindowInvisible(false);
    }
    AllowSetForegroundWindow(GetCurrentProcessId());
    _initializeWindowSize();
    Debug.add("QuickMenu: init");
  }

  void _dispose() {
    trk.stopTimer();
    PaintingBinding.instance.imageCache.clear();
    NativeHooks.removeListener(this);
    ClipboardHooks.removeListener(this);
    QuickMenuFunctions.removeListener(this);
    _quickMenuFocusRetryTimer?.cancel();
    focusNode.dispose();
  }

  bool get _canFocusQuickMenu {
    if (!mounted) return false;
    if (!QuickMenuFunctions.isQuickMenuVisible) return false;
    if (Globals.quickMenuPage != QuickMenuPage.quickMenu) return false;
    if (Navigator.of(context).canPop()) return false;
    return true;
  }

  void _requestQuickMenuFocus({bool focusWindow = false}) {
    void requestFocusIfNeeded() {
      if (!_canFocusQuickMenu) return;
      if (focusWindow) unawaited(windowManager.focus());
      if (!focusNode.hasPrimaryFocus) {
        focusNode.requestFocus();
      }
    }

    requestFocusIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) => requestFocusIfNeeded());
    _quickMenuFocusRetryTimer?.cancel();
    _quickMenuFocusRetryTimer = Timer(const Duration(milliseconds: 120), requestFocusIfNeeded);
  }

  void _initializeWindowSize() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // WidgetsBinding.instance.reassembleApplication(); // <- This
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      if (!mounted) return;
      await windowManager.setAsFrameless();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Force layout recalculation on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  DateTime _lastClipboard = DateTime.now();
  @override
  void onClipboardUpdate() async {
    final DateTime now = DateTime.now();
    if (now.difference(_lastClipboard).inMilliseconds < 500) {
      return;
    }
    _lastClipboard = now;
    await ClipboardHistoryStore.recordCurrentClipboard();
  }

  Future<void> _onViewsEvent(ViewsAction action, int hWnd) async {
    if (action == ViewsAction.open) {
      if (!userSettings.quickSnapOverlay) return;
      if (Boxes.quickGrids.isEmpty && !userSettings.quickSnapGrid) return;
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      _savedQuickMenuSize = await windowManager.getSize();

      final int exstyle = GetWindowLong(Win32.hWnd, GWL_EXSTYLE);
      SetWindowLongPtr(Win32.hWnd, GWL_EXSTYLE, exstyle | WS_EX_LAYERED);
      SetLayeredWindowAttributes(Win32.hWnd, 0, 0, LWA_ALPHA);

      if (mounted) setState(() => Globals.quickMenuPage = QuickMenuPage.quickSnap);

      Monitor.fetchMonitors();
      final Square? monitor = Monitor.monitorSizes[Win32.getCursorMonitor()];
      SetWindowLongPtr(Win32.hWnd, GWL_EXSTYLE, exstyle | WS_EX_LAYERED | WS_EX_TOOLWINDOW);

      final ({int? x, int? y, int? width, int? height}) sizeData =
          Win32.setDPIAware(Win32.hWnd, monitor!.x, monitor.y, monitor.width, monitor.height);

      if (sizeData.x != null && sizeData.y != null && sizeData.width != null && sizeData.height != null) {
        SetWindowPos(Win32.hWnd, HWND_TOP, sizeData.x!, sizeData.y!, sizeData.width!, sizeData.height!,
            SWP_NOZORDER | SWP_NOACTIVATE);
      }

      Future<void>.delayed(const Duration(milliseconds: 50), () {
        Monitor.fetchMonitors();
        SetLayeredWindowAttributes(Win32.hWnd, 0, 255, LWA_ALPHA);
      });
    } else if (action == ViewsAction.moveEnd) {
      if (Globals.quickMenuPage == QuickMenuPage.quickSnap) {
        if (mounted) setState(() => Globals.quickMenuPage = QuickMenuPage.quickMenu);

        SetLayeredWindowAttributes(Win32.hWnd, 0, 0, LWA_ALPHA);

        Future<void>.delayed(const Duration(milliseconds: 32), () async {
          if (_savedQuickMenuSize != null) {
            await windowManager.setSize(_savedQuickMenuSize!);
            _savedQuickMenuSize = null;
          }
          final int exstyle = GetWindowLong(Win32.hWnd, GWL_EXSTYLE);
          SetWindowLongPtr(Win32.hWnd, GWL_EXSTYLE, exstyle & ~WS_EX_TRANSPARENT & ~WS_EX_LAYERED & ~WS_EX_TOOLWINDOW);
          SetLayeredWindowAttributes(Win32.hWnd, 0, 255, LWA_ALPHA);
        });
      }
    } else if (action == ViewsAction.moveStart) {
      if (Globals.snappedWindowOriginalSizes.containsKey(hWnd)) {
        final List<int>? originalSize = Globals.snappedWindowOriginalSizes[hWnd];
        if (originalSize != null) {
          WinUtils.restoreAndReattachDrag(hWnd, originalSize[0], originalSize[1]);
          Globals.snappedWindowOriginalSizes.remove(hWnd);
        }
      }
    }
  }

  DateTime lastTimeShown = DateTime.now();
  Future<void> _onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    userSettings.launcherSearchText = "";
    Globals.clearQuickMenuSearchInput();
    unixVisible = DateTime.now().millisecondsSinceEpoch;
    Globals.quickMenuPage = type;
    QuickMenuFunctions.resetKeyboardSelection();

    if (visible) {
      // PaintingBinding.instance.imageCache.clear();

      if (Navigator.of(context).canPop()) {
        if (userSettings.hideTabameOnUnfocus) {
          if (!userSettings.keepPopupsOpen) {
            Navigator.of(context).pop();
          } else {
            if (DateTime.now().difference(lastTimeShown).inSeconds > 30) {
              Navigator.of(context).pop();
            }
          }
        }
      }
      if (Globals.quickMenuPage == QuickMenuPage.launcher) {
        userSettings.launcherSearchText = "";
        await WindowManager.instance.setSize(Size(Boxes.launcherSizeWidth, Globals.launcherSize.height));
        await windowManager.center();
        await windowManager.focus();
        if (mounted) setState(() {});
      } else if (Globals.quickMenuPage == QuickMenuPage.quickMenu) {
        if (mounted) setState(() {});
        _requestQuickMenuFocus(focusWindow: true);
        final Offset position = Win32.getPosition();
        if (position.dx < -99) {
          didNotResizedOnLastState = true;
        } else {
          final ({int height, int width}) size = Win32.getSize();
          if (size.width != Boxes.quickMenuWidth) {
            print("Redo Size");
            await WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
          }
        }
      } else if (mounted) {
        setState(() {});
      }
    } else {
      // PaintingBinding.instance.imageCache.clear();
      // PaintingBinding.instance.imageCache.clearLiveImages();
      QuickMenuFunctions.randomizeBackdrop();
      lastTimeShown = DateTime.now();
      // FocusScope.of(context).unfocus();
      tryPop = true;
      userSettings.launcherSearchText = "";
      Globals.clearQuickMenuSearchInput();
      if (mounted) setState(() {});
    }
  }

  Future<void> _onQuickMenuSwitchedPage(QuickMenuPage newType, QuickMenuPage oldType, bool visible) async {
    // if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    Win32.setWindowInvisible(true);
    if (oldType == QuickMenuPage.quickClick) WinUtils.makeWindowClickThrough(false);
    // SetLayeredWindowAttributes(Win32.hWnd, 0, 0, LWA_ALPHA);
  }

  Future<void> _onQuickMenuVisible(QuickMenuPage type, bool center) async {
    // SetLayeredWindowAttributes(Win32.hWnd, 0, 255, LWA_ALPHA);
    Win32.setWindowInvisible(false);
    tryPop = false;
    if (type != QuickMenuPage.quickClick) {
      Win32.activateWindow(Win32.hWnd);
    }
    Globals.quickMenuPage = type;
    if (type == QuickMenuPage.quickMenu) {
      WinUtils.makeWindowClickThrough(false);
      final ({int height, int width}) size = Win32.getSize();
      if (size.width != Boxes.quickMenuWidth) {
        print("Redu Size");
        WindowManager.instance.setSize(Size(Boxes.quickMenuWidth, Globals.quickMenuSize.height));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        _requestQuickMenuFocus(focusWindow: true);
        // await Future<void>.delayed(const Duration(milliseconds: 300));
        // print("aici?");
        // WidgetsBinding.instance.reassembleApplication(); // <- this.
      });
      // setState(() {});
    }
  }

  void _onQuickActionExecute(String actionName) {
    if (actionName == "page:launcher") {
      Globals.quickMenuPage = QuickMenuPage.launcher;
      if (mounted) setState(() {});
    }
  }

  void _onWindowFocus() {
    if (kReleaseMode) QuickMenuFunctions.isQuickMenuVisible = true;
    // Do not steal focus from the Launcher's TextField when it is active.
    if (Globals.quickMenuPage == QuickMenuPage.launcher) {
      QuickMenuFunctions.requestQuickMenuFocus();
    } else {
      _requestQuickMenuFocus();
    }
    setState(() {});
  }

  void _onWindowMoved() {
    final Offset position = Win32.getPosition();
    if (position.dx < -99) {
      QuickMenuFunctions.isQuickMenuVisible = false;
    } else {
      QuickMenuFunctions.isQuickMenuVisible = true;
    }
  }

  void _onWindowResize() {
    isresizing = true;
  }

  void _onWindowResized() async {
    if (isresizing == false) return;
    isresizing = false;
    final Size size = await windowManager.getSize();
    if (Globals.quickMenuPage == QuickMenuPage.launcher) {
      Boxes.launcherSizeWidth = size.width;
      Boxes.updateSettings("launcherSizeWidth", size.width);
    } else {
      Boxes.quickMenuWidth = size.width;
      Boxes.updateSettings("quickMenuWidth", size.width);
    }
  }

  void _refreshQuickMenu() {
    print("Refresh");
    if (mounted) setState(() {});
  }

  void _onWindowBlur() async {}

  void _onForegroundWindowChanged(int hWnd) {
    if (hWnd != Win32.hWnd) Globals.lastFocusedWinHWND = hWnd;
    if (userSettings.hookedWins.containsKey(hWnd)) {
      for (int win in userSettings.hookedWins[hWnd]!) {
        if (Win32.winExists(win)) {
          Win32.surfaceWindow(win);
        } else {
          userSettings.hookedWins[hWnd]?.remove(win);
        }
      }
      Win32.surfaceWindow(hWnd);
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
            if (userSettings.volumeSetBack) {
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
    if (userSettings.hideTabameOnUnfocus &&
        QuickMenuFunctions.isQuickMenuVisible &&
        Globals.quickMenuPage == QuickMenuPage.quickMenu &&
        !QuickMenuFunctions.keepOpen) {
      QuickMenuFunctions.hideQuickMenu();
      Future<void>.delayed(const Duration(milliseconds: 100), () => QuickMenuFunctions.hideQuickMenu());
    }
  }

  void _onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    handler.handle(hotkeyInfo);
  }

  Widget _build(BuildContext context) {
    tryPop = false;
    if (Globals.changingPages) {
      return const SizedBox(width: 10);
    }
    if (kReleaseMode) {
      return FutureBuilder<int>(
        future: quickMenuWindow,
        builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
          if (!snapshot.hasData) return const SizedBox(width: 10);
          return _mainWidget(context);
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
            return _mainWidget(context);
          },
        );
      },
    );
  }

  Widget _mainWidget(BuildContext context) {
    if (Globals.quickMenuPage == QuickMenuPage.quickSnap) {
      Navigator.of(context).maybePop();
      return const ViewsScreen();
    }
    if (Globals.quickMenuPage == QuickMenuPage.quickClick) {
      Navigator.of(context).maybePop();
      return const QuickClickOverlay();
    }
    if (Globals.quickMenuPage == QuickMenuPage.fancyShotLive) {
      Navigator.of(context).maybePop();
      return const FancyShotCaptureWidget(freezeMode: false);
    }
    if (Globals.quickMenuPage == QuickMenuPage.fancyShotFreeze) {
      Navigator.of(context).maybePop();
      return const FancyShotCaptureWidget(freezeMode: true);
    }
    if (Globals.quickMenuPage == QuickMenuPage.emojiPicker) {
      Navigator.of(context).maybePop();
      return const EmojiPage();
    }
    return Focus(
      focusNode: focusNode,
      autofocus: true,
      onKeyEvent: (FocusNode node, KeyEvent keyEvent) {
        final QuickMenuPage currentPage = Globals.quickMenuPage;
        final String? searchKey = _searchCharacterFromKeyEvent(keyEvent);

        // 1. When the Launcher is active, let the TextField own all input natively.
        //    We only buffer characters while QuickMenu still has primary focus
        //    during the handoff to the Launcher's TextField.
        if (currentPage == QuickMenuPage.launcher) {
          if (searchKey != null && focusNode.hasPrimaryFocus) {
            Globals.queueQuickMenuSearchInput(searchKey);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }

        // 2. Global Escape logic
        if (keyEvent.physicalKey == PhysicalKeyboardKey.escape) {
          if (keyEvent is KeyUpEvent) {
            //if (!Navigator.of(context).canPop()) {
            // Navigator.of(context).pop();
            // } else {
            QuickMenuFunctions.hideQuickMenu();
            //}
          }
          //_requestQuickMenuFocus(focusWindow: true);
          return KeyEventResult.handled;
        }
        // CTRL + H shortcut
        if (keyEvent.logicalKey == LogicalKeyboardKey.keyH && HardwareKeyboard.instance.isControlPressed) {
          if (keyEvent is KeyDownEvent) {
            userSettings.hideTabameOnUnfocus = !userSettings.hideTabameOnUnfocus;
            if (mounted) setState(() {});
          }
          return KeyEventResult.handled;
        }

        // 3. Quick Menu interactions (Navigation and Search initiation)
        // Initiate search on any character key → transition to launcher
        if (searchKey != null) {
          Globals.quickMenuPage = QuickMenuPage.launcher;
          Globals.queueQuickMenuSearchInput(searchKey);
          if (mounted) setState(() {});
          return KeyEventResult.handled;
        }

        // Navigation (Down keys only)
        if (keyEvent is KeyDownEvent) {
          final PhysicalKeyboardKey key = keyEvent.physicalKey;
          if (key == PhysicalKeyboardKey.arrowUp) {
            QuickMenuFunctions.onVerticalArrow(true);
            if (mounted) setState(() {});
            return KeyEventResult.handled;
          }
          if (key == PhysicalKeyboardKey.arrowDown) {
            QuickMenuFunctions.onVerticalArrow(false);
            if (mounted) setState(() {});
            return KeyEventResult.handled;
          }
          if (key == PhysicalKeyboardKey.enter) {
            QuickMenuFunctions.onEnter();
            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () {
          if (userSettings.hideTabameOnUnfocus && QuickMenuFunctions.isQuickMenuVisible) {
            QuickMenuFunctions.hideQuickMenu();
          }
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Align(
            alignment: Alignment.topLeft,
            child: Stack(
              children: <Widget>[
                if (userSettings.customSpash != "")
                  Positioned(child: Image.file(File(userSettings.customSpash), height: 30), left: 10),
                Padding(
                  padding: const EdgeInsets.all(10) + const EdgeInsets.only(top: 20),
                  child: DragToResizeArea(
                    resizeEdgeSize: 5,
                    enableResizeEdges: <ResizeEdge>[ResizeEdge.right],
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        key: Globals.quickMenu,
                        color: Colors.transparent,
                        child: MouseRegion(
                          onEnter: (PointerEnterEvent event) async {
                            Globals.isWindowActive = true;
                            // AllowSetForegroundWindow(pid);
                            if (Globals.quickMenuPage == QuickMenuPage.quickMenu) {
                              // Win32.activateWindow(Win32.hWnd);
                              _requestQuickMenuFocus();
                            }
                            // await WindowManager.instance.focus();
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
                                _requestQuickMenuFocus();
                              }
                            }
                          },
                          onExit: (PointerExitEvent event) {
                            Globals.isWindowActive = false;
                            lastCheck = 0;
                          },
                          child: Globals.quickMenuPage == QuickMenuPage.launcher
                              ? const Launcher()
                              : LoadQuickMenuDesign(key: Globals.quickMenuKey),
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
    if (!RegExp(r"^[^\x00-\x1F\x7F]+$", caseSensitive: false).hasMatch(character)) {
      return null;
    }
    return character;
  }
}
