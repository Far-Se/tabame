// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io' as io;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size, Point;
import 'package:window_manager/window_manager.dart';

import 'package:tabamewin32/tabamewin32.dart';

import '../globals.dart';
import '../keys.dart';
import '../utils.dart';
import 'imports.dart';
import 'mixed.dart';

class Win32 {
  static void activateWindow(int hWnd, {bool forced = false}) {
    final Pointer<WINDOWPLACEMENT> place = calloc<WINDOWPLACEMENT>();
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
    SetFocus(hWnd);
    SetActiveWindow(hWnd);
    SendMessage(hWnd, WM_UPDATEUISTATE, 2 & 0x2, 0);
  }

  static void forceActivateWindow(int hWnd) {
    activateWindow(hWnd, forced: true);
  }

  static void closeWindow(int hWnd, {bool forced = false}) {
    PostMessage(hWnd, WM_CLOSE, 0, 0);
    if (forced) {
      // final Pointer<Uint32> pId = calloc<Uint32>();
      // GetWindowThreadProcessId(hWnd, pId);
      // free(pId);
      PostMessage(hWnd, WM_CLOSE, 0, 0);
      PostMessage(hWnd, WM_DESTROY, 0, 0);
      PostMessage(hWnd, WM_NCDESTROY, 0, 0);
    }
  }

  static void forceCloseWindow(int hWnd, int pId) {
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

  static String getProcessExePath(int processID) {
    String exePath = "";
    final int hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processID);
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
    final int exstyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    if ((exstyle & WS_EX_TOOLWINDOW) != 0) visible = false;
    // final winInfo = calloc<WINDOWINFO>();
    // GetWindowInfo(hWnd, winInfo);
    // if ((winInfo.ref.dwExStyle & WS_EX_APPWINDOW) != 0) visible = false;
    // free(winInfo);
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
    return;
  }

  static getMainHandleByClass() {
    if (hWnd != 0) return hWnd;
    final int hwnd = FindWindow(TEXT("FLUTTER_RUNNER_WIN32_WINDOW"), nullptr);
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
      final double x = (GetSystemMetrics(SM_CXSCREEN) - rect.width) / 2;
      final double y = (GetSystemMetrics(SM_CYSCREEN) - rect.height) / 2;
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
    Point mousePos = WinUtils.getMousePos();
    double horizontal = mousePos.X.toDouble() - 10;
    double vertical = mousePos.Y.toDouble() - 30;

    int flags = TPM_LEFTALIGN;

    final Pointer<POINT> anchorPoint = calloc<POINT>();
    anchorPoint.ref.x = horizontal.toInt();
    anchorPoint.ref.y = vertical.toInt();
    final Pointer<RECT> popupWindowPosition = calloc<RECT>();

    final Pointer<SIZE> windowSize = calloc<SIZE>();
    windowSize.ref.cx = 300;
    windowSize.ref.cy = Globals.heights.allSummed.toInt();
    if (windowSize.ref.cy == 0) windowSize.ref.cy = 300;

    CalculatePopupWindowPosition(anchorPoint, windowSize, flags, nullptr, popupWindowPosition);
    horizontal = popupWindowPosition.ref.left.toDouble();
    vertical = popupWindowPosition.ref.top.toDouble();

    if (globalSettings.showQuickMenuAtTaskbarLevel == true) vertical -= 30;
    await WindowManager.instance.setPosition(Offset(horizontal + 1, vertical));

    free(anchorPoint);
    free(popupWindowPosition);
    free(windowSize);
  }

  static void setAlwaysOnTop(int hWnd, {bool? alwaysOnTop}) {
    int topmostOrNot = alwaysOnTop == true ? HWND_TOPMOST : HWND_NOTOPMOST;
    if (alwaysOnTop == null) {
      final int exstyle = GetWindowLong(hWnd, GWL_EXSTYLE);
      topmostOrNot = (exstyle & WS_EX_TOPMOST) != 0 ? HWND_NOTOPMOST : HWND_TOPMOST;
    }
    SetWindowPos(hWnd, topmostOrNot, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }
}

class WinUtils {
  static void setVolumeOSDStyle({required VolumeOSDStyle type, bool applyStyle = true, int recursiveCheckHwnd = 5}) {
    int volumeHwnd = FindWindowEx(0, NULL, TEXT("NativeHWNDHost"), nullptr);
    if (volumeHwnd == 0) {
      volumeHwnd = FindWindowEx(0, 0, TEXT("DirectUIHWND"), nullptr);
    }

    if (volumeHwnd != 0) {
      if (type == VolumeOSDStyle.media) {
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

            keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
            keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
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
      print("no hwnd");
      // WinKeys.single(VK.VOLUME_UP, KeySentMode.normal);
      // WinKeys.single(VK.VOLUME_DOWN, KeySentMode.normal);
      // keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), KEYEVENTF_EXTENDEDKEY, 0);
      // keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), KEYEVENTF_KEYUP, 0);

      // keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_DOWN, 0), KEYEVENTF_EXTENDEDKEY, 0);
      keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
      keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
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
    RoInitialize(RO_INIT_TYPE.RO_INIT_SINGLETHREADED);
    final UserDataPaths userData = UserDataPaths.GetDefault();
    final int hStrLocalAppData = userData.LocalAppData; //userData.RoamingAppData;

    final String localAppData = WindowsGetStringRawBuffer(hStrLocalAppData, nullptr).toDartString();

    RoUninitialize();
    return localAppData;
  }

  static String getKnownFolder(String FOLDERID) {
    final Pointer<GUID> appsFolder = GUIDFromString(FOLDERID);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();
    String path = "";
    final int hr = SHGetKnownFolderPath(appsFolder, KF_FLAG_DEFAULT, NULL, ppszPath);
    if (!FAILED(hr)) {
      path = ppszPath.value.toDartString();
    }
    free(ppszPath);
    free(appsFolder);
    return path;
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
    final Pointer<GUID> folder = GUIDFromString(FOLDERID_Windows);
    final Pointer<PWSTR> ppszPath = calloc<PWSTR>();
    final int hr = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, NULL, ppszPath);
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
    final int hr = SHGetKnownFolderPath(folder, KF_FLAG_DEFAULT, NULL, ppszPath);
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

  static void moveDesktop(DesktopDirection direction, {bool classMethod = true}) {
    if (classMethod) {
      moveDesktopMethod(direction);
      return;
    }
    String key = "RIGHT";
    if (direction == DesktopDirection.left) key = "LEFT";
    WinKeys.send("{#WIN}{#CTRL}{$key}");
  }

  static Point getMousePos() {
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    Point point = Point(X: 0, Y: 0);
    point.X = lpPoint.ref.x;
    point.Y = lpPoint.ref.y;
    free(lpPoint);
    point = Monitor.adjustPointToDPI(point);
    return point;
  }

  static alwaysAwakeRun(bool state) {
    if (state == false) {
      SetThreadExecutionState(ES_CONTINUOUS);
    } else {
      Timer.periodic(const Duration(seconds: 45), (Timer timer) {
        if (Globals.alwaysAwake == false) {
          SetThreadExecutionState(ES_CONTINUOUS);
          timer.cancel();
        } else {
          SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
        }
      });
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

//create a singletonclass with a function

class HwndPath {
  // HwndPath();
  // static bool isAppx = false;
  static String GetAppxInstallLocation(int hWnd) {
    //Ger Process Handle
    int process;
    final Pointer<Uint32> ppID = calloc<Uint32>();
    GetWindowThreadProcessId(hWnd, ppID);
    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
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
        process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, ppID.value);
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
    final int hProcess = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processID);
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
      // exePath = __cacheHwnds[hWnd]![0]!;
      // isAppx = __cacheHwnds[hWnd]![1]!;
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
    // __cacheHwnds[hWnd] = <dynamic>[exePath, isAppx];
    return HwndInfo(isAppx: isAppx, path: exePath);
  }

  static String getFullPathString(int hWnd) {
    final HwndInfo result = getFullPath(hWnd);
    return result.path;
  }
}
