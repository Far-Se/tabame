// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'package:tabame/models/utils.dart';
import 'package:tabamewin32/tabamewin32.dart';

// #region (collapsed) DLL IMPORT

/// [USER32]

final _user32 = DynamicLibrary.open('user32.dll');

void keybd_event(int bVk, int bScan, int dwFlags, int dwExtraInfo) => _keybd_event(bVk, bScan, dwFlags, dwExtraInfo);

final _keybd_event =
    _user32.lookupFunction<Void Function(Uint8 bVk, Uint8 bScan, Uint32 dwFlags, IntPtr dwExtraInfo), void Function(int bVk, int bScan, int dwFlags, int dwExtraInfo)>(
        'keybd_event');

int GetClassName(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount) => _GetClassName(hWnd, lpClassName, nMaxCount);

final _GetClassName =
    _user32.lookupFunction<Int32 Function(IntPtr hWnd, Pointer<Utf16> lpClassName, Int32 nMaxCount), int Function(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount)>(
        'GetClassNameW');

/// [KERNEL32]
final _kernel32 = DynamicLibrary.open('kernel32.dll');
int QueryFullProcessImageName(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize) =>
    _QueryFullProcessImageName(hProcess, dwFlags, lpExeName, lpdwSize);

final _QueryFullProcessImageName = _kernel32.lookupFunction<Int32 Function(IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize),
    int Function(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize)>('QueryFullProcessImageNameW');

int GetApplicationUserModelId(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId) =>
    _GetApplicationUserModelId(hProcess, applicationUserModelIdLength, applicationUserModelId);

final _GetApplicationUserModelId = _kernel32.lookupFunction<
    Uint32 Function(IntPtr hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId),
    int Function(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId)>('GetApplicationUserModelId');

int ParseApplicationUserModelId(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId) =>
    _ParseApplicationUserModelId(applicationUserModelId, packageFamilyNameLength, packageFamilyName, packageRelativeApplicationIdLength, packageRelativeApplicationId);

final _ParseApplicationUserModelId = _kernel32.lookupFunction<
    Uint32 Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId),
    int Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId)>('ParseApplicationUserModelId');

/// [GDI]

final _gdi32 = DynamicLibrary.open('gdi32.dll');
int CreateRectRgn(int x1, int y1, int x2, int y2) => _CreateRectRgn(x1, y1, x2, y2);

final _CreateRectRgn = _gdi32.lookupFunction<IntPtr Function(Int32 x1, Int32 y1, Int32 x2, Int32 y2), int Function(int x1, int y1, int x2, int y2)>('CreateRectRgn');

/// [SHELL]
final _shell32 = DynamicLibrary.open('shell32.dll');
int SHQueryUserNotificationState(Pointer<Int32> pquns) => _SHQueryUserNotificationState(pquns);

final _SHQueryUserNotificationState = _shell32.lookupFunction<Int32 Function(Pointer<Int32> pquns), int Function(Pointer<Int32> pquns)>('SHQueryUserNotificationState');

// #endregion

// #region (collapsed) lowlevelFunction Helpers
var __helperWinsList = <int>[];
int enumWindowsProc(int hWnd, int lParam) {
  __helperWinsList.add(hWnd);
  return 1;
}

List<int> enumWindows() {
  final wndProc = Pointer.fromFunction<EnumWindowsProc>(enumWindowsProc, 0);
  __helperWinsList.clear();
  EnumWindows(wndProc, 0);
  // calloc<Nothing>
  // free(wndProc);
  return __helperWinsList;
}

var __helpEnumChildWins = <int>[];
int helperChildEnumWindowFunc(int w, int p) {
  __helpEnumChildWins.add(w);
  return 1;
}

List enumChildWins(hWnd) {
  final wndProc = Pointer.fromFunction<EnumWindowsProc>(helperChildEnumWindowFunc, 0);
  __helpEnumChildWins.clear();
  //this was outside this function when i moved it..
  EnumChildWindows(hWnd, wndProc, 0);
  // calloc<Nothing>
  // free(wndProc);
  return __helpEnumChildWins;
}

final __helperMonitorList = <int>[];
int helperGetMonitorByIndex(int hMonitor, int hDC, Pointer lpRect, int lParam) {
  __helperMonitorList.add(hMonitor);
  return 1;
}

// #endregion

enum OSDType {
  media,
  visibility,
  thin,
}

enum ScreenState {
  notPresent,
  busy,
  runningD3dFullScreen,
  presentationMode,
  acceptsNotifications,
  quietTime,
  app,
}

class Monitor {
  static List<int> _monitors = [];
  static List<int> get monitors {
    if (_monitors.isEmpty) {
      fetchMonitor();
    }
    return _monitors;
  }

  static final Map<int, int> _monitorIds = {};
  static Map<int, int> get monitorIds {
    if (_monitorIds.isEmpty) {
      fetchMonitor();
    }
    return _monitorIds;
  }

  static Map<int, Map<int, int>> dpi = <int, Map<int, int>>{};
  static void fetchMonitor() {
    EnumDisplayMonitors(NULL, nullptr, Pointer.fromFunction<MonitorEnumProc>(helperGetMonitorByIndex, 0), 0);
    _monitors = [...__helperMonitorList];
    __helperMonitorList.clear();
    for (var i = 0; i < _monitors.length; i++) {
      final dpiX = calloc<Uint32>();
      final dpiY = calloc<Uint32>();
      GetDpiForMonitor(_monitors[i], 0, dpiX, dpiY);
      dpi[_monitors[i]] = {
        0: dpiX.value,
        1: dpiY.value,
      };
      free(dpiX);
      free(dpiY);
      _monitorIds[_monitors[i]] = i + 1;
    }
  }
}

class Win32 {
  static void activateWindow(hWnd) {
    //ShowWindow(hWnd, SW_RESTORE);
    // SetForegroundWindow(hWnd);
    // BringWindowToTop(hWnd);
    // SetFocus(hWnd);
    // SetActiveWindow(hWnd);
    // UpdateWindow(hWnd);
    final place = calloc<WINDOWPLACEMENT>();
    GetWindowPlacement(hWnd, place);

    switch (place.ref.showCmd) {
      case SW_SHOWMAXIMIZED:
        ShowWindow(hWnd, SW_SHOWMAXIMIZED);
        break;
      case SW_SHOWMINIMIZED:
        ShowWindow(hWnd, SW_RESTORE);
        break;
      default:
        ShowWindow(hWnd, SW_NORMAL);
        break;
    }
    free(place);
    SetForegroundWindow(hWnd);
  }

  static void closeWindow(hWnd) {
    PostMessage(hWnd, WM_CLOSE, 0, 0);
    // SendMessage(hWnd, WM_SYSCOMMAND, SC_CLOSE, 0);
    //PostMessage(hWnd, WM_DESTROY, 0, 0);
  }

  static String getProcessExePath(processID) {
    String exePath = "";
    final hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processID);
    if (hProcess == 0) {
      CloseHandle(hProcess);
      return "";
    }

    final imgName = wsalloc(MAX_PATH);
    final buff = calloc<Uint32>()..value = MAX_PATH;
    if (QueryFullProcessImageName(hProcess, 0, imgName, buff) != 0) {
      final szModName = wsalloc(MAX_PATH);
      GetModuleFileNameEx(hProcess, 0, szModName, MAX_PATH);
      exePath = szModName.toDartString();
      free(szModName);
    } else {
      exePath = "";
    }
    free(imgName);
    free(buff);
    CloseHandle(hProcess);
    return exePath;
  }

  @Deprecated("Outdated method one getWindowsExePath or getProcessExePath")
  static String getWindowExeModulePath(hWnd) {
    final lpBaseName = wsalloc(MAX_PATH);
    GetWindowModuleFileName(hWnd, lpBaseName, MAX_PATH);
    String moduleName = lpBaseName.toDartString();
    free(lpBaseName);
    if (moduleName == "") {
      final ppID = calloc<Uint32>();
      GetWindowThreadProcessId(hWnd, ppID);
      final wppID = ppID.value;
      free(ppID);
      final hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, wppID);
      if (hProcess == 0) {
        final szModName = wsalloc(MAX_PATH);
        GetModuleFileNameEx(hProcess, 0, szModName, MAX_PATH);
        moduleName = szModName.toDartString();
        free(szModName);
      }
      CloseHandle(hProcess);
    }
    return moduleName;
  }

  static String getWindowExePath(hWnd) {
    return HwndPath().getFullPathString(hWnd);
  }

  static String getTitle(hWnd) {
    String title = "";
    final length = GetWindowTextLength(hWnd);
    final buffer = wsalloc(length + 1);
    GetWindowText(hWnd, buffer, length + 1);
    title = buffer.toDartString();
    free(buffer);
    return title;
  }

  static bool isWindowPresent(int hWnd) {
    final winInfo = calloc<WINDOWINFO>();
    var visible = true;
    GetWindowInfo(hWnd, winInfo);
    if ((winInfo.ref.dwExStyle & WS_EX_TOOLWINDOW) != 0) visible = false;
    // if ((winInfo.ref.dwExStyle & WS_EX_APPWINDOW) != 0) visible = false;
    free(winInfo);
    return visible;
  }

  static bool isWindowCloaked(int hWnd) {
    final cloaked = calloc<Int>();
    DwmGetWindowAttribute(hWnd, DWMWINDOWATTRIBUTE.DWMWA_CLOAKED, cloaked, sizeOf<Int>());
    bool result = cloaked.value != 0;
    free(cloaked);
    return result;
  }

  static bool isWindowOnDesktop(int hWnd) {
    return IsWindowVisible(hWnd) != 0 && isWindowPresent(hWnd) && !isWindowCloaked(hWnd);
  }

  static String getClass(hWnd) {
    final name = wsalloc(256);
    GetClassName(hWnd, name, 256);
    final className = name.toDartString();
    free(name);
    return className;
  }
}

class WinUtils {
  static void setVolumeOSDStyle({required OSDType type, enabled = true, int recursiveCheckHwnd = 5}) {
    var hWnd = 0;
    if (type == OSDType.media) {
      hWnd = FindWindowEx(NULL, NULL, TEXT("NativeHWNDHost"), nullptr);
      if (hWnd != 0) {
        final dpi = GetDpiForWindow(hWnd);
        final dpiCoef = dpi ~/ 96.0;
        if (enabled == false) {
          final newOsdRegion = CreateRectRgn(0, 0, (60 * dpiCoef).round(), (140 * dpiCoef).round());
          SetWindowRgn(hWnd, newOsdRegion, 1);
        } else {
          SetWindowRgn(hWnd, 0, 1);
        }
        return;
      }
    } else if (type == OSDType.visibility) {
      var vohuleHwnd = FindWindowEx(0, NULL, TEXT("NativeHWNDHost"), nullptr);
      if (vohuleHwnd == 0) {
        vohuleHwnd = FindWindowEx(0, 0, TEXT("DirectUIHWND"), nullptr);
      }
      if (vohuleHwnd != 0) {
        if (enabled == true) {
          ShowWindow(vohuleHwnd, 9);
          keybd_event(VK_VOLUME_UP, 0, 0, 0);
          keybd_event(VK_VOLUME_DOWN, 0, 0, 0);
        } else {
          ShowWindow(vohuleHwnd, 6);
        }
        return;
      }
    } else if (type == OSDType.thin) {
      hWnd = FindWindowEx(NULL, NULL, TEXT("NativeHWNDHost"), nullptr);
      if (hWnd != 0) {
        final dpi = GetDpiForWindow(hWnd);
        final dpiCoef = dpi ~/ 96.0;
        if (enabled == true) {
          final newOsdRegion = CreateRectRgn(25, 18, (60 * dpiCoef).round() - 20, (140 * dpiCoef).round() - 16);
          SetWindowRgn(hWnd, newOsdRegion, 1);
          final dc = GetWindowDC(hWnd);
          SetBkColor(dc, 0xFF00FF00);
        } else {
          SetWindowRgn(hWnd, 0, 1);
        }
      }
    }

    if (hWnd == 0 && recursiveCheckHwnd > 0) {
      recursiveCheckHwnd--;
      Timer(const Duration(seconds: 3), () {
        setVolumeOSDStyle(type: type, enabled: enabled, recursiveCheckHwnd: recursiveCheckHwnd);
      });
    }
    return;
  }

  static ScreenState checkUserScreenState() {
    final pquns = calloc<Int32>();
    SHQueryUserNotificationState(pquns);
    int state = pquns.value;
    free(pquns);
    return ScreenState.values[state - 1];
  }
}

class Point {
  int X;
  int Y;
  Point({this.X = 0, this.Y = 0});
}

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

class HProcess {
  String path = "";
  String exe = "";
  int pId = 0;
  String className = "";

  @override
  String toString() {
    return 'HProcess(path: $path, exe: $exe, pId: $pId, className: $className)';
  }
}

class HwndPath {
  HwndPath();
  bool isAppx = false;
  String GetAppxInstallLocation(hWnd) {
    //Ger Process Handle
    final ppID = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, ppID);
    var process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
    free(ppID);

    //Get Text
    final cMax = calloc<Uint32>()..value = 512;
    var cAppName = wsalloc(cMax.value);
    GetApplicationUserModelId(process, cMax, cAppName);
    var name = cAppName.toDartString();
    free(cMax);

    //It's main Window Handle On EdgeView Apps, query first child
    if (name.isEmpty) {
      final parentHwnd = GetAncestor(hWnd, 2);
      final childWins = enumChildWins(parentHwnd);
      if (childWins.length > 1) {
        CloseHandle(process);
        hWnd = childWins[1];

        final ppID = calloc<Uint32>();
        GetWindowThreadProcessId(hWnd, ppID);
        process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
        free(ppID);

        final cMax = calloc<Uint32>()..value = 512;
        GetApplicationUserModelId(process, cMax, cAppName);
        name = cAppName.toDartString();
        free(cMax);
      }
    }
    if (name.isEmpty) {
      return "";
    }

    //Get Package Name
    final familyLength = calloc<Uint32>()..value = 65 * 2;
    final familyName = wsalloc(familyLength.value);
    final packageLength = calloc<Uint32>()..value = 65 * 2;
    final packageName = wsalloc(familyLength.value);
    ParseApplicationUserModelId(cAppName, familyLength, familyName, packageLength, packageName);

    //Get Count
    final count = calloc<Uint32>();
    final buffer = calloc<Uint32>();
    FindPackagesByPackageFamily(familyName, 0x00000010 | 0x00000000, count, nullptr, buffer, nullptr, nullptr);
    final packageFullnames = calloc<Pointer<Utf16>>();
    final bufferString = wsalloc(buffer.value * 2);

    //Get Path
    FindPackagesByPackageFamily(familyName, 0x00000010 | 0x00000000, count, packageFullnames, buffer, bufferString, nullptr);
    final packageLocation = bufferString.toDartString();

    CloseHandle(process);
    free(cAppName);
    free(familyLength);
    free(familyName);
    free(packageLength);
    free(packageName);
    free(count);
    free(buffer);
    free(packageFullnames);
    free(bufferString);
    return packageLocation;
  }

  String getProcessExePath(processID) {
    String exePath = "";
    final hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processID);
    if (hProcess == 0) {
      CloseHandle(hProcess);
      return "";
    }
    final imgName = wsalloc(MAX_PATH);
    final buff = calloc<Uint32>()..value = MAX_PATH;
    if (QueryFullProcessImageName(hProcess, 0, imgName, buff) != 0) {
      final szModName = wsalloc(MAX_PATH);
      GetModuleFileNameEx(hProcess, 0, szModName, MAX_PATH);
      exePath = szModName.toDartString();
      free(szModName);
    } else {
      exePath = "";
    }
    free(imgName);
    free(buff);
    CloseHandle(hProcess);
    return exePath;
  }

  String getWindowExePath(hWnd) {
    String result = "";
    final pId = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, pId);
    final processID = pId.value;
    free(pId);

    result = getProcessExePath(processID);
    if (result.contains("FrameHost.exe")) {
      isAppx = true;
      final wins = enumChildWins(hWnd);
      final winsProc = <int>[];
      int mainWinProcs = 0;
      for (var e in wins) {
        final xpId = calloc<Uint32>();

        GetWindowThreadProcessId(e, xpId);
        winsProc.add(xpId.value);
        if (processID != xpId.value) {
          mainWinProcs = xpId.value;
        }
        free(xpId);
      }
      if (mainWinProcs > 0) {
        result = getProcessExePath(mainWinProcs);
      }
    }
    return result;
  }

  Map<String, dynamic> getFullPath(hWnd) {
    var exePath = getWindowExePath(hWnd);
    if (exePath.contains('WWAHost')) {
      isAppx = true;
      final appx = GetAppxInstallLocation(hWnd);
      exePath = "";
      if (appx != "") {
        exePath = "C:\\Program Files\\WindowsApps\\$appx";
      }
    }
    return {"isAppx": isAppx, "path": exePath};
  }

  String getFullPathString(hWnd) {
    Map<String, dynamic> result = getFullPath(hWnd);
    return result["path"];
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
    process.pId = pId.value;
    free(pId);
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
    //print(appxLocation);
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
      } else {}
    }
  }
}

class WindowWatcher {
  List<Window> list = <Window>[];
  Map<int, Window> cacheList = <int, Window>{};
  Map<String, Window> specialList = <String, Window>{};
  int _activeWinHandle = 0;
  get active {
    if (list.length > _activeWinHandle) {
      return list[_activeWinHandle];
    } else {
      return 0;
    }
  }

  WindowWatcher() {
    fetchWindows();
    return;
  }

  bool fetchWindows({bool debug = false}) {
    final winHWNDS = enumWindows();
    final allHWNDs = <int>[];

    for (var hWnd in winHWNDS) {
      if (debug) {}
      if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "" && Win32.getTitle(hWnd) != "Tabame") {
        allHWNDs.add(hWnd);
      }
    }

    cacheList.keys.where((hWnd) => !allHWNDs.contains(hWnd)).toList().forEach((hWnd) => cacheList.remove(hWnd));

    list.clear();
    specialList.clear();

    for (int element in allHWNDs) {
      if (cacheList.containsKey(element)) {
        cacheList[element]!.getWorkspace();
        cacheList[element]!.getTitle();
        list.add(cacheList[element]!);
      } else {
        list.add(Window(element));
        cacheList[element] = list.last;
      }

      if (list.last.process.exe == "Spotify.exe") specialList["Spotify"] = list.last;
    }

    for (var element in list) {
      if (element.process.path == "" && (element.process.exe == "AccessBlocked.exe" || element.process.exe == "")) {
        getHwndName(element.hWnd).then((value) => element.process.exe = value);
      }
    }

    final activeWindow = GetForegroundWindow();
    _activeWinHandle = list.indexWhere((element) => element.hWnd == activeWindow);
    if (_activeWinHandle < 0) _activeWinHandle = 0;

    orderBy(globalSettings.taskBarStyle);
    return true;
  }

  bool orderBy(TaskBarAppsStyle type) {
    if ([TaskBarAppsStyle.activeMonitorFirst, TaskBarAppsStyle.onlyActiveMonitor].contains(type)) {
      final lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final monitor = MonitorFromPoint(lpPoint.ref, 0);
      if (Monitor.monitors.contains(monitor)) {
        if (type == TaskBarAppsStyle.activeMonitorFirst) {
          List<Window> firstItems = [];
          firstItems = list.where((element) => element.appearance.monitor == monitor ? true : false).toList();
          list.removeWhere((element) => firstItems.contains(element));
          list = firstItems + list;
          // list.sort((a, b) => monitor == a.appearance.monitor ? -1 : 1);
        } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {
          list.removeWhere((element) => element.appearance.monitor != monitor);
        }
      }
      free(lpPoint);
    } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {}
    return true;
  }

  bool mediaControl(index) {
    if (list[index].process.exe == "Spotify.exe") {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
    }
    if (list[index].process.exe == "chrome.exe") {
      print("chrome");
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, AppCommand.mediaFastForward);
      specialList.containsKey("Spotify") == false && SendMessage(specialList["Spotify"]!.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPlayPause) == 1;
    }
    return true;
  }
}

class AppCommand {
  static const appCommand = 0x319;
  static const bassBoost = 20 << 16;
  static const bassDown = 19 << 16;
  static const bassUp = 21 << 16;
  static const browserBackward = 1 << 16;
  static const browserFavorites = 6 << 16;
  static const browserForward = 2 << 16;
  static const browserHome = 7 << 16;
  static const browserRefresh = 3 << 16;
  static const browserSearch = 5 << 16;
  static const browserStop = 4 << 16;
  static const close = 31 << 16;
  static const copy = 36 << 16;
  static const correctionList = 45 << 16;
  static const cut = 37 << 16;
  static const dictateOrCommandControlToggle = 43 << 16;
  static const find = 28 << 16;
  static const forwardMail = 40 << 16;
  static const help = 27 << 16;
  static const launchApp1 = 17 << 16;
  static const launchApp2 = 18 << 16;
  static const launchMail = 15 << 16;
  static const launchMediaSelect = 16 << 16;
  static const mediaChannelDown = 52 << 16;
  static const mediaChannelUp = 51 << 16;
  static const mediaFastForward = 49 << 16;
  static const mediaNexttrack = 11 << 16;
  static const mediaPause = 47 << 16;
  static const mediaPlay = 46 << 16;
  static const mediaPlayPause = 14 << 16;
  static const mediaPrevioustrack = 12 << 16;
  static const mediaRecord = 48 << 16;
  static const mediaRewind = 50 << 16;
  static const mediaStop = 13 << 16;
  static const micOnOffToggle = 44 << 16;
  static const microphoneVolumeDown = 25 << 16;
  static const microphoneVolumeMute = 24 << 16;
  static const microphoneVolumeUp = 26 << 16;
  static const newFile = 29 << 16;
  static const open = 30 << 16;
  static const paste = 38 << 16;
  static const print = 33 << 16;
  static const redo = 35 << 16;
  static const replyToMail = 39 << 16;
  static const save = 32 << 16;
  static const sendMail = 41 << 16;
  static const spellCheck = 42 << 16;
  static const trebleDown = 22 << 16;
  static const trebleUp = 23 << 16;
  static const undo = 34 << 16;
  static const volumeDown = 9 << 16;
  static const volumeMute = 8 << 16;
  static const volumeUp = 10 << 16;
}
