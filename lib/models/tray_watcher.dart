// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import 'classes/boxes.dart';
import 'win32/win32.dart';

class TrayBarInfo extends TrayInfo {
  bool clickOpensExe = false;
  String processPath = "";
  String processExe = "";
  int brightness = 0;
  bool isPinned = false;
  Uint8List iconData = Uint8List.fromList(<int>[0]);
  TrayBarInfo({
    required this.clickOpensExe,
    required this.processPath,
    required this.processExe,
  }) : super();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrayBarInfo && other.clickOpensExe == clickOpensExe && other.processPath == processPath && other.processExe == processExe;
  }

  @override
  int get hashCode {
    return clickOpensExe.hashCode ^ processPath.hashCode ^ processExe.hashCode;
  }

  @override
  String toString() {
    return 'TrayBarInfo(executionType: $clickOpensExe, processPath: $processPath, processExe: $processExe, brightness: $brightness)';
  }
}

Map<int, Uint8List> __trayIconCache = <int, Uint8List>{};
Map<int, int> __trayIconHandleCache = <int, int>{};

class Tray {
  Tray._();
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static final Map<int, TrayBarInfo> _trayCache = <int, TrayBarInfo>{};

  static Future<bool> fetchTray({bool sort = true}) async {
    final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
    final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
    final List<String> action = Boxes.pref.getStringList("actionTray") ?? <String>[];
    final List<TrayInfo> winTray = await enumTrayIcons();

    final List<TrayBarInfo> newList = <TrayBarInfo>[];
    final Set<int> activeHwnds = <int>{};

    for (TrayInfo element in winTray) {
      final int hWnd = element.hWnd;
      activeHwnds.add(hWnd);

      HwndInfo processPath = HwndPath.getFullPath(GetAncestor(hWnd, 2));
      String exe = Win32.getExe(processPath.path);

      // Skip background/system items that aren't real tray icons or are explorer junk
      if (processPath.path.contains("explorer.exe") && element.toolTip.isEmpty) continue;

      // Reuse existing object if possible to save memory/allocations
      TrayBarInfo trayInfo = _trayCache[hWnd] ?? TrayBarInfo(clickOpensExe: false, processPath: processPath.path, processExe: exe);

      trayInfo
        ..hIcon = element.hIcon
        ..uID = element.uID
        ..uCallbackMessage = element.uCallbackMessage
        ..hWnd = hWnd
        ..processID = element.processID
        ..isVisible = !hidden.contains(exe) && !processPath.path.contains("explorer.exe")
        ..toolTip = element.toolTip
        ..isPinned = pinned.contains(exe)
        ..clickOpensExe = action.contains(exe);

      // Only load/update icon if the item is visible and the icon handle changed
      if (trayInfo.isVisible) {
        if (__trayIconHandleCache[hWnd] != element.hIcon || trayInfo.iconData.length <= 1) {
          try {
            final Uint8List? icon = WinUtils.hIconToBytes(element.hIcon);
            trayInfo.iconData = icon ?? Uint8List.fromList(<int>[0]);
            __trayIconCache[hWnd] = trayInfo.iconData;
            __trayIconHandleCache[hWnd] = element.hIcon;
          } catch (e) {
            // Silently fail for individual icons
          }
        }
      } else {
        // If invisible, clear heavy icon data from the object (keep it in global cache if needed later)
        trayInfo.iconData = Uint8List.fromList(<int>[0]);
      }

      _trayCache[hWnd] = trayInfo;
      newList.add(trayInfo);
    }

    // Efficient cleanup of stale items
    _trayCache.removeWhere((int key, _) => !activeHwnds.contains(key));
    __trayIconCache.removeWhere((int key, _) => !activeHwnds.contains(key));
    __trayIconHandleCache.removeWhere((int key, _) => !activeHwnds.contains(key));

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
