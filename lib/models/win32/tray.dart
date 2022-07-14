// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';

import 'win32.dart';

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

class Tray {
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static bool newTray = false;
  static Future<bool> fetchTray() async {
    final List<TrayInfo> winTray = await enumTrayIcons();
    newTray = true;
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

      // if (Boxes.traySettings.containsKey(exe)) {
      //   final box = Boxes.traySettings.get(exe) as TraySettings;

      //   trayInfo.isVisible = box.visible;
      //   trayInfo.executionType = box.executionType;
      // }

      trayList.add(trayInfo);
    }

    final List<int> handles = trayList.map((TrayBarInfo e) => e.hIcon).toList();
    final List<Uint8List> iconOutput = await WinIcons().getHandleIcons(handles);
    if (handles.length == iconOutput.length) {
      for (int x = 0; x < handles.length; x++) {
        final TrayBarInfo trayInfo = trayList[x];
        trayInfo.iconData = iconOutput[x];
        __trayIconCache[trayInfo.hWnd] = iconOutput[x];
      }
    } else {
      for (TrayBarInfo trayInfo in trayList) {
        if (__trayIconCache.containsKey(trayInfo.hWnd)) {
          trayInfo.iconData = __trayIconCache[trayInfo.hWnd]!;
        }
      }
    }
    return newTray;
  }
}
