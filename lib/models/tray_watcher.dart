// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';

import 'win32/win32.dart';

class TrayBarInfo extends TrayInfo {
  int executionType = 0;
  String processPath = "";
  String processExe = "";
  int brightness = 0;
  Uint8List iconData = Uint8List.fromList(<int>[0]);
  TrayBarInfo({
    required this.executionType,
    required this.processPath,
    required this.processExe,
  }) : super();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrayBarInfo &&
        other.executionType == executionType &&
        other.processPath == processPath &&
        other.processExe == processExe &&
        other.brightness == brightness;
  }

  @override
  int get hashCode {
    return executionType.hashCode ^ processPath.hashCode ^ processExe.hashCode ^ brightness.hashCode;
  }
}

Map<int, Uint8List> __trayIconCache = <int, Uint8List>{};
Map<int, int> __trayIconCacheHandle = <int, int>{};

class Tray {
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static bool newTray = false;
  static Future<bool> fetchTray() async {
    final List<TrayInfo> winTray = await enumTrayIcons();
    newTray = true;
    Map<int, int> oldIconHandles = <int, int>{};
    for (TrayBarInfo element in trayList) {
      oldIconHandles[element.hWnd] = element.hIcon;
    }
    trayList.clear();
    final Map<int, int> handlesToFetch = <int, int>{};
    for (TrayInfo element in winTray) {
      HwndInfo processPath = HwndPath.getFullPath(element.processID);
      String exe = Win32.getExe(processPath.path);

      final TrayBarInfo trayInfo = TrayBarInfo(executionType: 1, processPath: processPath.path, processExe: exe);
      trayInfo
        ..hIcon = element.hIcon
        ..uID = element.uID
        ..uCallbackMessage = element.uCallbackMessage
        ..hWnd = element.hWnd
        ..processID = element.processID
        ..isVisible = element.isVisible
        ..toolTip = element.toolTip;
      if (processPath.path.contains("explorer.exe")) trayInfo.isVisible = false;
      if (__trayIconCacheHandle.containsKey(element.hWnd)) {
        if (__trayIconCacheHandle[element.hWnd] != element.hIcon) {
          handlesToFetch[trayList.length] = element.hIcon;
          __trayIconCacheHandle[element.hWnd] = element.hIcon;
        } else {
          if (__trayIconCache.containsKey(element.hWnd)) {
            trayInfo.iconData = __trayIconCache[element.hWnd]!;
          }
        }
      } else {
        handlesToFetch[trayList.length] = element.hIcon;
        __trayIconCacheHandle[element.hWnd] = element.hIcon;
      }

      trayList.add(trayInfo);
    }
    if (handlesToFetch.isNotEmpty) {
      final List<Uint8List> result = await WinIcons().getHandleIcons(handlesToFetch.values.toList());
      int i = 0;
      if (result.length == handlesToFetch.keys.length) {
        for (int key in handlesToFetch.keys) {
          trayList[key].iconData = result[i];
          __trayIconCache[trayList[key].hWnd] = result[i];
          i++;
        }
      }
    }
    __trayIconCache.removeWhere((int key, Uint8List value) => trayList.where((TrayBarInfo element) => element.hWnd == key).isEmpty);
    return newTray;
  }
}
