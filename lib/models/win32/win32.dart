// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io' as io;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'imports.dart';
import 'mixed.dart';

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

  static void forceActivateWindow(hWnd) {
    ShowWindow(hWnd, SW_RESTORE);
    SetForegroundWindow(hWnd);
    BringWindowToTop(hWnd);
    SetFocus(hWnd);
    SetActiveWindow(hWnd);
    UpdateWindow(hWnd);
  }

  static void closeWindow(hWnd, {bool forced = false}) {
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
    // SendMessage(hWnd, WM_SYSCOMMAND, SC_CLOSE, 0);
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
  // C:\Users\Far Se\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch
  // C:\Users\Far Se\AppData\Roaming\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar

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

  int getRealPID(hWnd) {
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
