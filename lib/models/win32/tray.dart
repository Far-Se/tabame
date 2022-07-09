// ignore_for_file: public_member_api_docs, sort_constructors_first
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
}

final __brightnessCache = <int, int>{};

class Tray {
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static bool newTray = false;
  static Future<bool> fetchTray() async {
    final winTray = await enumTrayIcons();
    newTray = true;
    trayList.clear();

    for (var element in winTray) {
      String processPath = HwndPath().getProcessExePath(element.processID);
      String exe = Win32.getExe(processPath);

      final trayInfo = TrayBarInfo(executionType: 1, processPath: processPath, processExe: exe);

      trayInfo
        ..hIcon = element.hIcon
        ..uID = element.uID
        ..uCallbackMessage = element.uCallbackMessage
        ..hWnd = element.hWnd
        ..processID = element.processID
        ..isVisible = element.isVisible
        ..toolTip = element.toolTip;
      if (processPath.contains("explorer.exe")) trayInfo.isVisible = false;

      if (__brightnessCache.containsKey(trayInfo.hWnd)) {
        trayInfo.brightness = __brightnessCache[trayInfo.hWnd]!;
      } else {
        final image = await decodeImageFromList(trayInfo.hIcon);

        var data = trayInfo.hIcon;
        var colorSum = 0;
        for (var x = 0; x < data.length; x += 4) {
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
