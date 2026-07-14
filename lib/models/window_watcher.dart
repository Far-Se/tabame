// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:ffi/ffi.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import 'classes/boxes.dart';
import 'settings.dart';
import 'win32/imports.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';
import 'win32/win_utils.dart';
import 'win32/window.dart';

class WindowWatcher {
  WindowWatcher._();
  static bool firstEverRun = true;
  static List<Window> list = <Window>[];
  static Map<int, ExtractedIcon> icons = <int, ExtractedIcon>{};
  static Map<int, int> iconsHandles = <int, int>{};
  static Map<String, String> taskBarRewrites = Boxes.taskBarRewrites;
  static int _activeWinHandle = 0;
  static String taskManagerStats = "";
  static Object get active {
    if (list.length > _activeWinHandle) {
      return list[_activeWinHandle];
    } else {
      return 0;
    }
  }

  static bool fetching = false;

  static Future<bool> fetchWindows() async {
    if (fetching) return false;
    fetching = true;
    if (firstEverRun) Debug.add("QuickMenu: enumWindows");
    final List<int> winHWNDS = enumWindows();
    final List<int> allHWNDs = <int>[];
    if (winHWNDS.isEmpty) print("ENUM WINDS IS EMPTY");

    for (int hWnd in winHWNDS) {
      if (Win32.isWindowOnDesktop(hWnd) &&
          Win32.getTitle(hWnd).isNotEmpty &&
          hWnd != Win32.getMainHandle() &&
          !<String>["PopupHost"].contains(Win32.getTitle(hWnd))) {
        allHWNDs.add(hWnd);
      }
    }
    if (firstEverRun) Debug.add("QuickMenu: Wins ${allHWNDs.length}");
    final List<Window> newList = <Window>[];

    if (firstEverRun) Debug.add("QuickMenu: adding Win");
    for (int element in allHWNDs) {
      newList.add(Window(element));
    }

    List<TaskbarButtonInfo> taskbarItems = <TaskbarButtonInfo>[];
    if (Boxes.taskbarBadges.isNotEmpty) taskbarItems = await TaskbarUia.getButtonInfos();

    for (Window window in newList) {
      if (window.process.path == "" && (window.process.exe == "AccessBlocked.exe" || window.process.exe == "")) {
        window.process.exe = await getHwndName(window.hWnd);
      }
      if (window.process.exe == "Taskmgr.exe" && taskManagerStats != "") {
        window.title = taskManagerStats;
      }
      if (Boxes.taskBarRewrites.containsKey(window.process.exe)) {
        final TaskbarButtonInfo? result = taskbarItems
            .firstWhereOrNull((TaskbarButtonInfo b) => b.uiaName.contains(Boxes.taskBarRewrites[window.process.exe]!));
        if (result != null) {
          window.helpText = Boxes.taskBarRewrites[window.process.exe]!;
        }
      }
      for (MapEntry<String, String> rewrite in taskBarRewrites.entries) {
        final RegExp re = RegExp(rewrite.key, caseSensitive: false);
        if (re.hasMatch(window.title)) {
          window.title = window.title.replaceAllMapped(re, (Match match) {
            String replaced = rewrite.value;
            for (int x = 0; x < match.groupCount; x++) {
              replaced = replaced.replaceAll("\$${x + 1}", match.group(x + 1)!);
            }
            return replaced;
          });
        }
        if (window.title.contains(rewrite.key)) {
          window.title = window.title.replaceAll(rewrite.key, rewrite.value);
        }
      }
    }

    // Badge Monitoring
    final Map<String, List<String>> badgeRules = Boxes.taskbarBadges;
    if (badgeRules.isNotEmpty) {
      for (final MapEntry<String, List<String>> rule in badgeRules.entries) {
        if (rule.key.isEmpty || rule.value.isEmpty || rule.value[0].isEmpty) continue;
        final String targetExe = rule.key.toLowerCase();
        final String partialTitle = rule.value[0];
        final String hideRegex = rule.value.length > 1 ? rule.value[1] : "";

        for (Window window in newList) {
          if (window.process.exe.toLowerCase() == targetExe) {
            final TaskbarButtonInfo? badgeButton = taskbarItems
                .firstWhereOrNull((TaskbarButtonInfo b) => b.uiaName.contains(partialTitle) && b.helpText.isNotEmpty);
            if (badgeButton != null) {
              bool shouldHide = false;
              if (hideRegex.isNotEmpty) {
                try {
                  final RegExp re = RegExp(hideRegex, caseSensitive: false);
                  if (re.hasMatch(badgeButton.helpText)) {
                    shouldHide = true;
                  }
                } catch (_) {}
              }

              if (shouldHide) {
                window.helpText = "";
              } else {
                window.helpText = badgeButton.helpText;
              }
            }
          }
        }
      }
    }

    final int activeWindow = GetForegroundWindow();
    _activeWinHandle = newList.indexWhere((Window element) => element.hWnd == activeWindow);
    list = <Window>[...newList];

    if (_activeWinHandle > -1) {
      // Globals.lastFocusedWinHWND = list[_activeWinHandle].hWnd;
    }

    await handleIcons();
    await orderBy(user.taskBarAppsStyle);
    firstEverRun = false;
    return true;
  }

  static Future<bool> handleIcons() async {
    // Keep the cache scoped to currently-open windows only. Prune every cycle
    // (not just when the counts differ) so a window closing while another opens
    // — which leaves the counts equal — can't leave stale icon bytes behind.
    icons.removeWhere((int key, ExtractedIcon value) => !list.any((Window w) => w.hWnd == key));
    iconsHandles.removeWhere((int key, int value) => !list.any((Window w) => w.hWnd == key));

    for (Window win in list) {
      //?APPX
      if (icons.containsKey(win.hWnd) && win.isAppx) continue;
      if (win.isAppx) {
        if (win.appxIcon != "" && File(win.appxIcon).existsSync()) {
          icons[win.hWnd] = File(win.appxIcon).readAsBytesSync();
        } else {
          // Manifest logo couldn't be resolved (common for ApplicationFrameHost-
          // hosted apps) — fall back to the window's own HICON, the same icon
          // Windows shows in the title bar and the real taskbar, instead of the
          // blank placeholder. Left uncached on failure so a later cycle retries.
          final ExtractedIcon winIcon = WinUtils.windowIcon(win.hWnd);
          if (winIcon != null) icons[win.hWnd] = winIcon;
        }
        continue;
      }
      //?EXE
      bool fetchingIcon = false;
      if (!iconsHandles.containsKey(win.hWnd)) {
        fetchingIcon = true;
      } else if (iconsHandles[win.hWnd] != win.process.iconHandle) {
        fetchingIcon = true;
      }

      if (fetchingIcon) {
        icons[win.hWnd] = WinUtils.windowIcon(win.hWnd);
        if (<Object>[icons[win.hWnd] ?? 0].length == 3 || icons[win.hWnd] == null) {
          icons[win.hWnd] = WinUtils.extractIcon(win.process.path + win.process.exe);
          // printError(win.title);
        } else {
          // printWarning(win.title);
        }
        iconsHandles[win.hWnd] = win.process.iconHandle;
      }
    }
    return true;
  }

  static Future<bool> orderBy(TaskBarAppsStyle type) async {
    if (<TaskBarAppsStyle>[TaskBarAppsStyle.activeMonitorFirst, TaskBarAppsStyle.onlyActiveMonitor].contains(type)) {
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      // final Square rect = Win32.getWindowRect();
      // lpPoint.ref.x = rect.x;
      // lpPoint.ref.y = rect.y;
      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        if (type == TaskBarAppsStyle.activeMonitorFirst) {
          List<Window> firstItems = <Window>[];
          firstItems = list.where((Window element) => element.monitor == monitor ? true : false).toList();
          list.removeWhere((Window element) => firstItems.contains(element));
          list = firstItems + list;
        } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {
          list.removeWhere((Window element) => element.monitor != monitor);
        }
      }
    }
    fetching = false;
    return true;
  }

  static bool mediaControl(int index, {int button = AppCommand.mediaPlayPause}) {
    SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    return true;
  }

  static List<int> hierarchy = <int>[];
  static void hierarchyAdd(int hWnd) {
    if (hierarchy.contains(hWnd)) hierarchy.remove(hWnd);
    hierarchy.insert(0, hWnd);
    if (hierarchy.length != list.length) {
      final List<int> listHwnds = list.map((Window e) => e.hWnd).toList();
      hierarchy.removeWhere((int element) => !listHwnds.contains(element));
      hierarchy.addAll(listHwnds.where((int element) => !hierarchy.contains(element)).toList());
    }
  }

  static void focusSecondWindow() {
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        final List<int> hWnds = list
            .where((Window element) => element.monitor == monitor && !element.isPinned)
            .map((Window e) => e.hWnd)
            .toList();
        if (hWnds.length > 1) {
          final int h = hWnds[1];
          Win32.activateWindow(h);
          Future<void>.delayed(const Duration(milliseconds: 200), () {
            if (GetForegroundWindow() != h) {
              Win32.activateWindow(h);
            }
          });
          return;
        }
      }
    });
  }

  static void focusFirstWindow() {
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        final List<int> hWnds = list
            .where((Window element) => element.monitor == monitor && !element.isPinned)
            .map((Window e) => e.hWnd)
            .toList();
        if (hWnds.isNotEmpty) {
          final int h = hWnds[0];
          Win32.activateWindow(h);
          Future<void>.delayed(const Duration(milliseconds: 200), () {
            if (GetForegroundWindow() != h) {
              Win32.activateWindow(h);
            }
          });
          return;
        }
      }
    });
  }

  /// Shows the second window under the cursor.
  ///
  /// This function delays the execution for 100 milliseconds and then retrieves
  /// the current cursor position. It then checks if the cursor is within the
  /// boundaries of any windows and activates the second window found. If the
  /// second window cannot be activated, it waits for an additional 200
  /// milliseconds and tries again.
  static void showSecondWindowUnderCursor() {
    Win32.activeWindowUnderCursor();
    Future<void>.delayed(const Duration(milliseconds: 100), () async {
      await fetchWindows();
      if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final PointXY mousePos = PointXY(X: lpPoint.ref.x, Y: lpPoint.ref.y);

      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        final List<int> hWnds = list
            .where((Window element) => element.monitor == monitor && !element.isPinned)
            .map((Window e) => e.hWnd)
            .toList();
        if (hWnds.length > 1) {
          final int activeHandle = Win32.getActiveWindowHandle();
          //loop through hWnds and find the second one
          for (int i = 1; i < hWnds.length; i++) {
            final int h = hWnds[i];
            if (h == activeHandle) {
              continue;
            }
            final Square rect = Win32.getWindowRect(hwnd: h);
            if (mousePos.X.isBetween(rect.x, rect.x + rect.width) &&
                mousePos.Y.isBetween(rect.y, rect.y + rect.height)) {
              Win32.activateWindow(h);
              Future<void>.delayed(
                  const Duration(milliseconds: 200), () => GetForegroundWindow() != h ? Win32.activateWindow(h) : null);
              return;
            }
          }
          focusSecondWindow();
          return;
        }
        focusSecondWindow();
      }
    });
  }

  /// Activates the most recent window under the cursor.
  ///
  /// Queries every window at the current mouse position (top-most first in
  /// z-order) and activates the first one that is neither the currently active
  /// window nor Tabame's own window. This lets you "peel back" to the window
  /// sitting just beneath whatever is currently focused under the pointer.
  static void showLastWindowUnderCursor() async {
    await fetchWindows();
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final PointXY mousePos = PointXY(X: lpPoint.ref.x, Y: lpPoint.ref.y);
    free(lpPoint);

    final int activeHandle = Win32.getActiveWindowHandle();
    final int ownHandle = Win32.getMainHandle();

    for (final Window window in list) {
      final int h = window.hWnd;
      if (h == activeHandle || h == ownHandle) continue;
      final Square rect = Win32.getWindowRect(hwnd: h);
      if (mousePos.X.isBetween(rect.x, rect.x + rect.width) && mousePos.Y.isBetween(rect.y, rect.y + rect.height)) {
        Win32.activateWindow(h);
        Future<void>.delayed(
            const Duration(milliseconds: 200), () => GetForegroundWindow() != h ? Win32.activateWindow(h) : null);
        return;
      }
    }
  }
}
