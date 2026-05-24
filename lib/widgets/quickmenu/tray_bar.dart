// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/tray_watcher.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/windows_scroll.dart';

class TrayBar extends StatefulWidget {
  const TrayBar({super.key});

  @override
  // ignore: library_private_types_in_public_api
  TrayBarState createState() => TrayBarState();
}

class TrayBarState extends State<TrayBar> with QuickMenuTriggers {
  late Timer mainTimer;
  List<TrayBarInfo> tray = <TrayBarInfo>[];
  bool fetching = false;
  void fetchTray() async {
    fetching = true;
    await Tray.fetchTray();
    fetching = false;
    tray = <TrayBarInfo>[...Tray.trayList.where((TrayBarInfo element) => element.isVisible)];

    if (mounted) setState(() {});
  }

  void init() {
    QuickMenuFunctions.addListener(this);
    fetchTray();
    mainTimer = Timer.periodic(const Duration(milliseconds: 600), checkForNewTrayIcons);
    Debug.add("QuickMenu: Tray");
  }

  void checkForNewTrayIcons(Timer timer) async {
    // if (!QuickMenuFunctions.isQuickMenuVisible && kReleaseMode) return;
    if (QuickMenuFunctions.isQuickMenuVisible) {
      // PaintingBinding.instance.imageCache.clear();
      if (!fetching) fetchTray();
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (type != QuickMenuPage.quickMenu) return;
    if (visible) {
      fetchTray();
    } else {}
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
    QuickMenuFunctions.removeListener(this);
    mainTimer.cancel();
    super.dispose();
  }

  void sendClick(ExtendedTrayIcon element, TrayClickType clickType) async {
    final Pointer<POINT> point = calloc<POINT>();
    GetCursorPos(point);
    final int x = point.ref.x;
    final int y = point.ref.y;
    free(point);
    WinTray.click(element, clickType: TrayClickType.left);
    // interval 10ms move mosue back to pos
    await Future<void>.delayed(const Duration(milliseconds: 400));
    SetCursorPos(x, y);
  }

  @override
  Widget build(BuildContext context) {
    if (tray.isEmpty || !userSettings.showTrayBar) return Container();
    return ShaderMask(
      shaderCallback: (Rect rect) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
          stops: <double>[0.0, 0.93, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstOut,
      child: WindowsScrollView(
        scrollDirection: Axis.horizontal,
        showScrollbar: false,
        child: Row(
          children: <Widget>[
            for (final TrayBarInfo info in tray)
              GestureDetector(
                onSecondaryTap: () async {
                  if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                  // WinTray.click(info, clickType: TrayClickType.right);
                  // final List<TrayInfo> icons = await enumTrayIcons();
                  // final TrayInfo? thisTray = icons.firstWhereOrNull((TrayInfo e) => e.processID == info.processID);
                  // int hWnd = info.hWnd;
                  // if (thisTray != null) {
                  //   // hWnd = thisTray.hWnd;
                  //   print(<int>{info.uCallbackMessage, thisTray.uCallbackMessage});
                  //   print(<int>{info.uID, thisTray.uID});
                  // }
                  PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                  PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDOWN);
                  PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                  PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDBLCLK);
                  PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                },
                onLongPress: () {
                  if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                  WinUtils.openAndFocus(info.processPath, centered: true, usePowerShell: true);
                },
                onSecondaryLongPress: () async {
                  if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                  WinTray.click(info, clickType: TrayClickType.right);
                },
                onTertiaryTapUp: (TapUpDetails e) {
                  if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                  WinTray.click(info, clickType: TrayClickType.middle);
                },
                child: InkWell(
                  onTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                    sendClick(info, TrayClickType.left);
                  },
                  onDoubleTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();

                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDOWN);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDBLCLK);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2.2),
                    child: CustomTooltip(
                        message: info.processExe,
                        child: Boxes.getIconRewrite(info.processPath) != ""
                            ? Image.asset(Boxes.getIconRewrite(info.processPath), width: 20)
                            : Image.memory(
                                info.iconData,
                                fit: BoxFit.scaleDown,
                                gaplessPlayback: true,
                                width: 16.1,
                                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                    const Icon(
                                  Icons.check_box_outline_blank,
                                  size: 16,
                                ),
                              )),
                  ),
                ),
              ),
            const SizedBox(width: 5.1),
          ],
        ),
      ),
    );
  }
}
