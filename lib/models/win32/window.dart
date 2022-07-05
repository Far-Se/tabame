import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import '../utils.dart';

import 'win32.dart';

class Appearance {
  int? monitor;
  int? heirarchy;
  bool? visible;
  bool? cloaked;
  RECT? position;
  Point? size;
  bool isMinimized = false;

  @override
  String toString() {
    return 'Appearance(monitor: $monitor, heirarchy: $heirarchy, visible: $visible, cloaked: $cloaked, position: $position, size: $size, isMinimized: $isMinimized)';
  }
}

class Window {
  int hWnd;
  String title = "";
  HProcess process = HProcess();
  Appearance appearance = Appearance();
  bool isAppx = false;
  String appxIcon = "";
  String toJson() {
    var encoder = const JsonEncoder.withIndent("");
    return encoder.convert({'title': title.toString().truncate(20, suffix: '...'), 'path': process.path, 'exe': process.exe, 'class': process.className});
  }

  Window(this.hWnd) {
    getHandles();
    getTitle();
    getWorkspace();
    getPath();
    if (isAppx) {
      getManifestIcon();
    }
  }

  getHandles() {
    final pId = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, pId);
    process.mainPID = pId.value;
    free(pId);
    process.pId = HwndPath().getRealPID(hWnd);
    process.className = Win32.getClass(hWnd);
  }

  getTitle() {
    title = Win32.getTitle(hWnd);
  }

  getWorkspace() {
    appearance.visible = Win32.isWindowPresent(hWnd);
    appearance.cloaked = Win32.isWindowCloaked(hWnd);
    appearance.monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTOPRIMARY);
  }

  getPath() {
    Map<String, dynamic> pathInfo = HwndPath().getFullPath(hWnd);
    process.path = pathInfo["path"];
    isAppx = pathInfo["isAppx"];

    if (process.path == "") process.exe = "AccessBlocked.exe";
    if (process.path.contains("/") == true) {
      process.exe = process.path.substring(process.path.lastIndexOf('/') + 1);
    } else if (process.path.contains("\\") == true) {
      process.exe = process.path.substring(process.path.lastIndexOf('\\') + 1);
    }
    process.path = process.path.replaceAll(process.exe, "");
  }

  getManifestIcon() {
    String appxLocation = process.path;
    if (!process.exe.contains("exe")) appxLocation += "${process.exe}\\";
    // appxLocation += "AppxManifest.xml";
    if (File("${appxLocation}AppxManifest.xml").existsSync()) {
      final manifest = File("${appxLocation}AppxManifest.xml").readAsStringSync();
      //regex match Square44x44Logo="(.*?)"
      String icon = "";
      if (manifest.contains("Square44x44Logo")) {
        icon = manifest.split("Square44x44Logo=\"")[1].split("\"")[0];
      } else if (manifest.contains("Square150x150Logo")) {
        icon = manifest.split("Square150x150Logo=\"")[1].split("\"")[0];
      } else if (manifest.contains("Logo")) {
        icon = manifest.split("Logo=\"")[1].split("\"")[0];
      } else {
        icon = "";
      }
      appxIcon = "$appxLocation$icon";
      final scale100 = appxIcon.replaceFirst(".png", ".scale-100.png");
      if (File(scale100).existsSync()) {
        appxIcon = scale100;
      } else {
        final appxIcon2 = appxIcon.replaceFirst(".png", ".targetsize-32.png");
        if (File(appxIcon2).existsSync()) {
          appxIcon = appxIcon2;
        } else {
          final appxIcon2 = appxIcon.replaceFirst(".png", ".targetsize-48.png");
          if (File(appxIcon2).existsSync()) {
            appxIcon = appxIcon2;
          }
        }
      }
    }
  }
}
