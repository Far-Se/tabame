import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:local_notifier/local_notifier.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../classes/boxes.dart';
import '../globals.dart';
import '../settings.dart';
import '../util/scripts.dart';
import 'imports.dart';
import 'keys.dart';
import 'mixed.dart';
import 'registry.dart';
import 'win32.dart';

typedef ExtractedIcon = Object?;

class WinUtils {
  WinUtils._();
  static int _isAdministrator = -1;
  static String _programFilesPath = "";
  static bool windowsNotificationRegistered = false;

  // Environment and system information
  static bool isAdministrator() {
    if (_isAdministrator == -1) {
      _isAdministrator = IsUserAnAdmin() == true ? 1 : 0;
    }
    return _isAdministrator == 1;
  }

  static bool isWindows11() {
    final RegistryKey currentVersionKey =
        Registry.openPath(RegistryHive.localMachine, path: r'SOFTWARE\Microsoft\Windows NT\CurrentVersion');
    final int currentBuildNumber = currentVersionKey.getValueAsInt("CurrentBuild") ?? 0;

    return currentBuildNumber >= 22000;
  }

  static bool isWindows10() {
    return Platform.operatingSystemVersion.contains("Windows 10");
  }

  static ScreenState checkUserScreenState() {
    final Pointer<Int32> notificationStatePointer = calloc<Int32>();
    SHQueryUserNotificationState(notificationStatePointer);
    final int notificationStateIndex = notificationStatePointer.value;
    free(notificationStatePointer);
    return ScreenState.values[notificationStateIndex - 1];
  }

  static void sendCommand({int command = AppCommand.appCommand}) {
    SendMessage(NULL, AppCommand.appCommand, 0, command);
  }

  static String getKnownFolder(String folderId) {
    final Pointer<GUID> folderGuid = GUIDFromString(folderId);
    final Pointer<PWSTR> pathPointer = calloc<PWSTR>();
    String folderPath = "";
    final int result = SHGetKnownFolderPath(folderGuid, KF_FLAG_DEFAULT, NULL, pathPointer);
    if (!FAILED(result)) {
      folderPath = pathPointer.value.toDartString();
    }
    free(pathPointer);
    free(folderGuid);
    return folderPath;
  }

  static String getKnownFolderCLSID(int csidl) {
    final LPWSTR pathBuffer = wsalloc(MAX_PATH);
    String folderPath = "";
    final int result = SHGetFolderPath(NULL, csidl, NULL, 0, pathBuffer);
    if (!FAILED(result)) {
      folderPath = pathBuffer.toDartString();
    }
    free(pathBuffer);
    return folderPath;
  }

  static String getLocalAppData() {
    final Pointer<GUID> folderGuid = GUIDFromString(FOLDERID_LocalAppData);
    final Pointer<PWSTR> pathPointer = calloc<PWSTR>();

    try {
      final int result = SHGetKnownFolderPath(folderGuid, KF_FLAG_DEFAULT, NULL, pathPointer);

      if (FAILED(result)) {
        throw WindowsException(result);
      }

      return pathPointer.value.toDartString();
    } finally {
      free(folderGuid);
      free(pathPointer);
    }
  }

  static String expandEnvironmentVariables(String path) {
    if (path.isEmpty || !path.contains('%')) return path;

    final Pointer<Utf16> src = path.toNativeUtf16();
    final Pointer<Utf16> dst = wsalloc(MAX_PATH);
    try {
      final int result = ExpandEnvironmentStrings(src, dst, MAX_PATH);
      if (result == 0) return path;
      return dst.toDartString();
    } finally {
      free(src);
      free(dst);
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

  static String getProgramFilesFolder() {
    if (_programFilesPath != "") {
      return _programFilesPath;
    }

    String folderPath = "";
    final Pointer<GUID> folderGuid = GUIDFromString(FOLDERID_ProgramFiles);
    final Pointer<PWSTR> pathPointer = calloc<PWSTR>();
    final int result = SHGetKnownFolderPath(folderGuid, KF_FLAG_DEFAULT, NULL, pathPointer);
    if (!FAILED(result)) {
      folderPath = pathPointer.value.toDartString();
    }
    free(pathPointer);
    _programFilesPath = folderPath;
    return folderPath;
  }

  static String getTaskManagerPath() {
    String taskManagerPath = "";
    final Pointer<GUID> folderGuid = GUIDFromString(FOLDERID_Windows);
    final Pointer<PWSTR> pathPointer = calloc<PWSTR>();
    final int result = SHGetKnownFolderPath(folderGuid, KF_FLAG_DEFAULT, NULL, pathPointer);
    if (!FAILED(result)) {
      taskManagerPath = "${pathPointer.value.toDartString()}\\System32\\Taskmgr.exe";
    }
    free(pathPointer);
    return taskManagerPath;
  }

  static String getTempFolder() {
    final LPWSTR tempPathBuffer = wsalloc(MAX_PATH);
    GetTempPath(MAX_PATH, tempPathBuffer);
    final String tempFolder = tempPathBuffer.toDartString();
    free(tempPathBuffer);
    return tempFolder;
  }

  static String getTabameAppDataFolder({bool settings = false}) {
    final String appDataFolder = "${WinUtils.getKnownFolder(FOLDERID_LocalAppData)}\\Tabame";
    if (!Directory(appDataFolder).existsSync()) {
      Directory(appDataFolder).createSync(recursive: true);
    }
    if (settings == true) {
      const String settingsFolderName = kDebugMode ? "settings\\debug" : "settings";
      final String settingsDirectoryPath = "$appDataFolder\\$settingsFolderName";
      if (!Directory(settingsDirectoryPath).existsSync()) {
        Directory(settingsDirectoryPath).createSync(recursive: true);
      }
      return settingsDirectoryPath;
    }
    return appDataFolder;
  }

  static Future<String> folderPicker() async {
    return await pickFolder();
  }

  // Startup, desktop, and taskbar helpers
  static Future<void> setStartUpShortcut(bool enabled, {String args = "", String? exePath, int showCmd = 1}) async {
    exePath ??= Platform.resolvedExecutable;
    setStartOnSystemStartup(enabled, args: args, exePath: exePath, showCmd: showCmd);
  }

  static void startOnStartup({String? exeFilePath, String? arguments}) {
    // ! doenst work
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    final Pointer<Pointer<COMObject>> shellLinkPointer = calloc<Pointer<COMObject>>();
    final Pointer<COMObject> persistFilePointer = calloc<COMObject>();

    exeFilePath ??= Platform.resolvedExecutable;
    final String workingDirectory = Directory(exeFilePath).parent.path;
    final IShellLink shellLink = IShellLink(shellLinkPointer.cast());

    shellLink.setPath(TEXT(exeFilePath));
    shellLink.setWorkingDirectory(TEXT(workingDirectory));
    shellLink.setShowCmd(SW_SHOWNORMAL);

    if (arguments != null) {
      shellLink.setArguments(TEXT(arguments));
    }

    final IPersistFile persistFile = IPersistFile(shellLink.toInterface(IID_IPersistFile));
    final String startupFolderPath = getKnownFolderCLSID(CSIDL_STARTUP);
    final String shortcutName = File(exeFilePath).uri.pathSegments.last.replaceFirst(".exe", ".lnk");
    persistFile.save(TEXT("$startupFolderPath\\$shortcutName"), TRUE);
    persistFile.release();
    shellLink.release();
    CoUninitialize();
    free(shellLinkPointer);
    free(persistFilePointer);
  }

  static String getStartupShortcut() {
    final LPWSTR startupProgramsPathBuffer = wsalloc(MAX_PATH);
    final int result = SHGetFolderPath(NULL, CSIDL_PROGRAMS, NULL, 0, startupProgramsPathBuffer);
    if (result != S_OK) {
      free(startupProgramsPathBuffer);
      return "";
    }
    final String startupProgramsPath = startupProgramsPathBuffer.toDartString();
    free(startupProgramsPathBuffer);
    return "$startupProgramsPath\\Startup\\tabame.lnk";
  }

  static bool checkIfRegisterAsStartup() {
    final String startupShortcutPath = getStartupShortcut();
    if (startupShortcutPath == "") {
      return false;
    }
    final File shortcutFile = File(startupShortcutPath);
    return shortcutFile.existsSync();
  }

  static Future<List<String>> getTaskbarPinnedApps() async {
    List<String> pinnedAppPaths = <String>[];
    String pinnedFolderPath = getKnownFolder(FOLDERID_UserPinned);
    if (pinnedFolderPath == "") {
      pinnedFolderPath = "${getLocalAppData()}\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned";
    }
    if (!Directory(pinnedFolderPath).existsSync()) {
      return <String>[];
    }
    final Iterable<FileSystemEntity> shortcutFiles = Directory("$pinnedFolderPath\\TaskBar")
        .listSync()
        .where((FileSystemEntity entry) => entry.path.endsWith(".lnk"));
    for (final FileSystemEntity shortcutFile in shortcutFiles) {
      String targetPath = await convertLinkToPath(shortcutFile.path);
      if (targetPath == "") {
        targetPath = "${getKnownFolder(FOLDERID_Windows)}\\explorer.exe";
      }
      pinnedAppPaths.add(targetPath);
    }
    return pinnedAppPaths;
  }

  static Future<List<String>> getTaskbarPinnedAppsPowerShell() async {
    String pinnedFolderPath = getKnownFolder(FOLDERID_UserPinned);
    if (pinnedFolderPath == "") {
      pinnedFolderPath = "${getLocalAppData()}\\Microsoft\\Internet Explorer\\Quick Launch\\User Pinned";
    }
    pinnedFolderPath += "\\Taskbar";
    if (!Directory(pinnedFolderPath).existsSync()) {
      return <String>[];
    }
    final int shortcutCount =
        await Directory(pinnedFolderPath).list().where((FileSystemEntity entry) => entry.path.endsWith(".lnk")).length;
    final List<String> powerShellCommands = <String>[
      "\$WScript = New-Object -ComObject WScript.Shell;",
      "Get-ChildItem -Path \"$pinnedFolderPath\" | ForEach-Object {\$WScript.CreateShortcut(\$_.FullName).TargetPath};",
    ];
    final List<String> pinnedAppPaths = await runPowerShell(powerShellCommands);
    if (shortcutCount != pinnedAppPaths.length) {
      pinnedAppPaths.insert(0, "${getKnownFolder(FOLDERID_Windows)}\\explorer.exe");
    }
    return pinnedAppPaths;
  }

  static void toggleTaskbar({bool? visible}) {
    Globals.taskbarVisible = visible ?? !Win32.isTaskbarVisible();
    setTaskbarVisibility(Globals.taskbarVisible);
  }

  static void moveDesktop(DesktopDirection direction, {bool classMethod = false}) {
    // if (classMethod) {
    //   moveDesktopMethod(direction);
    //   return;
    // }
    String directionKey = "RIGHT";
    if (direction == DesktopDirection.left) {
      directionKey = "LEFT";
    }
    WinKeys.send("{#WIN}{#CTRL}{$directionKey}");
  }

  static void closeAllTabameExProcesses() {
    final List<int> windowHandles = enumWindows();
    for (final int windowHandle in windowHandles) {
      if (Win32.getClass(windowHandle) == "TABAME_WIN32_WINDOW" && windowHandle != Win32.hWnd) {
        if (!Win32.getTitle(windowHandle).contains("Debug")) {
          Win32.closeWindow(windowHandle);
        }
      }
    }
  }

  static void reloadTabameQuickMenu() {
    if (!kReleaseMode) {
      return;
    }
    closeAllTabameExProcesses();
    startTabame(closeCurrent: false, arguments: "-restarted");
  }

  static void toggleDesktopFiles({bool? visible}) {
    final String desktopFolderPath = getKnownFolderCLSID(CSIDL_DESKTOP);
    final List<String> desktopItemPaths = Directory(desktopFolderPath)
        .listSync()
        .map((FileSystemEntity entry) => entry.path)
        .where((String path) => !path.contains("desktop.ini"))
        .toList();

    if (visible == null) {
      int hiddenCount = 0;
      int visibleCount = 0;
      for (final String itemPath in desktopItemPaths) {
        final int fileAttributes = GetFileAttributes(TEXT(itemPath));
        if ((fileAttributes & FILE_ATTRIBUTE_HIDDEN) == FILE_ATTRIBUTE_HIDDEN) {
          hiddenCount++;
        } else {
          visibleCount++;
        }
      }
      // If most are hidden, we want to show them (visible = true).
      // Otherwise, we want to hide them (visible = false).
      visible = hiddenCount > visibleCount;
    }

    for (final String itemPath in desktopItemPaths) {
      final int fileAttributes = GetFileAttributes(TEXT(itemPath));
      if (!visible && (fileAttributes & FILE_ATTRIBUTE_HIDDEN) == 0) {
        SetFileAttributes(TEXT(itemPath), fileAttributes | FILE_ATTRIBUTE_HIDDEN);
      } else if (visible && (fileAttributes & FILE_ATTRIBUTE_HIDDEN) == FILE_ATTRIBUTE_HIDDEN) {
        SetFileAttributes(TEXT(itemPath), fileAttributes & ~FILE_ATTRIBUTE_HIDDEN);
      }
    }
  }

  static Future<void> toggleHiddenFiles({bool? visible}) async {
    final RegistryKey explorerSettingsKey = Registry.openPath(
      RegistryHive.currentUser,
      path: r'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
      desiredAccessRights: AccessRights.allAccess,
    );
    final int currentHiddenValue = explorerSettingsKey.getValueAsInt('Hidden') ?? 1;
    int nextHiddenValue = 1;
    if (visible != null) {
      nextHiddenValue = visible ? 1 : 2;
    } else if (currentHiddenValue == 2) {
      nextHiddenValue = 1;
    } else {
      nextHiddenValue = 2;
    }
    explorerSettingsKey.createValue(RegistryValue("Hidden", RegistryValueType.int32, nextHiddenValue));
    await Future<void>.delayed(
      const Duration(milliseconds: 500),
      () {
        shChangeNotify(0x08000000, 0x0000, nullptr, nullptr);
        // Tell Explorer to reload its settings (fixes file picker refresh)
        final Pointer<Utf16> pStr = 'Environment'.toNativeUtf16();
        SendMessageTimeout(
          HWND_BROADCAST,
          WM_SETTINGCHANGE, // 0x001A
          0,
          pStr.address,
          SMTO_ABORTIFHUNG, // 0x0002
          2000,
          nullptr,
        );
        SendNotifyMessage(HWND_BROADCAST, 0x111, 41504, NULL);
      },
    );
  }

  static int areHiddenFilesVisible() {
    final Pointer<HKEY> registryKeyPointer = calloc<HKEY>();
    final Pointer<Utf16> registrySubKey =
        r'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'.toNativeUtf16();

    try {
      final int openResult = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        registrySubKey,
        0,
        KEY_READ,
        registryKeyPointer,
      );

      if (openResult != ERROR_SUCCESS) {
        throw WindowsException(openResult);
      }

      final Pointer<Utf16> valueNamePointer = 'Hidden'.toNativeUtf16();
      final Pointer<DWORD> dataTypePointer = calloc<DWORD>();
      final Pointer<DWORD> dataPointer = calloc<DWORD>();
      final Pointer<DWORD> dataSizePointer = calloc<DWORD>()..value = sizeOf<DWORD>();

      try {
        final int queryResult = RegQueryValueEx(
          registryKeyPointer.value,
          valueNamePointer,
          nullptr,
          dataTypePointer,
          dataPointer.cast<BYTE>(),
          dataSizePointer,
        );

        if (queryResult != ERROR_SUCCESS) {
          throw WindowsException(queryResult);
        }

        if (dataTypePointer.value != REG_DWORD) {
          throw StateError('Registry value "Hidden" is not a REG_DWORD.');
        }

        return dataPointer.value;
      } finally {
        free(valueNamePointer);
        free(dataTypePointer);
        free(dataPointer);
        free(dataSizePointer);
        RegCloseKey(registryKeyPointer.value);
      }
    } catch (e) {
      return -1;
    } finally {
      free(registrySubKey);
      free(registryKeyPointer);
    }
  }

  // Scripts and process launching
  static String getScript(Scripts script) {
    final Directory scriptsDirectory = Directory("${WinUtils.getTabameAppDataFolder()}\\scripts");
    if (!scriptsDirectory.existsSync()) {
      scriptsDirectory.createSync(recursive: true);
    }

    final String scriptName = script.fileName;
    if (scriptName.isEmpty) {
      return "";
    }

    final String scriptPath = "${scriptsDirectory.path}\\$scriptName";
    if (!File(scriptPath).existsSync()) {
      writeScript(script);
    }
    if (!File(scriptPath).existsSync()) {
      return "";
    }
    return script.fileName;
  }

  static void runScript(Scripts script, {String? arguments}) {
    WinUtils.runPowerShell(<String>[
      "Set-Location -Path \"${WinUtils.getTabameAppDataFolder()}\\scripts\";",
      '.\\${getScript(script)} ${arguments ?? ""}',
    ]);
  }

  static Future<List<String>> runPowerShell(List<String> commands) async {
    final ProcessResult processResult = await Process.run(
      'powershell',
      <String>['-NoProfile', ...commands],
    );
    final List<String> outputLines =
        processResult.stdout.toString().trim().split('\n').map((String line) => line.trim()).toList();
    if (processResult.stderr != '') {
      return outputLines;
    }
    return outputLines;
  }

  static Future<void> runPowerShellDetachedVisible(
    String command, {
    String? workingDirectory,
    bool keepOpen = true,
  }) async {
    final String scriptContent = keepOpen ? '$command\nRead-Host "Press Enter to close"' : command;
    final List<int> utf16leBytes = <int>[
      for (final int codeUnit in scriptContent.codeUnits) ...<int>[
        codeUnit & 0xFF,
        codeUnit >> 8,
      ],
    ];
    final String encodedCommand = base64Encode(utf16leBytes);
    final String processArguments = '-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand';

    await launchWithExplorer(
      'powershell.exe',
      arguments: processArguments,
      workingDirectory: workingDirectory ?? "",
    );
  }

  static Future<void> shellOpen(
    String path, {
    String? arguments,
    String? workingDirectory,
  }) async {
    await nativeShellOpen(
      path,
      arguments: arguments ?? "",
      workingDirectory: workingDirectory ?? "",
    );
  }

  static Future<void> launchDeElevated(String target, {String? args}) async {
    // We use RUNASINVOKER to drop the admin requirement for the child
    // We use PowerShell because it handles nested quotes better than CMD
    String shellCommand = 'set __COMPAT_LAYER=RUNASINVOKER; ' 'Start-Process "$target"';
    if (args != null) {
      args = args.replaceAll(' ', '\\ ').replaceAll('"', '\\"');
      shellCommand = 'set __COMPAT_LAYER=RUNASINVOKER; '
          'Start-Process "$target" -ArgumentList "$args"';
    }

    await Process.run(
      'powershell',
      <String>['-NoProfile', '-Command', shellCommand],
      runInShell: true,
    );
  }

  static void open(String path, {String? arguments, bool parseParamaters = true, String? workingDirectory}) {
    final bool shouldParseParameters = parseParamaters;
    final String resolvedWorkingDirectory = workingDirectory ?? "";
    if (shouldParseParameters) {
      RegExpMatch? commandMatch;
      final RegExp commandPattern = RegExp(r"^([a-z0-9-_]+) (.*?)$");
      if (commandPattern.hasMatch(path)) {
        commandMatch = commandPattern.firstMatch(path)!;
      } else {
        final RegExp commandPattern = RegExp(r"^(.*?\.exe) (.*?)$");
        if (commandPattern.hasMatch(path)) {
          commandMatch = commandPattern.firstMatch(path)!;
        }
      }
      if (commandMatch != null) {
        launchWithExplorer(commandMatch.group(1)!,
            arguments: commandMatch.group(2)!, workingDirectory: resolvedWorkingDirectory);
        return;
      }
    }
    launchWithExplorer(path, arguments: arguments, workingDirectory: resolvedWorkingDirectory);
    return;
    // ignore: dead_code
    if (arguments == null && !shouldParseParameters && globalSettings.runAsAdministrator && !path.startsWith("http")) {
      //! you can gain admin priv with one command, but there is no command to de-elevate yourself or app you are launching.
      //! only way I've found is to start powershell that starts explorer THAT starts the file.
      runPowerShell(<String>['explorer.exe "$path"']);
      return;
    }

    if (!shouldParseParameters) {
      ShellExecute(
        NULL,
        TEXT("open"),
        TEXT(path),
        arguments == null ? nullptr : TEXT(arguments),
        nullptr,
        path == "code" ? SW_HIDE : SW_SHOWNORMAL,
      );
      return;
    }
    final RegExp commandPattern = RegExp(r"^([a-z0-9-_]+) (.*?)$");
    if (commandPattern.hasMatch(path)) {
      final RegExpMatch commandMatch = commandPattern.firstMatch(path)!;
      if (!globalSettings.runAsAdministrator) {
        ShellExecute(
            NULL, TEXT("open"), TEXT(commandMatch.group(1)!), TEXT(commandMatch.group(2)!), nullptr, SW_SHOWNORMAL);
        return;
      }
      final String launcherScriptPath = WinUtils.getScript(Scripts.open);
      File(launcherScriptPath).writeAsStringSync("""
Dim objShell
Set objShell = CreateObject("Shell.Application")
Call objShell.ShellExecute("${commandMatch.group(1)}", "${commandMatch.group(2)!.replaceAll('"', '""')}", "", "open", ${commandMatch.group(1) == "code" ? 0 : 1})""");
      runPowerShell(<String>['explorer.exe "$launcherScriptPath"']);
    } else {
      runPowerShell(<String>['explorer.exe "$path"']);
    }
  }

  static void runAsAdmin(String link, {String? arguments}) {
    ShellExecute(
        NULL, TEXT("runas"), TEXT(link), arguments == null ? nullptr : TEXT(arguments), nullptr, SW_SHOWNORMAL);
  }

  static void startTabame({bool closeCurrent = false, String? arguments}) {
    if (WinUtils.isAdministrator()) {
      WinUtils.runAsAdmin(Platform.resolvedExecutable, arguments: arguments);
    } else {
      WinUtils.open(Platform.resolvedExecutable, arguments: arguments);
    }
    if (closeCurrent) {
      Future<void>.delayed(const Duration(milliseconds: 400), () => exit(0));
    }
  }

  static void openAndFocus(String path, {bool centered = false, bool usePowerShell = false}) {
    final Set<int> initialWindowHandles = enumWindows().toSet();
    WinUtils.open(path);
    int pollCount = 0;
    Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      pollCount++;
      if (pollCount > 11) {
        timer.cancel();
        return;
      }
      final Set<int> currentWindowHandles = enumWindows().toSet();
      final List<int> newlyOpenedWindows = List<int>.from(currentWindowHandles.difference(initialWindowHandles));
      final List<int> desktopWindows =
          newlyOpenedWindows.where((int hWnd) => Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "").toList();
      if (desktopWindows.isEmpty) {
        return;
      }
      final int targetWindowHandle = desktopWindows[0];
      Win32.activateWindow(targetWindowHandle);
      if (!centered) {
        return;
      }
      Win32.setCenter(hwnd: targetWindowHandle, useMouse: true);
      timer.cancel();
    });
  }

  static void msgBox(String title, String text, {String? speak}) {
    speak ??= "";
    WinUtils.startTabame(
      arguments: '-msgbox -title "${title.replaceAll('"', '\\"')}" '
          '-message "${text.replaceAll('"', '\\"')}" '
          '-speak "${speak.replaceAll('"', '\\"')}"',
      closeCurrent: false,
    );
  }

  // Interaction, input, and notifications
  static PointXY getMousePos() {
    final Pointer<POINT> cursorPointPointer = calloc<POINT>();
    GetCursorPos(cursorPointPointer);
    final int physX = cursorPointPointer.ref.x;
    final int physY = cursorPointPointer.ref.y;
    free(cursorPointPointer);

    // Look up monitor using physical coords (before any DPI conversion).
    final Pointer<POINT> physPt = calloc<POINT>()
      ..ref.x = physX
      ..ref.y = physY;
    final int monitor = MonitorFromPoint(physPt.ref, 2); // DEFAULTTONEAREST
    free(physPt);

    if (!Monitor.dpi.containsKey(monitor)) Monitor.fetchMonitors();
    final Dpi? dpiInfo = Monitor.dpi[monitor];

    if (dpiInfo == null) return PointXY(X: physX, Y: physY);

    return PointXY(
      X: (physX / (dpiInfo.x / 96.0)).round(),
      Y: (physY / (dpiInfo.y / 96.0)).round(),
    );
  }

  static List<int> getMousePosXY() {
    final PointXY pos = getMousePos();
    return <int>[pos.X, pos.Y];
  }

  static void alwaysAwakeRun(bool state) {
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

  static void setVolumeOSDStyle({required VolumeOSDStyle type, bool applyStyle = true, int recursiveCheckHwnd = 5}) {
    int volumeWindowHandle = FindWindowEx(0, NULL, TEXT("NativeHWNDHost"), nullptr);
    if (volumeWindowHandle == 0) {
      volumeWindowHandle = FindWindowEx(0, 0, TEXT("DirectUIHWND"), nullptr);
    }

    if (volumeWindowHandle != 0) {
      if (type == VolumeOSDStyle.normal) {
        SetWindowRgn(volumeWindowHandle, 0, 1);
        ShowWindow(volumeWindowHandle, 9);
        keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
        keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
      } else if (type == VolumeOSDStyle.media) {
        final int dpi = GetDpiForWindow(volumeWindowHandle);
        final double dpiScale = dpi / 96.0;
        if (applyStyle == true) {
          final int osdRegionHandle = CreateRectRgn(0, 0, (60 * dpiScale).round(), (140 * dpiScale).round());
          SetWindowRgn(volumeWindowHandle, osdRegionHandle, 1);
        } else {
          SetWindowRgn(volumeWindowHandle, 0, 1);
        }
        return;
      } else if (type == VolumeOSDStyle.visible) {
        if (applyStyle == false) {
          ShowWindow(volumeWindowHandle, 9);
          keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
          keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
        } else {
          ShowWindow(volumeWindowHandle, 6);
        }
        return;
      } else if (type == VolumeOSDStyle.thin) {
        volumeWindowHandle = FindWindowEx(NULL, NULL, TEXT("NativeHWNDHost"), nullptr);
        if (volumeWindowHandle != 0) {
          final int dpi = GetDpiForWindow(volumeWindowHandle);
          final double dpiScale = dpi / 96.0;
          if (applyStyle == true) {
            final int osdRegionHandle = CreateRectRgn(
              25,
              18,
              (60 * dpiScale).round() - (20 * dpiScale).round(),
              (140 * dpiScale).round() - (16 * dpiScale).round(),
            );
            SetWindowRgn(volumeWindowHandle, osdRegionHandle, 1);
            final int windowDeviceContext = GetWindowDC(volumeWindowHandle);
            SetBkColor(windowDeviceContext, 0xFF00FF00);
          } else {
            SetWindowRgn(volumeWindowHandle, 0, 1);
          }
        }
      }
    } else {
      keybd_event(VK_VOLUME_UP, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
      keybd_event(VK_VOLUME_DOWN, MapVirtualKey(VK_VOLUME_UP, 0), 0, 0);
    }
    if (volumeWindowHandle == 0 && recursiveCheckHwnd > 0) {
      final int remainingRetryCount = recursiveCheckHwnd - 1;
      Timer(const Duration(seconds: 3), () {
        setVolumeOSDStyle(type: type, applyStyle: applyStyle, recursiveCheckHwnd: remainingRetryCount);
      });
    }
  }

  static Future<void> textToSpeech(String text, {int repeat = 1, int volume = 100}) async {
    if (repeat == -1) {
      final RegExp repeatPattern = RegExp(r'x\d+$');
      final RegExpMatch? repeatMatch = repeatPattern.firstMatch(text);
      if (repeatMatch != null) {
        text = text.substring(0, text.length - repeatMatch[0]!.length);
        repeat = int.parse(repeatMatch[0]!.substring(1));
      } else {
        repeat = 1;
      }
    }
    final List<String> powerShellCommands = <String>[
      "Add-Type -AssemblyName System.speech;",
      "\$speak = New-Object System.Speech.Synthesis.SpeechSynthesizer;",
      "\$speak.Volume = $volume;"
    ];
    for (int iteration = 0; iteration < repeat; iteration++) {
      powerShellCommands.add("\$speak.Speak('${text.replaceAll("'", '"')}');");
    }
    await WinUtils.runPowerShell(powerShellCommands);
  }

  static void showWindowsNotification(
      {required String title, required String body, required Null Function() onClick}) async {
    if (!windowsNotificationRegistered) {
      windowsNotificationRegistered = true;
      await localNotifier.setup(appName: 'Tabame', shortcutPolicy: ShortcutPolicy.requireCreate);
    }
    final LocalNotification notification = LocalNotification(
      title: title,
      body: body,
    );
    notification.onClick = () => onClick();
    await notification.show();
  }

  // Downloads, capture, and icons
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
    final http.Client httpClient = http.Client();
    final http.Request request = http.Request('GET', Uri.parse(url));
    final Future<http.StreamedResponse> streamedResponse = httpClient.send(request);

    final List<List<int>> dataChunks = <List<int>>[];
    streamedResponse.asStream().listen((http.StreamedResponse response) {
      response.stream.listen((List<int> chunk) {
        dataChunks.add(chunk);
      }, onDone: () async {
        final File destinationFile = File(filename);
        final Uint8List fileBytes = Uint8List(response.contentLength!);
        int byteOffset = 0;
        for (final List<int> chunk in dataChunks) {
          fileBytes.setRange(byteOffset, byteOffset + chunk.length, chunk);
          byteOffset += chunk.length;
        }
        await destinationFile.writeAsBytes(fileBytes);
        callback();
      });
    });
  }

  static bool isScreenClipping() {
    final int foregroundWindowHandle = GetForegroundWindow();
    final Pointer<Uint32> processIdPointer = calloc<Uint32>();

    GetWindowThreadProcessId(foregroundWindowHandle, processIdPointer);
    final int processHandle = OpenProcess(
      PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
      FALSE,
      processIdPointer.value,
    );

    if (processHandle == 0) {
      return false;
    }

    final Pointer<HMODULE> moduleHandles = calloc<HMODULE>(1024);
    final Pointer<DWORD> neededBytesPointer = calloc<DWORD>();

    try {
      final int enumerationResult = EnumProcessModules(
        processHandle,
        moduleHandles,
        sizeOf<HMODULE>() * 1024,
        neededBytesPointer,
      );

      if (enumerationResult == 1) {
        final int moduleCount = neededBytesPointer.value ~/ sizeOf<HMODULE>();
        for (int index = 0; index < moduleCount; index++) {
          final LPWSTR moduleNameBuffer = wsalloc(MAX_PATH);
          final int moduleHandle = (moduleHandles + index).value;
          if (GetModuleFileNameEx(processHandle, moduleHandle, moduleNameBuffer, MAX_PATH) != 0) {
            final String modulePath = moduleNameBuffer.toDartString();
            if (modulePath.contains("ScreenClippingHost.exe")) {
              free(moduleNameBuffer);
              return true;
            }
          }
          free(moduleNameBuffer);
        }
      }
    } finally {
      free(moduleHandles);
      free(neededBytesPointer);
      CloseHandle(processHandle);
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
      SW_SHOWNORMAL,
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    while (isScreenClipping()) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final String tempFolder = getTempFolder();
    await WinClipboard().saveClipboardToPng("$tempFolder\\capture.png");
    return true;
  }

  static Future<String?> getFaviconUrl(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    final Uri baseUri = Uri.parse(url);

    try {
      final http.Response response = await http.get(baseUri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final String html = response.body;

        // Extract <link ...> tags
        final RegExp linkRegExp = RegExp(r'<link[^>]*>', caseSensitive: false);
        final Iterable<RegExpMatch> matches = linkRegExp.allMatches(html);

        String? bestIcon;
        int bestPriority = -1;

        for (final RegExpMatch match in matches) {
          final String tag = match.group(0)!;

          // Check rel="icon", "shortcut icon", "apple-touch-icon"
          final RegExp relRegExp = RegExp('rel=["\']([^"\']+)["\']', caseSensitive: false);
          final RegExpMatch? relMatch = relRegExp.firstMatch(tag);
          if (relMatch == null) continue;

          final String rel = relMatch.group(1)!.toLowerCase();
          int priority = -1;
          if (rel.contains('apple-touch-icon')) {
            priority = 3;
          } else if (rel == 'icon') {
            priority = 2;
          } else if (rel == 'shortcut icon') {
            priority = 1;
          }

          if (priority > bestPriority) {
            final RegExp hrefRegExp = RegExp('href=["\']([^"\']+)["\']', caseSensitive: false);
            final RegExpMatch? hrefMatch = hrefRegExp.firstMatch(tag);
            if (hrefMatch != null) {
              bestIcon = hrefMatch.group(1);
              bestPriority = priority;
            }
          }
        }

        if (bestIcon != null) {
          // Resolve absolute/relative paths
          if (bestIcon.startsWith('http')) {
            return bestIcon;
          } else if (bestIcon.startsWith('//')) {
            return '${baseUri.scheme}:$bestIcon';
          } else if (bestIcon.startsWith('/')) {
            return '${baseUri.scheme}://${baseUri.host}$bestIcon';
          } else {
            // Path relative
            final String path = baseUri.path.endsWith('/')
                ? baseUri.path
                : baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
            return '${baseUri.scheme}://${baseUri.host}$path$bestIcon';
          }
        }
      }
    } catch (_) {}

    try {
      return "https://www.google.com/s2/favicons?sz=64&domain=${baseUri.host}";
    } catch (_) {
      return null;
    }
  }

  static Future<File?> getFaviconUrlData(String url) async {
    final String cachePath = '${getTabameAppDataFolder()}/cache/icon_cache';
    final Directory cacheDir = Directory(cachePath);
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final String cacheSearchPattern = 'url_${url.hashCode}.';
    try {
      final List<FileSystemEntity> files = cacheDir.listSync();
      for (final FileSystemEntity entity in files) {
        if (entity is File && entity.path.split(Platform.pathSeparator).last.startsWith(cacheSearchPattern)) {
          final DateTime lastModified = entity.lastModifiedSync();
          if (DateTime.now().difference(lastModified).inDays < 7) {
            return entity;
          }
        }
      }
    } catch (_) {}

    final String? faviconUrl = await getFaviconUrl(url);
    if (faviconUrl == null) return null;

    String extension = 'png';
    final String pathWithoutQuery = faviconUrl.split('?').first;
    if (pathWithoutQuery.endsWith('.ico')) {
      extension = 'ico';
    } else if (pathWithoutQuery.endsWith('.svg')) {
      extension = 'svg';
    } else if (pathWithoutQuery.endsWith('.jpg') || pathWithoutQuery.endsWith('.jpeg')) {
      extension = 'jpg';
    } else if (pathWithoutQuery.endsWith('.png')) {
      extension = 'png';
    }

    final File cacheFile = File('$cachePath/url_${url.hashCode}.$extension');

    try {
      final http.Response response = await http.get(Uri.parse(faviconUrl));
      if (response.statusCode == 200) {
        cacheFile.writeAsBytesSync(response.bodyBytes);
        return cacheFile;
      }
    } catch (_) {}
    return null;
  }

  static ExtractedIcon extractIcon(String path, {int iconID = 0}) {
    File? cacheFile;
    if (iconID == 0) {
      final String cachePath = '${getTabameAppDataFolder()}/cache/icon_cache';
      final Directory cacheDir = Directory(cachePath);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
      cacheFile = File('$cachePath/${path.hashCode}.ico');
      if (cacheFile.existsSync()) {
        final DateTime lastModified = cacheFile.lastModifiedSync();
        if (DateTime.now().difference(lastModified).inDays < 7) {
          return cacheFile.path;
        }
        cacheFile.deleteSync();
      }
    }

    final Uint8List? iconBytes = _extractIconInternal(path, iconID);

    if (iconID == 0 && iconBytes != null && cacheFile != null) {
      cacheFile.writeAsBytesSync(iconBytes);
      return cacheFile.path;
    }

    return iconBytes;
  }

  static Uint8List? _extractIconInternal(String path, int iconID) {
    if (path.toLowerCase().endsWith('.lnk') || path.toLowerCase().endsWith('.url')) {
      return using((Arena arena) {
        final Pointer<SHFILEINFO> fileInfo = arena<SHFILEINFO>();
        final Pointer<Utf16> pathPointer = path.toNativeUtf16(allocator: arena);

        const int shgfiSysiconindex = 0x000004000;
        const int ildNormal = 0x00000000;

        final int imageListHandle = SHGetFileInfo(
          pathPointer,
          0,
          fileInfo,
          sizeOf<SHFILEINFO>(),
          shgfiSysiconindex,
        );

        if (imageListHandle != 0) {
          final int iconHandle = ImageList_GetIcon(imageListHandle, fileInfo.ref.iIcon, ildNormal);
          if (iconHandle != 0) {
            final Uint8List? iconBytes = hIconToBytes(iconHandle);
            DestroyIcon(iconHandle);
            return iconBytes;
          }
        }
        return null;
      });
    } else if (path.contains('.dll') && iconID != 98988) {
      final Pointer<IntPtr> largeIconPointer = calloc<IntPtr>();
      final Pointer<IntPtr> smallIconPointer = calloc<IntPtr>();
      final Pointer<Utf16> filePathPointer = path.toNativeUtf16();

      try {
        final int extractionResult = ExtractIconEx(filePathPointer, iconID, largeIconPointer, smallIconPointer, 1);
        if (extractionResult > 0) {
          final int largeIconHandle = largeIconPointer.value;
          final int smallIconHandle = smallIconPointer.value;
          final Uint8List? largeIconBytes = hIconToBytes(largeIconHandle);
          if (largeIconBytes != null) {
            return largeIconBytes;
          }
          return hIconToBytes(smallIconHandle);
        }
      } finally {
        if (largeIconPointer.value != NULL) {
          DestroyIcon(largeIconPointer.value);
        }
        if (smallIconPointer.value != NULL) {
          DestroyIcon(smallIconPointer.value);
        }
        free(filePathPointer);
        calloc.free(largeIconPointer);
        calloc.free(smallIconPointer);
      }
      final ExtractedIcon fallbackIcon = extractIcon(path, iconID: 98988);
      return fallbackIcon is Uint8List ? fallbackIcon : null;
    } else {
      return using((Arena arena) {
        final Pointer<Utf16> filePathPointer = path.toNativeUtf16(allocator: arena);
        final int moduleHandle = GetModuleHandle(nullptr);
        final Pointer<WORD> iconIdPointer = arena<WORD>();
        // iconIdPointer.value = iconID;

        final int iconHandle = ExtractAssociatedIcon(moduleHandle, filePathPointer, iconIdPointer);
        if (iconHandle == NULL) {
          return null;
        }

        try {
          return hIconToBytes(iconHandle);
        } finally {
          DestroyIcon(iconHandle);
        }
      });
    }
  }

  static Uint8List? windowIcon(int hWnd) {
    int iconHandle = SendMessage(hWnd, WM_GETICON, 2, 0); // ICON_SMALL2 - User Made Apps
    if (iconHandle == 0) {
      iconHandle = GetClassLongPtr(hWnd, -14); // GCLP_HICON - Microsoft Win Apps
    }
    return hIconToBytes(iconHandle);
  }

  static Future<Uint8List?> getIconPng(int hIcon) async {
    return await getIconPng(hIcon);
  }

  static Uint8List? hIconToBytes(int hIcon, {int nColorBits = 32}) {
    if (hIcon == NULL) {
      return null;
    }

    return using((Arena arena) {
      final List<int> iconBuffer = <int>[];
      final int deviceContextHandle = CreateCompatibleDC(NULL);
      int colorBitmapHandle = NULL;
      int maskBitmapHandle = NULL;

      try {
        if (deviceContextHandle == NULL) {
          return null;
        }

        const List<int> iconHeader = <int>[0, 0, 1, 0, 1, 0];
        iconBuffer.addAll(iconHeader);

        final Pointer<ICONINFO> iconInfo = arena<ICONINFO>();
        if (GetIconInfo(hIcon, iconInfo) == 0) {
          return null;
        }
        colorBitmapHandle = iconInfo.ref.hbmColor;
        maskBitmapHandle = iconInfo.ref.hbmMask;

        final Pointer<BITMAPINFO> bitmapInfo = arena<BITMAPINFO>();
        bitmapInfo.ref.bmiHeader
          ..biSize = sizeOf<BITMAPINFOHEADER>()
          ..biBitCount = 0;

        if (GetDIBits(deviceContextHandle, colorBitmapHandle, 0, 0, nullptr, bitmapInfo, DIB_RGB_COLORS) == 0) {
          return null;
        }

        int bitmapInfoSize = sizeOf<BITMAPINFOHEADER>();
        if (nColorBits < 24) {
          bitmapInfoSize += sizeOf<RGBQUAD>() * (1 << nColorBits);
        }

        final int bitmapPixelSize = bitmapInfo.ref.bmiHeader.biSizeImage;
        if (bitmapPixelSize == 0) {
          return null;
        }

        final Pointer<Uint8> bitmapPixels = arena<Uint8>(bitmapPixelSize);

        bitmapInfo.ref.bmiHeader
          ..biBitCount = nColorBits
          ..biCompression = BI_RGB;

        if (GetDIBits(
              deviceContextHandle,
              colorBitmapHandle,
              0,
              bitmapInfo.ref.bmiHeader.biHeight,
              bitmapPixels,
              bitmapInfo,
              DIB_RGB_COLORS,
            ) ==
            0) {
          return null;
        }

        final Pointer<BITMAPINFO> maskBitmapInfo = arena<BITMAPINFO>();
        maskBitmapInfo.ref.bmiHeader
          ..biSize = sizeOf<BITMAPINFOHEADER>()
          ..biBitCount = 0;

        if (GetDIBits(deviceContextHandle, maskBitmapHandle, 0, 0, nullptr, maskBitmapInfo, DIB_RGB_COLORS) == 0 ||
            maskBitmapInfo.ref.bmiHeader.biBitCount != 1) {
          return null;
        }

        final int maskPixelSize = maskBitmapInfo.ref.bmiHeader.biSizeImage;
        if (maskPixelSize == 0) {
          return null;
        }

        final Pointer<Uint8> maskPixels = arena<Uint8>(maskPixelSize);
        if (GetDIBits(
              deviceContextHandle,
              maskBitmapHandle,
              0,
              maskBitmapInfo.ref.bmiHeader.biHeight,
              maskPixels,
              maskBitmapInfo,
              DIB_RGB_COLORS,
            ) ==
            0) {
          return null;
        }

        final Pointer<_IconDirectoryEntry> directoryEntry = arena<_IconDirectoryEntry>();
        directoryEntry.ref
          ..nWidth = bitmapInfo.ref.bmiHeader.biWidth
          ..nHeight = bitmapInfo.ref.bmiHeader.biHeight
          ..nNumColorsInPalette = (nColorBits == 4 ? 16 : 0)
          ..nNumColorPlanes = 0
          ..nBitsPerPixel = bitmapInfo.ref.bmiHeader.biBitCount
          ..nDataLength = bitmapPixelSize + maskPixelSize + bitmapInfoSize
          ..nOffset = sizeOf<_IconDirectoryEntry>() + 6;

        iconBuffer.addAll(directoryEntry.cast<Uint8>().asTypedList(sizeOf<_IconDirectoryEntry>()));

        bitmapInfo.ref.bmiHeader
          ..biHeight *= 2
          ..biCompression = 0
          ..biSizeImage = bitmapPixelSize + maskPixelSize;
        iconBuffer.addAll(bitmapInfo.cast<Uint8>().asTypedList(bitmapInfoSize));

        iconBuffer.addAll(bitmapPixels.asTypedList(bitmapPixelSize));
        iconBuffer.addAll(maskPixels.asTypedList(maskPixelSize));

        return Uint8List.fromList(iconBuffer);
      } finally {
        if (colorBitmapHandle != NULL) {
          DeleteObject(colorBitmapHandle);
        }
        if (maskBitmapHandle != NULL) {
          DeleteObject(maskBitmapHandle);
        }
        if (deviceContextHandle != NULL) {
          DeleteDC(deviceContextHandle);
        }
      }
    });
  }

  // Wallpaper helpers
  static DesktopBackgroundType getDesktopBackgroundType() {
    final String wallpaperPath = _getDesktopWallpaperPath();

    if (wallpaperPath.isNotEmpty) {
      return DesktopBackgroundType.wallpaper;
    }

    return DesktopBackgroundType.solidColor;
  }

  static Future<bool> setWallpaper(File file, int monitorIndex, WallpaperFillMode fillMode) async {
    final bool ok = await Desktop.setWallpaper(file.path, monitorIndex, fillMode: fillMode);
    if (!ok) return false;

    // Save to settings (do not load into globalSettings)
    final String savedJson = Boxes.pref.getString("monitorWallpapers") ?? "{}";
    try {
      final Map<String, dynamic> savedWallpapers = jsonDecode(savedJson) as Map<String, dynamic>;
      savedWallpapers[monitorIndex.toString()] = <String, Object>{
        "path": file.path,
        "fillMode": fillMode.index,
      };
      await Boxes.updateSettings("monitorWallpapers", jsonEncode(savedWallpapers));
    } catch (e) {
      // If corrupt, overwrite
      await Boxes.updateSettings(
          "monitorWallpapers",
          jsonEncode(<String, Map<String, Object>>{
            monitorIndex.toString(): <String, Object>{
              "path": file.path,
              "fillMode": fillMode.index,
            }
          }));
    }
    return true;
  }

  static Future<void> toggleDesktopWallpaper(bool enable) async {
    if (!enable) await toggleMonitorWallpaper(enable);
    if (enable) {
      final String savedJson = Boxes.pref.getString("monitorWallpapers") ?? "{}";
      try {
        final Map<String, dynamic> savedWallpapers = jsonDecode(savedJson) as Map<String, dynamic>;
        if (savedWallpapers.isEmpty) {
          await toggleMonitorWallpaper(enable);
          return;
        }
        for (final String monitorKey in savedWallpapers.keys) {
          final int? monitorIndex = int.tryParse(monitorKey);
          if (monitorIndex == null) continue;

          final Map<String, dynamic> data = savedWallpapers[monitorKey] as Map<String, dynamic>;
          final String? path = data["path"];
          final int? fillModeIndex = data["fillMode"];

          if (path != null && File(path).existsSync()) {
            final WallpaperFillMode fillMode =
                fillModeIndex != null ? WallpaperFillMode.values[fillModeIndex] : WallpaperFillMode.fill;
            await Desktop.setWallpaper(path, monitorIndex, fillMode: fillMode);
          }
        }
      } catch (e) {
        await toggleMonitorWallpaper(enable);
        // Silently skip if error
      }
    }
  }

  static bool hasDesktopWallpaper() => getDesktopBackgroundType() == DesktopBackgroundType.wallpaper;

  static bool isWallpaperEnabled() => hasDesktopWallpaper();

  static String getDesktopWallpaperPath() => _getDesktopWallpaperPath();

  static bool setDesktopWallpaper(String path) {
    final File wallpaperFile = File(path);
    if (!wallpaperFile.existsSync()) {
      return false;
    }

    final Pointer<Utf16> wallpaperPathPointer = path.toNativeUtf16();
    try {
      return SystemParametersInfo(
            SPI_SETDESKWALLPAPER,
            0,
            wallpaperPathPointer.cast(),
            SPIF_UPDATEINIFILE | SPIF_SENDCHANGE,
          ) !=
          0;
    } finally {
      calloc.free(wallpaperPathPointer);
    }
  }

  static String _getDesktopWallpaperPath() {
    final Pointer<Utf16> wallpaperBuffer = wsalloc(MAX_PATH);
    try {
      final bool isSuccessful = SystemParametersInfo(SPI_GETDESKWALLPAPER, MAX_PATH, wallpaperBuffer, 0) != 0;
      if (!isSuccessful) {
        return "";
      }

      final String wallpaperPath = wallpaperBuffer.toDartString().trim();
      if (wallpaperPath.isEmpty) {
        return "";
      }
      return File(wallpaperPath).existsSync() ? wallpaperPath : "";
    } finally {
      free(wallpaperBuffer);
    }
  }

  static void restoreAndReattachDrag(int hwnd, int origW, int origH) {
    // 1. Get cursor position BEFORE we do anything
    final Pointer<POINT> point = calloc<POINT>();
    GetCursorPos(point);
    final int cursorX = point.ref.x;
    final int cursorY = point.ref.y;
    free(point);

    // 2. Cancel the current drag loop — this releases mouse capture
    //    SendMessage is synchronous, so the drag is fully cancelled
    //    before we proceed
    SendMessage(hwnd, WM_CANCELMODE, 0, 0);
    ReleaseCapture();

    // 3. Resize to original size, keeping current top-left position.
    //    We use the cursor position to re-center the window under the
    //    cursor naturally — same behaviour as FancyZones
    final int newX = cursorX - origW ~/ 2; // center window on cursor
    Win32.changePosition(hwnd, newX, -1, origW, origH);

    // 4. Move cursor to the window's new title bar center so the
    //    re-attached drag feels natural
    SetCursorPos(newX + origW ~/ 2, cursorY);

    // 5. Re-post a WM_NCLBUTTONDOWN with HTCAPTION to re-start the
    //    drag loop from the new size/position.
    //    PostMessage (async) is important here — SendMessage would
    //    block until the drag loop exits (never), deadlocking.
    //    Pack cursor coords into lParam as LOWORD/HIWORD
    final int lParam = (cursorY << 16) | (cursorX & 0xFFFF);
    PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, lParam);
  }

  static bool _setDwordValue(int rootKey, String subKey, String name, int value) {
    final Pointer<IntPtr> phkResult = calloc<IntPtr>();
    final Pointer<Uint32> lpData = calloc<Uint32>()..value = value;

    try {
      final Pointer<Utf16> subKeyPtr = subKey.toNativeUtf16();
      final Pointer<Utf16> namePtr = name.toNativeUtf16();

      try {
        final int result = RegCreateKeyEx(
            rootKey, subKeyPtr, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_SET_VALUE, nullptr, phkResult, nullptr);

        if (result != ERROR_SUCCESS) {
          return false;
        }

        final int hKey = phkResult.value;

        final int setResult = RegSetValueEx(hKey, namePtr, 0, REG_DWORD, lpData.cast<Uint8>(), sizeOf<Uint32>());

        RegCloseKey(hKey);
        return setResult == ERROR_SUCCESS;
      } finally {
        calloc.free(subKeyPtr);
        calloc.free(namePtr);
      }
    } finally {
      calloc.free(phkResult);
      calloc.free(lpData);
    }
  }

  /// type: 0 = dark, 1 = light
  static bool setWindowsTheme(int type) {
    const String key = r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';

    final int value = (type == 1) ? 1 : 0;

    final bool ok1 = _setDwordValue(HKEY_CURRENT_USER, key, 'AppsUseLightTheme', value);

    final bool ok2 = _setDwordValue(HKEY_CURRENT_USER, key, 'SystemUsesLightTheme', value);

    final Pointer<Utf16> immersiveColorSet = 'ImmersiveColorSet'.toNativeUtf16();
    final Pointer<IntPtr> resultPtr = calloc<IntPtr>();

    try {
      SendMessageTimeout(
          HWND_BROADCAST, WM_SETTINGCHANGE, 0, immersiveColorSet.address, SMTO_ABORTIFHUNG, 2000, resultPtr);
    } finally {
      calloc.free(immersiveColorSet);
      calloc.free(resultPtr);
    }

    return ok1 && ok2;
  }

  /// Reads a DWORD value from registry
  static int? _getDwordValue(int rootKey, String subKey, String name) {
    final Pointer<IntPtr> phkResult = calloc<IntPtr>();
    final Pointer<Uint32> lpType = calloc<Uint32>();
    final Pointer<Uint32> lpData = calloc<Uint32>();
    final Pointer<Uint32> lpcbData = calloc<Uint32>()..value = sizeOf<Uint32>();

    try {
      final Pointer<Utf16> subKeyPtr = subKey.toNativeUtf16();
      final Pointer<Utf16> namePtr = name.toNativeUtf16();

      try {
        final int openResult = RegOpenKeyEx(
          rootKey,
          subKeyPtr,
          0,
          KEY_QUERY_VALUE,
          phkResult,
        );

        if (openResult != ERROR_SUCCESS) return null;

        final int hKey = phkResult.value;

        final int queryResult = RegQueryValueEx(
          hKey,
          namePtr,
          nullptr,
          lpType,
          lpData.cast<Uint8>(),
          lpcbData,
        );

        RegCloseKey(hKey);

        if (queryResult != ERROR_SUCCESS || lpType.value != REG_DWORD) {
          return null;
        }

        return lpData.value;
      } finally {
        calloc.free(subKeyPtr);
        calloc.free(namePtr);
      }
    } finally {
      calloc.free(phkResult);
      calloc.free(lpType);
      calloc.free(lpData);
      calloc.free(lpcbData);
    }
  }

  /// returns: 0 = dark, 1 = light, -1 = unknown
  static int getWindowsTheme() {
    const String key = r'Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';

    final int? value = _getDwordValue(
      HKEY_CURRENT_USER,
      key,
      'AppsUseLightTheme',
    );

    if (value == null) return -1;
    return (value == 1) ? 1 : 0;
  }

  static Future<void> deleteOldFiles(String directoryPath, {int days = 4}) async {
    final Directory directory = Directory(directoryPath);

    // 1. Check if the directory actually exists
    if (!await directory.exists()) {
      print("Directory does not exist: $directoryPath");
      return;
    }

    // 2. Calculate the threshold date (4 days ago)
    final DateTime threshold = DateTime.now().subtract(Duration(days: days));

    try {
      // 3. List all entities in the directory (non-recursive)
      final List<FileSystemEntity> entities = await directory.list().toList();

      for (FileSystemEntity entity in entities) {
        // We only want to delete files, not sub-folders
        if (entity is File) {
          DateTime lastModified = await entity.lastModified();

          if (lastModified.isBefore(threshold)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      print("Error during file cleanup: $e");
    }
  }
}

class ClipboardExtension {
  static Future<void> copyFile(String filePath) async {
    final List<int> pathUnits = filePath.codeUnits;
    final int bytesNeeded = sizeOf<DROPFILES>() + ((pathUnits.length + 2) * sizeOf<Uint16>());
    final Pointer<NativeType> hMem = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytesNeeded);
    if (hMem.address == 0) {
      throw Exception('Failed to allocate clipboard memory.');
    }

    final Pointer<DROPFILES> dropFiles = GlobalLock(hMem).cast<DROPFILES>();
    if (dropFiles.address == 0) {
      GlobalFree(hMem);
      throw Exception('Failed to lock clipboard memory.');
    }

    try {
      dropFiles.ref.pFiles = sizeOf<DROPFILES>();
      dropFiles.ref.pt.x = 0;
      dropFiles.ref.pt.y = 0;
      dropFiles.ref.fNC = 0;
      dropFiles.ref.fWide = 1;

      final Pointer<Uint16> fileListPtr = (dropFiles.cast<Uint8>() + sizeOf<DROPFILES>()).cast<Uint16>();
      for (int i = 0; i < pathUnits.length; i++) {
        fileListPtr[i] = pathUnits[i];
      }
      fileListPtr[pathUnits.length] = 0;
      fileListPtr[pathUnits.length + 1] = 0;
    } finally {
      GlobalUnlock(hMem);
    }

    if (OpenClipboard(NULL) == 0) {
      GlobalFree(hMem);
      throw Exception('Failed to open clipboard.');
    }

    try {
      EmptyClipboard();
      final int result = SetClipboardData(CF_HDROP, hMem.address);
      if (result == 0) {
        GlobalFree(hMem);
        throw Exception('Failed to set clipboard file data.');
      }
    } finally {
      CloseClipboard();
    }
  }
}

enum DesktopBackgroundType {
  wallpaper,
  solidColor,
  unknown,
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
