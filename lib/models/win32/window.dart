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
  String helpText = "";
  late HProcess process;
  int? monitor;
  bool isPinned = false;
  bool isAppx = false;
  String appxIcon = "";
  String toJson() {
    JsonEncoder encoder = const JsonEncoder.withIndent("");
    return encoder.convert(<String, dynamic>{
      'title': title.toString().truncate(20, suffix: '...'),
      'path': process.path,
      'exe': process.exe,
      'class': process.className
    });
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

  void getHandles() {
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

  void getTitle() {
    title = Win32.getTitle(hWnd);
  }

  void getWorkspace() {
    monitor = MonitorFromWindow(hWnd, MONITOR_DEFAULTTOPRIMARY);
    final int exstyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    isPinned = (exstyle & WS_EX_TOPMOST) != 0 ? true : false;
  }

  void getPath() {
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

  void getManifestIcon2() {
    String appxLocation = process.path;
    if (!process.exe.contains("exe")) appxLocation += "${process.exe}\\";
    appxIcon = Win32.getManifestIcon(appxLocation);
  }

  void getManifestIcon() {
    String appxLocation = process.path;
    if (!process.exe.contains("exe")) appxLocation += "${process.exe}\\";

    // ApplicationFrameHost-hosted apps resolve to the inner exe, which frequently
    // lives in a sub-folder of the package while AppxManifest.xml sits at the
    // package root — walk up from the exe folder until we find the manifest.
    final String manifestDir = _findManifestDir(appxLocation);
    if (manifestDir.isEmpty) return;

    final String manifest = File("${manifestDir}AppxManifest.xml").readAsStringSync();
    String icon = "";
    if (manifest.contains("Square44x44Logo")) {
      icon = manifest.split("Square44x44Logo=\"")[1].split("\"")[0];
    } else if (manifest.contains("Square150x150Logo")) {
      icon = manifest.split("Square150x150Logo=\"")[1].split("\"")[0];
    } else if (manifest.contains("Logo")) {
      icon = manifest.split("Logo=\"")[1].split("\"")[0];
    }
    if (icon.isEmpty) return;

    appxIcon = _resolveLogoVariant("$manifestDir${icon.replaceAll('/', '\\')}");
  }

  /// Finds the directory holding `AppxManifest.xml` by walking up from [startDir]
  /// (bounded to a handful of levels, stopping at the WindowsApps container or the
  /// drive root), so packages whose exe lives in a sub-folder still resolve.
  String _findManifestDir(String startDir) {
    String dir = startDir.replaceAll('/', '\\');
    if (!dir.endsWith('\\')) dir += '\\';
    for (int depth = 0; depth < 6; depth++) {
      final String trimmed = dir.substring(0, dir.length - 1);
      if (trimmed.toLowerCase().endsWith('windowsapps')) break;
      if (File("${dir}AppxManifest.xml").existsSync()) return dir;
      final int slash = trimmed.lastIndexOf('\\');
      if (slash <= 2) break; // reached the drive root ("C:\")
      dir = "${trimmed.substring(0, slash)}\\";
    }
    return "";
  }

  /// UWP logos ship as scale-/targetsize- variants; the bare path declared in the
  /// manifest rarely exists on disk. Tries the common variants, then falls back to
  /// any matching file in the logo's folder (handles `_altform-unplated`, etc.).
  String _resolveLogoVariant(String basePng) {
    const List<String> suffixes = <String>[
      '.scale-100',
      '.targetsize-32',
      '.targetsize-48',
      '.scale-200',
      '.targetsize-24',
      '.targetsize-16',
    ];
    for (final String suffix in suffixes) {
      final String candidate = basePng.replaceFirst('.png', '$suffix.png');
      if (File(candidate).existsSync()) return candidate;
    }
    if (File(basePng).existsSync()) return basePng;

    final int slash = basePng.lastIndexOf('\\');
    if (slash != -1) {
      final String dirPath = basePng.substring(0, slash);
      final String baseName = basePng.substring(slash + 1).replaceFirst('.png', '').toLowerCase();
      final Directory dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          for (final FileSystemEntity entity in dir.listSync()) {
            if (entity is! File) continue;
            final String name = entity.path.substring(entity.path.lastIndexOf('\\') + 1).toLowerCase();
            if (name.startsWith(baseName) && name.endsWith('.png')) return entity.path;
          }
        } catch (_) {}
      }
    }
    return basePng;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Window &&
        other.hWnd == hWnd &&
        other.title == title &&
        other.isAppx == isAppx &&
        other.appxIcon == appxIcon &&
        other.process == process;
  }

  @override
  int get hashCode {
    return hWnd.hashCode ^ title.hashCode ^ isAppx.hashCode ^ appxIcon.hashCode ^ process.hashCode;
  }

  @override
  String toString() {
    return 'Window{hWnd: $hWnd, title: $title, helpText: $helpText, process: $process, monitor: $monitor, isPinned: $isPinned, isAppx: $isAppx, appxIcon: $appxIcon}';
  }
}
