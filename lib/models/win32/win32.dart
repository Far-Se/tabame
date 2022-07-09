// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io' as io;
import 'dart:io';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart' hide Size, Point;

import '../keys.dart';
import '../utils.dart';
import 'imports.dart';
import 'mixed.dart';

class Win32 {
  static void activateWindow(int hWnd, {bool forced = false}) {
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
    if (forced) {
      ShowWindow(hWnd, SW_RESTORE);
      SetForegroundWindow(hWnd);
      BringWindowToTop(hWnd);
      SetFocus(hWnd);
      SetActiveWindow(hWnd);
      UpdateWindow(hWnd);
    }
    SetForegroundWindow(hWnd);
  }

  static void forceActivateWindow(int hWnd) {
    activateWindow(hWnd, forced: true);
  }

  static void closeWindow(int hWnd, {bool forced = false}) {
    PostMessage(hWnd, WM_CLOSE, 0, 0);
    if (forced) {
      final pId = calloc<Uint32>();
      GetWindowThreadProcessId(hWnd, pId);
      final mainPID = pId.value;
      final prID = HwndPath().getRealPID(hWnd);
      free(pId);
      PostMessage(hWnd, WM_CLOSE, 0, 0);
      PostMessage(hWnd, WM_QUIT, 0, 0);
      PostMessage(hWnd, WM_DESTROY, 0, 0);
      PostMessage(hWnd, WM_NCDESTROY, 0, 0);

      TerminateProcess(mainPID, 0);
      TerminateProcess(prID, 0);
    }
  }

  static String getProcessExePath(int processID) {
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
  static String getWindowExeModulePath(int hWnd) {
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

  static String getWindowExePath(int hWnd) {
    return HwndPath().getFullPathString(hWnd);
  }

  static String getTitle(int hWnd) {
    String title = "";
    final length = GetWindowTextLength(hWnd);
    final buffer = wsalloc(length + 1);
    GetWindowText(hWnd, buffer, length + 1);
    title = buffer.toDartString();
    free(buffer);
    return title;
  }

  static bool isWindowPresent(int hWnd) {
    var visible = true;
    final exstyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    if ((exstyle & WS_EX_TOOLWINDOW) != 0) visible = false;
    // final winInfo = calloc<WINDOWINFO>();
    // GetWindowInfo(hWnd, winInfo);
    // if ((winInfo.ref.dwExStyle & WS_EX_APPWINDOW) != 0) visible = false;
    // free(winInfo);
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

  static String getClass(int hWnd) {
    final name = wsalloc(256);
    GetClassName(hWnd, name, 256);
    final className = name.toDartString();
    free(name);
    return className;
  }

  static String getExe(String path) {
    String exe = "";
    if (path.contains("/") == true) {
      exe = path.substring(path.lastIndexOf('/') + 1);
    } else if (path.contains("\\") == true) {
      exe = path.substring(path.lastIndexOf('\\') + 1);
    }
    return exe;
  }

  static int hWnd = 0;
  static int getMainHandle() {
    if (hWnd == 0) getMainHandleByClass();
    return hWnd;
  }

  static Future fetchMainWindowHandle() async {
    hWnd = await getFlutterMainWindow();
    return;
  }

  static getMainHandleByClass() {
    if (hWnd != 0) return hWnd;
    final hwnd = FindWindow(TEXT("TABAME_FLUTTER_WINDOW"), nullptr);
    if (hwnd > 0) {
      hWnd = GetAncestor(hwnd, 2);
    }
    return hWnd;
  }

  static Square getWindowRect({int? hwnd}) {
    hwnd ??= hWnd;
    final rect = calloc<RECT>();
    GetWindowRect(hwnd, rect);
    final output = Square(x: rect.ref.left, y: rect.ref.top, width: rect.ref.right - rect.ref.left, height: rect.ref.bottom - rect.ref.top);
    free(rect);
    return output;
  }

  static setPosition(Offset position, {int? monitor, int? hwnd}) {
    hwnd ??= hWnd;
    final rect = getWindowRect(hwnd: hwnd);
    int x = position.dx ~/ 1;
    int y = position.dy ~/ 1;
    if (monitor != null) {
      x += Monitor.monitorSizes[monitor]!.x;
      y += Monitor.monitorSizes[monitor]!.y;
    }
    SetWindowPos(hwnd, HWND_TOP, x ~/ 1, y ~/ 1, rect.width, rect.height, NULL);
  }

  static setCenter({bool useMouse = false, int? hwnd}) {
    hwnd ??= hWnd;
    if (!useMouse) {
      final rect = getWindowRect(hwnd: hwnd);
      final x = (GetSystemMetrics(SM_CXSCREEN) - rect.width) / 2;
      final y = (GetSystemMetrics(SM_CYSCREEN) - rect.height) / 2;
      SetWindowPos(hwnd, HWND_TOP, x ~/ 1, y ~/ 1, rect.width, rect.height, NULL);
    } else {
      final rect = getWindowRect(hwnd: hwnd);
      final monitor = Monitor.getCursorMonitor();
      final monitorSize = Monitor.monitorSizes[monitor]!;
      final x = (((monitorSize.width + monitorSize.x) - monitorSize.x - rect.width) / 2) + monitorSize.x;
      final y = (((monitorSize.height + monitorSize.y) - monitorSize.y - rect.height) / 2) + monitorSize.y;
      SetWindowPos(hwnd, HWND_TOP, x ~/ 1, y ~/ 1, rect.width, rect.height, NULL);
    }
  }

  static int getWindowMonitor(int hwnd) {
    return Monitor.getWindowMonitor(hwnd);
  }

  static int getCursorMonitor() {
    return Monitor.getCursorMonitor();
  }

  //
  static Future<bool> moveWindowToDesktop(int hWnd, DesktopDirection direction, {bool classMethod = true}) async {
    if (classMethod) return await moveWindowToDesktopMethod(hWnd: hWnd, direction: direction);
    String key = "RIGHT";
    if (direction == DesktopDirection.left) key = "LEFT";
    await setSkipTaskbar(hWnd: hWnd, skip: true);
    WinKeys.send("{#WIN}{#CTRL}{$key}");
    await setSkipTaskbar(hWnd: hWnd, skip: false);
    return true;
  }
}

class WinUtils {
  static void setVolumeOSDStyle({required VolumeOSDStyle type, bool applyStyle = true, int recursiveCheckHwnd = 5}) {
    var volumeHwnd = FindWindowEx(0, NULL, TEXT("NativeHWNDHost"), nullptr);
    if (volumeHwnd == 0) {
      volumeHwnd = FindWindowEx(0, 0, TEXT("DirectUIHWND"), nullptr);
    }

    if (volumeHwnd != 0) {
      if (type == VolumeOSDStyle.media) {
        final dpi = GetDpiForWindow(volumeHwnd);
        final dpiCoef = dpi ~/ 96.0;
        if (applyStyle == true) {
          final newOsdRegion = CreateRectRgn(0, 0, (60 * dpiCoef).round(), (140 * dpiCoef).round());
          SetWindowRgn(volumeHwnd, newOsdRegion, 1);
        } else {
          SetWindowRgn(volumeHwnd, 0, 1);
        }
        return;
      } else if (type == VolumeOSDStyle.visible) {
        if (volumeHwnd != 0) {
          if (applyStyle == false) {
            ShowWindow(volumeHwnd, 9);
            keybd_event(VK_VOLUME_UP, 0, 0, 0);
            keybd_event(VK_VOLUME_DOWN, 0, 0, 0);
          } else {
            ShowWindow(volumeHwnd, 6);
          }
          return;
        }
      } else if (type == VolumeOSDStyle.thin) {
        volumeHwnd = FindWindowEx(NULL, NULL, TEXT("NativeHWNDHost"), nullptr);
        if (volumeHwnd != 0) {
          final dpi = GetDpiForWindow(volumeHwnd);
          final dpiCoef = dpi ~/ 96.0;
          if (applyStyle == true) {
            final newOsdRegion = CreateRectRgn(25, 18, (60 * dpiCoef).round() - 20, (140 * dpiCoef).round() - 16);
            SetWindowRgn(volumeHwnd, newOsdRegion, 1);
            final dc = GetWindowDC(volumeHwnd);
            SetBkColor(dc, 0xFF00FF00);
          } else {
            SetWindowRgn(volumeHwnd, 0, 1);
          }
        }
      }
    } else {
      print("no hwnd");
    }
    if (volumeHwnd == 0 && recursiveCheckHwnd > 0) {
      recursiveCheckHwnd--;
      Timer(const Duration(seconds: 3), () {
        setVolumeOSDStyle(type: type, applyStyle: applyStyle, recursiveCheckHwnd: recursiveCheckHwnd);
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

  static int _isAdministrator = -1;
  static bool isAdministrator() {
    if (_isAdministrator == -1) {
      _isAdministrator = IsUserAnAdmin() == true ? 1 : 0;
    }
    return _isAdministrator == 1;
  }

  static String getLocalAppData() {
    RoInitialize(RO_INIT_TYPE.RO_INIT_SINGLETHREADED);
    final userData = UserDataPaths.GetDefault();
    final hStrLocalAppData = userData.LocalAppData; //userData.RoamingAppData;

    final localAppData = WindowsGetStringRawBuffer(hStrLocalAppData, nullptr).toDartString();

    RoUninitialize();
    return localAppData;
  }

  static Future<List<String>> getTaskbarPinnedApps() async {
    final appsFolder = GUIDFromString(FOLDERID_UserPinned);
    final ppszPath = calloc<PWSTR>();
    String path = "";
    final hr = SHGetKnownFolderPath(appsFolder, KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      path = ppszPath.value.toDartString();
    } else {
      path = "${getLocalAppData()}\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned";
    }
    free(ppszPath);
    path += "\\Taskbar";
    final allContents = await Directory(path).list().where((event) => event.path.endsWith(".lnk")).length;
    List<String> commands = <String>[
      "\$WScript = New-Object -ComObject WScript.Shell;",
      "Get-ChildItem -Path \"$path\" | ForEach-Object {\$WScript.CreateShortcut(\$_.FullName).TargetPath};",
    ];
    List<String> output = await runPowerShell(commands);
    if (allContents != output.length) {
      output.insert(0, "C:\\Windows\\explorer.exe");
    }
    return output;
  }

  static Future<List<String>> runPowerShell(List<String> commands) async {
    final result = await io.Process.run(
      'powershell',
      ['-NoProfile', ...commands],
    );
    if (result.stderr != '') {
      return <String>[];
    }
    var output = result.stdout.toString().trim().split('\n').map((e) => e.trim()).toList();

    return output;
  }

  static void open(String link) {
    ShellExecute(NULL, TEXT("open"), TEXT(link), nullptr, nullptr, SW_SHOWNORMAL);
  }

  static void run(String link) {
    ShellExecute(NULL, TEXT("run"), TEXT(link), nullptr, nullptr, SW_SHOWNORMAL);
  }

  static void sendCommand({int command = AppCommand.appCommand}) {
    SendMessage(NULL, AppCommand.appCommand, 0, command);
  }

  static String getTaskManagerPath() {
    String location = "";
    final folder = GUIDFromString(FOLDERID_Windows);
    final ppszPath = calloc<PWSTR>();
    final hr = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      location = "${ppszPath.value.toDartString()}\\System32\\Taskmgr.exe";
    }
    free(ppszPath);
    return location;
  }

  static bool taskbarVisible = true;
  static void toggleTaskbar() {
    taskbarVisible = !taskbarVisible;
    setTaskbarVisibility(taskbarVisible);
  }

  static void moveDesktop(DesktopDirection direction, {bool classMethod = true}) {
    if (classMethod) {
      moveDesktopMethod(direction);
      return;
    }
    String key = "RIGHT";
    if (direction == DesktopDirection.left) key = "LEFT";
    WinKeys.send("{#WIN}{#CTRL}{$key}");
  }
}

class HProcess {
  String path = "";
  String exe = "";
  int pId = 0;
  int mainPID = 0;
  String className = "";

  @override
  String toString() {
    return 'HProcess(path: $path, exe: $exe, pId: $pId, className: $className)';
  }
}

class HwndPath {
  HwndPath();
  bool isAppx = false;
  String GetAppxInstallLocation(int hWnd) {
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

  String getProcessExePath(int processID) {
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

  String getWindowExePath(int hWnd) {
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

  int getRealPID(int hWnd) {
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
        return mainWinProcs;
      }
    }
    return processID;
  }

  Map<String, dynamic> getFullPath(int hWnd) {
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

  String getFullPathString(int hWnd) {
    Map<String, dynamic> result = getFullPath(hWnd);
    return result["path"];
  }
}
