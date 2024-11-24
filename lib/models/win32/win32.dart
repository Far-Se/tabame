// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io' as io;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../globals.dart';
import 'keys.dart';
import '../settings.dart';
import 'imports.dart';
import 'mixed.dart';
import 'registry.dart';

// vscode-fold=2
class Win32 {
  static void activateWindow(int hWnd, {bool forced = false}) {
    // keybd_event(VK_MENU, 0, KEYEVENTF_EXTENDEDKEY | 0, 0);
    WinKeys.single("VK_MENU", KeySentMode.down);
    AttachThreadInput(GetCurrentThreadId(), GetWindowThreadProcessId(hWnd, nullptr), TRUE);

    final Pointer<WINDOWPLACEMENT> place = calloc<WINDOWPLACEMENT>();
    GetWindowPlacement(hWnd, place);

    switch (place.ref.showCmd) {
      case SHOW_WINDOW_CMD.SW_SHOWMAXIMIZED:
        ShowWindow(hWnd, SHOW_WINDOW_CMD.SW_SHOWMAXIMIZED);
        break;
      case SHOW_WINDOW_CMD.SW_SHOWMINIMIZED:
        ShowWindow(hWnd, SHOW_WINDOW_CMD.SW_RESTORE);
        break;
      default:
        ShowWindow(hWnd, SHOW_WINDOW_CMD.SW_NORMAL);
        break;
    }
    free(place);
    if (forced) {
      ShowWindow(hWnd, SHOW_WINDOW_CMD.SW_RESTORE);
      SetForegroundWindow(hWnd);
      BringWindowToTop(hWnd);
      SetFocus(hWnd);
      SetActiveWindow(hWnd);
      UpdateWindow(hWnd);
    }
    SetForegroundWindow(hWnd);
    if (GetForegroundWindow() != hWnd) {
      SwitchToThisWindow(hWnd, TRUE);
      SetForegroundWindow(hWnd);
    }

    // keybd_event(VK_MENU, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0);
    AttachThreadInput(GetCurrentThreadId(), GetWindowThreadProcessId(hWnd, nullptr), FALSE);
    WinKeys.single("VK_MENU", KeySentMode.up);
    // Future<void>.delayed(const Duration(milliseconds: 50), () => keybd_event(VK_MENU, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, 0));
    // SendMessage(hWnd, WM_UPDATEUISTATE, 2 & 0x2, 0);
    // SendMessage(hWnd, WM_ACTIVATE, 0, 0);
  }

  static void forceActivateWindow(int hWnd) {
    activateWindow(hWnd, forced: true);
  }

  static int getActiveWindowHandle() {
    return GetForegroundWindow();
  }

  static void closeWindow(int hWnd, {bool forced = false}) {
    PostMessage(hWnd, WM_CLOSE, 0, 0);
    if (forced) {
      PostMessage(hWnd, WM_CLOSE, 0, 0);
      PostMessage(hWnd, WM_DESTROY, 0, 0);
      PostMessage(hWnd, WM_NCDESTROY, 0, 0);
    }
  }

  static void forceCloseWindowbyProcess(int pId) {
    final List<int> windows = enumWindows();
    for (int hwnd in windows) {
      final Pointer<Uint32> dwID = calloc<Uint32>();
      GetWindowThreadProcessId(hwnd, dwID);
      if (dwID.value == pId) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
      free(dwID);
    }
  }

  //might be useless
  static void forceCloseWindowbyPath(String path) {
    path = path.replaceFirst(Win32.getExe(path), '');
    final List<int> windows = enumWindows();
    for (int hwnd in windows) {
      String hwndPath = HwndPath.getFullPathString(hwnd);
      hwndPath = hwndPath.replaceAll(Win32.getExe(hwndPath), '');
      if (hwndPath == path) {
        closeWindow(hwnd, forced: true);
      }
    }
  }

  //useless
  static void forceCloseByProcessID(int pId) {
    String processPath = Win32.getProcessExePath(pId);
    processPath = processPath.replaceFirst(Win32.getExe(processPath), '');
    if (processPath == "") return;

    final Pointer<Uint32> lpcbNeeded = calloc<Uint32>();
    final Pointer<Uint32> lpidProcess = calloc<Uint32>(1024);

    EnumProcesses(lpidProcess, 1024, lpcbNeeded);
    final int cProcesses = lpcbNeeded.value ~/ sizeOf<DWORD>();

    for (int i = cProcesses - 1; i >= 0; i--) {
      String path = Win32.getProcessExePath(lpidProcess[i]);
      path = path.replaceFirst(Win32.getExe(path), '');
      if (path == processPath) {
        TerminateProcess(lpidProcess[i], 0);
      }
    }

    free(lpcbNeeded);
    free(lpidProcess);
  }

  static String getProcessExePath(int processID) {
    String exePath = "";
    final int hProcess = OpenProcess(PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_INFORMATION | PROCESS_ACCESS_RIGHTS.PROCESS_VM_READ, FALSE, processID);
    if (hProcess == 0) {
      CloseHandle(hProcess);
      return "";
    }

    final LPWSTR imgName = wsalloc(MAX_PATH);
    final Pointer<Uint32> buff = calloc<Uint32>()..value = MAX_PATH;
    if (QueryFullProcessImageName(hProcess, 0, imgName, buff) != 0) {
      final LPWSTR szModName = wsalloc(MAX_PATH);
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
    final LPWSTR lpBaseName = wsalloc(MAX_PATH);
    GetWindowModuleFileName(hWnd, lpBaseName, MAX_PATH);
    String moduleName = lpBaseName.toDartString();
    free(lpBaseName);
    if (moduleName == "") {
      final Pointer<Uint32> ppID = calloc<Uint32>();
      GetWindowThreadProcessId(hWnd, ppID);
      final int wppID = ppID.value;
      free(ppID);
      final int hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, wppID);
      if (hProcess == 0) {
        final LPWSTR szModName = wsalloc(MAX_PATH);
        GetModuleFileNameEx(hProcess, 0, szModName, MAX_PATH);
        moduleName = szModName.toDartString();
        free(szModName);
      }
      CloseHandle(hProcess);
    }
    return moduleName;
  }

  static String getWindowExePath(int hWnd) {
    return HwndPath.getFullPathString(hWnd);
  }

  static String getTitle(int hWnd) {
    String title = "";
    final int length = GetWindowTextLength(hWnd);
    final LPWSTR buffer = wsalloc(length + 1);
    GetWindowText(hWnd, buffer, length + 1);
    title = buffer.toDartString();
    free(buffer);
    return title;
  }

  static bool isWindowPresent(int hWnd) {
    bool visible = true;
    final int exstyle = GetWindowLong(hWnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
    if ((exstyle & WINDOW_EX_STYLE.WS_EX_TOOLWINDOW) != 0) visible = false;
    return visible;
  }

  static bool isWindowCloaked(int hWnd) {
    final Pointer<Int> cloaked = calloc<Int>();
    DwmGetWindowAttribute(hWnd, DWMWINDOWATTRIBUTE.DWMWA_CLOAKED, cloaked, sizeOf<Int>());
    bool result = cloaked.value != 0;
    free(cloaked);
    return result;
  }

  static bool isWindowOnDesktop(int hWnd) {
    return IsWindowVisible(hWnd) != 0 && isWindowPresent(hWnd) && !isWindowCloaked(hWnd);
  }

  static findWindow(String title) {
    return FindWindow(nullptr, TEXT(title));
  }

  static String getClass(int hWnd) {
    final LPWSTR name = wsalloc(256);
    GetClassName(hWnd, name, 256);
    final String className = name.toDartString();
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

  static Future<void> fetchMainWindowHandle() async {
    hWnd = await getFlutterMainWindow();
    hWnd = GetAncestor(hWnd, 2);
    return;
  }

  static getMainHandleByClass() {
    if (hWnd != 0) return hWnd;
    final int hwnd = FindWindow(TEXT("TABAME_WIN32_WINDOW"), nullptr);
    if (hwnd > 0) {
      hWnd = GetAncestor(hwnd, 2);
    }
    return hWnd;
  }

  static Square getWindowRect({int? hwnd}) {
    hwnd ??= hWnd;
    final Pointer<RECT> rect = calloc<RECT>();
    GetWindowRect(hwnd, rect);
    final Square output = Square(x: rect.ref.left, y: rect.ref.top, width: rect.ref.right - rect.ref.left, height: rect.ref.bottom - rect.ref.top);
    free(rect);
    return output;
  }

  static setPosition(Offset position, {int? monitor, int? hwnd}) {
    hwnd ??= hWnd;
    final Square rect = getWindowRect(hwnd: hwnd);
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
      final Square rect = getWindowRect(hwnd: hwnd);
      final double x = (GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CXSCREEN) - rect.width) / 2;
      final double y = (GetSystemMetrics(SYSTEM_METRICS_INDEX.SM_CYSCREEN) - rect.height) / 2;
      SetWindowPos(hwnd, HWND_TOP, x ~/ 1, y ~/ 1, rect.width, rect.height, NULL);
    } else {
      final Square rect = getWindowRect(hwnd: hwnd);
      final int monitor = Monitor.getCursorMonitor();
      final Square monitorSize = Monitor.monitorSizes[monitor]!;
      final double x = (((monitorSize.width + monitorSize.x) - monitorSize.x - rect.width) / 2) + monitorSize.x;
      final double y = (((monitorSize.height + monitorSize.y) - monitorSize.y - rect.height) / 2) + monitorSize.y;
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

  static String getManifestIcon(String appxLocation) {
    if (appxLocation.lastIndexOf('\\') != appxLocation.length) appxLocation += "\\";
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
      String appxIcon = "$appxLocation$icon";
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
      return appxIcon;
    }
    return "";
  }

  static String extractFileNameFromPath(String path) {
    if (path == "") return "";
    path = path.replaceAll('/', '\\');
    if (path.contains('.exe')) {
      return path.substring(path.lastIndexOf('\\') + 1, path.lastIndexOf('.exe'));
    } else {
      final String lastPart = path.substring(path.lastIndexOf('\\') + 1);
      return lastPart.substring(lastPart.indexOf('.') + 1, lastPart.indexOf('_'));
    }
  }

  static Future<void> setMainWindowToMousePos() async {
    PointXY mousePos = WinUtils.getMousePos();
    double horizontal = mousePos.X.toDouble() - 10;
    double vertical = mousePos.Y.toDouble() - 30;

    int flags = TRACK_POPUP_MENU_FLAGS.TPM_LEFTALIGN;

    final Pointer<POINT> anchorPoint = calloc<POINT>();
    anchorPoint.ref.x = horizontal.toInt();
    anchorPoint.ref.y = vertical.toInt();
    final Pointer<RECT> popupWindowPosition = calloc<RECT>();

    final Pointer<SIZE> windowSize = calloc<SIZE>();
    windowSize.ref.cx = 300;
    windowSize.ref.cy = Globals.heights.allSummed.toInt();
    if (globalSettings.showQuickMenuAtTaskbarLevel == false) windowSize.ref.cy += 30;
    if (globalSettings.quickMenuPinnedWithTrayAtBottom == true) windowSize.ref.cy += 30;
    if (windowSize.ref.cy == 0) windowSize.ref.cy = 300;

    CalculatePopupWindowPosition(anchorPoint, windowSize, flags, nullptr, popupWindowPosition);
    horizontal = popupWindowPosition.ref.left.toDouble();
    vertical = popupWindowPosition.ref.top.toDouble();

    if (globalSettings.showQuickMenuAtTaskbarLevel == true) vertical -= 30;
    if (globalSettings.quickMenuPinnedWithTrayAtBottom == false) vertical -= 30;
    await WindowManager.instance.setPosition(Offset(horizontal + 1, vertical));
    // SetForegroundWindow(hWnd);
    // WindowManager.instance.blur();
    WindowManager.instance.focus();

    free(anchorPoint);
    free(popupWindowPosition);
    free(windowSize);
  }

  static void setAlwaysOnTop(int hWnd, {bool? alwaysOnTop}) {
    int topmostOrNot = alwaysOnTop == true ? HWND_TOPMOST : HWND_NOTOPMOST;
    if (alwaysOnTop == null) {
      final int exstyle = GetWindowLong(hWnd, WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE);
      topmostOrNot = (exstyle & WINDOW_EX_STYLE.WS_EX_TOPMOST) != 0 ? HWND_NOTOPMOST : HWND_TOPMOST;
    }
    SetWindowPos(hWnd, topmostOrNot, 0, 0, 0, 0, SET_WINDOW_POS_FLAGS.SWP_NOMOVE | SET_WINDOW_POS_FLAGS.SWP_NOSIZE | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
  }

  /// Activates the window under the cursor.
  static void activeWindowUnderCursor() {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    int hwnd = WindowFromPoint(lpPoint.ref);
    hwnd = GetAncestor(hwnd, 2);
    if (GetForegroundWindow() != hwnd) {
      activateWindow(hwnd);
    }
    free(lpPoint);
  }

  static int parent(int hWnd) {
    int gW = GetWindow(hWnd, 4);
    if (gW != 0 || gW != GetDesktopWindow()) return gW;

    return GetAncestor(hWnd, 2);
  }

  static void focusWindow(int hWnd) {
    SetFocus(hWnd);
    SetActiveWindow(hWnd);
  }

  static bool winExists(int win) {
    return IsWindow(win) != 0;
  }

  static void surfaceWindow(int hWnd) {
    // ShowWindow(hWnd, SW_SHOWNOACTIVATE);
    ShowWindow(hWnd, SHOW_WINDOW_CMD.SW_SHOWNA);

    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SET_WINDOW_POS_FLAGS.SWP_NOMOVE | SET_WINDOW_POS_FLAGS.SWP_NOSIZE | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
    SetWindowPos(hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SET_WINDOW_POS_FLAGS.SWP_NOMOVE | SET_WINDOW_POS_FLAGS.SWP_NOSIZE | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
  }

  static void changePosition(int hWnd, int x, int y, int width, int height) {
    if (x == -1 || y == -1) {
      SetWindowPos(hWnd, HWND_TOP, 0, 0, width, height, SET_WINDOW_POS_FLAGS.SWP_NOMOVE | SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
    } else {
      SetWindowPos(hWnd, HWND_TOP, x, y, width, height, SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE);
    }
  }
}

class WinUtils {
  static void setVolumeOSDStyle({required VolumeOSDStyle type, bool applyStyle = true, int recursiveCheckHwnd = 5}) {
    int volumeHwnd = FindWindowEx(0, NULL, TEXT("NativeHWNDHost"), nullptr);
    if (volumeHwnd == 0) {
      volumeHwnd = FindWindowEx(0, 0, TEXT("DirectUIHWND"), nullptr);
    }

    if (volumeHwnd != 0) {
      if (type == VolumeOSDStyle.normal) {
        SetWindowRgn(volumeHwnd, 0, 1);
        ShowWindow(volumeHwnd, 9);
        keybd_event(VIRTUAL_KEY.VK_VOLUME_UP, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
        keybd_event(VIRTUAL_KEY.VK_VOLUME_DOWN, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
      } else if (type == VolumeOSDStyle.media) {
        final int dpi = GetDpiForWindow(volumeHwnd);
        final double dpiCoef = dpi / 96.0;
        if (applyStyle == true) {
          final int newOsdRegion = CreateRectRgn(0, 0, (60 * dpiCoef).round(), (140 * dpiCoef).round());
          SetWindowRgn(volumeHwnd, newOsdRegion, 1);
        } else {
          SetWindowRgn(volumeHwnd, 0, 1);
        }
        return;
      } else if (type == VolumeOSDStyle.visible) {
        if (volumeHwnd != 0) {
          if (applyStyle == false) {
            ShowWindow(volumeHwnd, 9);

            keybd_event(VIRTUAL_KEY.VK_VOLUME_UP, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
            keybd_event(VIRTUAL_KEY.VK_VOLUME_DOWN, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
          } else {
            ShowWindow(volumeHwnd, 6);
          }
          return;
        }
      } else if (type == VolumeOSDStyle.thin) {
        volumeHwnd = FindWindowEx(NULL, NULL, TEXT("NativeHWNDHost"), nullptr);
        if (volumeHwnd != 0) {
          final int dpi = GetDpiForWindow(volumeHwnd);
          final double dpiCoef = dpi / 96.0;
          if (applyStyle == true) {
            final int newOsdRegion = CreateRectRgn(25, 18, (60 * dpiCoef).round() - (20 * dpiCoef).round(), (140 * dpiCoef).round() - (16 * dpiCoef).round());
            SetWindowRgn(volumeHwnd, newOsdRegion, 1);
            final int dc = GetWindowDC(volumeHwnd);
            SetBkColor(dc, 0xFF00FF00);
          } else {
            SetWindowRgn(volumeHwnd, 0, 1);
          }
        }
      }
    } else {
      keybd_event(VIRTUAL_KEY.VK_VOLUME_UP, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
      keybd_event(VIRTUAL_KEY.VK_VOLUME_DOWN, MapVirtualKey(VIRTUAL_KEY.VK_VOLUME_UP, 0), 0, 0);
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
    final Pointer<Int32> pquns = calloc<Int32>();
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
    final Pointer<GUID> appsFolder = GUIDFromString(FOLDERID_LocalAppData);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();

    try {
      final int hr = SHGetKnownFolderPath(appsFolder, KNOWN_FOLDER_FLAG.KF_FLAG_DEFAULT, NULL, ppszPath);

      if (FAILED(hr)) {
        throw WindowsException(hr);
      }

      final String path = ppszPath.value.toDartString();
      return path;
    } finally {
      free(appsFolder);
      free(ppszPath);
    }
  }

/*   static String getLocalAppData() {
    RoInitialize(RO_INIT_TYPE.RO_INIT_SINGLETHREADED);
    final UserDataPaths userData = UserDataPaths.GetDefault();
    final int hStrLocalAppData = userData.LocalAppData; //userData.RoamingAppData;

    final String localAppData = WindowsGetStringRawBuffer(hStrLocalAppData, nullptr).toDartString();

    RoUninitialize();
    return localAppData;
  } */

  static String getKnownFolder(String FOLDERID) {
    final Pointer<GUID> appsFolder = GUIDFromString(FOLDERID);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();
    String path = "";
    final int hr = SHGetKnownFolderPath(appsFolder, KNOWN_FOLDER_FLAG.KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      path = ppszPath.value.toDartString();
    }
    free(ppszPath);
    free(appsFolder);
    return path;
  }

  static String getKnownFolderCLSID(int CSIDL) {
    final LPWSTR startMenuPath = wsalloc(MAX_PATH);
    String path = "";
    // final int hr = SHGetKnownFolderPath(NULL, KF_FLAG_DEFAULT, NULL, ppszPath);
    final int hr = SHGetFolderPath(NULL, CSIDL, NULL, 0, startMenuPath);
    if (!FAILED(hr)) {
      path = startMenuPath.toDartString();
    }
    free(startMenuPath);
    return path;
  }

  static String getTempFolder() {
    final LPWSTR out = wsalloc(MAX_PATH);
    GetTempPath(MAX_PATH, out);
    final String result = out.toDartString();
    free(out);
    return result;
  }

  static String getTabameSettingsFolder() {
    final String folder = "${WinUtils.getKnownFolder(FOLDERID_LocalAppData)}\\Tabame";
    if (!Directory(folder).existsSync()) Directory(folder).createSync();
    return folder;
  }

  static Future<void> setStartUpShortcut(bool enabled, {String args = "", String? exePath, int showCmd = 1}) async {
    exePath ??= Platform.resolvedExecutable;
    setStartOnSystemStartup(enabled, args: args, exePath: exePath, showCmd: showCmd);
  }

  static Future<List<String>> getTaskbarPinnedApps() async {
    List<String> output = <String>[];
    String path = getKnownFolder(FOLDERID_UserPinned);
    if (path == "") {
      path = "${getLocalAppData()}\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned";
    }
    final Iterable<io.FileSystemEntity> items = Directory("$path\\TaskBar").listSync().where((io.FileSystemEntity event) => event.path.endsWith(".lnk"));
    for (io.FileSystemEntity element in items) {
      String newPath = await convertLinkToPath(element.path);
      if (newPath == "") {
        newPath = "${getKnownFolder(FOLDERID_Windows)}\\explorer.exe";
      }
      output.add(newPath);
    }
    return output;
  }

  static bool checkIfRegisterAsStartup() {
    final String filePath = getStartupShortcut();
    if (filePath == "") return false;
    final io.File file = io.File(filePath);
    return file.existsSync();
  }

  static String getStartupShortcut() {
    final LPWSTR startMenuPath = wsalloc(MAX_PATH);
    int result = SHGetFolderPath(NULL, CSIDL_PROGRAMS, NULL, 0, startMenuPath);
    if (result != S_OK) {
      free(startMenuPath);
      return "";
    }
    final String path = startMenuPath.toDartString();
    free(startMenuPath);
    final String filePath = "$path\\Startup\\tabame.lnk";
    return filePath;
  }

  static Future<List<String>> getTaskbarPinnedAppsPowerShell() async {
    String path = getKnownFolder(FOLDERID_UserPinned);
    if (path == "") {
      path = "${getLocalAppData()}\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned";
    }
    path += "\\Taskbar";
    final int allContents = await Directory(path).list().where((io.FileSystemEntity event) => event.path.endsWith(".lnk")).length;
    List<String> commands = <String>[
      "\$WScript = New-Object -ComObject WScript.Shell;",
      "Get-ChildItem -Path \"$path\" | ForEach-Object {\$WScript.CreateShortcut(\$_.FullName).TargetPath};",
    ];
    List<String> output = await runPowerShell(commands);
    if (allContents != output.length) {
      output.insert(0, "${getKnownFolder(FOLDERID_Windows)}\\explorer.exe");
    }
    return output;
  }

  static Future<List<String>> runPowerShell(List<String> commands) async {
    final io.ProcessResult result = await io.Process.run(
      'powershell',
      <String>['-NoProfile', ...commands],
    );
    if (result.stderr != '') {
      return <String>[];
    }
    List<String> output = result.stdout.toString().trim().split('\n').map((String e) => e.trim()).toList();
    return output;
  }

  static Future<void> shellOpen(String path, {String? arguments}) async {
    await nativeShellOpen(path, arguments: arguments ?? "");
  }

  static void open(String path, {String? arguments, bool parseParamaters = false, bool userpowerShell = false}) {
    if (userpowerShell && arguments == null && !parseParamaters && globalSettings.runAsAdministrator && !path.startsWith("http")) {
      //! you can gain admin priv with one command, but there is no command to de-elevate yourself or app you are launching.
      //! only way I've found is to start powershell that starts explorer THAT starts the file.
      runPowerShell(<String>['explorer.exe "$path"']);

/*  //? testing every method, didnt work
       $newProc = new-object System.Diagnostics.ProcessStartInfo "PowerShell"
      # Specify what to run, you need the full path after explorer.exe
      $newProc.Arguments = "explorer.exe C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
      [System.Diagnostics.Process]::Start($newProc)
      io.Process.run("explorer.exe", <String>['"$path"']);
      io.Process.run("runas", <String>["/trustlevel:0x20000", '"$path"']);
      ShellExecute(NULL, TEXT("runas"), TEXT(path), TEXT("/trustlevel:0x20000"), nullptr, SW_SHOWNORMAL);

      io.Process.run("explorer.exe", <String>['"$path"']);

      return;
      ShellExecute(hwnd, lpOperation, lpFile, lpParameters, lpDirectory, nShowCmd)

      final io.File vbs = File("${getTabameSettingsFolder()}\\bat.vbs");
      if (!vbs.existsSync()) {
        vbs.writeAsStringSync('Set shell = CreateObject("WScript.Shell")\nshell.Run "run_aux.bat"');
      }
      final io.File bat = File("${getTabameSettingsFolder()}\\vbs.bat");
      if (!bat.existsSync()) {
        bat.writeAsStringSync("@echo off\npushd %~dp0\ncscript bat.vbs");
      }
      final String run = "${getTabameSettingsFolder()}\\run_aux.bat";
      File(run).writeAsStringSync('START "" "$path"');

      io.Process.run("${getTabameSettingsFolder()}\\vbs.bat", <String>[]);
      runPowerShell(['-c', '"$path"']);
      io.Process.run(
        "powershell",
        <String>['-c "$path"'],
        // includeParentEnvironment: false,
        runInShell: true,
      );
      WinUtils.runPowerShell(<String>['Invoke-Item "$path"']);  
*/
      return;
    }
    if (parseParamaters) {
      final RegExp reg = RegExp(r"^([a-z0-9-_]+) (.*?)$");
      if (reg.hasMatch(path)) {
        final RegExpMatch out = reg.firstMatch(path)!;
        if (!globalSettings.runAsAdministrator) {
          ShellExecute(NULL, TEXT("open"), TEXT(out.group(1)!), TEXT(out.group(2)!), nullptr, SHOW_WINDOW_CMD.SW_SHOWNORMAL);
          return;
        }
        final String fileOpen = "${WinUtils.getTabameSettingsFolder()}\\open.vbs";
        File(fileOpen).writeAsStringSync("""
Dim objShell
Set objShell = CreateObject("Shell.Application")
Call objShell.ShellExecute("${out.group(1)}", "${out.group(2)!.replaceAll('"', '""')}", "", "open", ${out.group(1) == "code" ? 0 : 1})""");
        runPowerShell(<String>['explorer.exe "$fileOpen"']);
      } else {
        // ShellExecute(NULL, TEXT("open"), TEXT(path), arguments == null ? nullptr : TEXT(arguments), nullptr, SW_SHOWNORMAL);
        runPowerShell(<String>['explorer.exe "$path"']);
      }
    } else {
      ShellExecute(NULL, TEXT("open"), TEXT(path), arguments == null ? nullptr : TEXT(arguments), nullptr,
          path == "code" ? SHOW_WINDOW_CMD.SW_HIDE : SHOW_WINDOW_CMD.SW_SHOWNORMAL);
    }
  }

  static void run(String link, {String? arguments}) {
    ShellExecute(NULL, TEXT("runas"), TEXT(link), arguments == null ? nullptr : TEXT(arguments), nullptr, SHOW_WINDOW_CMD.SW_SHOWNORMAL);
  }

  static void nativeOpen(String link, {String? arguments}) {
    ShellExecute(NULL, TEXT("open"), TEXT(link), arguments == null ? nullptr : TEXT(arguments), nullptr, SHOW_WINDOW_CMD.SW_SHOWNORMAL);
  }

  static void sendCommand({int command = AppCommand.appCommand}) {
    SendMessage(NULL, AppCommand.appCommand, 0, command);
  }

  static String getTaskManagerPath() {
    String location = "";
    final Pointer<GUID> folder = GUIDFromString(FOLDERID_Windows);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();
    final int hr = SHGetKnownFolderPath(folder, KNOWN_FOLDER_FLAG.KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      location = "${ppszPath.value.toDartString()}\\System32\\Taskmgr.exe";
    }
    free(ppszPath);
    return location;
  }

  static String __programFiles = "";
  static String getProgramFilesFolder() {
    if (__programFiles != "") return __programFiles;
    String location = "";
    final Pointer<GUID> folder = GUIDFromString(FOLDERID_ProgramFiles);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();
    final int hr = SHGetKnownFolderPath(folder, KNOWN_FOLDER_FLAG.KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      location = ppszPath.value.toDartString();
    }
    free(ppszPath);
    __programFiles = location;
    return location;
  }

  static void toggleTaskbar({bool? visible}) {
    Globals.taskbarVisible = visible ?? !Globals.taskbarVisible;
    setTaskbarVisibility(Globals.taskbarVisible);
  }

  static void moveDesktop(DesktopDirection direction, {bool classMethod = false}) {
    // if (classMethod) {
    //   moveDesktopMethod(direction);
    //   return;
    // }
    String key = "RIGHT";
    if (direction == DesktopDirection.left) key = "LEFT";
    WinKeys.send("{#WIN}{#CTRL}{$key}");
  }

  static PointXY getMousePos() {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    PointXY point = PointXY(X: 0, Y: 0);
    point.X = lpPoint.ref.x;
    point.Y = lpPoint.ref.y;
    free(lpPoint);
    point = Monitor.adjustPointToDPI(point);
    return point;
  }

  static List<int> getMousePosXY() {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    PointXY point = PointXY(X: 0, Y: 0);
    point.X = lpPoint.ref.x;
    point.Y = lpPoint.ref.y;
    free(lpPoint);
    point = Monitor.adjustPointToDPI(point);
    return <int>[point.X, point.Y];
  }

  static alwaysAwakeRun(bool state) {
    if (state == false) {
      SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
    } else {
      Timer.periodic(const Duration(seconds: 45), (Timer timer) {
        if (Globals.alwaysAwake == false) {
          SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS);
          timer.cancel();
        } else {
          SetThreadExecutionState(EXECUTION_STATE.ES_CONTINUOUS | EXECUTION_STATE.ES_SYSTEM_REQUIRED | EXECUTION_STATE.ES_AWAYMODE_REQUIRED);
        }
      });
    }
  }

  static void openAndFocus(String path, {bool centered = false, bool usePowerShell = false}) {
    final Set<int> startWindows = enumWindows().toSet();
    WinUtils.open(path, userpowerShell: usePowerShell);
    int ticker = 0;
    Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      ticker++;
      if (ticker > 11) {
        timer.cancel();
        return;
      }
      final Set<int> endWindows = enumWindows().toSet();
      final List<int> newWnds = List<int>.from(endWindows.difference(startWindows));
      final List<int> windows = newWnds.where(((int hWnd) => (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "") ? true : false)).toList();
      if (windows.isEmpty) return;
      final int hwnd = windows[0];
      Win32.activateWindow(hwnd);
      if (!centered) return;
      Win32.setCenter(hwnd: hwnd, useMouse: true);
      timer.cancel();
    });
  }

  static void toggleDesktopFiles({bool? visible}) {
    final String desktop = WinUtils.getKnownFolderCLSID(CSIDL_DESKTOP);
    final List<String> files = Directory(desktop).listSync().map((io.FileSystemEntity event) => event.path).toList();
    for (String file in files.reversed) {
      if (file.contains("desktop.ini")) continue;
      final int attributes = GetFileAttributes(TEXT(file));
      if (visible == null) {
        if ((attributes & FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN) == FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN) {
          visible = true;
        } else {
          visible = false;
        }
      }
      if (!visible && (attributes & FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN) == 0) {
        SetFileAttributes(TEXT(file), attributes | FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN);
      }
      if (visible && (attributes & FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN) == FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN) {
        SetFileAttributes(TEXT(file), attributes & ~FILE_FLAGS_AND_ATTRIBUTES.FILE_ATTRIBUTE_HIDDEN);
      }
    }
  }

  static Future<void> toggleHiddenFiles({bool? visible}) async {
    final RegistryKey key =
        Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced', desiredAccessRights: AccessRights.allAccess);
    final int hidden = key.getValueAsInt('Hidden') ?? 1;
    // 1 - Visible, 2 - Hidden
    int newValue = 1;
    if (visible != null) {
      if (visible) {
        newValue = 1;
      } else {
        newValue = 2;
      }
    } else if (hidden == 2) {
      newValue = 1;
    } else {
      newValue = 2;
    }
    key.createValue(RegistryValue("Hidden", RegistryValueType.int32, newValue));
    await Future<void>.delayed(const Duration(milliseconds: 500), () => SendNotifyMessage(HWND_BROADCAST, 0x111, 41504, NULL));
    return;
  }

  static Future<void> textToSpeech(String text, {int repeat = 1, int volume = 100}) async {
    if (repeat == -1) {
      final RegExp reg = RegExp(r'x\d+$');
      final RegExpMatch? match = reg.firstMatch(text);
      if (match != null) {
        text = text.substring(0, text.length - match[0]!.length);
        repeat = int.parse(match[0]!.substring(1));
      } else {
        repeat = 1;
      }
    }
    List<String> commands = <String>[
      "Add-Type -AssemblyName System.speech;",
      "\$speak = New-Object System.Speech.Synthesis.SpeechSynthesizer;",
      "\$speak.Volume = $volume;"
    ];
    for (int i = 0; i < repeat; i++) {
      commands.add("\$speak.Speak('${text.replaceAll("'", '"')}');");
    }
    await WinUtils.runPowerShell(commands);
  }

  static bool windowsNotificationRegistered = false;
  static void showWindowsNotification({required String title, required String body, required Null Function() onClick}) async {
    if (!windowsNotificationRegistered) {
      windowsNotificationRegistered = true;
      await localNotifier.setup(appName: 'Tabame', shortcutPolicy: ShortcutPolicy.requireCreate);
    }
    if (globalSettings.usePowerShellAsToastNotification) {
      await WinUtils.runPowerShell(<String>[
        '''\$subject = [Security.SecurityElement]::Escape("${title.replaceAll('"', "'")}");''',
        '''\$message = [Security.SecurityElement]::Escape("${body.replaceAll('"', "'")}");''',
        '''[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null;''',
        '''[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null;''',
        '''[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null;''',
        '''\$xml = New-Object Windows.Data.Xml.Dom.XmlDocument;''',
        '''\$template = "<toast><audio silent='false'/><visual><binding template='ToastGeneric'><text id='1'>\$subject</text><text id='2'>\$message</text></binding></visual></toast>";''',
        '''\$xml.LoadXml(\$template);''',
        '''\$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml;''',
        '''[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Tabame").Show(\$toast);''',
      ]);
      return;
    }
    LocalNotification notification = LocalNotification(
      title: title,
      body: body,
    );
    notification.onClick = () => onClick();
    await notification.show();
  }

  static Future<String> folderPicker() async {
    return await pickFolder();
  }

  static startOnStartup({String? exeFilePath, String? arguments}) {
    // ! doenst work
    CoInitializeEx(nullptr, COINIT.COINIT_APARTMENTTHREADED);
    final Pointer<Pointer<COMObject>> ppsi = calloc<Pointer<COMObject>>();
    final Pointer<COMObject> ppfi = calloc<COMObject>();

    exeFilePath ??= Platform.resolvedExecutable;
    final String directory = Directory(exeFilePath).parent.path;
    final IShellLink shell = IShellLink(ppsi.cast());

    shell.setPath(TEXT(exeFilePath));
    shell.setWorkingDirectory(TEXT(directory));
    shell.setShowCmd(SHOW_WINDOW_CMD.SW_SHOWNORMAL);

    if (arguments != null) shell.setArguments(TEXT(arguments));

    final IPersistFile file = IPersistFile(shell.toInterface(IID_IPersistFile));
    final String startUpPath = getKnownFolderCLSID(CSIDL_STARTUP);
    final String exeName = File(exeFilePath).uri.pathSegments.last.replaceFirst(".exe", ".lnk");
    file.save(TEXT("$startUpPath\\$exeName"), TRUE);
    file.release();
    shell.release();
    CoUninitialize();
    free(ppsi);
    free(ppfi);
  }

  static msgBox(String text, String title) {
    MessageBox(0, TEXT(text), TEXT(title), MESSAGEBOX_STYLE.MB_ICONEXCLAMATION | MESSAGEBOX_STYLE.MB_DEFAULT_DESKTOP_ONLY);
  }

  static startTabame({bool closeCurrent = false, String? arguments}) {
    if (WinUtils.isAdministrator()) {
      WinUtils.run(Platform.resolvedExecutable, arguments: arguments);
    } else {
      WinUtils.open(Platform.resolvedExecutable, arguments: arguments);
    }
    if (closeCurrent) {
      Future<void>.delayed(const Duration(milliseconds: 400), () => exit(0));
    }
  }

  static closeAllTabameExProcesses() {
    final List<int> wins = enumWindows();
    for (int win in wins) {
      if (Win32.getClass(win) == "TABAME_WIN32_WINDOW" && win != Win32.hWnd) {
        Win32.closeWindow(win);
      }
    }
  }

  static reloadTabameQuickMenu() {
    if (!kReleaseMode) return;
    closeAllTabameExProcesses();
    startTabame(closeCurrent: false, arguments: "-restarted");
  }

/*   static Future<String> getCountryCityFromIP(String defaultResult) async {
    final http.Response ip = await http.get(Uri.parse("http://ifconfig.me/ip"));
    if (ip.statusCode == 200) {
      final http.Response response = await http.get(Uri.parse("http://ip-api.com/json/${ip.body}"));
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        if (data.containsKey("city") && data.containsKey("country")) {
          return "${data["city"]}, ${data["country"]}";
        }
      }
    }
    return defaultResult;
  } */
  static Future<void> downloadFile(String url, String filename, Function callback) async {
    http.Client httpClient = http.Client();
    http.Request request = http.Request('GET', Uri.parse(url));
    Future<http.StreamedResponse> response = httpClient.send(request);

    List<List<int>> chunks = <List<int>>[];
    response.asStream().listen((http.StreamedResponse r) {
      r.stream.listen((List<int> chunk) {
        chunks.add(chunk);
      }, onDone: () async {
        File file = File('$filename');
        final Uint8List bytes = Uint8List(r.contentLength!);
        int offset = 0;
        for (List<int> chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        await file.writeAsBytes(bytes);
        callback();
        return;
      });
    });
  }

  static bool isWindows11() {
    // var reg = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
    final RegistryKey reg = Registry.openPath(RegistryHive.localMachine, path: r'SOFTWARE\Microsoft\Windows NT\CurrentVersion');

    // var currentBuildStr = (string)reg.GetValue("CurrentBuild");
    // var currentBuild = int.Parse(currentBuildStr);
    final int currentBuild = reg.getValueAsInt("CurrentBuild") ?? 0;

    return currentBuild >= 22000;
  }

  static bool isWindows10() {
    return Platform.operatingSystemVersion.contains("Windows 10");
  }

  static bool isScreenClipping() {
    final int hWnd = GetForegroundWindow();
    final Pointer<Uint32> lpdwProcessId = calloc<Uint32>();

    GetWindowThreadProcessId(hWnd, lpdwProcessId);
    // Get a handle to the process.
    final int hProcess = OpenProcess(
      PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_INFORMATION | PROCESS_ACCESS_RIGHTS.PROCESS_VM_READ,
      FALSE,
      lpdwProcessId.value,
    );

    if (hProcess == 0) {
      return false;
    }

    // Get a list of all the modules in this process.
    final Pointer<HMODULE> hModules = calloc<HMODULE>(1024);
    final Pointer<DWORD> cbNeeded = calloc<DWORD>();

    try {
      int r = EnumProcessModules(
        hProcess,
        hModules,
        sizeOf<HMODULE>() * 1024,
        cbNeeded,
      );

      if (r == 1) {
        for (int i = 0; i < (cbNeeded.value ~/ sizeOf<HMODULE>()); i++) {
          final LPWSTR szModName = wsalloc(MAX_PATH);
          // Get the full path to the module's file.
          final int hModule = (hModules + i).value;
          if (GetModuleFileNameEx(hProcess, hModule, szModName, MAX_PATH) != 0) {
            String moduleName = szModName.toDartString();
            if (moduleName.contains("ScreenClippingHost.exe")) {
              free(szModName);
              return true;
            }
          }
          free(szModName);
        }
      }
    } finally {
      free(hModules);
      free(cbNeeded);
      CloseHandle(hProcess);
    }

    return false;
  }

  static Future<bool> screenCapture() async {
    await Clipboard.setData(const ClipboardData(text: ''));
    ShellExecute(
      0,
      "open".toNativeUtf16(),
      "ms-screenclip://?clippingMode=Rectangle".toNativeUtf16(),
      nullptr,
      nullptr,
      SHOW_WINDOW_CMD.SW_SHOWNORMAL,
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    while (isScreenClipping()) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final String temp = getTempFolder();
    await WinClipboard().saveClipboardToPng("$temp\\capture.png");
    return true;
  }

  static Uint8List? extractIcon(String path, {int iconID = 0}) {
    if (path.contains('.dll') && iconID != 98988) {
      final Pointer<IntPtr> phiconLarge = calloc<IntPtr>();
      final Pointer<IntPtr> phiconSmall = calloc<IntPtr>();
      final Pointer<Utf16> lpszFile = path.toNativeUtf16();

      final int result = ExtractIconEx(lpszFile, iconID, phiconLarge, phiconSmall, 1);
      free(lpszFile);
      if (result > 0) {
        calloc.free(phiconLarge);
        calloc.free(phiconSmall);
        final Uint8List? bytes = hIconToBytes(phiconLarge.value);

        DestroyIcon(phiconLarge.value);
        DestroyIcon(phiconSmall.value);
        return bytes;
      }
      calloc.free(phiconLarge);
      calloc.free(phiconSmall);
      return extractIcon(path, iconID: 98988);
    }
    return using((Arena arena) {
      final Pointer<Utf16> filePath = path.toNativeUtf16(allocator: arena);
      final int instance = GetModuleHandle(nullptr);
      final Pointer<WORD> iID = arena<WORD>();
      //iID.value = iconID;

      final int hIcon = ExtractAssociatedIcon(instance, filePath, iID);
      if (hIcon == NULL) return null;

      return hIconToBytes(hIcon);
    });
  }

  static Uint8List? windowIcon(int hWnd) {
    int iconResult = SendMessage(hWnd, WM_GETICON, 2, 0); // ICON_SMALL2 - User Made Apps
    if (iconResult == 0) {
      iconResult = GetClassLongPtr(hWnd, -14); // GCLP_HICON - Microsoft Win Apps
      // print("$hWnd From Class: ${Win32.getTitle(hWnd)}");
    } else {
      // print("$hWnd From Message: ${Win32.getTitle(hWnd)}");
    }
    return hIconToBytes(iconResult);
  }

  static Uint8List? hIconToBytes(int hIcon, {int nColorBits = 32}) {
    return using((Arena arena) {
      final List<int> buffer = <int>[];
      final int hdc = CreateCompatibleDC(NULL);

      final List<int> icoHeader = <int>[0, 0, 1, 0, 1, 0];
      buffer.addAll(icoHeader);

      final Pointer<ICONINFO> iconInfo = arena<ICONINFO>();
      if (GetIconInfo(hIcon, iconInfo) == 0) {
        DeleteDC(hdc);
        return null;
      }

      final Pointer<BITMAPINFO> bmInfo = arena<BITMAPINFO>();
      bmInfo.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biBitCount = 0;

      if (GetDIBits(
            hdc,
            iconInfo.ref.hbmColor,
            0,
            0,
            nullptr,
            bmInfo,
            DIB_USAGE.DIB_RGB_COLORS,
          ) ==
          0) {
        DeleteDC(hdc);
        return null;
      }

      int nBmInfoSize = sizeOf<BITMAPINFOHEADER>();
      if (nColorBits < 24) {
        nBmInfoSize += sizeOf<RGBQUAD>() * (1 << nColorBits);
      }

      if (bmInfo.ref.bmiHeader.biSizeImage == 0) {
        DeleteDC(hdc);
        return null;
      }

      final Pointer<Uint8> bits = arena<Uint8>(bmInfo.ref.bmiHeader.biSizeImage);

      bmInfo.ref.bmiHeader
        ..biBitCount = nColorBits
        ..biCompression = BI_COMPRESSION.BI_RGB;

      if (GetDIBits(
            hdc,
            iconInfo.ref.hbmColor,
            0,
            bmInfo.ref.bmiHeader.biHeight,
            bits,
            bmInfo,
            DIB_USAGE.DIB_RGB_COLORS,
          ) ==
          0) {
        DeleteDC(hdc);
        return null;
      }

      final Pointer<BITMAPINFO> maskInfo = arena<BITMAPINFO>();
      maskInfo.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biBitCount = 0;

      if (GetDIBits(
                hdc,
                iconInfo.ref.hbmMask,
                0,
                0,
                nullptr,
                maskInfo,
                DIB_USAGE.DIB_RGB_COLORS,
              ) ==
              0 ||
          maskInfo.ref.bmiHeader.biBitCount != 1) {
        DeleteDC(hdc);
        return null;
      }

      final Pointer<Uint8> maskBits = arena<Uint8>(maskInfo.ref.bmiHeader.biSizeImage);
      if (GetDIBits(
            hdc,
            iconInfo.ref.hbmMask,
            0,
            maskInfo.ref.bmiHeader.biHeight,
            maskBits,
            maskInfo,
            DIB_USAGE.DIB_RGB_COLORS,
          ) ==
          0) {
        DeleteDC(hdc);
        return null;
      }

      final Pointer<_IconDirectoryEntry> dir = arena<_IconDirectoryEntry>();
      dir.ref
        ..nWidth = bmInfo.ref.bmiHeader.biWidth
        ..nHeight = bmInfo.ref.bmiHeader.biHeight
        ..nNumColorsInPalette = (nColorBits == 4 ? 16 : 0)
        ..nNumColorPlanes = 0
        ..nBitsPerPixel = bmInfo.ref.bmiHeader.biBitCount
        ..nDataLength = bmInfo.ref.bmiHeader.biSizeImage + maskInfo.ref.bmiHeader.biSizeImage + nBmInfoSize
        ..nOffset = sizeOf<_IconDirectoryEntry>() + 6;

      buffer.addAll(dir.cast<Uint8>().asTypedList(sizeOf<_IconDirectoryEntry>()));

      bmInfo.ref.bmiHeader
        ..biHeight *= 2
        ..biCompression = 0
        ..biSizeImage += maskInfo.ref.bmiHeader.biSizeImage;
      buffer.addAll(bmInfo.cast<Uint8>().asTypedList(nBmInfoSize));

      buffer.addAll(bits.asTypedList(bmInfo.ref.bmiHeader.biSizeImage));
      buffer.addAll(maskBits.asTypedList(maskInfo.ref.bmiHeader.biSizeImage));

      DeleteObject(iconInfo.ref.hbmColor);
      DeleteObject(iconInfo.ref.hbmMask);
      DeleteDC(hdc);

      return Uint8List.fromList(buffer);
    });
  }
}

base class _IconDirectoryEntry extends Struct {
  @Uint8()
  external int nWidth;

  @Uint8()
  external int nHeight;

  @Uint8()
  external int nNumColorsInPalette;

  @Uint8()
  external int nReserved;

  @Uint16()
  external int nNumColorPlanes;

  @Uint16()
  external int nBitsPerPixel;

  @Uint32()
  external int nDataLength;

  @Uint32()
  external int nOffset;
}

class WizardlyContextMenu {
  bool isWizardlyInstalledInContextMenu() {
    try {
      final RegistryKey xxxkey = Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory');
      if (!xxxkey.subkeyNames.contains('Background')) {
        xxxkey.createKey("Background");
      }
      xxxkey.close();
      final RegistryKey xxkey = Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background');
      if (!xxkey.subkeyNames.contains('shell')) {
        xxkey.createKey("shell");
      }
      xxkey.close();
      final RegistryKey key =
          Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background\shell', desiredAccessRights: AccessRights.allAccess);

      final bool output = key.subkeyNames.contains("tabame");
      key.close();
      return output;
    } catch (_) {
      return false;
    }
  }

  void toggleWizardlyToContextMenu() {
    try {
      final RegistryKey xxkey = Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background');
      if (!xxkey.subkeyNames.contains('shell')) {
        xxkey.createKey("shell");
      }
      xxkey.close();
      final RegistryKey key =
          Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background\shell', desiredAccessRights: AccessRights.allAccess);

      final String exe = Platform.resolvedExecutable;
      if (key.subkeyNames.contains("tabame")) {
        key.deleteKey(r'tabame\command');
        key.deleteKey('tabame');
        return;
      }
      final RegistryKey subkey = key.createKey("tabame");
      subkey.createValue(RegistryValue(r"Icon", RegistryValueType.string, exe));
      subkey.createValue(const RegistryValue("", RegistryValueType.string, "Open in Wizardly"));

      final RegistryKey command = subkey.createKey("command");
      command.createValue(RegistryValue("", RegistryValueType.string, '"$exe" "%V" -interface -wizardly'));

      key.close();
      return;
    } catch (_) {
      return;
    }
  }
}

class WinIcons {
  //[0] - Path, [1] - iconINDEX, which is +/- int
  List<List<dynamic>> list = <List<dynamic>>[];
  WinIcons();
  void add(String item) {
    int dll = 0;
    if (item.contains(',')) {
      final String lastItem = item.substring(item.lastIndexOf('.'));
      final List<String> xploded = lastItem.split(',');
      if (xploded.length == 2) {
        dll = int.parse(xploded[1]);
        item = item.replaceAll(',$dll', '');
      }
    }
    list.add(<dynamic>[item, dll]);
  }

  void addAll(List<String> item) {
    for (String element in item) {
      add(element);
    }
  }

  Future<void> fetch(String directory) async {
    List<String> commands = <String>[
      "Add-Type -AssemblyName System.Drawing;",
      "\$Format = [System.Drawing.Imaging.ImageFormat]::Png;",
    ];
    if (list.where((List<dynamic> e) => e[1] != 0).isNotEmpty) {
      commands.add(
          '''add-type -typeDefinition ' using System; using System.Runtime.InteropServices; public class Shell32_Extract {  [DllImport(  "Shell32.dll",  EntryPoint = "ExtractIconExW",  CharSet = CharSet.Unicode,  ExactSpelling = true,  CallingConvention = CallingConvention.StdCall)  ]  public static extern int ExtractIconEx(  string lpszFile ,   int iconIndex ,   out IntPtr phiconLarge,  out IntPtr phiconSmall,  int nIcons  ); }';''');
    }
    int totalAdded = 0;
    for (List<dynamic> element in list) {
      final String path = element[0];
      final int iconID = element[1];
      final String exePath = Win32.getExe(path);
      String exeCache = directory;

      if (iconID != 0) {
        exeCache += "\\dll_${iconID}_$exePath.cached";
        if (File(exeCache).existsSync()) continue;
        totalAdded++;
        commands.addAll(<String>[
          "[System.IntPtr] \$phiconLarge = 0;",
          "[System.IntPtr] \$phiconSmall = 0;",
          "[Shell32_Extract]::ExtractIconEx('$path', $iconID, [ref] \$phiconLarge, [ref] \$phiconSmall, 1);",
          "\$Icon = [System.Drawing.Icon]::FromHandle(\$phiconSmall).ToBitMap().Save('$exeCache',\$Format);",
        ]);
      } else {
        exeCache += "\\$exePath.cached";
        if (File(exeCache).existsSync()) continue;
        totalAdded++;
        commands.add("\$Icon = [System.Drawing.Icon]::ExtractAssociatedIcon('$path').ToBitMap().Save('$exeCache',\$Format);");
      }
    }
    if (totalAdded > 0) {
      await WinUtils.runPowerShell(commands);
    }
  }

  Future<List<Uint8List>> getHandleIcons(List<int> handles) async {
    List<String> commands = <String>[
      "Add-Type -AssemblyName System.Drawing;",
      "\$Format = [System.Drawing.Imaging.ImageFormat]::Png;",
    ];
    for (int handle in handles) {
      commands.addAll(<String>[
        "\$MemoryStream = New-Object System.IO.MemoryStream;",
        "[System.Drawing.Icon]::FromHandle($handle).ToBitMap().Save(\$MemoryStream,\$Format);",
        "\$Bytes = \$MemoryStream.ToArray();",
        "\$MemoryStream.Flush();",
        "\$MemoryStream.Dispose();",
        "[convert]::ToBase64String(\$Bytes);",
      ]);
    }
    final List<String> output = await WinUtils.runPowerShell(commands);
    List<Uint8List> list = output.map(base64Decode).toList();

    return list;
  }

  Future<Uint8List> getHandleIcon(int handle) async {
    final List<int> handles = <int>[handle];
    final List<Uint8List> output = await getHandleIcons(handles);
    if (output.isNotEmpty) {
      return output[0];
    } else {
      return Uint8List.fromList(<int>[0]);
    }
  }
}

class HProcess {
  String path = "";
  String exe = "";
  int pId = 0;
  int mainPID = 0;
  int iconHandle = 0;
  String className = "";
  HProcess();
  String get exePath => "$path$exe";

  @override
  String toString() {
    return 'HProcess(path: $path, exe: $exe, pId: $pId, className: $className)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HProcess && other.path == path && other.exe == exe && other.pId == pId && other.mainPID == mainPID && other.className == className;
  }

  @override
  int get hashCode {
    return path.hashCode ^ exe.hashCode ^ pId.hashCode ^ mainPID.hashCode ^ className.hashCode;
  }
}

class HwndInfo {
  String path = "";
  bool isAppx = false;
  HwndInfo({
    required this.path,
    required this.isAppx,
  });

  @override
  String toString() => 'HwndInfo(path: $path, isAppx: $isAppx)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is HwndInfo && other.path == path && other.isAppx == isAppx;
  }

  @override
  int get hashCode => path.hashCode ^ isAppx.hashCode;
}

final Map<int, HwndInfo> __cacheHwnds = <int, HwndInfo>{};

class HwndPath {
  static String GetAppxInstallLocation(int hWnd) {
    //Get Process Handle
    int process;
    final Pointer<Uint32> ppID = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, ppID);
    process = OpenProcess(PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
    free(ppID);
    //Get Text
    final Pointer<Uint32> cMax = calloc<Uint32>()..value = 512;
    LPWSTR cAppName = wsalloc(cMax.value);
    GetApplicationUserModelId(process, cMax, cAppName);
    String name = cAppName.toDartString();
    free(cMax);

    //It's main Window Handle On EdgeView Apps, query first child
    if (name.isEmpty) {
      final int parentHwnd = GetAncestor(hWnd, 2);
      final List<int> childWins = enumChildWins(parentHwnd);
      if (childWins.length > 1) {
        CloseHandle(process);
        hWnd = childWins[1];

        final Pointer<Uint32> ppID = calloc<Uint32>();
        GetWindowThreadProcessId(hWnd, ppID);
        process = OpenProcess(PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
        free(ppID);

        final Pointer<Uint32> cMax = calloc<Uint32>()..value = 512;
        GetApplicationUserModelId(process, cMax, cAppName);
        name = cAppName.toDartString();
        free(cMax);
      }
    }
    if (name.isEmpty) {
      return "";
    }

    //Get Package Name
    final Pointer<Uint32> familyLength = calloc<Uint32>()..value = 65 * 2;
    final LPWSTR familyName = wsalloc(familyLength.value);
    final Pointer<Uint32> packageLength = calloc<Uint32>()..value = 65 * 2;
    final LPWSTR packageName = wsalloc(familyLength.value);
    ParseApplicationUserModelId(cAppName, familyLength, familyName, packageLength, packageName);

    //Get Count
    final Pointer<Uint32> count = calloc<Uint32>();
    final Pointer<Uint32> buffer = calloc<Uint32>();
    FindPackagesByPackageFamily(familyName, 0x00000010 | 0x00000000, count, nullptr, buffer, nullptr, nullptr);
    final Pointer<Pointer<Utf16>> packageFullnames = calloc<Pointer<Utf16>>();
    final LPWSTR bufferString = wsalloc(buffer.value * 2);

    //Get Path
    FindPackagesByPackageFamily(familyName, 0x00000010 | 0x00000000, count, packageFullnames, buffer, bufferString, nullptr);
    final String packageLocation = bufferString.toDartString();

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

  static String getProcessExePath(int processID) {
    String exePath = "";
    final int hProcess = OpenProcess(PROCESS_ACCESS_RIGHTS.PROCESS_QUERY_INFORMATION | PROCESS_ACCESS_RIGHTS.PROCESS_VM_READ, FALSE, processID);
    if (hProcess == 0) {
      CloseHandle(hProcess);
      return "";
    }
    final LPWSTR imgName = wsalloc(MAX_PATH);
    final Pointer<Uint32> buff = calloc<Uint32>()..value = MAX_PATH;
    if (QueryFullProcessImageName(hProcess, 0, imgName, buff) != 0) {
      final LPWSTR szModName = wsalloc(MAX_PATH);
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

  static HwndInfo getWindowExePath(int hWnd) {
    bool isAppx = false;
    String result = "";
    final Pointer<Uint32> pId = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, pId);
    final int processID = pId.value;
    free(pId);

    result = getProcessExePath(processID);
    if (result.contains("FrameHost.exe")) {
      isAppx = true;
      final List<int> wins = enumChildWins(hWnd);
      final List<int> winsProc = <int>[];
      int mainWinProcs = 0;
      for (int e in wins) {
        final Pointer<Uint32> xpId = calloc<Uint32>();

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
    return HwndInfo(path: result, isAppx: isAppx);
  }

  static int getRealPID(int hWnd) {
    String result = "";
    final Pointer<Uint32> pId = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, pId);
    final int processID = pId.value;
    free(pId);

    result = getProcessExePath(processID);
    if (result.contains("FrameHost.exe")) {
      final List<int> wins = enumChildWins(hWnd);
      final List<int> winsProc = <int>[];
      int mainWinProcs = 0;
      for (int e in wins) {
        final Pointer<Uint32> xpId = calloc<Uint32>();

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

  static HwndInfo getFullPath(int hWnd) {
    String exePath = "";
    if (__cacheHwnds.containsKey(hWnd)) {
      if (!__cacheHwnds[hWnd]!.isAppx) {
        return HwndInfo(isAppx: __cacheHwnds[hWnd]!.isAppx, path: __cacheHwnds[hWnd]!.path);
      }
    }
    final HwndInfo hwndPath = getWindowExePath(hWnd);
    exePath = hwndPath.path;
    bool isAppx = hwndPath.isAppx;
    if (exePath.contains('WWAHost') || exePath.contains("ApplicationFrameHost")) {
      isAppx = true;
      final String appx = GetAppxInstallLocation(hWnd);
      exePath = "";
      if (appx != "") {
        exePath = "${WinUtils.getProgramFilesFolder()}\\WindowsApps\\$appx";
      }
    }
    return HwndInfo(isAppx: isAppx, path: exePath);
  }

  static String getFullPathString(int hWnd) {
    final HwndInfo result = getFullPath(hWnd);
    return result.path;
  }
}
