// ignore_for_file: unnecessary_string_interpolations

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide MenuItem;
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import 'package:tabamewin32/tabamewin32.dart';
import '../../models/keys.dart';
import '../../models/globals.dart';

class TaskBar extends StatefulWidget {
  const TaskBar({Key? key}) : super(key: key);

  @override
  TaskBarState createState() => TaskBarState();
}

class Caches {
  static double lastHeight = 0;
  static List<int> audioMixer = <int>[];
  static List<String> audioMixerExes = <String>[];
  List<Window> windows = <Window>[];
}

const double oneColumnHeight = 26.4;

class TaskBarState extends State<TaskBar> with QuickMenuTriggers, TabameListener {
  List<Window> windows = <Window>[];
  int _hoverElement = -1;
  bool fetching = false;
  late Timer mainTimer;
  double lastQuickMenuHeight = 0;
  List<String> wasPausedByButton = <String>[];

  bool justToggled = false;

  Future<void> handleHeight() async {
    if (Globals.changingPages == true) return;
    double currentHeight = (windows.length * oneColumnHeight).clamp(100, 400) + 5;
    Globals.heights.taskbar = currentHeight;
    if (currentHeight != Caches.lastHeight) {
      if (justToggled && 1 + 1 == 3) {
        final double newHeight = Globals.heights.allSummed + 80;
        if (Caches.lastHeight != newHeight) {
          if (!mounted) return;
          await windowManager.setSize(Size(300, newHeight));
          Caches.lastHeight = newHeight;
        }
        justToggled = false;
      }
      Caches.lastHeight = currentHeight;
    }
  }

  bool spotifyWasPaused = false;
  int spotifyDelayPlay = 0;
  Future<void> handleAudio() async {
    Debug.add("QuickMenu: Taskbar: Audio Handling");
    final List<ProcessVolume> audioMixer = await Audio.enumAudioMixer() ?? <ProcessVolume>[];
    if (audioMixer.isEmpty) return Caches.audioMixer.clear();
    Caches.audioMixer.clear();
    Caches.audioMixer = audioMixer.where((ProcessVolume element) => element.peakVolume > 0.005).map((ProcessVolume x) => x.processId).toList();
    Caches.audioMixerExes = audioMixer
        .where((ProcessVolume element) => element.peakVolume > 0.01)
        .map((ProcessVolume x) => x.processPath.substring(x.processPath.lastIndexOf('\\') + 1))
        .toList();
    if (globalSettings.pauseSpotifyWhenNewSound) {
      if (Caches.audioMixerExes.length > 1 && Caches.audioMixerExes.contains("Spotify.exe")) {
        WindowWatcher.triggerSpotify(button: AppCommand.mediaPause);
        spotifyWasPaused = true;
      } else {
        if (spotifyWasPaused && Caches.audioMixerExes.isEmpty) {
          if (spotifyDelayPlay > 2) {
            WindowWatcher.triggerSpotify(button: AppCommand.mediaPlay);
            spotifyWasPaused = false;
            spotifyDelayPlay = 0;
          } else {
            spotifyDelayPlay++;
          }
        }
      }
    }
    Debug.add("QuickMenu: Taskbar: Audio Handled");
  }

  Future<void> fetchWindows({bool state = true}) async {
    // ! commented this, moved on initState;
    // PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    if (keepFetching && !fetching && await WindowWatcher.fetchWindows()) {
      windows = <Window>[...WindowWatcher.list];
      fetching = true;
      await handleAudio();
      await handleHeight();

      if (state && mounted) setState(() => fetching = false);
    }
    return;
  }

  int timerTicks = 0;
  bool keepFetching = true;
  bool audioJumpOneTick = false;
  @override
  void initState() {
    Debug.add("QuickMenu: Taskbar-Init");
    super.initState();
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    if (!mounted) return;
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Taskbar:Listener Quick");
    NativeHooks.addListener(this);
    Debug.add("QuickMenu: Taskbar:Listener NativeHooks");
    fetchWindows();
    Debug.add("QuickMenu: Taskbar: Windows Fetched");
    mainTimer = Timer.periodic(const Duration(milliseconds: 300), (Timer timer) {
      if (globalSettings.pauseSpotifyWhenNewSound && !keepFetching) {
        if (audioJumpOneTick) {
          audioJumpOneTick = false;
        } else {
          handleAudio();
          audioJumpOneTick = true;
        }
      }
      if (!keepFetching) return;
      if (!fetching) {
        fetchWindows();
      }
    });
    Debug.add("QuickMenu: Taskbar");
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    mainTimer.cancel();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, int type) async {
    if (visible) {
      keepFetching = true;
      await fetchWindows();
      justToggled = true;
    } else {
      justToggled = false;
      keepFetching = false;
      setState(() {});
    }
    return;
  }

  @override
  void onWinEventReceived(int hWnd, WinEventType type) async {
    if (type == WinEventType.foreground) {
      if (!QuickMenuFunctions.isQuickMenuVisible) {
        hWnd = Win32.parent(hWnd);
        if (!windows.any((Window element) => element.hWnd == hWnd)) {
          Future<void>.delayed(const Duration(milliseconds: 300), () async => await fetchWindows());
        }
      }
    }
  }

  @override
  void onForegroundWindowChanged(int hWnd) {
    WindowWatcher.hierarchyAdd(hWnd);
  }

  //3 Initializing
  bool inside = false;
  @override
  Widget build(BuildContext context) {
    final Color hoverColor = globalSettings.themeTypeMode == ThemeType.dark ? Colors.white12.withOpacity(0.15) : Colors.black12.withOpacity(0.15);
    double dragMovement = 0.0;
    return Container(
      color: Colors.transparent,
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: Caches.lastHeight,
          constraints: const BoxConstraints(minHeight: 100),
          child: ShaderMask(
            shaderCallback: (Rect rect) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
                stops: <double>[0.00, 0.93, 1.0],
              ).createShader(rect);
            },
            blendMode: BlendMode.dstOut,
            child: ListView.builder(
              scrollDirection: Axis.vertical,
              itemCount: windows.length,
              itemBuilder: (BuildContext context, int index) {
                final Window window = windows.elementAt(index);
                double hoverButtonsWidth = (Boxes.mediaControls.contains(window.process.exe))
                    ? 75
                    : ((Caches.audioMixerExes.contains(window.process.exe) || wasPausedByButton.contains(window.process.exe)) ? 50 : 25);
                if (!globalSettings.showMediaControlForApp) hoverButtonsWidth = 25;

                return SizedBox(
                  width: 300,
                  child: MouseRegion(
                    onEnter: (PointerEnterEvent e) {
                      setState(() {
                        _hoverElement = index;
                      });
                    },
                    onExit: (PointerExitEvent e) {
                      setState(() {
                        _hoverElement = -1;
                      });
                    },

                    //x3
                    child: Stack(
                      children: <Widget>[
                        Container(
                          margin: !(index > 0 && window.monitor != windows[index - 1].monitor) ? null : const EdgeInsets.only(top: 2),
                          decoration: BoxDecoration(
                              color: _hoverElement == index ? (hoverColor) : Colors.transparent,
                              border: !(index > 0 && window.monitor != windows[index - 1].monitor)
                                  ? null
                                  : Border(top: BorderSide(width: 1, color: Theme.of(context).dividerColor))),
                          child: InkWell(
                            onTap: () {
                              if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                              }
                              Win32.activateWindow(window.hWnd);
                              if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
                              Globals.lastFocusedWinHWND = window.hWnd;
                            },
                            onFocusChange: (bool h) {
                              if (h) {
                                _hoverElement = index;
                              } else {
                                // _hoverElement = -1;
                              }
                              setState(() {});
                            },
                            hoverColor: Colors.transparent,
                            child: GestureDetector(
                              onTap: () {
                                if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                  WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                }
                                if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
                                Win32.activateWindow(window.hWnd);
                                Globals.lastFocusedWinHWND = window.hWnd;
                              },
                              onVerticalDragEnd: (DragEndDetails e) {
                                if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                  WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                }
                                if (kReleaseMode) QuickMenuFunctions.toggleQuickMenu(visible: false);
                                Win32.activateWindow(window.hWnd);
                                Globals.lastFocusedWinHWND = window.hWnd;
                              },
                              onSecondaryTap: () async {
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
                                          child: Padding(
                                            padding: const EdgeInsets.all(2.0),
                                            child: ContextMenuWidget(hWnd: window.hWnd),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                                /* 
                                  Menu menu = Menu(
                                    items: <MenuItem>[
                                      MenuItem(
                                          label: 'To Right Desktop', onClick: (_) => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.right, classMethod: false)),
                                      MenuItem(label: 'To Left Desktop', onClick: (_) => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.left, classMethod: false)),
                                      MenuItem.separator(),
                                      MenuItem(
                                          label: window.isPinned ? "Unpin" : 'Set Always on Top',
                                          onClick: (_) {
                                            Win32.setAlwaysOnTop(window.hWnd);
                                            setState(() {});
                                          }),
                                      MenuItem(
                                          label: "Force Close",
                                          onClick: (_) {
                                            Win32.forceCloseWindowbyProcess(window.process.pId);
                                          })
                                    ],
                                  );
                                  popUpContextualMenu(menu, placement: Placement.bottomRight); 
                                */
                              },
                              onLongPress: () {
                                Win32.forceActivateWindow(window.hWnd);
                              },
                              onHorizontalDragUpdate: (DragUpdateDetails details) {
                                dragMovement += details.delta.dx;
                              },
                              onHorizontalDragEnd: (DragEndDetails details) {
                                if (dragMovement.abs() < 50) {
                                  if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                    WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                  }
                                  Win32.activateWindow(window.hWnd);
                                  Globals.lastFocusedWinHWND = window.hWnd;
                                  return;
                                }
                                if (dragMovement > 0) {
                                  Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.left);
                                } else {
                                  Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.right);
                                }
                                dragMovement = 0.0;
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                //1 Window List
                                child: Wrap(
                                  spacing: 0,
                                  clipBehavior: Clip.hardEdge,
                                  children: <Widget>[
                                    const SizedBox(
                                      width: 5,
                                    ),
                                    //2 Icon
                                    SizedBox(
                                      width: 20,
                                      child: ((WindowWatcher.icons.containsKey(window.hWnd))
                                          ? Image.memory(
                                              WindowWatcher.icons[window.hWnd] ?? Uint8List(0),
                                              width: 20,
                                              height: 20,
                                              gaplessPlayback: true,
                                              errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                                                Icons.check_box_outline_blank,
                                                size: 20,
                                              ),
                                            )
                                          : const Icon(Icons.web_asset_sharp, size: 20)),
                                    ),

                                    //2 Info
                                    SizedBox(
                                      width: 10,
                                      child: Column(
                                        children: <Widget>[
                                          const SizedBox(height: 2),
                                          Text(
                                            Monitor.monitorIds.length > 1 ? "${Monitor.monitorIds[window.monitor]}" : " ",
                                            style: const TextStyle(fontSize: 8, height: 1),
                                          ),
                                          SizedBox(
                                            width: 10,
                                            height: 10,
                                            child: (window.isPinned
                                                ? const Icon(Icons.bookmark, size: 8, color: Colors.grey)
                                                : ((Caches.audioMixer.where((int e) => <int>[window.process.pId, window.process.mainPID].contains(e)).isNotEmpty) ||
                                                        Caches.audioMixerExes.contains(window.process.exe))
                                                    ? const Icon(Icons.volume_up_rounded, size: 8, color: Colors.grey)
                                                    : const SizedBox()),
                                          )
                                        ],
                                      ),
                                    ),

                                    //2 Title
                                    SizedBox(
                                      width: index != _hoverElement ? 240 : 240 - hoverButtonsWidth + 5,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(
                                          "${window.title.toString()}",
                                          overflow: TextOverflow.fade,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: TextStyle(fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        //x1

                        //1 HOVER

                        if (index == _hoverElement)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            width: hoverButtonsWidth,
                            child: Container(
                              color: hoverColor,
                              constraints: BoxConstraints(minWidth: hoverButtonsWidth, maxWidth: hoverButtonsWidth, minHeight: oneColumnHeight),
                              child: Material(
                                type: MaterialType.transparency,
                                child: Wrap(
                                  children: <Widget>[
                                    //2 Play & Next Button
                                    if (Boxes.mediaControls.contains(window.process.exe) && globalSettings.showMediaControlForApp)
                                      Wrap(
                                        children: <Widget>[
                                          InkWell(
                                            hoverColor: hoverColor,
                                            onTap: () {
                                              WindowWatcher.mediaControl(index);
                                            },
                                            child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.play_arrow, size: 15)),
                                          ),
                                          InkWell(
                                            hoverColor: hoverColor,
                                            onTap: () {
                                              WindowWatcher.mediaControl(index, button: AppCommand.mediaNexttrack);
                                            },
                                            child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.skip_next, size: 15)),
                                          ),
                                        ],
                                      ),

                                    //2 Play Button

                                    if (globalSettings.showMediaControlForApp &&
                                        (wasPausedByButton.contains(window.process.exe) ||
                                            (Caches.audioMixerExes.contains(window.process.exe) && !Boxes.mediaControls.contains(window.process.exe))))
                                      InkWell(
                                        hoverColor: hoverColor,
                                        onTap: () {
                                          if (!wasPausedByButton.contains(window.process.exe)) {
                                            wasPausedByButton.add(window.process.exe);
                                          }
                                          WindowWatcher.mediaControl(index);
                                        },
                                        child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.play_arrow, size: 15)),
                                      ),

                                    //2 Close Button
                                    InkWell(
                                      hoverColor: hoverColor,
                                      onTap: () async {
                                        if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                          WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                        }
                                        fetching = true;
                                        Win32.closeWindow(window.hWnd);
                                        windows.removeAt(index);
                                        await handleAudio();
                                        await handleHeight();
                                        fetchWindows();
                                        setState(() => fetching = false);
                                      },
                                      onLongPress: () {
                                        Win32.closeWindow(window.hWnd, forced: true);
                                      },
                                      child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.close, size: 15)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                      //#e
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class ContextMenuWidget extends StatefulWidget {
  final int hWnd;
  const ContextMenuWidget({Key? key, required this.hWnd}) : super(key: key);
  @override
  ContextMenuWidgetState createState() => ContextMenuWidgetState();
}

class ContextMenuWidgetState extends State<ContextMenuWidget> {
  late Window window;
  late Uint8List? icon;
  @override
  void initState() {
    super.initState();
    window = Window(widget.hWnd);
    icon = WindowWatcher.icons[window.hWnd];
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          // height: MediaQuery.of(context).size.height,
          height: double.infinity,
          width: 280,
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 350),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            // border: Border.all(color: Theme.of(context).backgroundColor.withOpacity(0.5), width: 1),
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
            ],
            color: Theme.of(context).backgroundColor,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              height: 350,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SizedBox(
                        width: 30,
                        child: ((icon != null)
                            ? Image.memory(
                                WindowWatcher.icons[window.hWnd] ?? Uint8List(0),
                                width: 20,
                                height: 20,
                                gaplessPlayback: true,
                                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                                  Icons.check_box_outline_blank,
                                  size: 20,
                                ),
                              )
                            : const Icon(Icons.web_asset_sharp, size: 20)),
                      ),
                      Expanded(
                        child: Text(
                          window.title,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: TextStyle(
                            fontWeight: globalSettings.theme.quickMenuBoldFont ? FontWeight.w500 : FontWeight.w400,
                            fontSize: 16,
                            height: 1,
                          ),
                        ),
                      )
                    ],
                  ),
                  const Divider(height: 10, thickness: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        InkWell(
                          onTap: () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.right, classMethod: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                        child:
                                            Icon(Icons.keyboard_double_arrow_right, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), size: 18))),
                                Expanded(child: Text("Move to right Desktop", style: Theme.of(context).textTheme.button?.copyWith(height: 1))),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => Win32.moveWindowToDesktop(window.hWnd, DesktopDirection.left, classMethod: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                        child: Icon(Icons.keyboard_double_arrow_left, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), size: 18))),
                                Expanded(child: Text("Move to left Desktop", style: Theme.of(context).textTheme.button?.copyWith(height: 1))),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Win32.setAlwaysOnTop(window.hWnd);
                            Navigator.pop(context);
                            // setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                    child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                  child: Icon(Icons.pin_end_outlined, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), size: 18),
                                )),
                                Expanded(child: Text(window.isPinned ? "Unpin" : 'Set Always on Top', style: Theme.of(context).textTheme.button?.copyWith(height: 1))),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Win32.forceCloseWindowbyProcess(window.process.pId);
                            Navigator.pop(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                SizedBox(
                                    child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                  child: Icon(Icons.highlight_off, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), size: 18),
                                )),
                                Expanded(child: Text("Force Close", style: Theme.of(context).textTheme.button?.copyWith(height: 1))),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 10, thickness: 1),
                        if (globalSettings.hookedWins.containsKey(widget.hWnd))
                          InkWell(
                            onTap: () {
                              globalSettings.hookedWins.remove(widget.hWnd);
                              setState(() {});
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  SizedBox(
                                      child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
                                    child: Icon(Icons.pin_end_outlined, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6), size: 18),
                                  )),
                                  Expanded(child: Text("UnHook", style: Theme.of(context).textTheme.button?.copyWith(height: 1))),
                                ],
                              ),
                            ),
                          ),
                        const Text("Hook window with:"),
                        Container(
                          height: 130,
                          child: ListView.builder(
                              controller: ScrollController(),
                              itemCount: WindowWatcher.list.length,
                              itemBuilder: (BuildContext context, int index) {
                                final Window win = WindowWatcher.list.elementAt(index);
                                if (win.hWnd == widget.hWnd) return const SizedBox();
                                return InkWell(
                                  onTap: () {
                                    globalSettings.hookedWins[widget.hWnd] ??= <int>[];
                                    globalSettings.hookedWins[widget.hWnd]!.toggle(win.hWnd);
                                    if (globalSettings.hookedWins[widget.hWnd]!.isEmpty) globalSettings.hookedWins.remove(widget.hWnd);
                                    setState(() {});
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        SizedBox(
                                          width: 25,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                                            child: ((WindowWatcher.icons.containsKey(win.hWnd))
                                                ? Image.memory(
                                                    WindowWatcher.icons[win.hWnd] ?? Uint8List(0),
                                                    width: 16,
                                                    height: 16,
                                                    gaplessPlayback: true,
                                                    errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                                                      Icons.check_box_outline_blank,
                                                      size: 16,
                                                    ),
                                                  )
                                                : const Icon(Icons.web_asset_sharp, size: 20)),
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            win.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.fade,
                                            softWrap: false,
                                          ),
                                        ),
                                        SizedBox(
                                          width: 20,
                                          child: Icon((globalSettings.hookedWins[widget.hWnd] ?? <int>[]).contains(win.hWnd) ? Icons.phishing : null,
                                              size: 16, color: Theme.of(context).iconTheme.color?.withOpacity(0.7)),
                                        )
                                      ],
                                    ),
                                  ),
                                );
                              }),
                        )
                      ],
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
