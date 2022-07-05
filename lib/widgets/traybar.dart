// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../models/win32/tray.dart';
import '../models/win32/win32.dart';

class Traybar extends StatefulWidget {
  const Traybar({Key? key}) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _TraybarState createState() => _TraybarState();
}

class _TraybarState extends State<Traybar> {
  final ScrollController _scrollController = ScrollController();
  late Timer mainTimer;
  List<TrayBarInfo> tray = <TrayBarInfo>[];

  void fetchTray() async {
    final newTray = await Tray.fetchTray();
    if (newTray.length == tray.length) {
      return;
    }
    tray = newTray;
    print(tray.length);
    if (!mounted) return;
    setState(() {});
  }

  void init() {
    fetchTray();
    Timer.periodic(Duration(milliseconds: 400), (timer) {
      mainTimer = timer;
      fetchTray();
    });
  }

  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    init();
  }

  // @override
  // void reassemble() {
  //   super.reassemble();
  //   init();
  // }

  @override
  void dispose() {
    _scrollController.dispose();
    mainTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (tray.isEmpty) return Container();

    return SizedBox(
      // color: Colors.red,
      width: 150,
      height: 20,
      child: ListView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.antiAliasWithSaveLayer,
        shrinkWrap: true,
        // spacing: 0,
        children: [
          for (final info in tray)
            (info.isVisible == false)
                ? SizedBox(width: 0)
                : Listener(
                    onPointerDown: (PointerDownEvent event) {
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
                          // print("forceClosed");
                          // TerminateProcess(info.processID, 0);
                          Win32.closeWindow(info.hWnd, forced: true);
                          // onMouseMBClick?.call(event);
                        }
                      }
                    },
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        // onPointerScroll?.call(pointerSignal);
                        if (pointerSignal.scrollDelta.dy < 0) {
                          _scrollController.animateTo(_scrollController.position.minScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.ease);
                        } else {
                          _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.ease);
                        }
                      }
                    },
                    child: InkWell(
                      child: IconButton(
                        splashRadius: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 0,
                          minHeight: 0,
                        ),
                        onPressed: () {},
                        // width: 20,
                        icon: Image.memory(
                          info.hIcon,
                          fit: BoxFit.scaleDown,
                        ),
                      ),
                    ),
                  ),
        ],
      ),
    );
  }
}
