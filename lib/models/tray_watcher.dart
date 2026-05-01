// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import 'classes/boxes.dart';
import 'win32/win32.dart';
import 'win32/win_utils.dart';
import 'window_watcher.dart';

class TrayBarInfo extends ExtendedTrayIcon {
  String processPath = "";
  String processExe = "";
  int brightness = 0;
  bool isPinned = false;
  Uint8List iconData = Uint8List.fromList(<int>[0]);
  TrayBarInfo({
    required this.processPath,
    required this.processExe,
    required super.toolTip,
    required super.processId,
    required super.hWnd,
    required super.uID,
    required super.uCallbackMsg,
    required super.hIcon,
    required super.isVisible,
    required super.isOverflow,
  });

  int get processID => processId;

  int get uCallbackMessage => uCallbackMsg;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrayBarInfo && other.processPath == processPath && other.processExe == processExe;
  }

  @override
  int get hashCode {
    return processPath.hashCode ^ processExe.hashCode;
  }

  @override
  String toString() {
    return 'TrayBarInfo(processPath: $processPath, processExe: $processExe, brightness: $brightness)';
  }
}

Map<int, Uint8List> __trayIconCache = <int, Uint8List>{};
Map<int, int> __trayIconHandleCache = <int, int>{};

int _trayIconCacheKey(ExtendedTrayIcon icon) {
  return Object.hash(icon.hWnd, icon.uID, icon.uCallbackMsg, icon.isOverflow);
}

class Tray {
  Tray._();
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static final Map<int, TrayBarInfo> _trayCache = <int, TrayBarInfo>{};

  static Future<bool> fetchTray({bool sort = true}) async {
    final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
    final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
    final List<ExtendedTrayIcon> winTray = await WinTray.enumAllIcons();

    final List<TrayBarInfo> newList = <TrayBarInfo>[];
    final Set<int> activeIconKeys = <int>{};
    final Set<int> processIds = <int>{};
    int taskManagerProcessId = -1;
    for (ExtendedTrayIcon element in winTray) {
      if (element.toolTip == "Task Manager") {
        taskManagerProcessId = element.processId;
      } else if (taskManagerProcessId == element.processId) {
        if (element.toolTip != "Task Manager") {
          WindowWatcher.taskManagerStats = element.toolTip
              .replaceAll("\n", ' ')
              .replaceAll(RegExp(r' +'), ' ')
              .replaceFirst('Memory', "RAM")
              .replaceAll("Network", "NET")
              .replaceAll("Disk", "DISK");
          // print(element.toolTip);
        }
      }
      if (processIds.contains(element.processId)) continue;
      processIds.add(element.processId);
      final int hWnd = element.hWnd;
      final int iconKey = _trayIconCacheKey(element);
      activeIconKeys.add(iconKey);

      final String processExePath = Win32.getProcessExePath(element.processId);
      HwndInfo processPath = HwndInfo(path: processExePath, isAppx: false);
      if (processPath.path.isEmpty && hWnd != 0) {
        final int ancestor = GetAncestor(hWnd, 2);
        processPath = HwndPath.getFullPath(ancestor != 0 ? ancestor : hWnd);
      }
      String exe = Win32.getExe(processPath.path);

      // Skip background/system items that aren't real tray icons or are explorer junk
      if (processPath.path.contains("explorer.exe") && element.toolTip.isEmpty) continue;

      final TrayBarInfo? cachedTrayInfo = _trayCache[iconKey];
      final TrayBarInfo trayInfo = TrayBarInfo(
        processPath: processPath.path,
        processExe: exe,
        toolTip: element.toolTip,
        processId: element.processId,
        hWnd: hWnd,
        uID: element.uID,
        uCallbackMsg: element.uCallbackMsg,
        hIcon: element.hIcon,
        isVisible: !hidden.contains(exe) && !processPath.path.contains("explorer.exe"),
        isOverflow: element.isOverflow,
      )..isPinned = pinned.contains(exe);

      if (cachedTrayInfo != null) {
        trayInfo.iconData = cachedTrayInfo.iconData;
      }

      // Only load/update icon if the item is visible and the icon handle changed
      if (trayInfo.isVisible) {
        if (__trayIconHandleCache[iconKey] != element.hIcon || trayInfo.iconData.length <= 1) {
          try {
            final Uint8List? icon = WinUtils.hIconToBytes(element.hIcon);
            trayInfo.iconData = icon ?? Uint8List.fromList(<int>[0]);
            __trayIconCache[iconKey] = trayInfo.iconData;
            __trayIconHandleCache[iconKey] = element.hIcon;
          } catch (e) {
            // Silently fail for individual icons
          }
        }
      } else {
        // If invisible, clear heavy icon data from the object (keep it in global cache if needed later)
        trayInfo.iconData = Uint8List.fromList(<int>[0]);
      }

      _trayCache[iconKey] = trayInfo;
      newList.add(trayInfo);
    }
    if (taskManagerProcessId == -1) WindowWatcher.taskManagerStats = '';

    // Efficient cleanup of stale items
    _trayCache.removeWhere((int key, _) => !activeIconKeys.contains(key));
    __trayIconCache.removeWhere((int key, _) => !activeIconKeys.contains(key));
    __trayIconHandleCache.removeWhere((int key, _) => !activeIconKeys.contains(key));

    trayList = newList;

    if (sort) {
      trayList.sort((TrayBarInfo a, TrayBarInfo b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        if (a.isVisible && !b.isVisible) return -1;
        if (!a.isVisible && b.isVisible) return 1;
        return 0;
      });
    }

    return true;
  }
}
