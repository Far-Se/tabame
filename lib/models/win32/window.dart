// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../settings.dart';
import 'imports.dart';
import 'win32.dart';

class Window {
  int hWnd;
  String title = "";
  late HProcess process;
  int? monitor;
  bool isPinned = false;
  bool isAppx = false;
  String appxIcon = "";
  String toJson() {
    JsonEncoder encoder = const JsonEncoder.withIndent("");
    return encoder
        .convert(<String, dynamic>{'title': title.toString().truncate(20, suffix: '...'), 'path': process.path, 'exe': process.exe, 'class': process.className});
  }

  Window(this.hWnd) {
    process = HProcess();
    getHandles();
    getTitle();
    getWorkspace();
    getPath();
    if (isAppx) {
      getManifestIcon();
    }
  }

  getHandles() {
    final Pointer<Uint32> pId = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, pId);
    process.mainPID = pId.value;
    free(pId);
    process.pId = HwndPath.getRealPID(hWnd);
    process.className = Win32.getClass(hWnd);

    int icon = SendMessage(hWnd, WM_GETICON, 2, 0); // ICON_SMALL2 - User Made Apps
    if (icon == 0) icon = GetClassLongPtr(hWnd, -14); // GCLP_HICON - Microsoft Win Apps
    process.iconHandle = icon;
  }

  getTitle() {
    title = Win32.getTitle(hWnd);
  }

  getWorkspace() {
    monitor = MonitorFromWindow(hWnd, MONITOR_FROM_FLAGS.MONITOR_DEFAULTTOPRIMARY);
    final int exstyle = GetWindowLong(hWnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
    isPinned = (exstyle & WINDOW_EX_STYLE.WS_EX_TOPMOST) != 0 ? true : false;
  }

  getPath() {
    HwndInfo pathInfo = HwndPath.getFullPath(hWnd);
    process.path = pathInfo.path;
    isAppx = pathInfo.isAppx;

    if (process.path == "") process.exe = "AccessBlocked.exe";
    process.path = process.path.replaceAll('/', '\\');
    if (process.path.contains("\\") == true) {
      process.exe = process.path.substring(process.path.lastIndexOf('\\') + 1);
    }
    process.path = process.path.replaceAll(process.exe, "");
  }

  getManifestIcon2() {
    String appxLocation = process.path;
    if (!process.exe.contains("exe")) appxLocation += "${process.exe}\\";
    appxIcon = Win32.getManifestIcon(appxLocation);
  }

  getManifestIcon() {
    String appxLocation = process.path;
    if (!process.exe.contains("exe")) appxLocation += "${process.exe}\\";
    if (File("${appxLocation}AppxManifest.xml").existsSync()) {
      final String manifest = File("${appxLocation}AppxManifest.xml").readAsStringSync();
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
      final String scale100 = appxIcon.replaceFirst(".png", ".scale-100.png");
      if (File(scale100).existsSync()) {
        appxIcon = scale100;
      } else {
        final String appxIcon2 = appxIcon.replaceFirst(".png", ".targetsize-32.png");
        if (File(appxIcon2).existsSync()) {
          appxIcon = appxIcon2;
        } else {
          final String appxIcon2 = appxIcon.replaceFirst(".png", ".targetsize-48.png");
          if (File(appxIcon2).existsSync()) {
            appxIcon = appxIcon2;
          }
        }
      }
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Window && other.hWnd == hWnd && other.title == title && other.isAppx == isAppx && other.appxIcon == appxIcon && other.process == process;
  }

  @override
  int get hashCode {
    return hWnd.hashCode ^ title.hashCode ^ isAppx.hashCode ^ appxIcon.hashCode ^ process.hashCode;
  }
}
