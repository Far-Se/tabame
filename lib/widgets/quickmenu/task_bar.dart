// ignore_for_file: unnecessary_string_interpolations

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../models/window_watcher.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/window.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/keys.dart';
import '../../models/globals.dart';

final windows = WindowWatcher();

class TaskBar extends StatefulWidget {
  const TaskBar({Key? key}) : super(key: key);

  @override
  TaskBarState createState() => TaskBarState();
}

class Caches {
  static final icons = <int, Uint8List?>{};
  static double lastHeight = 0;
  static List<int> audioMixer = <int>[];
  static List<String> audioMixerExes = <String>[];
}

class TaskBarState extends State<TaskBar> {
  int _hoverElement = -1;
  bool fetching = false;
  late Timer mainTimer;

  Future<bool> handleIcons({bool refreshIcons = false}) async {
    if (windows.list.length != Caches.icons.length) {
      Caches.icons.removeWhere((key, value) => !windows.list.any((w) => w.hWnd == key));
    }
    final tempWinList = {...windows.list};
    for (Window win in tempWinList) {
      if (Caches.icons.containsKey(win.hWnd) && !refreshIcons) continue;

      if (win.isAppx) {
        if (win.appxIcon != "" && File(win.appxIcon).existsSync()) Caches.icons[win.hWnd] = File(win.appxIcon).readAsBytesSync();
        continue;
      }

      Caches.icons[win.hWnd] = win.process.path.contains("System32") ? await nativeIconToBytes(win.process.path + win.process.exe) : await getWindowIcon(win.hWnd);

      if (!(Caches.icons.containsKey(win.hWnd) && !(Caches.icons[win.hWnd]!.any((element) => element != 204)))) continue;
      Caches.icons[win.hWnd] = win.process.path != "" ? await nativeIconToBytes(win.process.path + win.process.exe) : await getWindowIcon(win.hWnd);
    }
    return true;
  }

  Future<void> changeHeight() async {
    double currentHeight = (windows.list.length * 27).clamp(100, (Monitor.monitorSizes[Monitor.getWindowMonitor(Win32.hWnd)]?.height ?? 1080) / 1.7) + 5;
    Globals.heights.taskbar = currentHeight;
    if (currentHeight != Caches.lastHeight || true) {
      if (currentHeight < Caches.lastHeight) {
        Future.delayed(const Duration(milliseconds: 100), () => windowManager.setSize(Size(300, Globals.heights.allSummed + 50)));
      } else {
        await windowManager.setSize(Size(300, Globals.heights.allSummed + 70));
      }
      Caches.lastHeight = currentHeight;
    }
  }

  Future<void> audioHandle() async {
    final audioMixer = await Audio.enumAudioMixer() ?? [];
    if (audioMixer.isEmpty) return Caches.audioMixer.clear();
    Caches.audioMixer.clear();
    Caches.audioMixer = audioMixer.where((element) => element.peakVolume > 0.01).map((x) => x.processId).toList();

    Caches.audioMixerExes = audioMixer.where((element) => element.peakVolume > 0.01).map((x) => x.processPath.substring(x.processPath.lastIndexOf('\\') + 1)).toList();
  }

  Future fetchWindows({bool refreshIcons = false}) async {
    if (!fetching && windows.fetchWindows()) {
      fetching = true;
      await handleIcons(refreshIcons: refreshIcons);
      await audioHandle();
      await changeHeight();
      if (!mounted) return;

      setState(() => fetching = false);
    }
  }

  int timerTicks = 0;
  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    fetchWindows();
    mainTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!Globals.isWindowActive) return;
      timerTicks++;
      if (timerTicks == 3) {
        fetchWindows(refreshIcons: true);
        timerTicks = 0;
      } else {
        fetchWindows();
      }
    });
  }

  @override
  void dispose() {
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
              itemCount: windows.list.length,
              itemBuilder: (context, index) {
                final window = windows.list[index];
                return SizedBox(
                  width: 300,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (index > 0 && window.appearance.monitor != windows.list[index - 1].appearance.monitor)
                        Divider(
                          height: 3,
                          color: Theme.of(context).dividerColor,
                        ),
                      //#h white
                      MouseRegion(
                        onEnter: (e) {
                          setState(() {
                            _hoverElement = index;
                          });
                        },
                        onExit: (e) {
                          setState(() {
                            _hoverElement = -1;
                          });
                        },
                        //x3
                        child: Stack(
                          children: [
                            InkWell(
                              onTap: () {},
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
                                    children: [
                                      //2 Icon
                                      SizedBox(
                                        width: 20,
                                        child: ((Caches.icons.containsKey(window.hWnd))
                                            ? Image.memory(Caches.icons[window.hWnd] ?? Uint8List(0), width: 20, height: 20, gaplessPlayback: true)
                                            : const Icon(Icons.web_asset_sharp, size: 20)),
                                      ),

                                      //2 Info
                                      SizedBox(
                                        width: 10,
                                        child: Column(
                                          children: [
                                            Text(
                                              Monitor.monitorIds.length > 1 ? "${Monitor.monitorIds[window.appearance.monitor]}" : " ",
                                              style: const TextStyle(fontSize: 8),
                                            ),
                                            SizedBox(
                                              width: 10,
                                              height: 10,
                                              child: (window.appearance.isPinned
                                                  ? const Icon(Icons.bookmark, size: 8, color: Colors.grey)
                                                  : ((Caches.audioMixer.where((e) => [window.process.pId, window.process.mainPID].contains(e)).isNotEmpty) ||
                                                          Caches.audioMixerExes.contains(window.process.exe))
                                                      ? const Icon(Icons.volume_up_rounded, size: 8, color: Colors.grey)
                                                      : const SizedBox()),
                                            )
                                          ],
                                        ),
                                      ),

                                      //2 Title
                                      SizedBox(
                                        width: index != _hoverElement
                                            ? 240
                                            : 240 -
                                                ((["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                                    ? 75
                                                    : (Caches.audioMixerExes.contains(window.process.exe) ? 50 : 25)),
                                        child: SingleChildScrollView(
                                          clipBehavior: Clip.hardEdge,
                                          scrollDirection: index == _hoverElement ? Axis.horizontal : Axis.vertical,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 4),
                                            child: Text(
                                              "${window.title.toString()}",
                                              overflow: TextOverflow.ellipsis,
                                              // style: const TextStyle(fontFamily: "Roboto", fontWeight: FontWeight.w200),
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
                                width: (["Spotify.exe", "chrome.exe"].contains(window.process.exe)) ? 75 : (Caches.audioMixerExes.contains(window.process.exe) ? 50 : 25),
                                child: Container(
                                  color: Colors.transparent,
                                  width: 100,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: Wrap(
                                      children: [
                                        //2 Play & Next Button
                                        if (["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                          Wrap(
                                            children: [
                                              InkWell(
                                                onTap: () {
                                                  windows.mediaControl(index);
                                                },
                                                child: const SizedBox(width: 25, height: 25, child: Icon(Icons.play_arrow, size: 15)),
                                              ),
                                              InkWell(
                                                onTap: () {
                                                  windows.mediaControl(index, button: AppCommand.mediaNexttrack);
                                                },
                                                child: const SizedBox(width: 25, height: 25, child: Icon(Icons.skip_next, size: 15)),
                                              ),
                                            ],
                                          ),

                                        //2 Play Button

                                        if (Caches.audioMixerExes.contains(window.process.exe) && !["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                          InkWell(
                                            onTap: () {
                                              windows.mediaControl(index);
                                            },
                                            child: const SizedBox(width: 25, height: 25, child: Icon(Icons.play_arrow, size: 15)),
                                          ),

                                        //2 Close Button
                                        InkWell(
                                          onTap: () {
                                            if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                              WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                            }
                                            Win32.closeWindow(window.hWnd);
                                            windows.list.removeAt(index);
                                            setState(() {});
                                            fetchWindows();
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
