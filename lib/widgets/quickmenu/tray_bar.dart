// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../models/globals.dart';
import '../../models/win32/tray.dart';
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

  void fetchTray() async {
    await Tray.fetchTray();
    if (listEquals(Tray.trayList, tray)) return;
    tray = <TrayBarInfo>[...Tray.trayList];
    if (mounted) setState(() {});
  }

  void init() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    fetchTray();
    mainTimer = Timer.periodic(const Duration(milliseconds: 600), (Timer timer) async {
      if (Globals.isWindowActive || true) {
        PaintingBinding.instance.imageCache.clear();
        fetchTray();
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

    Globals.heights.traybar = 30;
    return Align(
      alignment: Alignment.centerRight,
      child: Theme(
        data: Theme.of(context)
            .copyWith(tooltipTheme: Theme.of(context).tooltipTheme.copyWith(preferBelow: false, decoration: BoxDecoration(color: Theme.of(context).backgroundColor))),
        child: Padding(
          padding: const EdgeInsets.only(right: 3),
          child: SizedBox(
            height: 20,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.antiAliasWithSaveLayer,
              child: Row(children: <Widget>[
                for (final TrayBarInfo info in tray)
                  (info.isVisible == false)
                      ? const SizedBox(width: 0)
                      : Listener(
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
                                // if (info.processPath.isEmpty) return;
                                final int hWnd = await findTopWindow(info.processID);
                                if (hWnd > 0) {
                                  print("$hWnd ${info.processID}");
                                  Win32.closeWindow(hWnd, forced: true);
                                } else {
                                  print("dsa");
                                }

                                // final windows = enumWindows();
                                // for (var win in windows) {
                                //   final path = Win32.getWindowExePath(win);
                                //   if (path == info.processPath) {
                                //     print(win);
                                //     Win32.closeWindow(win);
                                //     await Tray.fetchTray();
                                //     setState(() {});
                                //   }
                                // }
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
                            child: IconButton(
                              splashRadius: 15,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 0,
                                minHeight: 0,
                              ),
                              onPressed: () {},
                              icon: Tooltip(
                                message: info.toolTip.length > 1 ? info.toolTip : "",
                                height: 0,
                                preferBelow: false,
                                child: (info.brightness < 400)
                                    ? Image.memory(info.hIcon, fit: BoxFit.scaleDown, gaplessPlayback: true)
                                    : ColorFiltered(
                                        colorFilter: ColorFilter.matrix(ColorFilterGenerator.brightnessAdjustMatrix(
                                          value: -0.5,
                                        )),
                                        child: Image.memory(info.hIcon, fit: BoxFit.scaleDown, gaplessPlayback: true),
                                      ),
                              ),
                            ),
                          ),
                        ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// #region [collapsed] ColorFilterGenerator

class ColorFilterGenerator {
  static List<double> hueAdjustMatrix({required double value}) {
    value = value * pi;

    if (value == 0) {
      return <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }

    double cosVal = cos(value);
    double sinVal = sin(value);
    double lumR = 0.213;
    double lumG = 0.715;
    double lumB = 0.072;

    return List<double>.from(<double>[
      (lumR + (cosVal * (1 - lumR))) + (sinVal * (-lumR)),
      (lumG + (cosVal * (-lumG))) + (sinVal * (-lumG)),
      (lumB + (cosVal * (-lumB))) + (sinVal * (1 - lumB)),
      0,
      0,
      (lumR + (cosVal * (-lumR))) + (sinVal * 0.143),
      (lumG + (cosVal * (1 - lumG))) + (sinVal * 0.14),
      (lumB + (cosVal * (-lumB))) + (sinVal * (-0.283)),
      0,
      0,
      (lumR + (cosVal * (-lumR))) + (sinVal * (-(1 - lumR))),
      (lumG + (cosVal * (-lumG))) + (sinVal * lumG),
      (lumB + (cosVal * (1 - lumB))) + (sinVal * lumB),
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]).map((double i) => i.toDouble()).toList();
  }

  static List<double> brightnessAdjustMatrix({required double value}) {
    if (value <= 0) {
      value = value * 255;
    } else {
      value = value * 100;
    }

    if (value == 0) {
      return <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }

    return List<double>.from(<double>[1, 0, 0, 0, value, 0, 1, 0, 0, value, 0, 0, 1, 0, value, 0, 0, 0, 1, 0]).map((double i) => i.toDouble()).toList();
  }

  static List<double> saturationAdjustMatrix({required double value}) {
    value = value * 100;

    if (value == 0) {
      return <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }

    double x = ((1 + ((value > 0) ? ((3 * value) / 100) : (value / 100)))).toDouble();
    double lumR = 0.3086;
    double lumG = 0.6094;
    double lumB = 0.082;

    return List<double>.from(<double>[
      (lumR * (1 - x)) + x,
      lumG * (1 - x),
      lumB * (1 - x),
      0,
      0,
      lumR * (1 - x),
      (lumG * (1 - x)) + x,
      lumB * (1 - x),
      0,
      0,
      lumR * (1 - x),
      lumG * (1 - x),
      (lumB * (1 - x)) + x,
      0,
      0,
      0,
      0,
      0,
      1,
      0
    ]).map((double i) => i.toDouble()).toList();
  }
}

// #endregion
