// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import 'utils.dart';
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
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static Future<bool> fetchTray({bool sort = true}) async {
    final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
    final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
    final List<String> action = Boxes.pref.getStringList("actionTray") ?? <String>[];
    final List<TrayInfo> winTray = await enumTrayIcons();
    Map<int, int> oldIconHandles = <int, int>{};
    for (TrayBarInfo element in trayList) {
      oldIconHandles[element.hWnd] = element.hIcon;
    }
    trayList.clear();
    for (TrayInfo element in winTray) {
      HwndInfo processPath = HwndPath.getFullPath(GetAncestor(element.hWnd, 2));
      // print(processPath);
      String exe = Win32.getExe(processPath.path);
      // print(element.processID);
      final TrayBarInfo trayInfo = TrayBarInfo(clickOpensExe: false, processPath: processPath.path, processExe: exe);
      // print(trayInfo);
      trayInfo
        ..hIcon = element.hIcon
        ..uID = element.uID
        ..uCallbackMessage = element.uCallbackMessage
        ..hWnd = element.hWnd
        ..processID = element.processID
        ..isVisible = true //element.isVisible
        ..toolTip = element.toolTip;

      if (processPath.path.contains("explorer.exe")) trayInfo.isVisible = false;
      if (pinned.contains(exe)) trayInfo.isPinned = true;
      if (hidden.contains(exe)) trayInfo.isVisible = false;
      if (action.contains(exe)) trayInfo.clickOpensExe = true;

      if (__trayIconCache.containsKey(element.hWnd)) {
        if (__trayIconHandleCache[element.hWnd] != element.hIcon) {
          final Uint8List? icon = await getIconPng(element.hIcon);
          trayInfo.iconData = icon!;
          __trayIconCache[element.hWnd] = trayInfo.iconData;
          __trayIconHandleCache[element.hWnd] = element.hIcon; //? Fetch New
        } else {
          trayInfo.iconData = __trayIconCache[element.hWnd]!; //? Cache
        }
      } else {
        final Uint8List? icon = await getIconPng(element.hIcon); //? First Fetch
        trayInfo.iconData = icon!;
        __trayIconCache[element.hWnd] = trayInfo.iconData;
        __trayIconHandleCache[element.hWnd] = element.hIcon;
      }
      trayList.add(trayInfo);
    }
    __trayIconCache.removeWhere((int key, Uint8List value) => trayList.where((TrayBarInfo element) => element.hWnd == key).isEmpty);
    // order trayList by pinned and visible
    if (!sort) return true;
    trayList.sort((TrayBarInfo a, TrayBarInfo b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isVisible && !b.isVisible) return -1;
      if (!a.isVisible && b.isVisible) return 1;
      return 0;
    });
    return true;
  }
}
