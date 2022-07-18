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

    return other is TrayBarInfo && other.executionType == executionType && other.processPath == processPath && other.processExe == processExe;
  }

  @override
  int get hashCode {
    return executionType.hashCode ^ processPath.hashCode ^ processExe.hashCode;
  }
}

Map<int, Uint8List> __trayIconCache = <int, Uint8List>{};
Map<int, int> __trayIconHandleCache = <int, int>{};

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
    return newTray;
  }
}
