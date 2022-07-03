import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabame/models/win32.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tabame/models/utils.dart';
import 'package:tabame/models/keys.dart';

final windows = WindowWatcher();

class Taskbar extends StatefulWidget {
  const Taskbar({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _TaskbarState createState() => _TaskbarState();
}

final _iconCache = <int, Uint8List?>{};
double lastHeight = 0;

class _TaskbarState extends State<Taskbar> {
  int _hoverElement = -1;

  Future<void> handleIcons() async {
    if (windows.list.length != _iconCache.length) {
      _iconCache.removeWhere((key, value) => !windows.list.any((w) => w.hWnd == key));
    }
    for (Window win in windows.list) {
      if (_iconCache.containsKey(win.hWnd)) {
        continue;
      }
      if (win.isAppx && win.appxIcon != "") {
        _iconCache[win.hWnd] = File(win.appxIcon).readAsBytesSync();
      } else if (win.process.path == "") {
        _iconCache[win.hWnd] = await getWindowIcon(win.hWnd);
      } else {
        _iconCache[win.hWnd] = await nativeIconToBytes(win.process.path + win.process.exe);
      }
    }
  }

  Future<void> changeHeight() async {
    double currentHeight = windows.list.length * 33;
    if (currentHeight != lastHeight || true) {
      windowManager.setSize(Size(300, currentHeight + 100));
      lastHeight = currentHeight;
    }
  }

  @override
  void initState() {
    if (!mounted) return;
    super.initState();
    windows.fetchWindows();
    Timer.periodic(const Duration(milliseconds: 300), (timer) async {
      if (windows.fetchWindows()) {
        await handleIcons();
        await changeHeight();
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return windows.list.isEmpty
        ? const SizedBox(width: 300)
        : Padding(
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

                        //#h
                        Listener(
                          onPointerDown: (PointerDownEvent event) {
                            print(event.position.dx);
                            if (event.position.dx < 260) {
                              print(windows.list[index].process.exe);
                              windows.mediaControl(index);
                              if (windows.list[index].process.exe == "Taskmgr.exe") {
                                WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
                              }
                              Win32.activateWindow(windows.list[index].hWnd);
                            } else {
                              Win32.closeWindow(windows.list[index].hWnd);
                            }
                          },
                          child: InkWell(
                            onTap: () {
                              //print("x");
                            },
                            //#h
                            child: MouseRegion(
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
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3.0),
                                child: MouseRegion(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      clipBehavior: Clip.none,
                                      fit: StackFit.loose,
                                      children: [
                                        ((_iconCache.containsKey(windows.list[index].hWnd))
                                            ? Image.memory(_iconCache[windows.list[index].hWnd] ?? Uint8List(0), width: 20, height: 20)
                                            : const Icon(Icons.spoke_outlined)),
                                        Positioned(
                                          // top: 0,
                                          left: 15,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: Text(
                                              "${Monitor.monitorIds[window.appearance.monitor]}: ${window.title.toString().truncate(30, suffix: '...')}",
                                            ),
                                          ),
                                        ),
                                        if (index == _hoverElement)
                                          Positioned(
                                            // top: 0,
                                            left: MediaQuery.of(context).size.width - 30,
                                            // width: 30,

                                            child: InkWell(
                                              onTap: () {},
                                              onHover: (e) {},
                                              child: const Icon(Icons.close),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        //#e
                      ],
                    ),
                  );
                },
              ),
            ),
          );
  }
}
