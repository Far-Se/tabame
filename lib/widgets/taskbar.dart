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
  // ignore: library_private_types_in_public_api
  _TaskbarState createState() => _TaskbarState();
}

final _iconCache = <int, Uint8List?>{};
double lastHeight = 0;
bool fetching = false;
List<int> _audioMixer = <int>[];
List<String> _audioMixerExes = <String>[];

class _TaskbarState extends State<Taskbar> {
  int _hoverElement = -1;
  late Timer mainTimer;

  Future<void> handleIcons() async {
    if (windows.list.length != _iconCache.length) {
      _iconCache.removeWhere((key, value) => !windows.list.any((w) => w.hWnd == key));
    }
    for (Window win in windows.list) {
      if (_iconCache.containsKey(win.hWnd)) {
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
        _iconCache[win.hWnd] = await getWindowIcon(win.hWnd); //  await nativeIconToBytes(win.process.path + win.process.exe);
      }
      if (!win.isAppx && _iconCache.containsKey(win.hWnd) && !(_iconCache[win.hWnd]!.any((element) => element != 204))) {
        _iconCache[win.hWnd] = await nativeIconToBytes(win.process.path + win.process.exe);
      }
    }
  }

  Future<void> changeHeight() async {
    double currentHeight = windows.list.length * 28;
    if (currentHeight != lastHeight || true) {
      if (currentHeight < lastHeight) {
        Future.delayed(const Duration(milliseconds: 100), () => windowManager.setSize(Size(300, currentHeight + 100)));
      } else {
        await windowManager.setSize(Size(300, currentHeight + 150));
        // await windowManager.setSize(Size(300, MediaQuery.of(context).size.height.clamp(100, 1000) + 100));
        // await windowManager.setSize(Size(300, MediaQuery.of(context).size.height + 100));
        // MediaQuery.of(context).size.height;
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

  Future fetchWindows() async {
    if (!fetching && windows.fetchWindows()) {
      fetching = true;
      await handleIcons();
      await audioHandle();
      await changeHeight();
      if (!mounted) return;
      setState(() => fetching = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (!mounted) return;

    Timer.periodic(const Duration(milliseconds: 300), (timer) {
      mainTimer = timer;
      fetchWindows();
    });
  }

  @override
  void dispose() {
    mainTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (windows.list.isEmpty) {
      return const SizedBox(width: 300);
    } else {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.all(3.0),
            child: SizedBox(
              height: lastHeight,
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisAlignment: MainAxisAlignment.start,

                                //#h black

                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (window.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) {
                                        WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                                      }
                                      Win32.activateWindow(window.hWnd);
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
                                                ? Image.memory(_iconCache[window.hWnd] ?? Uint8List(0), width: 20, height: 20)
                                                : const Icon(Icons.web_asset_sharp)),
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
                                ],
                              ),
                              //1 HOVER

                              if (index == _hoverElement)
                                Positioned(
                                  right: 0,
                                  bottom: 1,
                                  //width: _audioMixer.contains(window.process.pId) ? 75 : 25,
                                  width: (["Spotify.exe", "chrome.exe"].contains(window.process.exe)) ? 75 : (_audioMixerExes.contains(window.process.exe) ? 50 : 25),
                                  child: Container(
                                    color: Theme.of(context).scaffoldBackgroundColor,
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
}
