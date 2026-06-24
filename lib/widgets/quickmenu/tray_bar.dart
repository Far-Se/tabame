// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

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
  // static const bool _useSystrayAlternative = true;
  Timer? mainTimer;
  List<TrayBarInfo> tray = <TrayBarInfo>[];
  bool fetching = false;

  void fetchActiveTray() {
    if (user.trayBarAlternative) {
      fetchSystrayTray();
    } else {
      fetchTray();
    }
  }

  void fetchTray() async {
    fetching = true;
    await TrayWatcher.fetchTray();
    fetching = false;
    tray = <TrayBarInfo>[...TrayWatcher.trayList.where((TrayBarInfo element) => element.isVisible)];

    if (mounted) setState(() {});
  }

  void fetchSystrayTray() async {
    fetching = true;
    final bool fetched = await SystrayWatcher.fetchTray();
    fetching = false;
    tray = fetched
        ? <TrayBarInfo>[...SystrayWatcher.trayList.where((TrayBarInfo element) => element.isVisible)]
        : <TrayBarInfo>[];

    if (mounted) setState(() {});
  }

  void init() {
    QuickMenuFunctions.addListener(this);
    fetchActiveTray();
    // mainTimer = Timer.periodic(const Duration(milliseconds: 600), checkForNewTrayIcons);
    Debug.add("QuickMenu: Tray");
  }

  void checkForNewTrayIcons(Timer timer) async {
    // if (!QuickMenuFunctions.isQuickMenuVisible && kReleaseMode) return;
    if (QuickMenuFunctions.isQuickMenuVisible) {
      // PaintingBinding.instance.imageCache.clear();
      if (!fetching) fetchActiveTray();
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (type != QuickMenuPage.quickMenu) return;
    if (visible) {
      fetchActiveTray();
      mainTimer?.cancel();
      mainTimer = Timer.periodic(const Duration(milliseconds: 600), checkForNewTrayIcons);
    } else {
      mainTimer?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    if (!mounted) return;
    init();
  }

  @override
  void dispose() {
    // PaintingBinding.instance.imageCache.clear();
    QuickMenuFunctions.removeListener(this);
    if (user.trayBarAlternative) unawaited(SystrayWatcher.stop());
    mainTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (tray.isEmpty || !user.showTrayBar) return Container();
    Theme.of(context);
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
                  // sendTrayClick(info, TrayClickType.right);
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
                  hoverColor: Design.text.withAlpha(30),
                  borderRadius: BorderRadius.circular(3),
                  onTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                    sendSimpleClick(info, TrayClickType.left);
                    // sendTrayClick(info, TrayClickType.left);
                  },
                  onDoubleTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                    // sendTrayClick(info, TrayClickType.doubleClick);

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
                          ? Image.file(File(Boxes.getIconRewrite(info.processPath)), width: 20)
                          // Packaged (Appx/UWP) apps: prefer the manifest logo resolved in
                          // TrayWatcher.fetchTray. It's the only icon source that survives
                          // running Tabame elevated (shell/HICON paths don't).
                          : (info.iconData.length == 1
                              ? fallBackImage(info)
                              : Image.memory(
                                  info.iconData,
                                  cacheWidth: 32,
                                  fit: BoxFit.scaleDown,
                                  gaplessPlayback: true,
                                  width: 16.1,
                                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                      fallBackImage(info),
                                )),
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 5.1),
          ],
        ),
      ),
    );
  }

  Widget fallBackImage(TrayBarInfo info) {
    return info.appxIconPath != ""
        ? Image.file(
            File(info.appxIconPath),
            fit: BoxFit.scaleDown,
            gaplessPlayback: true,
            width: 16.1,
            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                const Icon(Icons.check_box_outline_blank, size: 16),
          )
        : const Icon(Icons.check_box_outline_blank, size: 16);
  }
}

// Modern shell notification codes — not reliably exported by package:win32, so
// pinned to their documented literal values.
const int _kNinSelect = 0x0400; // WM_USER + 0  (V3+ left-click "select")
const int _kNinContextMenu = 0x007B; // == WM_CONTEXTMENU (V3+ right-click)

/// Packs two 16-bit values into a 32-bit MAKELPARAM/MAKEWPARAM word.
int _packCoord(int low, int high) => (low & 0xFFFF) | ((high & 0xFFFF) << 16);

/// Delivers a tray-icon mouse interaction the way Explorer itself does, so it
/// works across both legacy (`NOTIFYICON_VERSION` ≤ 3) and modern
/// (`NOTIFYICON_VERSION_4`) apps.
///
/// We read icons straight off the tray toolbar and therefore don't know each
/// icon's registered version, so:
///   1. We grant the owning process foreground rights first — otherwise
///      Windows' foreground lock silently swallows the context menu / window
///      the app tries to show (this is the main reason right-clicks were a
///      "hit or miss" with raw PostMessage).
///   2. We send BOTH the legacy and the V4 wParam/lParam layouts. Each app only
///      recognizes the layout matching its own version and ignores the other,
///      so there's no double-trigger.
///   3. After button-up we send `NIN_SELECT` / `NIN_CONTEXTMENU`, which V3+ apps
///      act on instead of the raw `WM_*BUTTONUP`.
///
/// Mirrors yasb/systray's `IconWidget.send_action` (systray_widget.py).
void sendTrayClick(TrayBarInfo info, TrayClickType clickType) {
  if (info.hWnd == 0 || info.uCallbackMsg == 0) return;

  final Pointer<POINT> point = calloc<POINT>();
  GetCursorPos(point);
  final int cx = point.ref.x;
  final int cy = point.ref.y;
  free(point);

  // Lift the foreground lock for the owning process so its menu can appear.
  if (info.processId != 0) AllowSetForegroundWindow(info.processId);

  void deliver(int message) {
    // Legacy layout: wParam = uID, lParam = message.
    SendNotifyMessage(info.hWnd, info.uCallbackMsg, info.uID, _packCoord(message, 0));
    // V4 layout: wParam = cursor (x, y), lParam = (message, uID).
    SendNotifyMessage(info.hWnd, info.uCallbackMsg, _packCoord(cx, cy), _packCoord(message, info.uID));
  }

  switch (clickType) {
    case TrayClickType.left:
      deliver(WM_LBUTTONDOWN);
      deliver(WM_LBUTTONUP);
      deliver(_kNinSelect);
      break;
    case TrayClickType.right:
      deliver(WM_RBUTTONDOWN);
      deliver(WM_RBUTTONUP);
      deliver(_kNinContextMenu);
      break;
    case TrayClickType.middle:
      deliver(WM_MBUTTONDOWN);
      deliver(WM_MBUTTONUP);
      break;
    case TrayClickType.doubleClick:
      deliver(WM_LBUTTONDBLCLK);
      break;
  }
}

void sendSimpleClick(ExtendedTrayIcon element, TrayClickType clickType) async {
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
