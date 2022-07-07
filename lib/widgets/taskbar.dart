// ignore_for_file: unnecessary_string_interpolations

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/window_watcher.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/window.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';
import '../models/keys.dart';

final windows = WindowWatcher();

class Taskbar extends StatefulWidget {
  const Taskbar({Key? key}) : super(key: key);

  @override
  TaskbarState createState() => TaskbarState();
}

var _iconCacheCashed = <int, Uint8List?>{}; //xzibity
final _iconCache = <int, Uint8List?>{};
double lastHeight = 0;
bool fetching = false;
List<int> _audioMixer = <int>[];
List<String> _audioMixerExes = <String>[];

class TaskbarState extends State<Taskbar> {
  int _hoverElement = -1;
  late Timer mainTimer;

  Future<bool> handleIcons({bool refreshIcons = false}) async {
    if (windows.list.length != _iconCache.length) {
      _iconCache.removeWhere((key, value) => !windows.list.any((w) => w.hWnd == key));
    }
    final tempWinList = {...windows.list};
    for (Window win in tempWinList) {
      if (_iconCache.containsKey(win.hWnd) && !refreshIcons) {
        continue;
      }
      if (win.isAppx) {
        if (win.appxIcon != "") {
          if (File(win.appxIcon).existsSync()) {
            _iconCache[win.hWnd] = File(win.appxIcon).readAsBytesSync();
          }
        }
      } else if (win.process.path == "") {
        _iconCache[win.hWnd] = await getWindowIcon(win.hWnd);
      } else {
        if (win.process.path.contains("System32")) {
          _iconCache[win.hWnd] = await nativeIconToBytes(win.process.path + win.process.exe);
        } else {
          _iconCache[win.hWnd] = await getWindowIcon(win.hWnd);
        }
      }
      if (!win.isAppx && _iconCache.containsKey(win.hWnd) && !(_iconCache[win.hWnd]!.any((element) => element != 204))) {
        if (win.process.path != "") {
          _iconCache[win.hWnd] = await nativeIconToBytes(win.process.path + win.process.exe);
        } else {
          _iconCache[win.hWnd] = await getWindowIcon(win.hWnd);
        }
      }
    }
    _iconCacheCashed = _iconCache; //{..._iconCache};
    return true;
  }

  Future<void> changeHeight() async {
    double currentHeight = (windows.list.length * 28).clamp(0, Monitor.monitorSizes[Monitor.getWindowMonitor(Win32.hWnd)]!.height / 1.7).toDouble();
    if (currentHeight != lastHeight || true) {
      if (currentHeight < lastHeight) {
        Future.delayed(const Duration(milliseconds: 100), () => windowManager.setSize(Size(300, currentHeight + 100)));
      } else {
        await windowManager.setSize(Size(300, currentHeight + 150));
      }
      lastHeight = currentHeight;
    }
  }

  Future<void> audioHandle() async {
    final audioMixer = await Audio.enumAudioMixer() ?? [];
    if (audioMixer.isEmpty) return _audioMixer.clear();
    _audioMixer.clear();
    _audioMixer = audioMixer.where((element) => element.peakVolume > 0.01).map((x) => x.processId).toList();

    _audioMixerExes = audioMixer.where((element) => element.peakVolume > 0.01).map((x) => x.processPath.substring(x.processPath.lastIndexOf('\\') + 1)).toList();
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

    mainTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      timerTicks++;
      if (timerTicks == 3) {
        _iconCache.clear();
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).backgroundColor,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.all(3.0),
          child: Container(
            height: lastHeight,
            constraints: BoxConstraints(minHeight: 100),
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
                        child: Stack(
                          children: [
                            InkWell(
                              onTap: () {
                                if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                  WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                }
                                Win32.activateWindow(window.hWnd);
                              },
                              onLongPress: () {
                                Win32.forceActivateWindow(window.hWnd);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                //1 Window List
                                child: Wrap(
                                  spacing: 0,
                                  children: [
                                    // ? Icon
                                    SizedBox(
                                      width: 20,
                                      child: ((_iconCache.containsKey(window.hWnd))
                                          ? Image.memory(_iconCache[window.hWnd] ?? Uint8List(0), width: 20, height: 20, gaplessPlayback: true)
                                          : (_iconCacheCashed.containsKey(window.hWnd)
                                              ? Image.memory(_iconCacheCashed[window.hWnd] ?? Uint8List(0), width: 20, height: 20, gaplessPlayback: true)
                                              : const Icon(Icons.web_asset_sharp, size: 20))),
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
                                            child: ((_audioMixer.where((e) => [window.process.pId, window.process.mainPID].contains(e)).isNotEmpty) ||
                                                    _audioMixerExes.contains(window.process.exe))
                                                ? const Icon(
                                                    Icons.volume_up_rounded,
                                                    size: 8,
                                                    color: Colors.grey,
                                                  )
                                                : const SizedBox(),
                                          )
                                        ],
                                      ),
                                    ),
                                    //2 Title
                                    SizedBox(
                                      width: 240,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: Text(
                                          "${window.title.toString()}",
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            //1 HOVER

                            if (index == _hoverElement)
                              Positioned(
                                right: 0,
                                bottom: 1,
                                width: (["Spotify.exe", "chrome.exe"].contains(window.process.exe)) ? 75 : (_audioMixerExes.contains(window.process.exe) ? 50 : 25),
                                child: Container(
                                  color: Theme.of(context).backgroundColor,
                                  width: 100,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: Wrap(
                                      children: [
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
                                        if (_audioMixerExes.contains(window.process.exe) && !["Spotify.exe", "chrome.exe"].contains(window.process.exe))
                                          InkWell(
                                            onTap: () {
                                              windows.mediaControl(index);
                                            },
                                            child: const SizedBox(width: 25, height: 25, child: Icon(Icons.play_arrow, size: 15)),
                                          ),
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
