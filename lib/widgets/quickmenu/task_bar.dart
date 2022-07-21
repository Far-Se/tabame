// ignore_for_file: unnecessary_string_interpolations

import 'dart:async';
import 'dart:typed_data';

import 'package:contextual_menu/contextual_menu.dart';
import 'package:flutter/material.dart' hide MenuItem;
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import '../../models/utils.dart';
import '../../models/win32/imports.dart';
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

class TaskBarState extends State<TaskBar> {
  List<Window> windows = <Window>[];
  int _hoverElement = -1;
  bool fetching = false;
  late Timer mainTimer;

  Future<void> changeHeight() async {
    if (Globals.changingPages == true) return;
    double currentHeight = (windows.length * oneColumnHeight).clamp(100, 400) + 5;
    Globals.heights.taskbar = currentHeight;
    if (currentHeight != Caches.lastHeight) Caches.lastHeight = currentHeight;
  }

  Future<void> audioHandle() async {
    final List<ProcessVolume> audioMixer = await Audio.enumAudioMixer() ?? <ProcessVolume>[];
    if (audioMixer.isEmpty) return Caches.audioMixer.clear();
    Caches.audioMixer.clear();
    Caches.audioMixer = audioMixer.where((ProcessVolume element) => element.peakVolume > 0.01).map((ProcessVolume x) => x.processId).toList();

    Caches.audioMixerExes = audioMixer
        .where((ProcessVolume element) => element.peakVolume > 0.01)
        .map((ProcessVolume x) => x.processPath.substring(x.processPath.lastIndexOf('\\') + 1))
        .toList();
  }

  Future<void> fetchWindows() async {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    if (!fetching && await WindowWatcher.fetchWindows()) {
      // if (listEquals(WindowWatcher.list, windows)) {
      //   await audioHandle();
      //   await changeHeight();
      //   if (mounted) setState(() => fetching = false);
      //   return;
      // }
      windows = <Window>[...WindowWatcher.list];
      fetching = true;
      await audioHandle();
      await changeHeight();

      if (mounted) {
        setState(() {
          fetching = false;
          Globals.quickMenuFullyInitiated = true;
        });
      }
    }
  }

  int timerTicks = 0;
  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    fetchWindows();
    mainTimer = Timer.periodic(const Duration(milliseconds: 300), (Timer timer) {
      if (!fetching) fetchWindows();
    });
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    mainTimer.cancel();
    super.dispose();
  }

  //3 Initializing
  bool inside = false;
  @override
  Widget build(BuildContext context) {
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
                double hoverButtonsWidth = (Boxes.mediaControls.contains(window.process.exe)) ? 75 : (Caches.audioMixerExes.contains(window.process.exe) ? 50 : 25);
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
                              color: _hoverElement == index ? Colors.black12.withOpacity(0.15) : Colors.transparent,
                              border: !(index > 0 && window.monitor != windows[index - 1].monitor)
                                  ? null
                                  : Border(top: BorderSide(width: 1, color: Theme.of(context).dividerColor))),
                          child: InkWell(
                            onTap: () {},
                            // hoverColor: Colors.black12.withOpacity(0.15),
                            child: GestureDetector(
                              onTap: () {
                                if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                  WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                }
                                Win32.activateWindow(window.hWnd);
                                Globals.lastFocusedWinHWND = window.hWnd;
                              },
                              onSecondaryTap: () async {
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
                                          Win32.forceCloseWindow(window.hWnd, window.process.pId);
                                        })
                                  ],
                                );
                                popUpContextualMenu(menu, placement: Placement.bottomRight);
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
                                          style: const TextStyle(
                                              // fontSize: 13,
                                              // height: 1.2,
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
                        //x1

                        //1 HOVER

                        if (index == _hoverElement)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            width: hoverButtonsWidth,
                            child: Container(
                              color: Colors.black12.withOpacity(0.15),
                              // width: hoverButtonsWidth,
                              constraints: BoxConstraints(minWidth: hoverButtonsWidth, maxWidth: hoverButtonsWidth, minHeight: oneColumnHeight),
                              child: Material(
                                type: MaterialType.transparency,
                                child: Wrap(
                                  children: <Widget>[
                                    //2 Play & Next Button
                                    if (Boxes.mediaControls.contains(window.process.exe))
                                      Wrap(
                                        children: <Widget>[
                                          InkWell(
                                            hoverColor: Colors.black12.withOpacity(0.25),
                                            onTap: () {
                                              WindowWatcher.mediaControl(index);
                                            },
                                            child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.play_arrow, size: 15)),
                                          ),
                                          InkWell(
                                            hoverColor: Colors.black12.withOpacity(0.25),
                                            onTap: () {
                                              WindowWatcher.mediaControl(index, button: AppCommand.mediaNexttrack);
                                            },
                                            child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.skip_next, size: 15)),
                                          ),
                                        ],
                                      ),

                                    //2 Play Button

                                    if (Caches.audioMixerExes.contains(window.process.exe) && !Boxes.mediaControls.contains(window.process.exe))
                                      InkWell(
                                        hoverColor: Colors.black12.withOpacity(0.25),
                                        onTap: () {
                                          WindowWatcher.mediaControl(index);
                                        },
                                        child: const SizedBox(width: 25, height: oneColumnHeight, child: Icon(Icons.play_arrow, size: 15)),
                                      ),

                                    //2 Close Button
                                    InkWell(
                                      hoverColor: Colors.black12.withOpacity(0.25),
                                      onTap: () async {
                                        if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                          WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                        }
                                        fetching = true;
                                        Win32.closeWindow(window.hWnd);
                                        windows.removeAt(index);
                                        await audioHandle();
                                        await changeHeight();
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
