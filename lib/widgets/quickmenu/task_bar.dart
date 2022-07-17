// ignore_for_file: unnecessary_string_interpolations

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
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

class TaskBarState extends State<TaskBar> {
  int _hoverElement = -1;
  bool fetching = false;
  late Timer mainTimer;
  final bool _skipFirst = true;
  List<Window> windows = <Window>[];
  Future<void> changeHeight() async {
    if (Globals.changingPages == true) return;
    // double currentHeight = (windows.length * 27).clamp(100, (Monitor.monitorSizes[Monitor.getWindowMonitor(Win32.hWnd)]?.height ?? 1080) / 1.7) + 5;
    double currentHeight = (windows.length * 27).clamp(100, 400) + 5;
    Globals.heights.taskbar = currentHeight;
    if (currentHeight != Caches.lastHeight || true) {
      if (currentHeight < Caches.lastHeight) {
        // Future<void>.delayed(const Duration(milliseconds: 100), () => windowManager.setSize(Size(300, Globals.heights.allSummed + 50)));
      } else {
        // await windowManager.setSize(Size(300, Globals.heights.allSummed + 70));
      }
      Caches.lastHeight = currentHeight;
    }
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
      if (listEquals(WindowWatcher.list, windows)) {
        await audioHandle();
        await changeHeight();
        if (mounted) setState(() => fetching = false);
        return;
      }
      windows = <Window>[...WindowWatcher.list];
      fetching = true;

      await audioHandle();
      await changeHeight();

      if (mounted) setState(() => fetching = false);
    }
  }

  int timerTicks = 0;
  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    fetchWindows();
    mainTimer = Timer.periodic(const Duration(milliseconds: 300), (Timer timer) {
      // if (!Globals.isWindowActive) return;
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
        child: Padding(
          padding: const EdgeInsets.all(3.0),
          child: Container(
            height: Caches.lastHeight,
            constraints: const BoxConstraints(minHeight: 100),
            child: ListView.builder(
              scrollDirection: Axis.vertical,
              itemCount: windows.length,
              itemBuilder: (BuildContext context, int index) {
                final Window window = windows.elementAt(index);
                double hoverButtonsWidth =
                    (<String>["Spotify.exe", "chrome.exe"].contains(window.process.exe)) ? 75 : (Caches.audioMixerExes.contains(window.process.exe) ? 50 : 25);
                return SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (index > 0 && window.appearance.monitor != windows[index - 1].appearance.monitor)
                        Divider(
                          height: 3,
                          color: Theme.of(context).dividerColor,
                        ),
                      //#h white
                      MouseRegion(
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
                            InkWell(
                              onTap: () {},
                              hoverColor: Colors.black12.withOpacity(0.15),
                              child: GestureDetector(
                                onTap: () {
                                  if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                    WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                  }
                                  Win32.activateWindow(window.hWnd);
                                  Globals.lastFocusedWinHWND = window.hWnd;
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
                                    children: <Widget>[
                                      const SizedBox(
                                        width: 2,
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
                                            Text(
                                              Monitor.monitorIds.length > 1 ? "${Monitor.monitorIds[window.appearance.monitor]}" : " ",
                                              style: const TextStyle(fontSize: 8),
                                            ),
                                            SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: (window.appearance.isPinned
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
                                      ClipRect(
                                        clipBehavior: Clip.hardEdge,
                                        child: SizedBox(
                                          width: index != _hoverElement ? 240 : 240 - hoverButtonsWidth,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              "${window.title.toString()}",
                                              overflow: index == _hoverElement ? TextOverflow.visible : TextOverflow.ellipsis,
                                              maxLines: 1,
                                              softWrap: false,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            //x1

                            //1 HOVER

                            if (index == _hoverElement)
                              Positioned(
                                right: 0,
                                bottom: 1,
                                width: hoverButtonsWidth,
                                child: Container(
                                  color: Colors.transparent,
                                  width: 100,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: Wrap(
                                      children: <Widget>[
                                        //2 Play & Next Button
                                        if (<String>["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                          Wrap(
                                            children: <Widget>[
                                              InkWell(
                                                onTap: () {
                                                  WindowWatcher.mediaControl(index);
                                                },
                                                child: const SizedBox(width: 25, height: 25, child: Icon(Icons.play_arrow, size: 15)),
                                              ),
                                              InkWell(
                                                onTap: () {
                                                  WindowWatcher.mediaControl(index, button: AppCommand.mediaNexttrack);
                                                },
                                                child: const SizedBox(width: 25, height: 25, child: Icon(Icons.skip_next, size: 15)),
                                              ),
                                            ],
                                          ),

                                        //2 Play Button

                                        if (Caches.audioMixerExes.contains(window.process.exe) && !<String>["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                          InkWell(
                                            onTap: () {
                                              WindowWatcher.mediaControl(index);
                                            },
                                            child: const SizedBox(width: 25, height: 25, child: Icon(Icons.play_arrow, size: 15)),
                                          ),

                                        //2 Close Button
                                        InkWell(
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
                                          child: const SizedBox(width: 25, height: 25, child: Icon(Icons.close, size: 15)),
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
                    ],
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
