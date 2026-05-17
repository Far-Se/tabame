// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../globals.dart';
import '../settings.dart';
import 'imports.dart';
import 'keys.dart';
import 'mixed.dart';
import 'registry.dart';
import 'win_utils.dart';

// vscode-fold=2
class Win32 {
  Win32._();
  static int hWnd = 0;

  // Window handles and metadata
  static int getMainHandle() {
    if (hWnd == 0) {
      final int? mainWindowHandle = getMainWindowHandle();
      if (mainWindowHandle != null) {
        hWnd = GetAncestor(mainWindowHandle, 2);
      } else {
        hWnd = getMainHandleByClass();
      }
    }
    return hWnd;
  }

  static int? getMainWindowHandle() {
    final int currentPid = GetCurrentProcessId();
    final List<int> wins = enumWindows();
    int? foundHwnd;

    for (int hwnd in wins) {
      final Pointer<Uint32> pidPtr = calloc<Uint32>();

      GetWindowThreadProcessId(hwnd, pidPtr);

      final int windowPid = pidPtr.value;
      calloc.free(pidPtr);

      if (windowPid == currentPid && IsWindowVisible(hwnd) != 0 && GetWindow(hwnd, GW_OWNER) == 0) {
        foundHwnd = hwnd;
        return foundHwnd;
      }
    }

    return foundHwnd;
  }

  static Future<void> fetchMainWindowHandle() async {
    hWnd = await getFlutterMainWindow();
    hWnd = GetAncestor(hWnd, 2);
    return;
  }

  static int getMainHandleByClass() {
    if (hWnd != 0) return hWnd;
    final int hwnd = FindWindow(TEXT("TABAME_WIN32_WINDOW"), nullptr);
    if (hwnd > 0) {
      hWnd = GetAncestor(hwnd, 2);
    }
    return hWnd;
  }

  static int getActiveWindowHandle() {
    return GetForegroundWindow();
  }

  static int findWindow(String title) {
    return FindWindow(nullptr, TEXT(title));
  }

  static bool winExists(int win) {
    return IsWindow(win) != 0;
  }

  static int parent(int hWnd) {
    final int parentHandle = GetWindow(hWnd, 4);
    if (parentHandle != 0 || parentHandle != GetDesktopWindow()) {
      return parentHandle;
    }

    return GetAncestor(hWnd, 2);
  }

  static void shellOpen(String path) {
    ShellExecute(0, TEXT("open"), TEXT(path), nullptr, nullptr, SW_SHOW);
  }

  static String getProcessExePath(int processID) {
    String executablePath = "";
    int processHandle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processID);
    if (processHandle == 0) {
      processHandle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processID);
    }
    if (processHandle == 0) return "";

    try {
      final LPWSTR imageNameBuffer = wsalloc(MAX_PATH);
      final Pointer<Uint32> imageNameLength = calloc<Uint32>()..value = MAX_PATH;
      try {
        if (QueryFullProcessImageName(processHandle, 0, imageNameBuffer, imageNameLength) != 0) {
          executablePath = imageNameBuffer.toDartString();
        } else {
          final LPWSTR moduleNameBuffer = wsalloc(MAX_PATH);
          try {
            if (GetModuleFileNameEx(processHandle, 0, moduleNameBuffer, MAX_PATH) != 0) {
              executablePath = moduleNameBuffer.toDartString();
            }
          } finally {
            free(moduleNameBuffer);
          }
        }
      } finally {
        free(imageNameBuffer);
        free(imageNameLength);
      }
    } finally {
      CloseHandle(processHandle);
    }
    return executablePath;
  }

  static List<int> getProcessIdsByName(String exeName) {
    if (exeName.isEmpty) return <int>[];

    final Pointer<Uint32> neededBytesPointer = calloc<Uint32>();
    final Pointer<Uint32> processIds = calloc<Uint32>(4096);

    try {
      if (EnumProcesses(processIds, 4096 * sizeOf<Uint32>(), neededBytesPointer) == 0) {
        return <int>[];
      }
      final int processCount = neededBytesPointer.value ~/ sizeOf<Uint32>();
      final List<int> matchedPids = <int>[];

      for (int i = 0; i < processCount; i++) {
        final int pid = processIds[i];
        if (pid == 0) continue;
        final String path = getProcessExePath(pid);
        if (path.isEmpty) continue;

        if (getExe(path).toLowerCase() == exeName.toLowerCase()) {
          matchedPids.add(pid);
        }
      }
      return matchedPids;
    } finally {
      free(neededBytesPointer);
      free(processIds);
    }
  }

  @Deprecated("Outdated method one getWindowsExePath or getProcessExePath")
  static String getWindowExeModulePath(int hWnd) {
    final LPWSTR moduleNameBuffer = wsalloc(MAX_PATH);
    GetWindowModuleFileName(hWnd, moduleNameBuffer, MAX_PATH);
    String moduleName = moduleNameBuffer.toDartString();
    free(moduleNameBuffer);
    if (moduleName == "") {
      final Pointer<Uint32> processIdPointer = calloc<Uint32>();
      GetWindowThreadProcessId(hWnd, processIdPointer);
      final int processId = processIdPointer.value;
      free(processIdPointer);
      final int processHandle = OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, processId);
      if (processHandle == 0) {
        final LPWSTR executablePathBuffer = wsalloc(MAX_PATH);
        GetModuleFileNameEx(processHandle, 0, executablePathBuffer, MAX_PATH);
        moduleName = executablePathBuffer.toDartString();
        free(executablePathBuffer);
      }
      CloseHandle(processHandle);
    }
    return moduleName;
  }

  static String getWindowExePath(int hWnd) {
    return HwndPath.getFullPathString(hWnd);
  }

  static String getTitle(int hWnd) {
    String title = "";
    final int titleLength = GetWindowTextLength(hWnd);
    final LPWSTR titleBuffer = wsalloc(titleLength + 1);
    GetWindowText(hWnd, titleBuffer, titleLength + 1);
    title = titleBuffer.toDartString();
    free(titleBuffer);
    return title;
  }

  static String getClass(int hWnd) {
    final LPWSTR classNameBuffer = wsalloc(256);
    GetClassName(hWnd, classNameBuffer, 256);
    final String className = classNameBuffer.toDartString();
    free(classNameBuffer);
    return className;
  }

  static String getExe(String path) {
    if (path.isEmpty) return "";
    final String normalized = path.replaceAll('/', '\\');
    if (!normalized.contains('\\')) return path;
    return normalized.substring(normalized.lastIndexOf('\\') + 1);
  }

  static bool isWindowPresent(int hWnd) {
    bool isVisibleInSwitcher = true;
    final int extendedStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    if ((extendedStyle & WS_EX_TOOLWINDOW) != 0) {
      isVisibleInSwitcher = false;
    }
    return isVisibleInSwitcher;
  }

  static bool isWindowCloaked(int hWnd) {
    final Pointer<Int> cloakedState = calloc<Int>();
    DwmGetWindowAttribute(hWnd, DWMWA_CLOAKED, cloakedState, sizeOf<Int>());
    final bool isCloaked = cloakedState.value != 0;
    free(cloakedState);
    return isCloaked;
  }

  static bool isWindowOnDesktop(int hWnd) {
    return IsWindowVisible(hWnd) != 0 && isWindowPresent(hWnd) && !isWindowCloaked(hWnd);
  }

  static int getWindowMonitor(int hwnd) {
    return Monitor.getWindowMonitor(hwnd);
  }

  static int getCursorMonitor() {
    return Monitor.getCursorMonitor();
  }

  static String getManifestIcon(String appxLocation) {
    if (appxLocation.lastIndexOf('\\') != appxLocation.length) {
      appxLocation += "\\";
    }
    if (File("${appxLocation}AppxManifest.xml").existsSync()) {
      final String manifestContents = File("${appxLocation}AppxManifest.xml").readAsStringSync();
      String iconRelativePath = "";
      if (manifestContents.contains("Square44x44Logo")) {
        iconRelativePath = manifestContents.split("Square44x44Logo=\"")[1].split("\"")[0];
      } else if (manifestContents.contains("Square150x150Logo")) {
        iconRelativePath = manifestContents.split("Square150x150Logo=\"")[1].split("\"")[0];
      } else if (manifestContents.contains("Logo")) {
        iconRelativePath = manifestContents.split("Logo=\"")[1].split("\"")[0];
      } else {
        iconRelativePath = "";
      }
      String manifestIconPath = "$appxLocation$iconRelativePath";
      final String scale100IconPath = manifestIconPath.replaceFirst(".png", ".scale-100.png");
      if (File(scale100IconPath).existsSync()) {
        manifestIconPath = scale100IconPath;
      } else {
        final String targetSize32IconPath = manifestIconPath.replaceFirst(".png", ".targetsize-32.png");
        if (File(targetSize32IconPath).existsSync()) {
          manifestIconPath = targetSize32IconPath;
        } else {
          final String targetSize48IconPath = manifestIconPath.replaceFirst(".png", ".targetsize-48.png");
          if (File(targetSize48IconPath).existsSync()) {
            manifestIconPath = targetSize48IconPath;
          }
        }
      }
      return manifestIconPath;
    }
    return "";
  }

  static String extractFileNameFromPath(String path) {
    if (path == "") {
      return "";
    }
    final String normalizedPath = path.replaceAll('/', '\\');
    if (normalizedPath.contains('.exe')) {
      return normalizedPath.substring(normalizedPath.lastIndexOf('\\') + 1, normalizedPath.lastIndexOf('.exe'));
    }

    final String lastPathSegment = normalizedPath.substring(normalizedPath.lastIndexOf('\\') + 1);
    return lastPathSegment.substring(lastPathSegment.indexOf('.') + 1, lastPathSegment.indexOf('_'));
  }

  // Window lifecycle and focus
  static void activateWindow2(int hWnd, {bool forced = false}) {
    final int currentThreadId = GetCurrentThreadId();
    final int foregroundWindow = GetForegroundWindow();
    final int foregroundThreadId = GetWindowThreadProcessId(foregroundWindow, nullptr);
    final int targetThreadId = GetWindowThreadProcessId(hWnd, nullptr);

    bool attachedToTarget = false;
    bool attachedToForeground = false;

    try {
      // Attach to foreground thread to inherit foreground permission
      if (foregroundThreadId != currentThreadId) {
        attachedToForeground = AttachThreadInput(currentThreadId, foregroundThreadId, TRUE) != 0;
      }

      // Attach to target thread to allow focus/activation
      if (targetThreadId != currentThreadId && targetThreadId != foregroundThreadId) {
        attachedToTarget = AttachThreadInput(currentThreadId, targetThreadId, TRUE) != 0;
      }

      // Alt key trick to bypass SetForegroundWindow restrictions
      WinKeys.single("VK_MENU", KeySentMode.down);

      final Pointer<WINDOWPLACEMENT> windowPlacement = calloc<WINDOWPLACEMENT>();
      GetWindowPlacement(hWnd, windowPlacement);

      switch (windowPlacement.ref.showCmd) {
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
      free(windowPlacement);

      if (forced) {
        ShowWindow(hWnd, SW_RESTORE);
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
    } finally {
      // ALWAYS release the Alt key to prevent it from getting stuck
      WinKeys.single("VK_MENU", KeySentMode.up);

      // ALWAYS detach thread input
      if (attachedToForeground) {
        AttachThreadInput(currentThreadId, foregroundThreadId, FALSE);
      }
      if (attachedToTarget) {
        AttachThreadInput(currentThreadId, targetThreadId, FALSE);
      }
    }
  }

  static void activateWindow(int hwnd) {
    if (IsWindow(hwnd) == 0) return;

    // Restore if minimized
    if (IsIconic(hwnd) != 0) {
      ShowWindow(hwnd, SW_RESTORE);
    } else {
      ShowWindow(hwnd, SW_SHOW);
    }

    final int fg = GetForegroundWindow();

    final int fgThread = GetWindowThreadProcessId(fg, nullptr);
    final int thisThread = GetCurrentThreadId();
    final int targetThread = GetWindowThreadProcessId(hwnd, nullptr);

    // Attach to foreground thread
    AttachThreadInput(thisThread, fgThread, TRUE);
    AttachThreadInput(thisThread, targetThread, TRUE);

    SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE);

    BringWindowToTop(hwnd);
    SetForegroundWindow(hwnd);
    SetFocus(hwnd);
    SetActiveWindow(hwnd);

    AttachThreadInput(thisThread, targetThread, FALSE);
    AttachThreadInput(thisThread, fgThread, FALSE);
  }

  static void activateWindowOld(int hWnd) {
    final int currentThread = GetCurrentThreadId();
    final int targetThread = GetWindowThreadProcessId(hWnd, nullptr);

    // Bypass foreground lock cleanly using AllowSetForegroundWindow
    AllowSetForegroundWindow(-1);

    AttachThreadInput(currentThread, targetThread, TRUE);

    final Pointer<WINDOWPLACEMENT> wp = calloc<WINDOWPLACEMENT>();
    GetWindowPlacement(hWnd, wp);

    switch (wp.ref.showCmd) {
      case SW_SHOWMAXIMIZED:
        ShowWindow(hWnd, SW_SHOWMAXIMIZED);
        break;
      case SW_SHOWMINIMIZED:
        ShowWindow(hWnd, SW_RESTORE);
        break;
      default:
        ShowWindow(hWnd, SW_NORMAL);
    }
    free(wp);

    SetForegroundWindow(hWnd);
    BringWindowToTop(hWnd);
    SetFocus(hWnd);
    // new code
    SetActiveWindow(hWnd);
    UpdateWindow(hWnd);
    final int extendedStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
    if ((extendedStyle & WS_EX_TOPMOST) == 0) {
      SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      SetWindowPos(hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    }
    //
    AttachThreadInput(currentThread, targetThread, FALSE);
  }

  static void forceActivateWindow(int hWnd) {
    activateWindow(hWnd);
  }

  /// Activates the window under the cursor.
  static void activeWindowUnderCursor() {
    final Pointer<POINT> cursorPosition = calloc<POINT>();
    GetCursorPos(cursorPosition);
    int windowHandle = WindowFromPoint(cursorPosition.ref);
    windowHandle = GetAncestor(windowHandle, 2);
    if (GetForegroundWindow() != windowHandle) {
      activateWindow(windowHandle);
    }
    free(cursorPosition);
  }

  static void focusWindow(int hWnd) {
    SetFocus(hWnd);
    SetActiveWindow(hWnd);
  }

  static void surfaceWindow(int hWnd) {
    // ShowWindow(hWnd, SW_SHOWNOACTIVATE);
    ShowWindow(hWnd, SW_SHOWNA);

    SetWindowPos(hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
    SetWindowPos(hWnd, HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  static void setAlwaysOnTop(int hWnd, {bool? alwaysOnTop}) {
    int topmostHandle = alwaysOnTop == true ? HWND_TOPMOST : HWND_NOTOPMOST;
    if (alwaysOnTop == null) {
      final int extendedStyle = GetWindowLong(hWnd, GWL_EXSTYLE);
      topmostHandle = (extendedStyle & WS_EX_TOPMOST) != 0 ? HWND_NOTOPMOST : HWND_TOPMOST;
    }
    SetWindowPos(hWnd, topmostHandle, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  }

  static void restoreIfMaximized(int hWnd) {
    final Pointer<WINDOWPLACEMENT> placement = calloc<WINDOWPLACEMENT>();
    placement.ref.length = sizeOf<WINDOWPLACEMENT>();

    final int result = GetWindowPlacement(hWnd, placement);

    if (result != 0) {
      if (placement.ref.showCmd == SW_SHOWMAXIMIZED) {
        ShowWindow(hWnd, SW_RESTORE);
      }
    }

    free(placement);
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
    final List<int> windowHandles = enumWindows();
    for (final int hwnd in windowHandles) {
      final Pointer<Uint32> processIdPointer = calloc<Uint32>();
      GetWindowThreadProcessId(hwnd, processIdPointer);
      if (processIdPointer.value == pId) {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      }
      free(processIdPointer);
    }
  }

  // might be useless
  static void forceCloseWindowbyPath(String path) {
    final String parentPath = path.replaceFirst(Win32.getExe(path), '');
    final List<int> windowHandles = enumWindows();
    for (final int hwnd in windowHandles) {
      String windowPath = HwndPath.getFullPathString(hwnd);
      windowPath = windowPath.replaceAll(Win32.getExe(windowPath), '');
      if (windowPath == parentPath) {
        closeWindow(hwnd, forced: true);
      }
    }
  }

  // useless
  static void forceCloseByProcessID(int pId) {
    String processPath = Win32.getProcessExePath(pId);
    processPath = processPath.replaceFirst(Win32.getExe(processPath), '');
    if (processPath == "") {
      return;
    }

    final Pointer<Uint32> neededBytesPointer = calloc<Uint32>();
    final Pointer<Uint32> processIds = calloc<Uint32>(1024);

    EnumProcesses(processIds, 1024, neededBytesPointer);
    final int processCount = neededBytesPointer.value ~/ sizeOf<DWORD>();

    for (int index = processCount - 1; index >= 0; index--) {
      String candidatePath = Win32.getProcessExePath(processIds[index]);
      candidatePath = candidatePath.replaceFirst(Win32.getExe(candidatePath), '');
      if (candidatePath == processPath) {
        TerminateProcess(processIds[index], 0);
      }
    }

    free(neededBytesPointer);
    free(processIds);
  }

  // Geometry and positioning
  static Square getWindowRect({int? hwnd}) {
    hwnd ??= hWnd;
    final Pointer<RECT> windowRect = calloc<RECT>();
    GetWindowRect(hwnd, windowRect);
    final Square bounds = Square(
      x: windowRect.ref.left,
      y: windowRect.ref.top,
      width: windowRect.ref.right - windowRect.ref.left,
      height: windowRect.ref.bottom - windowRect.ref.top,
    );
    free(windowRect);
    return bounds;
  }

  static ({int width, int height}) getSize({int? hwnd}) {
    hwnd ??= hWnd;
    final Pointer<RECT> windowRect = calloc<RECT>();

    try {
      final int result = GetWindowRect(hwnd, windowRect);
      if (result == 0) {
        throw WindowsException(HRESULT_FROM_WIN32(GetLastError()));
      }

      final int width = windowRect.ref.right - windowRect.ref.left;
      final int height = windowRect.ref.bottom - windowRect.ref.top;

      return (width: width, height: height);
    } finally {
      calloc.free(windowRect);
    }
  }

  static Offset getPosition({int? monitor, int? hwnd}) {
    hwnd ??= hWnd;
    final Square windowRect = getWindowRect(hwnd: hwnd);
    double x = windowRect.x.toDouble();
    double y = windowRect.y.toDouble();
    if (monitor != null) {
      x -= Monitor.monitorSizes[monitor]!.x;
      y -= Monitor.monitorSizes[monitor]!.y;
    }
    return Offset(x, y);
  }

  static void setPosition(Offset position, {int? monitor, int? hwnd}) {
    hwnd ??= hWnd;
    final Square windowRect = getWindowRect(hwnd: hwnd);
    int targetX = position.dx ~/ 1;
    int targetY = position.dy ~/ 1;
    if (monitor != null) {
      targetX += Monitor.monitorSizes[monitor]!.x;
      targetY += Monitor.monitorSizes[monitor]!.y;
    }
    SetWindowPos(hwnd, HWND_TOP, targetX, targetY, windowRect.width, windowRect.height, NULL);
  }

  static void changePositionOld(int hWnd, int x, int y, int width, int height) {
    if (x == -1 || y == -1) {
      SetWindowPos(hWnd, HWND_TOP, 0, 0, width, height, SWP_NOMOVE | SWP_NOACTIVATE);
    } else {
      SetWindowPos(hWnd, HWND_TOP, x, y, width, height, SWP_NOACTIVATE);
    }
  }

  static void setSize(int hWnd, int width, int height) {
    changePosition(hWnd, -1, -1, width, height);
  }

  static ({int x, int y, int width, int height}) setDPIAware(int hWnd, int x, int y, int width, int height) {
    // Get target monitor — use position if provided, else current window position.
    final int targetMonitor;
    if (x == -1 || y == -1) {
      final Pointer<RECT> rectPtr = calloc<RECT>();
      GetWindowRect(hWnd, rectPtr);
      targetMonitor = MonitorFromRect(rectPtr, 2); // DEFAULTTONEAREST
      free(rectPtr);
    } else {
      // Two-pass: estimate physical pos to find the target monitor.
      final Pointer<RECT> rectPtr = calloc<RECT>();
      GetWindowRect(hWnd, rectPtr);
      final int currentMonitor = MonitorFromRect(rectPtr, 2);
      free(rectPtr);

      if (!Monitor.dpi.containsKey(currentMonitor)) Monitor.fetchMonitors();
      final Dpi? currentDpi = Monitor.dpi[currentMonitor];
      final double guessScale = currentDpi != null ? currentDpi.x / 96.0 : 1.0;

      final Pointer<POINT> estPt = calloc<POINT>()
        ..ref.x = (x * guessScale).round()
        ..ref.y = (y * guessScale).round();
      targetMonitor = MonitorFromPoint(estPt.ref, 2);
      free(estPt);
    }

    if (!Monitor.dpi.containsKey(targetMonitor)) Monitor.fetchMonitors();
    final Dpi? dpiInfo = Monitor.dpi[targetMonitor];
    final double scaleX = dpiInfo != null ? dpiInfo.x / 96.0 : 1.0;
    final double scaleY = dpiInfo != null ? dpiInfo.y / 96.0 : 1.0;

    final int physW = (width * scaleX).round();
    final int physH = (height * scaleY).round();

    if (x == -1 || y == -1) {
      return (x: 0, y: 0, width: physW, height: physH);
      // SetWindowPos(hWnd, HWND_TOP, 0, 0, physW, physH, SWP_NOMOVE | SWP_NOACTIVATE);
    } else {
      final int physX = (x * scaleX).round();
      final int physY = (y * scaleY).round();
      return (x: physX, y: physY, width: physW, height: physH);
      // SetWindowPos(hWnd, HWND_TOP, physX, physY, physW, physH, SWP_NOACTIVATE);
    }
  }

  static void changePosition(int hWnd, int x, int y, int width, int height) {
    // Get target monitor — use position if provided, else current window position.
    final int targetMonitor;
    if (x == -1 || y == -1) {
      final Pointer<RECT> rectPtr = calloc<RECT>();
      GetWindowRect(hWnd, rectPtr);
      targetMonitor = MonitorFromRect(rectPtr, 2); // DEFAULTTONEAREST
      free(rectPtr);
    } else {
      // Two-pass: estimate physical pos to find the target monitor.
      final Pointer<RECT> rectPtr = calloc<RECT>();
      GetWindowRect(hWnd, rectPtr);
      final int currentMonitor = MonitorFromRect(rectPtr, 2);
      free(rectPtr);

      if (!Monitor.dpi.containsKey(currentMonitor)) Monitor.fetchMonitors();
      final Dpi? currentDpi = Monitor.dpi[currentMonitor];
      final double guessScale = currentDpi != null ? currentDpi.x / 96.0 : 1.0;

      final Pointer<POINT> estPt = calloc<POINT>()
        ..ref.x = (x * guessScale).round()
        ..ref.y = (y * guessScale).round();
      targetMonitor = MonitorFromPoint(estPt.ref, 2);
      free(estPt);
    }

    if (!Monitor.dpi.containsKey(targetMonitor)) Monitor.fetchMonitors();
    final Dpi? dpiInfo = Monitor.dpi[targetMonitor];
    final double scaleX = dpiInfo != null ? dpiInfo.x / 96.0 : 1.0;
    final double scaleY = dpiInfo != null ? dpiInfo.y / 96.0 : 1.0;

    final int physW = (width * scaleX).round();
    final int physH = (height * scaleY).round();

    if (x == -1 || y == -1) {
      SetWindowPos(hWnd, HWND_TOP, 0, 0, physW, physH, SWP_NOMOVE | SWP_NOACTIVATE);
    } else {
      final int physX = (x * scaleX).round();
      final int physY = (y * scaleY).round();
      SetWindowPos(hWnd, HWND_TOP, physX, physY, physW, physH, SWP_NOACTIVATE);
    }
  }

  static void setPosDPI(int hwnd, PointXY logicalPos, {int? logicalWidth, int? logicalHeight}) {
    // Peek at what monitor the TARGET position lands on.
    // We need physical coords for MonitorFromPoint, but we only have logical ones.
    // Use a best-effort scale from the current monitor first, then re-resolve.
    final Pointer<RECT> rectPtr = calloc<RECT>();
    GetWindowRect(hwnd, rectPtr);
    final int currentMonitor = MonitorFromRect(rectPtr, 2);
    free(rectPtr);

    if (!Monitor.dpi.containsKey(currentMonitor)) Monitor.fetchMonitors();
    final Dpi? currentDpi = Monitor.dpi[currentMonitor];
    final double guessScaleX = currentDpi != null ? currentDpi.x / 96.0 : 1.0;
    final double guessScaleY = currentDpi != null ? currentDpi.y / 96.0 : 1.0;

    // First-pass physical estimate to find the target monitor.
    final Pointer<POINT> estPt = calloc<POINT>()
      ..ref.x = (logicalPos.X * guessScaleX).round()
      ..ref.y = (logicalPos.Y * guessScaleY).round();
    final int targetMonitor = MonitorFromPoint(estPt.ref, 2);
    free(estPt);

    // Now use the TARGET monitor's DPI for the real conversion.
    if (!Monitor.dpi.containsKey(targetMonitor)) Monitor.fetchMonitors();
    final Dpi? targetDpi = Monitor.dpi[targetMonitor];
    final double scaleX = targetDpi != null ? targetDpi.x / 96.0 : 1.0;
    final double scaleY = targetDpi != null ? targetDpi.y / 96.0 : 1.0;

    final int physX = (logicalPos.X * scaleX).round();
    final int physY = (logicalPos.Y * scaleY).round();

    int flags = SWP_NOZORDER | SWP_NOACTIVATE;

    if (logicalWidth != null && logicalHeight != null) {
      final int physW = (logicalWidth * scaleX).round();
      final int physH = (logicalHeight * scaleY).round();
      SetWindowPos(hwnd, 0, physX, physY, physW, physH, flags);
    } else {
      SetWindowPos(hwnd, 0, physX, physY, 0, 0, flags | SWP_NOSIZE);
    }
  }

  static void setCenter({bool useMouse = false, int? hwnd}) {
    hwnd ??= hWnd;
    if (!useMouse) {
      final Square windowRect = getWindowRect(hwnd: hwnd);
      final double centerX = (GetSystemMetrics(SM_CXSCREEN) - windowRect.width) / 2;
      final double centerY = (GetSystemMetrics(SM_CYSCREEN) - windowRect.height) / 2;
      SetWindowPos(hwnd, HWND_TOP, centerX ~/ 1, centerY ~/ 1, windowRect.width, windowRect.height, NULL);
    } else {
      final Square windowRect = getWindowRect(hwnd: hwnd);
      final int monitorIndex = Monitor.getCursorMonitor();
      final Square monitorBounds = Monitor.monitorSizes[monitorIndex]!;
      final double centerX =
          (((monitorBounds.width + monitorBounds.x) - monitorBounds.x - windowRect.width) / 2) + monitorBounds.x;
      final double centerY =
          (((monitorBounds.height + monitorBounds.y) - monitorBounds.y - windowRect.height) / 2) + monitorBounds.y;
      SetWindowPos(hwnd, HWND_TOP, centerX ~/ 1, centerY ~/ 1, windowRect.width, windowRect.height, NULL);
    }
  }

  static Future<void> setMainWindowToMousePos() async {
    final PointXY mousePosition = WinUtils.getMousePos();
    double horizontalPosition = mousePosition.X.toDouble() - 10;
    double verticalPosition = mousePosition.Y.toDouble() - 30;

    const int alignmentFlags = TPM_LEFTALIGN;

    final Pointer<POINT> anchorPoint = calloc<POINT>();
    anchorPoint.ref.x = horizontalPosition.toInt();
    anchorPoint.ref.y = verticalPosition.toInt();
    final Pointer<RECT> popupBounds = calloc<RECT>();
    final ({int height, int width}) windowSize = getSize();
    final Pointer<SIZE> popupSize = calloc<SIZE>();
    popupSize.ref.cx = windowSize.width;
    popupSize.ref.cy = Globals.quickMenuCurrentHeight.toInt();
    // popupSize.ref.cy = Globals.heights.allSummed.toInt() + 20;
    if (userSettings.showQuickMenuAtTaskbarLevel == false) {
      popupSize.ref.cy += 30;
    }
    popupSize.ref.cy += 3;
    if (popupSize.ref.cy == 0) {
      popupSize.ref.cy = 300;
    }

    CalculatePopupWindowPosition(anchorPoint, popupSize, alignmentFlags, nullptr, popupBounds);
    horizontalPosition = popupBounds.ref.left.toDouble();
    verticalPosition = popupBounds.ref.top.toDouble();

    if (userSettings.showQuickMenuAtTaskbarLevel == true) {
      switch (QuickMenuDesigns.values[userSettings.quickMenuDesign]) {
        case QuickMenuDesigns.classic:
          verticalPosition -= 30;
          break;
        case QuickMenuDesigns.interface:
          verticalPosition -= 30;
          break;
        case QuickMenuDesigns.modern:
          verticalPosition -= 40;
          break;
        case QuickMenuDesigns.matrix:
          verticalPosition -= 70;
          horizontalPosition -= 10;
          break;
      }
    }
    await WindowManager.instance.setPosition(Offset(horizontalPosition + 1, verticalPosition));
    // SetForegroundWindow(hWnd);
    // WindowManager.instance.blur();
    WindowManager.instance.focus();
    Win32.activateWindow(Win32.hWnd);

    free(anchorPoint);
    free(popupBounds);
    free(popupSize);
  }

  static void setMaxSizeForHwnd(int hwnd, int maxWidth, int maxHeight) {
    // Subclass or use SetWindowLongPtr + WM_GETMINMAXINFO is complex,
    // so the simplest approach is to hook via SetWindowPos to enforce size:
    SetWindowPos(
      hwnd,
      NULL,
      0, 0, // position (ignored with SWP_NOMOVE)
      maxWidth,
      maxHeight,
      SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE,
    );
  }

  static bool isTaskbarVisible() {
    final Pointer<APPBARDATA> abd = calloc<APPBARDATA>();

    try {
      abd.ref.cbSize = sizeOf<APPBARDATA>();

      final int state = SHAppBarMessage(0x00000004, abd);

      if (state & 0x00000001 != 0) {
        return false; // auto-hide: effectively hidden
      }

      return true; // always visible
    } finally {
      calloc.free(abd);
    }
  }

  /// Returns the invisible border (shadow/gutter) widths for [hWnd].
  ///
  /// On Windows 10/11, `GetWindowRect` includes an invisible resize handle border
  /// (~8 px on left/right/bottom) that is NOT visually rendered. This causes
  /// apparent gaps between adjacent snapped windows even at gap=0.
  ///
  /// Internally compares `GetWindowRect` with `DWMWA_EXTENDED_FRAME_BOUNDS`
  /// (the actual painted bounds). Falls back to zeros if DWM fails.
  static ({int left, int top, int right, int bottom}) getInvisibleBorder(int hWnd) {
    final Pointer<RECT> windowRect = calloc<RECT>();
    final Pointer<RECT> frameRect = calloc<RECT>();
    try {
      GetWindowRect(hWnd, windowRect);
      // DWMWA_EXTENDED_FRAME_BOUNDS = 9
      final int result = DwmGetWindowAttribute(hWnd, 9, frameRect, sizeOf<RECT>());
      if (result != 0) {
        // DWM call failed (e.g. minimised / WS_EX_NOREDIRECTIONBITMAP)
        return (left: 0, top: 0, right: 0, bottom: 0);
      }
      return (
        left: frameRect.ref.left - windowRect.ref.left,
        top: frameRect.ref.top - windowRect.ref.top,
        right: windowRect.ref.right - frameRect.ref.right,
        bottom: windowRect.ref.bottom - frameRect.ref.bottom,
      );
    } finally {
      free(windowRect);
      free(frameRect);
    }
  }

  // Virtual desktops
  static Future<bool> moveWindowToDesktop(int hWnd, DesktopDirection direction, {bool classMethod = true}) async {
    if (classMethod) {
      return await moveWindowToDesktopMethod(hWnd: hWnd, direction: direction);
    }
    String directionKey = "RIGHT";
    if (direction == DesktopDirection.left) {
      directionKey = "LEFT";
    }
    await setSkipTaskbar(hWnd: hWnd, skip: true);
    WinKeys.send("{#WIN}{#CTRL}{$directionKey}");
    await setSkipTaskbar(hWnd: hWnd, skip: false);
    return true;
  }

  static void setWindowInvisible(bool invisible, {int? hWnd}) {
    hWnd ??= Win32.hWnd;

    final int exStyle = GetWindowLongPtr(hWnd, GWL_EXSTYLE);

    // Always keep layered enabled
    SetWindowLongPtr(hWnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);

    if (invisible) {
      // Fully transparent
      SetLayeredWindowAttributes(hWnd, 0, 0, LWA_ALPHA);
    } else {
      // Fully visible
      SetLayeredWindowAttributes(hWnd, 0, 255, LWA_ALPHA);
    }

    // Force style refresh
    SetWindowPos(hWnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE);

    // Optional redraw
    RedrawWindow(hWnd, nullptr, 0, RDW_INVALIDATE | RDW_UPDATENOW);
  }

  static void setClipHeight(int height, {int? hWnd}) {
    hWnd ??= Win32.hWnd;
    final Pointer<RECT> rect = calloc<RECT>();

    GetWindowRect(hWnd, rect);

    final int width = rect.ref.right - rect.ref.left;

    calloc.free(rect);

    final int region = CreateRectRgn(0, 0, width, height);

    SetWindowRgn(hWnd, region, TRUE);
  }
}

enum Scripts {
  colorPicker('color_picker.ps1'),
  msgBox('msgbox.ps1'),
  open('open.vbs');

  final String fileName;

  const Scripts(this.fileName);
}

class WizardlyContextMenu {
  bool isWizardlyInstalledInContextMenu() {
    try {
      final RegistryKey xxxkey = Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory');
      if (!xxxkey.subkeyNames.contains('Background')) {
        xxxkey.createKey("Background");
      }
      xxxkey.close();
      final RegistryKey xxkey =
          Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background');
      if (!xxkey.subkeyNames.contains('shell')) {
        xxkey.createKey("shell");
      }
      xxkey.close();
      final RegistryKey key = Registry.openPath(RegistryHive.currentUser,
          path: r'SOFTWARE\Classes\Directory\Background\shell', desiredAccessRights: AccessRights.allAccess);

      final bool output = key.subkeyNames.contains("tabame");
      key.close();
      return output;
    } catch (_) {
      return false;
    }
  }

  void toggleWizardlyToContextMenu() {
    try {
      final RegistryKey xxkey =
          Registry.openPath(RegistryHive.currentUser, path: r'SOFTWARE\Classes\Directory\Background');
      if (!xxkey.subkeyNames.contains('shell')) {
        xxkey.createKey("shell");
      }
      xxkey.close();
      final RegistryKey key = Registry.openPath(RegistryHive.currentUser,
          path: r'SOFTWARE\Classes\Directory\Background\shell', desiredAccessRights: AccessRights.allAccess);

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

    return other is HProcess &&
        other.path == path &&
        other.exe == exe &&
        other.pId == pId &&
        other.mainPID == mainPID &&
        other.className == className;
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

final Map<int, HwndInfo> _hwndPathCache = <int, HwndInfo>{};

class HwndPath {
  static const int _appxPackageFilter = 0x00000010 | 0x00000000;
  static const int _applicationUserModelIdBufferLength = 512;
  static const int _cacheLimit = 20;

  static String GetAppxInstallLocation(int hWnd) {
    int process = _openLimitedProcessHandle(hWnd);
    final Pointer<Uint32> cMax = calloc<Uint32>()..value = _applicationUserModelIdBufferLength;
    final LPWSTR cAppName = wsalloc(cMax.value);

    try {
      String name = _readApplicationUserModelId(process, cMax, cAppName);

      // Edge WebView-hosted apps may require reading the first child window instead.
      if (name.isEmpty) {
        final int fallbackHwnd = _getSecondaryAppxWindowHandle(hWnd);
        if (fallbackHwnd != 0) {
          if (process != 0) {
            CloseHandle(process);
          }
          process = _openLimitedProcessHandle(fallbackHwnd);
          name = _readApplicationUserModelId(process, cMax, cAppName);
        }
      }

      if (name.isEmpty) {
        return "";
      }

      final Pointer<Uint32> familyLength = calloc<Uint32>()..value = 65 * 2;
      final LPWSTR familyName = wsalloc(familyLength.value);
      final Pointer<Uint32> packageLength = calloc<Uint32>()..value = 65 * 2;
      final LPWSTR packageName = wsalloc(familyLength.value);
      final Pointer<Uint32> count = calloc<Uint32>();
      final Pointer<Uint32> buffer = calloc<Uint32>();
      Pointer<Pointer<Utf16>>? packageFullnames;
      Pointer<Utf16>? bufferString;

      try {
        ParseApplicationUserModelId(cAppName, familyLength, familyName, packageLength, packageName);
        FindPackagesByPackageFamily(
          familyName,
          _appxPackageFilter,
          count,
          nullptr,
          buffer,
          nullptr,
          nullptr,
        );

        packageFullnames = calloc<Pointer<Utf16>>();
        bufferString = wsalloc(buffer.value * 2);

        FindPackagesByPackageFamily(
          familyName,
          _appxPackageFilter,
          count,
          packageFullnames,
          buffer,
          bufferString,
          nullptr,
        );
        return bufferString.toDartString();
      } finally {
        free(familyLength);
        free(familyName);
        free(packageLength);
        free(packageName);
        free(count);
        free(buffer);
        if (packageFullnames != null) {
          free(packageFullnames);
        }
        if (bufferString != null) {
          free(bufferString);
        }
      }
    } finally {
      if (process != 0) {
        CloseHandle(process);
      }
      free(cAppName);
      free(cMax);
    }
  }

  static String getProcessExePath(int processID) => Win32.getProcessExePath(processID);

  static HwndInfo getWindowExePath(int hWnd) {
    final int processID = _getWindowProcessId(hWnd);
    String result = getProcessExePath(processID);
    bool isAppx = false;

    if (_usesChildWindowProcessLookup(result)) {
      isAppx = true;
      final int mainWindowProcessId = _findMainWindowProcessId(hWnd, processID);
      if (mainWindowProcessId > 0) {
        result = getProcessExePath(mainWindowProcessId);
      }
    }

    return HwndInfo(path: result, isAppx: isAppx);
  }

  static int getRealPID(int hWnd) {
    final int processID = _getWindowProcessId(hWnd);
    if (_usesChildWindowProcessLookup(getProcessExePath(processID))) {
      final int mainWindowProcessId = _findMainWindowProcessId(hWnd, processID);
      if (mainWindowProcessId > 0) {
        return mainWindowProcessId;
      }
    }

    return processID;
  }

  static HwndInfo getFullPath(int hWnd) {
    final HwndInfo? cachedPath = _hwndPathCache[hWnd];
    if (cachedPath != null && !cachedPath.isAppx) {
      return HwndInfo(isAppx: cachedPath.isAppx, path: cachedPath.path);
    }

    // Limit the cache to only [_cacheLimit] entries.
    if (_hwndPathCache.length > _cacheLimit) {
      _hwndPathCache.remove(_hwndPathCache.keys.first);
    }

    final HwndInfo hwndPath = getWindowExePath(hWnd);
    String exePath = hwndPath.path;
    bool isAppx = hwndPath.isAppx;
    if (_needsAppxInstallLocation(exePath)) {
      isAppx = true;
      final String appx = GetAppxInstallLocation(hWnd);
      exePath = "";
      if (appx != "") {
        exePath = "${WinUtils.getProgramFilesFolder()}\\WindowsApps\\$appx";
      }
    }

    final HwndInfo resolvedPath = HwndInfo(isAppx: isAppx, path: exePath);
    _hwndPathCache[hWnd] = resolvedPath;
    return HwndInfo(isAppx: resolvedPath.isAppx, path: resolvedPath.path);
  }

  static String getFullPathString(int hWnd) {
    final HwndInfo result = getFullPath(hWnd);
    return result.path;
  }

  static int _getWindowProcessId(int hWnd) {
    final Pointer<Uint32> processId = calloc<Uint32>();
    try {
      GetWindowThreadProcessId(hWnd, processId);
      return processId.value;
    } finally {
      free(processId);
    }
  }

  static int _openLimitedProcessHandle(int hWnd) {
    final int processId = _getWindowProcessId(hWnd);
    return OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
  }

  static String _readApplicationUserModelId(int process, Pointer<Uint32> bufferLength, LPWSTR buffer) {
    bufferLength.value = _applicationUserModelIdBufferLength;
    GetApplicationUserModelId(process, bufferLength, buffer);
    return buffer.toDartString();
  }

  static int _getSecondaryAppxWindowHandle(int hWnd) {
    final int parentHwnd = GetAncestor(hWnd, 2);
    final List<int> childWins = enumChildWindows(parentHwnd);
    if (childWins.length > 1) {
      return childWins[1];
    }
    return 0;
  }

  // ApplicationFrameHost-backed windows often expose the real app process via a child window.
  static int _findMainWindowProcessId(int hWnd, int processID) {
    for (final int childHwnd in enumChildWindows(hWnd)) {
      final int childProcessId = _getWindowProcessId(childHwnd);
      if (childProcessId != processID) {
        return childProcessId;
      }
    }
    return 0;
  }

  static bool _usesChildWindowProcessLookup(String exePath) {
    return exePath.contains("FrameHost.exe");
  }

  static bool _needsAppxInstallLocation(String exePath) {
    return exePath.contains('WWAHost') || exePath.contains("ApplicationFrameHost");
  }
}
// lib/src/appx_packages_win32.dart
//
// Enumerates all AppX / MSIX packages installed under
// C:\Program Files\WindowsApps using only Win32 / WinRT package-management
// APIs via dart:ffi.
//
// APIs used
// ─────────
//  kernel32  : GetPackagesByPackageFamily  (not used here — see note below)
//  kernel32  : GetPackagePathByFullName
//  appmodel  : OpenPackageInfoByFullName
//              GetPackageInfo
//              ClosePackageInfo
//
// The highest-level API that enumerates ALL packages for ALL users without
// PowerShell is FindPackages() / FindPackagesByUserSecurityId() from the
// Windows.Management.Deployment WinRT namespace.  Because calling WinRT
// from plain FFI is verbose, we use the lower-level kernel32 approach:
//
//   1. GetCurrentPackageFullName — not useful (host is not packaged)
//   2. PackageManager::FindPackages — WinRT only
//   3. ✔  Enumerate HKLM\SOFTWARE\Classes\Local Settings\Software\
//             Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages
//      and then call GetPackagePathByFullName for each key name.
//
// The registry hive above is the canonical source that Windows itself reads;
// it contains every machine-wide and per-user package registration.

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────

class AppxPackage {
  final String fullName;
  final String installLocation;

  const AppxPackage({required this.fullName, required this.installLocation});

  @override
  String toString() => 'AppxPackage($fullName  →  $installLocation)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FFI bindings not already in the win32 package
// ─────────────────────────────────────────────────────────────────────────────

// LONG GetPackagePathByFullName(
//   PCWSTR packageFullName,
//   UINT32 *pathLength,   // in/out: in chars, including null terminator
//   PWSTR  path           // out: may be NULL on the first call
// );
typedef _GetPackagePathByFullNameNative = Int32 Function(
  Pointer<Utf16> packageFullName,
  Pointer<Uint32> pathLength,
  Pointer<Utf16> path,
);
typedef _GetPackagePathByFullNameDart = int Function(
  Pointer<Utf16> packageFullName,
  Pointer<Uint32> pathLength,
  Pointer<Utf16> path,
);

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

final _GetPackagePathByFullNameDart _getPackagePathByFullName = _kernel32
    .lookupFunction<_GetPackagePathByFullNameNative, _GetPackagePathByFullNameDart>('GetPackagePathByFullName');

// ─────────────────────────────────────────────────────────────────────────────
// Registry helpers (using win32's RegOpenKeyEx / RegEnumKeyEx)
// ─────────────────────────────────────────────────────────────────────────────

// Registry path that lists every registered package (machine + per-user).
const String _kPackageRepoKey = r'SOFTWARE\Classes\Local Settings\Software\Microsoft'
    r'\Windows\CurrentVersion\AppModel\Repository\Packages';

/// Opens [subKey] under HKLM and returns the handle, or 0 on failure.
int _openKey(String subKey) {
  final Pointer<HKEY> hKey = calloc<HKEY>();
  final Pointer<Utf16> lpSubKey = subKey.toNativeUtf16();
  try {
    final int rc = RegOpenKeyEx(
      HKEY_LOCAL_MACHINE,
      lpSubKey,
      0,
      KEY_READ | KEY_WOW64_64KEY,
      hKey,
    );
    if (rc != ERROR_SUCCESS) return 0;
    return hKey.value;
  } finally {
    calloc.free(lpSubKey);
    calloc.free(hKey);
  }
}

/// Enumerates the immediate sub-key names of [hKey].
List<String> _enumSubKeyNames(int hKey) {
  final List<String> names = <String>[];
  final Pointer<Uint16> nameBuffer = calloc<Uint16>(256); // MAX_PATH in chars
  final Pointer<DWORD> nameLen = calloc<DWORD>();

  try {
    for (int index = 0;; index++) {
      nameLen.value = 256;
      final int rc = RegEnumKeyEx(
        hKey,
        index,
        nameBuffer.cast<Utf16>(),
        nameLen,
        nullptr, // reserved
        nullptr, // class
        nullptr, // class size
        nullptr, // last-write time
      );

      if (rc == ERROR_NO_MORE_ITEMS) break;
      if (rc != ERROR_SUCCESS) break;

      names.add(nameBuffer.cast<Utf16>().toDartString(length: nameLen.value));
    }
  } finally {
    calloc.free(nameBuffer);
    calloc.free(nameLen);
  }

  return names;
}

// ─────────────────────────────────────────────────────────────────────────────
// GetPackagePathByFullName wrapper
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the install path for [fullName], or `null` if the package is not
/// found / the path cannot be retrieved.
String? getPackagePathByFullName(String fullName) {
  final Pointer<Utf16> pFullName = fullName.toNativeUtf16();
  final Pointer<Uint32> pathLen = calloc<Uint32>();

  try {
    // First call: pathLen receives the required buffer size (in WCHARs,
    // including the null terminator).  path must be NULL.
    int rc = _getPackagePathByFullName(pFullName, pathLen, nullptr);

    // ERROR_INSUFFICIENT_BUFFER (122) is the expected success code here.
    const int errorInsufficientBuffer = 122;
    if (rc != errorInsufficientBuffer) return null;

    final Pointer<Uint16> pathBuffer = calloc<Uint16>(pathLen.value);
    try {
      rc = _getPackagePathByFullName(pFullName, pathLen, pathBuffer.cast<Utf16>());
      if (rc != ERROR_SUCCESS) return null;

      return pathBuffer.cast<Utf16>().toDartString(length: pathLen.value - 1);
    } finally {
      calloc.free(pathBuffer);
    }
  } finally {
    calloc.free(pFullName);
    calloc.free(pathLen);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Returns every AppX / MSIX package installed under
/// `C:\Program Files\WindowsApps` using only Win32 kernel32 APIs.
///
/// Throws [UnsupportedError] on non-Windows platforms.
List<AppxPackage> getAllAppxPackages() {
  if (!Platform.isWindows) {
    throw UnsupportedError('getAllAppxPackages() is Windows-only.');
  }

  const String windowsAppsPrefix = r'C:\Program Files\WindowsApps\';

  final int hKey = _openKey(_kPackageRepoKey);
  if (hKey == 0) {
    throw StateError('Could not open package repository registry key. '
        'Try running as Administrator.');
  }

  try {
    final List<String> fullNames = _enumSubKeyNames(hKey);
    final List<AppxPackage> packages = <AppxPackage>[];

    for (final String fullName in fullNames) {
      final String? path = getPackagePathByFullName(fullName);

      // Filter to WindowsApps only (machine-wide / provisioned packages).
      if (path != null && path.toLowerCase().startsWith(windowsAppsPrefix.toLowerCase())) {
        packages.add(AppxPackage(fullName: fullName, installLocation: path));
      }
    }

    return packages;
  } finally {
    RegCloseKey(hKey);
  }
}
