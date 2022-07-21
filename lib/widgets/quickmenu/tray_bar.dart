// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart' hide Rect;

import '../../models/globals.dart';
import '../../models/tray_watcher.dart';
import '../../models/win32/win32.dart';

class TrayBar extends StatefulWidget {
  const TrayBar({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  TrayBarState createState() => TrayBarState();
}

class TrayBarState extends State<TrayBar> {
  final ScrollController _scrollController = ScrollController();
  late Timer mainTimer;
  List<TrayBarInfo> tray = <TrayBarInfo>[];
  List<Uint8List> iconData = <Uint8List>[];
  bool fetching = false;
  int _hoverID = -1;
  void fetchTray() async {
    fetching = true;
    await Tray.fetchTray();
    fetching = false;
    // if (listEquals(Tray.trayList, tray)) return;
    tray = <TrayBarInfo>[...Tray.trayList.where((TrayBarInfo element) => element.isVisible)];
    if (mounted) setState(() {});
  }

  void init() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    fetchTray();
    mainTimer = Timer.periodic(const Duration(milliseconds: 600), (Timer timer) async {
      if (Globals.isWindowActive || true) {
        PaintingBinding.instance.imageCache.clear();
        if (!fetching) fetchTray();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    init();
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    _scrollController.dispose();
    mainTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (tray.isEmpty) return Container();

    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: SizedBox(
        height: Globals.heights.traybar - 10,
        width: tray.length * 20.4,
        child: ShaderMask(
          shaderCallback: (Rect rect) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: <Color>[Color.fromARGB(255, 0, 0, 0), Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
              stops: <double>[0.0, 0.05, 0.93, 1.0],
            ).createShader(rect);
          },
          blendMode: BlendMode.dstOut,
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.antiAliasWithSaveLayer,
            child: Row(children: <Widget>[
              for (final TrayBarInfo info in tray)
                Listener(
                  onPointerHover: (PointerHoverEvent event) {
                    if (_hoverID != info.hWnd) {
                      print(event);
                      _hoverID = info.hWnd;
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_NCMOUSEMOVE);
                    }
                  },
                  onPointerDown: (PointerDownEvent event) async {
                    if (event.kind == PointerDeviceKind.mouse) {
                      if (event.buttons == kSecondaryMouseButton) {
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDOWN);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDBLCLK);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                      } else if (event.buttons == kPrimaryMouseButton) {
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDOWN);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDBLCLK);
                        PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                      } else if (event.buttons == kMiddleMouseButton) {
                        final int hWnd = await findTopWindow(info.processID);
                        if (hWnd > 0) {
                          Win32.closeWindow(hWnd, forced: true);
                        } else {}
                      }
                    }
                  },
                  onPointerSignal: (PointerSignalEvent pointerSignal) {
                    if (pointerSignal is PointerScrollEvent) {
                      if (pointerSignal.scrollDelta.dy < 0) {
                        _scrollController.animateTo(_scrollController.position.minScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.ease);
                      } else {
                        _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.ease);
                      }
                    }
                  },
                  child: InkWell(
                    onTap: () {},
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2.2),
                      child: Tooltip(
                          message: info.toolTip.length > 1 ? info.toolTip : "",
                          height: 0,
                          preferBelow: false,
                          child: Image.memory(info.iconData, fit: BoxFit.scaleDown, gaplessPlayback: true)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
