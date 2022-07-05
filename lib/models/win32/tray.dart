// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:tabamewin32/tabamewin32.dart';

import '../boxes.dart';
import '../utils.dart';
import 'win32.dart';

class TrayBarInfo extends TrayInfo {
  int executionType = 0;
  String processPath = "";
  String processExe = "";
  TrayBarInfo({
    required this.executionType,
    required this.processPath,
    required this.processExe,
  }) : super();
}

class Tray {
  static List<TrayBarInfo> tray = <TrayBarInfo>[];

  static Future<List<TrayBarInfo>> fetchTray() async {
    final newTray = await enumTrayIcons();

    if (newTray.length == tray.length) {
      return tray;
    }

    tray.clear();

    for (var element in newTray) {
      String processPath = HwndPath().getWindowExePath(element.hWnd);
      String exe = Win32.getExe(processPath);

      final trayInfo = TrayBarInfo(executionType: 1, processPath: processPath, processExe: exe);

      trayInfo
        ..hIcon = element.hIcon
        ..uID = element.uID
        ..uCallbackMessage = element.uCallbackMessage
        ..hWnd = element.hWnd
        ..isVisible = element.isVisible;

      if (processPath.contains("explorer.exe")) trayInfo.isVisible = false;

      if (Boxes.traySettings.containsKey(exe)) {
        final box = Boxes.traySettings.get(exe) as TraySettings;

        trayInfo.isVisible = box.visible;
        trayInfo.executionType = box.executionType;
      }

      tray.add(trayInfo);
    }
    return tray;
  }
}
