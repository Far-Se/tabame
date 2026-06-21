// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:io';
import 'dart:typed_data';

import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import 'classes/boxes.dart';
import 'win32/win32.dart';
import 'win32/win_utils.dart';
import 'window_watcher.dart';

Map<int, Uint8List> __trayIconCache = <int, Uint8List>{};

Map<int, int> __trayIconHandleCache = <int, int>{};
int _trayIconCacheKey(ExtendedTrayIcon icon) {
  return Object.hash(icon.hWnd, icon.uID, icon.uCallbackMsg, icon.isOverflow);
}

Future<List<TrayBarInfo>> _buildTrayBarInfoList(
  List<ExtendedTrayIcon> winTray,
  Map<int, TrayBarInfo> trayCache, {
  bool sort = true,
}) async {
  final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
  final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];

  final List<TrayBarInfo> newList = <TrayBarInfo>[];
  final Set<int> activeIconKeys = <int>{};
  final Set<int> processIds = <int>{};
  int taskManagerProcessId = -1;
  for (ExtendedTrayIcon element in winTray) {
    if (element.toolTip.contains("%")) {
      final RegExp regex = RegExp(r'(\d+)%');
      final List<int> result =
          regex.allMatches(element.toolTip).map((RegExpMatch m) => int.parse(m.group(1)!)).toList();
      if (result.length == 4) {
        taskManagerProcessId = element.processId;
        WindowWatcher.taskManagerStats = "CPU ${result[0]}% RAM ${result[1]}% DISK ${result[2]}% NET ${result[3]}%";
      }
    }
    if (processIds.contains(element.processId)) continue;
    processIds.add(element.processId);
    final int hWnd = element.hWnd;
    final int iconKey = _trayIconCacheKey(element);
    activeIconKeys.add(iconKey);

    final String processExePath = Win32.getProcessExePath(element.processId);
    HwndInfo processPath = HwndInfo(path: processExePath, isAppx: false);
    if (processPath.path.isEmpty && hWnd != 0) {
      final int ancestor = GetAncestor(hWnd, 2);
      processPath = HwndPath.getFullPath(ancestor != 0 ? ancestor : hWnd);
    }
    String exe = Win32.getExe(processPath.path);

    // Skip background/system items that aren't real tray icons or are explorer junk
    if (processPath.path.contains("explorer.exe") && element.toolTip.isEmpty) continue;

    final TrayBarInfo? cachedTrayInfo = trayCache[iconKey];
    final TrayBarInfo trayInfo = TrayBarInfo(
      processPath: processPath.path,
      processExe: exe,
      toolTip: element.toolTip,
      processId: element.processId,
      hWnd: hWnd,
      uID: element.uID,
      uCallbackMsg: element.uCallbackMsg,
      hIcon: element.hIcon,
      isVisible: !hidden.contains(exe) && !processPath.path.contains("explorer.exe"),
      isOverflow: element.isOverflow,
    )..isPinned = pinned.contains(exe);

    if (cachedTrayInfo != null) {
      trayInfo.iconData = cachedTrayInfo.iconData;
      // trayInfo.appxIconPath = cachedTrayInfo.appxIconPath;
    }

    // Only load/update icon if the item is visible and the icon handle changed
    if (trayInfo.isVisible) {
      if (__trayIconHandleCache[iconKey] != element.hIcon || trayInfo.iconData.length <= 1) {
        try {
          final Uint8List? icon = WinUtils.hIconToBytes(element.hIcon);
          trayInfo.iconData = icon ?? Uint8List.fromList(<int>[0]);
          __trayIconCache[iconKey] = trayInfo.iconData;
          __trayIconHandleCache[iconKey] = element.hIcon;
        } catch (e) {
          // Silently fail for individual icons
        }
      }

      // if (trayInfo.appxIconPath.isEmpty) {
      //   trayInfo.appxIconPath = TrayWatcher._resolveAppxIconPath(processPath.path);
      // }
    } else {
      // If invisible, clear heavy icon data from the object (keep it in global cache if needed later)
      trayInfo.iconData = Uint8List.fromList(<int>[0]);
    }

    trayCache[iconKey] = trayInfo;
    newList.add(trayInfo);
  }
  if (taskManagerProcessId == -1) WindowWatcher.taskManagerStats = '';

  // Efficient cleanup of stale items
  trayCache.removeWhere((int key, _) => !activeIconKeys.contains(key));
  __trayIconCache.removeWhere((int key, _) => !activeIconKeys.contains(key));
  __trayIconHandleCache.removeWhere((int key, _) => !activeIconKeys.contains(key));

  if (sort) {
    newList.sort((TrayBarInfo a, TrayBarInfo b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      if (a.isVisible && !b.isVisible) return -1;
      if (!a.isVisible && b.isVisible) return 1;
      return 0;
    });
  }

  return newList;
}

class TrayWatcher {
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static final Map<int, TrayBarInfo> _trayCache = <int, TrayBarInfo>{};
  TrayWatcher._();

  static Future<bool> fetchTray({bool sort = true}) async {
    final List<ExtendedTrayIcon> winTray = await WinTray.enumAllIcons();
    trayList = await _buildTrayBarInfoList(winTray, _trayCache, sort: sort);
    return true;
  }

  /// Resolves the on-disk manifest logo for an Appx/UWP app given its process
  /// exe path (which, for packaged apps, lives under `...\WindowsApps\...`).
  /// Returns "" for non-packaged apps or when no logo could be found. Results
  /// (including the empty "not found" result) are cached per exe path so the
  /// manifest is parsed at most once, not on every 600ms refresh tick.
  static final Map<String, String> _appxIconByExe = <String, String>{};
  // ignore: unused_element
  static String _resolveAppxIconPath(String exePath) {
    if (exePath.isEmpty || !exePath.toLowerCase().contains("windowsapps")) return "";

    final String key = exePath.toLowerCase();
    final String? cached = _appxIconByExe[key];
    if (cached != null) return cached;

    String result = "";
    // Prefer the package root (`...\WindowsApps\<PackageFullName>\`) which always
    // contains AppxManifest.xml, even when the running exe is in a subfolder.
    final String root = _appxPackageRoot(exePath);
    String icon = Win32.getManifestIcon(root);
    if (icon.isNotEmpty && File(icon).existsSync()) {
      result = icon;
    } else {
      // Fallback: the folder of the exe itself (covers manifests placed alongside).
      final String normalized = exePath.replaceAll('/', '\\');
      final int slash = normalized.lastIndexOf('\\');
      if (slash > 0) {
        icon = Win32.getManifestIcon(normalized.substring(0, slash));
        if (icon.isNotEmpty && File(icon).existsSync()) result = icon;
      }
    }

    _appxIconByExe[key] = result;
    return result;
  }

  /// Given an exe path under WindowsApps, returns the package-root folder:
  /// the first path segment after `WindowsApps\` (the `<PackageFullName>` dir).
  static String _appxPackageRoot(String exePath) {
    final String normalized = exePath.replaceAll('/', '\\');
    const String marker = "windowsapps\\";
    final int idx = normalized.toLowerCase().indexOf(marker);
    if (idx == -1) return normalized;
    final int afterMarker = idx + marker.length;
    final int nextSlash = normalized.indexOf('\\', afterMarker);
    if (nextSlash == -1) return normalized;
    return normalized.substring(0, nextSlash);
  }
}

class SystrayWatcher {
  static List<TrayBarInfo> trayList = <TrayBarInfo>[];
  static final Map<int, TrayBarInfo> _trayCache = <int, TrayBarInfo>{};
  static bool _monitorStarted = false;
  SystrayWatcher._();

  static Future<bool> fetchTray({bool sort = true}) async {
    if (!_monitorStarted) {
      _monitorStarted = await WinSystray.startMonitor();
      if (!_monitorStarted) return false;
    }

    final List<ExtendedTrayIcon> winTray = await WinSystray.snapshotIcons();
    trayList = await _buildTrayBarInfoList(winTray, _trayCache, sort: sort);
    return true;
  }

  static Future<void> stop() async {
    if (!_monitorStarted) return;
    await WinSystray.stopMonitor();
    _monitorStarted = false;
    trayList = <TrayBarInfo>[];
    _trayCache.clear();
  }
}

class TrayBarInfo extends ExtendedTrayIcon {
  String processPath = "";
  String processExe = "";
  int brightness = 0;
  bool isPinned = false;
  Uint8List iconData = Uint8List.fromList(<int>[0]);

  /// For Appx/UWP apps whose tray HICON can't be rendered cross-process,
  /// the resolved on-disk path to the package's manifest logo. Empty when
  /// not applicable or unresolved.
  String appxIconPath = "";
  TrayBarInfo({
    required this.processPath,
    required this.processExe,
    required super.toolTip,
    required super.processId,
    required super.hWnd,
    required super.uID,
    required super.uCallbackMsg,
    required super.hIcon,
    required super.isVisible,
    required super.isOverflow,
  });

  @override
  int get hashCode {
    return processPath.hashCode ^ processExe.hashCode;
  }

  int get processID => processId;

  int get uCallbackMessage => uCallbackMsg;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrayBarInfo && other.processPath == processPath && other.processExe == processExe;
  }

  @override
  String toString() {
    return 'TrayBarInfo(processPath: $processPath, processExe: $processExe, brightness: $brightness)';
  }
}
