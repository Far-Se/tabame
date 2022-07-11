// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'package:tabamewin32/tabamewin32.dart';

import 'win32.dart';

class TrayBarInfo extends TrayInfo {
  int executionType = 0;
  String processPath = "";
  String processExe = "";
  int brightness = 0;
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

final Map<int, int> __brightnessCache = <int, int>{};

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

      if (__brightnessCache.containsKey(trayInfo.hWnd)) {
        trayInfo.brightness = __brightnessCache[trayInfo.hWnd]!;
      } else {
        // ignore: always_specify_types
        final image = await decodeImageFromList(trayInfo.hIcon);

        Uint8List data = trayInfo.hIcon;
        int colorSum = 0;
        for (int x = 0; x < data.length; x += 4) {
          int r = data[x];
          int g = data[x + 1];
          int b = data[x + 2];
          int avg = ((r + g + b) / 3).floor();
          colorSum += avg;
        }
        trayInfo.brightness = (colorSum / (image.width * image.height)).floor();
      }
      // print("${trayInfo.processExe}: ${trayInfo.brightness}");
      // if (Boxes.traySettings.containsKey(exe)) {
      //   final box = Boxes.traySettings.get(exe) as TraySettings;

      //   trayInfo.isVisible = box.visible;
      //   trayInfo.executionType = box.executionType;
      // }

      trayList.add(trayInfo);
    }
    return newTray;
  }
}
