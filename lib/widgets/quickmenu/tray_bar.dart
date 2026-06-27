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
  const TrayBar({super.key, this.wrapScroll = true});

  /// When false, only the row of tray icons is returned (no own scroll
  /// view/shader mask), so callers can splice it into a shared scrollable
  /// row (e.g. merging with the pinned apps bar).
  final bool wrapScroll;

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
    final Widget row = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final TrayBarInfo info in tray)
              GestureDetector(
                onSecondaryTap: () async {
                  // if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                  if (Boxes.pref.getStringList("postMessageTray")?.contains(info.processExe) ?? false) {
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDOWN);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONDBLCLK);
                    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_RBUTTONUP);
                  } else {
                    sendTrayClick(info, TrayClickType.right);
                  }
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
                  if (Boxes.pref.getStringList("postMessageTray")?.contains(info.processExe) ?? false) {
                    WinTray.click(info, clickType: TrayClickType.middle);
                  } else {
                    sendTrayClick(info, TrayClickType.middle);
                  }
                },
                child: InkWell(
                  hoverColor: Design.text.withAlpha(30),
                  borderRadius: BorderRadius.circular(3),
                  onTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
                    if (Boxes.pref.getStringList("postMessageTray")?.contains(info.processExe) ?? false) {
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDOWN);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                    } else {
                      sendTrayClick(info, TrayClickType.left);
                    }
                  },
                  onDoubleTap: () async {
                    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();

                    if (Boxes.pref.getStringList("postMessageTray")?.contains(info.processExe) ?? false) {
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDOWN);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDBLCLK);
                      PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
                    } else {
                      sendTrayClick(info, TrayClickType.doubleClick);
                    }
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
        );
    if (!widget.wrapScroll) return row;
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
        // hardEdge: avoids the anti-aliased saveLayer clip that wobbles on
        // re-raster for this fractionally-offset, right-aligned bar.
        clipBehavior: Clip.hardEdge,
        child: row,
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
/// icon's registered version, unlike yasb/systray's `IconWidget.send_action`
/// (systray_widget.py), which intercepts `NIM_SETVERSION` and so always sends
/// the one correct wParam/lParam layout. To compensate:
///   1. We grant the owning process foreground rights first — otherwise
///      Windows' foreground lock silently swallows the context menu / window
///      the app tries to show (this is the main reason right-clicks were a
///      "hit or miss" with raw PostMessage).
///   2. Raw button messages are sent ONCE using the legacy layout (the
///      un-versioned default most apps still use). Sending both the legacy
///      and V4 layouts back-to-back looked harmless, but apps that crack the
///      message with `LOWORD(lParam)` (a very common idiom) read the
///      notification code out of *either* layout and process the click
///      twice — e.g. qBittorrent's window would restore but render blank
///      until manually minimized/restored, because the second toggle raced
///      the first window-show before it had finished painting.
///   3. After button-up we additionally send `NIN_SELECT` / `NIN_CONTEXTMENU`
///      using the V4 (coord-packed) layout — these are V3+-only notification
///      codes that legacy apps don't recognize, so there's no double-trigger
///      risk in sending just the one layout for them.
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
  }

  void deliverNotify(int message) {
    // V4 layout: wParam = cursor (x, y), lParam = (message, uID).
    SendNotifyMessage(info.hWnd, info.uCallbackMsg, _packCoord(cx, cy), _packCoord(message, info.uID));
  }

  switch (clickType) {
    case TrayClickType.left:
      deliver(WM_LBUTTONDOWN);
      deliver(WM_LBUTTONUP);
      deliverNotify(_kNinSelect);
      break;
    case TrayClickType.right:
      deliver(WM_RBUTTONDOWN);
      deliver(WM_RBUTTONUP);
      deliverNotify(_kNinContextMenu);
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
