import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:crypto/crypto.dart' as crypto;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../platform/windows/tabamewin32_api.dart';
import '../../platform/windows/win32_api.dart';
import 'package:window_manager/window_manager.dart';

import '../classes/boxes.dart';
import '../globals.dart';
import '../settings.dart';
import '../util/scripts.dart';
import '../../platform/app_paths.dart';
import '../../platform/distribution_profile.dart';
import '../../platform/shell_integration_service.dart';
import '../../services/extension_policy.dart';
import '../../services/native_integration_coordinator.dart';
import 'imports.dart';
import 'keys.dart';
import 'mixed.dart';
import 'registry.dart';
import 'win32.dart';

typedef ExtractedIcon = Object?;

final class _TokenElevation extends Struct {
  @Uint32()
  external int tokenIsElevated;
}

const int _tokenQuery = 0x0008;
const int _tokenElevationInformation = 20;

class WinUtils {
  WinUtils._();
  static int _isAdministratorAccount = -1;
  static DynamicLibrary? _advapi32;
  static String _programFilesPath = "";

  static const Set<String> _perPathIconExtensions = <String>{'.exe', '.lnk', '.url', '.ico'};
  static const Duration _iconCacheMaxAge = Duration(days: 7);
  static ExtractedIcon _defaultFolderIcon;

  static Directory _iconCacheDirectory({String? cacheDirectoryPath}) {
    return Directory(cacheDirectoryPath ?? AppPaths.cachePath('icon_cache', forWrite: true));
  }

  static Directory fileFormatIconCacheDirectory({String? cacheDirectoryPath}) {
    return Directory(p.join(_iconCacheDirectory(cacheDirectoryPath: cacheDirectoryPath).path, 'file_formats'));
  }

  static bool _isFreshCacheFile(File file) {
    return DateTime.now().difference(file.lastModifiedSync()) < _iconCacheMaxAge;
  }

  static String? _fileFormatIconCacheKey(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty || trimmed.endsWith('/') || trimmed.endsWith(r'\')) return null;

    try {
      if (Directory(trimmed).existsSync()) return null;
    } catch (_) {}

    final String ext = p.extension(trimmed).toLowerCase();
    if (ext.isEmpty || _perPathIconExtensions.contains(ext)) return null;

    final String key = ext.substring(1).replaceAll(RegExp(r'[^a-z0-9_-]'), '_');
    return key.isEmpty ? null : key;
  }

  static File? _fileFormatIconCacheFile(String path, {String? cacheDirectoryPath}) {
    final String? key = _fileFormatIconCacheKey(path);
    if (key == null) return null;
    return File(p.join(
      fileFormatIconCacheDirectory(cacheDirectoryPath: cacheDirectoryPath).path,
      '$key.ico',
    ));
  }

  static File? getCachedFileFormatIcon(String path) {
    final File? cacheFile = _fileFormatIconCacheFile(path);
    if (cacheFile == null || !cacheFile.existsSync()) return null;
    if (_isFreshCacheFile(cacheFile)) return cacheFile;

    try {
      cacheFile.deleteSync();
    } catch (_) {}
    return null;
  }

  static bool _isDirectoryPath(String path) {
    try {
      return Directory(path.trim()).existsSync();
    } catch (_) {
      return false;
    }
  }

  static bool _hasCustomFolderIcon(String path) {
    final String trimmed = path.trim();
    if (trimmed.isEmpty) return false;

    final File desktopIni = File(p.join(trimmed, 'desktop.ini'));
    if (!desktopIni.existsSync()) return false;

    try {
      final String content = desktopIni.readAsStringSync().toLowerCase();
      return content.contains('iconresource=') || content.contains('iconfile=');
    } catch (_) {
      return true;
    }
  }

  static bool usesDefaultFolderIcon(String path) {
    return _isDirectoryPath(path) && !_hasCustomFolderIcon(path);
  }

  // Environment and system information
  /// Returns whether the account belongs to the local Administrators group.
  ///
  /// Group membership is intentionally separate from process elevation. An
  /// administrator account normally starts at medium integrity under UAC.
  static bool isAdministratorAccount() {
    if (_isAdministratorAccount == -1) {
      _isAdministratorAccount = IsUserAnAdmin() == true ? 1 : 0;
    }
    return _isAdministratorAccount == 1;
  }

  /// Returns whether this process currently has an elevated token.
  ///
  /// Do not replace this with [isAdministratorAccount]; the latter is true for
  /// a medium-integrity administrator account and cannot authorize access to
  /// elevated windows or protected registry keys.
  static bool isProcessElevated() {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return false;
    }

    final Pointer<IntPtr> tokenHandle = calloc<IntPtr>();
    final Pointer<_TokenElevation> elevation = calloc<_TokenElevation>();
    final Pointer<Uint32> returnLength = calloc<Uint32>();
    try {
      final DynamicLibrary advapi32 = _advapi32 ??= DynamicLibrary.open('advapi32.dll');
      final int openResult = advapi32
          .lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<IntPtr>), int Function(int, int, Pointer<IntPtr>)>(
        'OpenProcessToken',
      )(GetCurrentProcess(), _tokenQuery, tokenHandle);
      if (openResult == 0 || tokenHandle.value == 0) return false;

      final int queryResult = advapi32.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32, Pointer<Uint32>),
          int Function(int, int, Pointer<Void>, int, Pointer<Uint32>)>('GetTokenInformation')(
        tokenHandle.value,
        _tokenElevationInformation,
        elevation.cast<Void>(),
        sizeOf<_TokenElevation>(),
        returnLength,
      );
      return queryResult != 0 && elevation.ref.tokenIsElevated != 0;
    } catch (_) {
      return false;
    } finally {
      if (tokenHandle.value != 0) CloseHandle(tokenHandle.value);
      free(tokenHandle);
      free(elevation);
      free(returnLength);
    }
  }

  /// Returns the process-elevation state used by existing Windows callers.
  ///
  /// Older call sites used the administrator-group check as if it represented
  /// the current token. Keep the method name for compatibility, but make its
  /// meaning match the access checks those callers perform.
  static bool isAdministrator() => isProcessElevated();

  static bool isWindows11() {
    final RegistryKey currentVersionKey =
        Registry.openPath(RegistryHive.localMachine, path: r'SOFTWARE\Microsoft\Windows NT\CurrentVersion');
    final int currentBuildNumber = currentVersionKey.getValueAsInt("CurrentBuild") ?? 0;
    currentVersionKey.close();
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

  static String getTempFolder() => AppPaths.temporaryDirectory;

  static String getTabameAppDataFolder({bool settings = false}) {
    final String directory = settings ? AppPaths.settingsDirectory : AppPaths.root;
    Directory(directory).createSync(recursive: true);
    return directory;
  }

  /// Configured root folder holding user-installed launcher plugins
  /// (`<plugins>\\<id>\\plugin.json` + the plugin's script files).
  static String getPluginsFolder() {
    final String directory = AppPaths.pluginsDirectory;
    Directory(directory).createSync(recursive: true);
    return directory;
  }

  static String getFancyshotFolder() {
    if (user.fancyshotFolder.isEmpty) return AppPaths.fancyshotDirectory;
    return user.fancyshotFolder;
  }

  /// Root folder holding Rewindly's rolling segment buffer
  /// (`<root>\\<monitorIndex>\\seg_<epochMs>.mp4`). Exported clips go to FancyShot.
  // static String getRewindlyFolder() {
  //   final String directory = AppPaths.rewindlyDirectory;
  //   Directory(directory).createSync(recursive: true);
  //   return directory;
  // }

  static Future<String> folderPicker() async {
    return await pickFolder();
  }

  // ── Install / Uninstall ──

  static const String _uninstallRegistryRoot = r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall';

  /// Removes the legacy portable "Apps & Features" entry during the
  /// service-owned custom uninstall flow.
  static void _unregisterUninstallEntry() {
    try {
      final RegistryKey uninstallRoot = Registry.openPath(RegistryHive.currentUser,
          path: _uninstallRegistryRoot, desiredAccessRights: AccessRights.allAccess);
      if (uninstallRoot.subkeyNames.contains('Tabame')) uninstallRoot.deleteKey('Tabame');
      uninstallRoot.close();
    } catch (_) {}
  }

  /// Full uninstall flow: disables startup/context-menu integrations, removes
  /// the Apps & Features entry, then deletes the install + app data folders via
  /// a detached script (since the running exe can't delete its own files) and exits.

  static Future<void> performUninstall() async {
    if (!DistributionProfileConfig.current.capabilities.customUninstall || !kReleaseMode) return;

    await setStartUpShortcut(false);

    final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
    if (wizardlyContextMenu.isWizardlyInstalledInContextMenu()) {
      wizardlyContextMenu.toggleWizardlyToContextMenu();
    }

    _unregisterUninstallEntry();

    // 1. Strip trailing slashes/backslashes to prevent path issues
    final String exeDir = Directory(Platform.resolvedExecutable).parent.path.replaceAll(RegExp(r'[/\\]+$'), '');
    final String appData = getTabameAppDataFolder().replaceAll(RegExp(r'[/\\]+$'), '');
    final String exeName = p.basenameWithoutExtension(Platform.resolvedExecutable);
    await toggleTaskbar(visible: true);

    final String tempDir = getTempFolder().replaceAll(RegExp(r'[/\\]+$'), '');
    final String scriptPath = p.join(tempDir, 'uninstall_$exeName.ps1');
    final String logPath = p.join(tempDir, 'uninstall_$exeName.log');

    // 2. Use SINGLE quotes in PowerShell for all paths. Single quotes treat
    // backslashes as literal characters, avoiding the `\"` escaping problem entirely.
    final String psScript = '''
  \$ErrorActionPreference = 'Continue'
  Start-Transcript -Path '$logPath' -Force | Out-Null
  try {
    Set-Location -LiteralPath '$tempDir'
    for (\$i = 0; \$i -lt 30; \$i++) {
      Start-Sleep -Seconds 1
      if (-not (Get-Process -Name '$exeName' -ErrorAction SilentlyContinue)) { break }
    }
    taskkill /F /IM '$exeName.exe' /T 2>\$null
    Start-Sleep -Seconds 1

    # Retry a few times in case file handles take a moment to release
    for (\$r = 0; \$r -lt 5; \$r++) {
      \$err1 = \$null
      \$err2 = \$null
      Remove-Item -LiteralPath '$appData' -Recurse -Force -ErrorVariable err1
      Remove-Item -LiteralPath '$exeDir'  -Recurse -Force -ErrorVariable err2
      if ((-not (Test-Path '$appData')) -and (-not (Test-Path '$exeDir'))) { break }
      Start-Sleep -Seconds 1
    }
  } finally {
    Stop-Transcript | Out-Null
    Remove-Item -LiteralPath '$scriptPath' -Force -ErrorAction SilentlyContinue
  }
  ''';

    await File(scriptPath).writeAsString(psScript);

    // cmd /c start "" /b is the canonical way to fully orphan a child on Windows.
    await Process.start(
      'cmd.exe',
      <String>[
        '/c',
        'start',
        '""', // window title (required)
        '/b', // no new window
        'powershell.exe',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-WindowStyle', 'Hidden',
        '-File', scriptPath,
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: tempDir,
    );

    closeAllTabameExProcesses();
    exit(0);
  }

  // Startup, desktop, and taskbar helpers
  static Future<void> setStartUpShortcut(bool enabled, {String args = "", String? exePath, int showCmd = 1}) async {
    if (kDebugMode) return;
    exePath ??= Platform.resolvedExecutable;
    await setStartOnSystemStartup(enabled, args: args, exePath: exePath, showCmd: showCmd);
  }

  static void startOnStartup({
    String? exeFilePath,
    String? arguments,
  }) {
    final int hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    // S_OK or S_FALSE mean COM is initialized
    final bool initialized = hr >= 0;

    final Pointer<Pointer<COMObject>> shellLinkPtr = calloc<Pointer<COMObject>>();

    try {
      exeFilePath ??= Platform.resolvedExecutable;
      final String workingDirectory = Directory(exeFilePath).parent.path;

      final IShellLink shellLink = IShellLink(shellLinkPtr.cast());

      final Pointer<Utf16> exePtr = exeFilePath.toNativeUtf16();
      final Pointer<Utf16> workingDirPtr = workingDirectory.toNativeUtf16();
      final Pointer<Utf16>? argsPtr = arguments?.toNativeUtf16();

      try {
        shellLink.setPath(exePtr);
        shellLink.setWorkingDirectory(workingDirPtr);
        shellLink.setShowCmd(SW_SHOWNORMAL);

        if (argsPtr != null) {
          shellLink.setArguments(argsPtr);
        }

        final IPersistFile persistFile = IPersistFile(shellLink.toInterface(IID_IPersistFile));

        try {
          final String startupFolderPath = getKnownFolderCLSID(CSIDL_STARTUP);
          final String shortcutName = File(exeFilePath).uri.pathSegments.last.replaceFirst('.exe', '.lnk');

          final Pointer<Utf16> shortcutPath = '$startupFolderPath\\$shortcutName'.toNativeUtf16();

          try {
            persistFile.save(shortcutPath, TRUE);
          } finally {
            calloc.free(shortcutPath);
          }
        } finally {
          persistFile.release();
        }
      } finally {
        calloc.free(exePtr);
        calloc.free(workingDirPtr);

        if (argsPtr != null) {
          calloc.free(argsPtr);
        }

        shellLink.release();
      }
    } finally {
      calloc.free(shellLinkPtr);

      if (initialized) {
        CoUninitialize();
      }
    }
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
    final String executableName = p.basenameWithoutExtension(Platform.resolvedExecutable);
    return "$startupProgramsPath\\Startup\\$executableName.lnk";
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

  static Future<bool> toggleTaskbar({bool? visible}) async {
    final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
    if (!integrations.canStart(NativeIntegrationId.shellIntegration)) {
      integrations.reportDisabled(
        NativeIntegrationId.shellIntegration,
        reason: integrations.denialReason(NativeIntegrationId.shellIntegration) ??
            'Taskbar changes are disabled; the normal taskbar remains visible.',
        reducedMode: true,
      );
      return false;
    }

    final TaskbarVisibilityService taskbar = TaskbarVisibilityService.instance;
    final bool requestedVisible = visible ?? !taskbar.isVisible;
    final ShellIntegrationResult result = await taskbar.setVisible(requestedVisible);
    if (!result.success) {
      integrations.reportError(
        NativeIntegrationId.shellIntegration,
        reason: result.message,
        reducedMode: true,
      );
      return false;
    }
    Globals.taskbarVisible = result.visible;
    integrations.reportRunning(NativeIntegrationId.shellIntegration);
    return true;
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

  static void closeAllTabameExProcesses({bool closeInterface = true, bool closeQuickMenu = true}) {
    final List<int> windowHandles = enumWindows();
    final int mainHandle = Win32.getMainHandle();
    for (final int windowHandle in windowHandles) {
      if (Win32.getClass(windowHandle) != "TABAME_WIN32_WINDOW" || windowHandle == mainHandle) continue;
      if (Win32.getTitle(windowHandle).contains("Debug")) continue;

      final String title = Win32.getTitle(windowHandle);
      if (closeInterface && closeQuickMenu) {
        Win32.closeWindow(windowHandle);
        continue;
      }

      final bool isInterfaceWindow =
          title == "Tabame - Interface" || title == "Tabame - Wizardly" || title == "Tabame - Fancyshot";
      final bool isQuickMenuWindow = title == "Tabame";
      if ((isInterfaceWindow && closeInterface) || (isQuickMenuWindow && closeQuickMenu)) {
        Win32.closeWindow(windowHandle);
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
    final Directory scriptsDirectory = Directory(AppPaths.currentPath('scripts'));
    if (!scriptsDirectory.existsSync()) {
      scriptsDirectory.createSync(recursive: true);
    }

    final String scriptName = script.fileName;
    if (scriptName.isEmpty) {
      return "";
    }

    final String scriptPath = p.join(scriptsDirectory.path, scriptName);
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
      "Set-Location -Path \"${AppPaths.currentPath('scripts')}\";",
      '.\\${getScript(script)} ${arguments ?? ""}',
    ]);
  }

  static Future<List<String>> runPowerShell(List<String> commands, {bool userProvided = false}) async {
    if (userProvided && !ExtensionPolicy.current.canRunArbitraryPowerShell) return const <String>[];
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
    bool userProvided = false,
  }) async {
    if (userProvided && !ExtensionPolicy.current.canRunArbitraryPowerShell) return;
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

  static void open(
    String path, {
    String? arguments,
    bool parseParamaters = true,
    String? workingDirectory,
    bool userProvided = false,
  }) {
    if (userProvided && ExtensionPolicy.current.blocksUserTarget(path)) return;
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
  }

  /// Requests a UAC launch and returns ShellExecute's result code.
  ///
  /// Callers that need user-facing cancellation/error handling should use the
  /// elevation service rather than interpreting this native result directly.
  static int runAsAdmin(String link, {String? arguments}) {
    return ShellExecute(
        NULL, TEXT("runas"), TEXT(link), arguments == null ? nullptr : TEXT(arguments), nullptr, SW_SHOWNORMAL);
  }

  /// Starts a Tabame child process without changing its integrity by default.
  ///
  /// Only an explicit, user-confirmed caller may pass `admin: true`.
  static void startTabame({bool closeCurrent = false, String? arguments, bool? admin}) {
    admin == true
        ? WinUtils.runAsAdmin(Platform.resolvedExecutable, arguments: arguments)
        : WinUtils.open(Platform.resolvedExecutable, arguments: arguments);
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

  static Timer? alwaysRun;
  static void alwaysAwakeRun(bool state) {
    if (state == false) {
      alwaysRun?.cancel();
      SetThreadExecutionState(ES_CONTINUOUS);
    } else {
      alwaysRun?.cancel();
      alwaysRun = Timer.periodic(const Duration(seconds: 45), (Timer timer) {
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
            ReleaseDC(volumeWindowHandle, windowDeviceContext);
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
    final http.Client client = http.Client();

    try {
      final http.Request request = http.Request('GET', Uri.parse(url));
      final http.StreamedResponse response = await client.send(request);

      final File file = File(filename);
      final IOSink sink = file.openWrite();

      try {
        await response.stream.pipe(sink);
      } finally {
        await sink.close();
      }

      callback();
    } finally {
      client.close();
    }
  }

  // static Future<void> downloadFile2(String url, String filename, Function callback) async {
  //   final http.Client httpClient = http.Client();
  //   final http.Request request = http.Request('GET', Uri.parse(url));
  //   final Future<http.StreamedResponse> streamedResponse = httpClient.send(request);

  //   final List<List<int>> dataChunks = <List<int>>[];
  //   streamedResponse.asStream().listen((http.StreamedResponse response) {
  //     response.stream.listen((List<int> chunk) {
  //       dataChunks.add(chunk);
  //     }, onDone: () async {
  //       final File destinationFile = File(filename);
  //       final Uint8List fileBytes = Uint8List(response.contentLength!);
  //       int byteOffset = 0;
  //       for (final List<int> chunk in dataChunks) {
  //         fileBytes.setRange(byteOffset, byteOffset + chunk.length, chunk);
  //         byteOffset += chunk.length;
  //       }
  //       await destinationFile.writeAsBytes(fileBytes);
  //       callback();
  //     });
  //   });
  // }

  static bool isScreenClipping() {
    final int foregroundWindowHandle = GetForegroundWindow();
    final Pointer<Uint32> processIdPointer = calloc<Uint32>();
    final int processId;
    try {
      GetWindowThreadProcessId(foregroundWindowHandle, processIdPointer);
      processId = processIdPointer.value;
    } finally {
      free(processIdPointer);
    }

    final int processHandle = OpenProcess(
      PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
      FALSE,
      processId,
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

    final Pointer<Utf16> operation = "open".toNativeUtf16();
    final Pointer<Utf16> uri = "ms-screenclip://?clippingMode=Rectangle".toNativeUtf16();

    try {
      ShellExecute(0, operation, uri, nullptr, nullptr, SW_SHOWNORMAL);
    } finally {
      calloc.free(operation);
      calloc.free(uri);
    }

    await Future<void>.delayed(const Duration(seconds: 1));

    while (isScreenClipping()) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    await WinClipboard().saveClipboardToPng(AppPaths.temporaryPath('capture.png'));

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

          // Check rel="icon", "shortcut icon", "Serene-touch-icon"
          final RegExp relRegExp = RegExp('rel=["\']([^"\']+)["\']', caseSensitive: false);
          final RegExpMatch? relMatch = relRegExp.firstMatch(tag);
          if (relMatch == null) continue;

          final String rel = relMatch.group(1)!.toLowerCase();
          int priority = -1;
          if (rel.contains('Serene-touch-icon')) {
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
    final Directory cacheDir = _iconCacheDirectory();
    if (!cacheDir.existsSync()) {
      cacheDir.createSync(recursive: true);
    }

    final String cacheSearchPattern = 'url_${url.hashCode}.';
    try {
      final List<FileSystemEntity> files = cacheDir.listSync();
      for (final FileSystemEntity entity in files) {
        if (entity is File && entity.path.split(Platform.pathSeparator).last.startsWith(cacheSearchPattern)) {
          if (_isFreshCacheFile(entity)) {
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

    final File cacheFile = File(p.join(cacheDir.path, 'url_${url.hashCode}.$extension'));

    try {
      final http.Response response = await http.get(Uri.parse(faviconUrl));
      if (response.statusCode == 200) {
        cacheFile.writeAsBytesSync(response.bodyBytes);
        return cacheFile;
      }
    } catch (_) {}
    return null;
  }

  static ExtractedIcon extractIcon(
    String path, {
    int iconID = 0,
    String? cacheDirectoryPath,
  }) {
    File? cacheFile;
    final bool isDefaultFolder = iconID == 0 && usesDefaultFolderIcon(path);
    if (isDefaultFolder && _defaultFolderIcon != null) {
      return _defaultFolderIcon;
    }

    if (iconID == 0) {
      final Directory cacheDir = _iconCacheDirectory(cacheDirectoryPath: cacheDirectoryPath);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }

      cacheFile = _fileFormatIconCacheFile(path, cacheDirectoryPath: cacheDirectoryPath);
      if (cacheFile != null) {
        final Directory fileFormatCacheDir = cacheFile.parent;
        if (!fileFormatCacheDir.existsSync()) {
          fileFormatCacheDir.createSync(recursive: true);
        }
      } else if (isDefaultFolder) {
        cacheFile = null;
      } else {
        cacheFile = File(p.join(cacheDir.path, '${path.hashCode}.ico'));
      }

      if (cacheFile != null && cacheFile.existsSync()) {
        if (_isFreshCacheFile(cacheFile)) {
          return cacheFile.path;
        }
        try {
          cacheFile.deleteSync();
        } catch (_) {}
      }
    }

    final Uint8List? iconBytes = extractIconInternal(path, iconID);

    if (isDefaultFolder && iconBytes != null) {
      _defaultFolderIcon = iconBytes;
      return iconBytes;
    }

    if (iconID == 0 && iconBytes != null && cacheFile != null) {
      final String hash = crypto.md5.convert(iconBytes).toString();
      if (hash != 'a326e0850b34c1935b2e3499fc986380' && hash != '5b290ed4dac06a15d465c7f0f9d5003b') {
        cacheFile.writeAsBytesSync(iconBytes);
        return cacheFile.path;
      }
    }

    return iconBytes;
  }

  static Uint8List? extractIconInternal(String path, int iconID) {
    if (path.toLowerCase().endsWith('.lnk') || path.toLowerCase().endsWith('.url')) {
      // For .url files (Steam shortcuts), try to read the IconFile field first.
      // SHGetFileInfo can't resolve steam:// protocol URLs and returns a blank icon.
      if (path.toLowerCase().endsWith('.url')) {
        final Uint8List? urlIcon = _extractIconFromUrlFile(path);
        if (urlIcon != null) return urlIcon;
      }

      return using((Arena arena) {
        final Pointer<SHFILEINFO> fileInfo = arena<SHFILEINFO>();
        final Pointer<Utf16> pathPointer = path.toNativeUtf16(allocator: arena);
        const int shgfiSysiconindex = 0x000004000;
        const int ildNormal = 0x00000000;
        final int imageListHandle = SHGetFileInfo(pathPointer, 0, fileInfo, sizeOf<SHFILEINFO>(), shgfiSysiconindex);
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

  static Uint8List? _extractIconFromUrlFile(String urlFilePath) {
    try {
      final List<String> lines = File(urlFilePath).readAsLinesSync();
      String? iconFile;
      int iconIndex = 0;

      for (final String line in lines) {
        if (line.startsWith('IconFile=')) {
          iconFile = line.substring('IconFile='.length).trim();
        } else if (line.startsWith('IconIndex=')) {
          iconIndex = int.tryParse(line.substring('IconIndex='.length).trim()) ?? -1;
        }
      }

      if (iconFile == null || iconFile.isEmpty) return null;

      // Expand environment variables like %ProgramFiles(x86)%
      iconFile = _expandEnvironmentStrings(iconFile);

      if (!File(iconFile).existsSync()) return null;
      if (iconFile.endsWith('.ico')) {
        return File(iconFile).readAsBytesSync();
      }
      return using((Arena arena) {
        final Pointer<Utf16> iconPathPtr = iconFile!.toNativeUtf16(allocator: arena);
        // ExtractIconEx gives us the real icon at the specified index
        final Pointer<IntPtr> hIconLarge = arena<IntPtr>();
        if (iconIndex == 0) iconIndex = -1;
        final int extracted = ExtractIconEx(iconPathPtr, iconIndex, hIconLarge, nullptr, 1);
        if (extracted > 0 && hIconLarge.value != 0) {
          final Uint8List? bytes = hIconToBytes(hIconLarge.value);
          DestroyIcon(hIconLarge.value);
          return bytes;
        }
        return null;
      });
    } catch (_) {
      return null;
    }
  }

  static String _expandEnvironmentStrings(String input) {
    // Use ExpandEnvironmentStrings Win32 API for correctness
    return using((Arena arena) {
      final Pointer<Utf16> src = input.toNativeUtf16(allocator: arena);
      // First call to get required buffer size
      final int size = ExpandEnvironmentStrings(src, nullptr, 0);
      if (size == 0) return input;
      final Pointer<Uint16> dst = arena<Uint16>(size);
      ExpandEnvironmentStrings(src, dst.cast<Utf16>(), size);
      return dst.cast<Utf16>().toDartString();
    });
  }

  static Uint8List? windowIcon(int hWnd) {
    int iconHandle = SendMessage(hWnd, WM_GETICON, 2, 0); // ICON_SMALL2 - User Made Apps
    if (iconHandle == 0) {
      iconHandle = GetClassLongPtr(hWnd, -14); // GCLP_HICON - Microsoft Win Apps
    }
    return hIconToBytes(iconHandle);
  }

  // static Future<Uint8List?> getIconPng(int hIcon) async {
  //   return await getIconPng(hIcon);
  // }

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

    // Save to settings (do not load into userSettings)
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
      // 3. List all entities in the directory, including cache subfolders.
      final List<FileSystemEntity> entities = await directory.list(recursive: true).toList();

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

  static void setSortByDateModifiedDesc(String folderPath) {
    // Make folder a "system folder" so desktop.ini is respected
    final Pointer<Utf16> pathPtr = folderPath.toNativeUtf16();
    SetFileAttributes(pathPtr, FILE_ATTRIBUTE_READONLY | FILE_ATTRIBUTE_SYSTEM);
    calloc.free(pathPtr);

    final String iniPath = '$folderPath\\desktop.ini';
    const String iniContent = '[.ShellClassInfo]\r\n'
        'FolderType=Pictures\r\n'
        '\r\n'
        '[ViewState]\r\n'
        'Mode=4\r\n'
        'Vid={137E7700-3573-11CF-AE69-08002B2E1262}\r\n';

    File(iniPath).writeAsStringSync(iniContent);

    final Pointer<Utf16> iniPtr = iniPath.toNativeUtf16();
    SetFileAttributes(iniPtr, FILE_ATTRIBUTE_HIDDEN | FILE_ATTRIBUTE_SYSTEM);
    calloc.free(iniPtr);
  }

  static void fixDrawBug({Duration delay = const Duration(milliseconds: 100)}) {
    WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) async {
      await Future<void>.delayed(delay);
      final Size value = await windowManager.getSize();
      await windowManager.setSize(Size(value.width + 1, value.height + 1));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await windowManager.setSize(Size(value.width, value.height));
    });
  }

  static void enableClickThrough(int hwnd) {
    if (hwnd == 0) return;

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(
      hwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
    );

    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    // Important: refresh cached window styles
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }

  /// Disable click-through: window captures mouse again.
  static void disableClickThrough(int hwnd) {
    if (hwnd == 0) return;

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT & ~WS_EX_LAYERED & ~WS_EX_NOACTIVATE);

    // Restore full opacity (or whatever you prefer)
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    // Refresh style cache (same as before)
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }

  static void makeWindowClickThrough(bool clickThrough, {int? hWnd}) {
    final int targetHwnd = hWnd ?? Win32.hWnd;
    if (clickThrough) {
      enableClickThrough(targetHwnd);
    } else {
      disableClickThrough(targetHwnd);
    }
  }

  static void minimizeWindow(int hwnd) {
    ShowWindow(hwnd, SW_MINIMIZE);
  }

  static void setWindowFullyTransparent(int hwnd) {
    final int currentExStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    if ((currentExStyle & WS_EX_LAYERED) == 0) {
      SetWindowLongPtr(
        hwnd,
        GWL_EXSTYLE,
        currentExStyle | WS_EX_LAYERED,
      );
    }

    // alpha = 0 -> fully transparent, still "visible"/on-screen per Windows,
    // just invisible to the user.
    SetLayeredWindowAttributes(hwnd, 0, 0, LWA_ALPHA);
  }

  static void setWindowFullyOpaque(int hwnd, {bool removeLayeredStyle = false}) {
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    if (removeLayeredStyle) {
      final int currentExStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
      if ((currentExStyle & WS_EX_LAYERED) != 0) {
        SetWindowLongPtr(
          hwnd,
          GWL_EXSTYLE,
          currentExStyle & ~WS_EX_LAYERED,
        );
      }
    }
  }

  /// Maximizes the window if not maximized,
  /// otherwise restores it.
  static void maximizeOrRestoreWindow(int hwnd) {
    if (IsZoomed(hwnd) != 0) {
      // Window is maximized -> restore
      ShowWindow(hwnd, SW_RESTORE);
    } else {
      // Window is normal/minimized -> maximize
      ShowWindow(hwnd, SW_MAXIMIZE);
    }

    SetForegroundWindow(hwnd);
  }

  static String shellUser() {
    final String name = Platform.environment['USERNAME'] ?? 'user';
    final String clean = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return clean.isEmpty ? 'user' : clean;
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
