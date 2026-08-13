import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../platform/windows/tabamewin32_api.dart';
import '../platform/windows/windows_bootstrap.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/clipboard_history.dart';
import '../models/classes/save_settings.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../platform/app_paths.dart';
import '../platform/clipboard_service.dart';
import '../platform/distribution_profile.dart';
import '../platform/shell_integration_service.dart';
import '../services/browser_bridge_service.dart';
import '../services/clipboard_history_coordinator.dart';
import '../services/elevation_service.dart';
import '../services/native_integration_coordinator.dart';
import 'error_handler.dart';

class AppStartup {
  static Future<void> initialize() async {
    Debug.register(clean: true);

    Debug.add("===");
    Debug.add("Started");
    // WidgetsFlutterBinding.ensureInitialized();
    Debug.add("Register WindowManager");
    await windowManager.ensureInitialized();
    if (kReleaseMode) {
      // FlutterError.onError = handleErrors;
      // PlatformDispatcher.instance.onError = handlePlatformErrors;
      //
      FlutterError.onError = (FlutterErrorDetails details) async {
        await ErrorLogger.log(
          'FlutterError',
          details.exceptionAsString(),
          details.stack,
        );
      };

      // Dart async/platform errors not caught by Flutter
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        ErrorLogger.log('PlatformDispatcher', error.toString(), stack);
        return true; // returning true = you handled it
      };
    }
  }

  static void parseArguments(List<String> arguments2) {
    List<String> arguments = <String>[...arguments2];
    if (arguments.isNotEmpty) {
      if (arguments[0].endsWith('"') && !arguments[0].startsWith('"')) arguments[0] = '"${arguments[0]}';
      user.args = <String>[...arguments];
      final int launcherIndex = arguments.indexOf("-launcher");
      if (launcherIndex != -1) {
        Globals.isStandaloneLauncher = true;
        Globals.quickMenuPage = QuickMenuPage.launcher;
        user.launcherSearchText = launcherIndex + 1 < arguments.length ? arguments[launcherIndex + 1] : '';
      }
      final bool interfaceRequested = arguments.any((String argument) => argument.toLowerCase() == "-interface");
      final bool quickMenuRequested = arguments.any((String argument) => argument.toLowerCase() == "-quickmenu");
      if (interfaceRequested) {
        user.page = TPage.interface;
        // This process is the Interface: bump the reload marker on settings writes so the
        // running QuickMenu process live-reloads (see SavedStore + QuickMenu file watcher).
        SavedStore.signalOnWrite = true;
      } else if (quickMenuRequested) {
        user.page = TPage.quickmenu;
      }
    }
    Debug.add("Parsed arguments ${user.page}");
  }

  static Future<bool> registerServices() async {
    final DistributionRuntimeReport distribution = DistributionRuntime.inspect();
    Debug.add('Distribution profile: ${distribution.profile.value}');
    if (!distribution.profileMatchesPackageIdentity) {
      Debug.add('Distribution profile mismatch: ${distribution.diagnostic}');
    }

    if (Globals.isStandaloneLauncher) {
      await Boxes.registerBoxes(justLoad: true);
      _configureNativeIntegrations();
      await BrowserBridgeService.instance.initialize(asLauncherClient: true);
      Debug.add("Registered: Standalone launcher settings");
      return false;
    }
    // Load the persisted settings before starting side-effectful services so a
    // configured elevation handoff cannot overlap browser bridges or hooks.
    await Boxes.registerBoxes(justLoad: true);
    if (await ensureConfiguredElevation()) return true;
    await registerAll();
    if (user.page == TPage.quickmenu) {
      await BrowserBridgeService.instance.initialize();
      Debug.add("Registered: Browser bridge");
    }
    if (File(AppPaths.resolvePath('enable_debug.txt')).existsSync()) {
      Debug.methodDebug(clean: true);
    }
    Debug.add("Registered All");
    return false;
  }

  /// Replaces the normal process with an elevated one when the user has opted
  /// into persistent elevation. The replacement keeps the original page and
  /// receives a one-shot marker so it can close the old process after startup.
  static Future<bool> ensureConfiguredElevation() async {
    if (kDebugMode) return false;
    if (Globals.isStandaloneLauncher ||
        !user.runAsAdministrator ||
        user.args.contains(Globals.elevatedStartupArgument) ||
        user.args.contains(Globals.elevatedQuickMenuArgument)) {
      return false;
    }

    final ElevationService elevationService = ElevationService.forCurrentProfile();
    if (!elevationService.capability.canStartAutomatically) {
      Debug.add('Configured elevation is unavailable: ${elevationService.capability.message}');
      return false;
    }

    // A mismatched package/profile build must fail closed for automatic
    // elevation. The selected distribution profile remains authoritative for
    // normal behavior, but a packaged process must never inherit a desktop
    // profile's startup UAC policy by accident.
    final DistributionRuntimeReport runtime = DistributionRuntime.inspect();
    if (runtime.packageIdentityStatus == PackageIdentityStatus.unavailable || !runtime.profileMatchesPackageIdentity) {
      Debug.add('Configured elevation skipped: ${runtime.diagnostic}');
      return false;
    }

    final PrivilegeStatus status = elevationService.readPrivilegeStatus();
    if (status.isElevated) {
      Debug.add('Configured elevation is already active.');
      return false;
    }

    final String signalToken = DateTime.now().microsecondsSinceEpoch.toString();
    final File readySignal = _elevatedStartupReadyFile(signalToken);
    try {
      if (readySignal.existsSync()) readySignal.deleteSync();
    } catch (_) {}

    final ElevationRequestResult result = await elevationService.restartCurrentSessionElevated(
      executable: Platform.resolvedExecutable,
      arguments: <String>[
        ...user.args,
        Globals.elevatedStartupArgument,
        Globals.elevatedStartupSignalArgument,
        readySignal.path
      ],
    );
    if (!result.didLaunch) {
      _deleteElevationReadySignal(readySignal);
      Debug.add('Configured elevation was not started: ${result.message}');
      return false;
    }

    final bool replacementReady = await _waitForElevatedReplacement(readySignal);
    _deleteElevationReadySignal(readySignal);
    if (!replacementReady) {
      Debug.add('Configured elevation replacement did not become ready; keeping this session running normally.');
      return false;
    }

    Debug.add('Started configured elevated replacement process.');
    return true;
  }

  static File _elevatedStartupReadyFile(String token) {
    return File(AppPaths.resolvePath('elevated-startup-$token.ready', forWrite: true));
  }

  static File? _elevatedStartupReadyFileFromArguments() {
    final int signalIndex = user.args.indexOf(Globals.elevatedStartupSignalArgument);
    if (signalIndex == -1 || signalIndex + 1 >= user.args.length) return null;
    final String signalPath = user.args[signalIndex + 1].trim();
    return signalPath.isEmpty ? null : File(signalPath);
  }

  static Future<bool> _waitForElevatedReplacement(File readySignal) async {
    for (int attempt = 0; attempt < 100; attempt++) {
      if (readySignal.existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static Future<bool> _waitForElevationReadyAcknowledgement(File readySignal) async {
    for (int attempt = 0; attempt < 50; attempt++) {
      if (!readySignal.existsSync()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static void _deleteElevationReadySignal(File readySignal) {
    try {
      if (readySignal.existsSync()) readySignal.deleteSync();
    } catch (_) {}
  }

  static bool _signalElevatedStartupReady() {
    final File? readySignal = _elevatedStartupReadyFileFromArguments();
    if (readySignal == null) return false;
    try {
      readySignal.writeAsStringSync('ready');
      return true;
    } catch (error) {
      Debug.add('Could not signal elevated startup readiness: $error');
      return false;
    }
  }

  /// Applies the persisted taskbar preference after Explorer and the Flutter
  /// window are available. Windows login can finish creating the taskbar after
  /// Tabame starts, so keep retrying for a short, bounded settling period.
  static Future<void> _applyStartupTaskbarVisibility() async {
    if (Globals.isStandaloneLauncher || user.page != TPage.quickmenu || !user.hideTaskbarOnStartup) return;

    const int attempts = 20;
    final TaskbarVisibilityService taskbar = TaskbarVisibilityService.instance;
    for (int attempt = 0; attempt < attempts; attempt++) {
      if (!user.hideTaskbarOnStartup) return;
      final int expectedGeneration = taskbar.operationGeneration + 1;
      final bool applied = await WinUtils.toggleTaskbar(visible: false);
      if (taskbar.operationGeneration != expectedGeneration) return;
      if (applied) {
        Debug.add('Startup: Taskbar hide applied.');
        return;
      }
      if (attempt + 1 < attempts) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    Debug.add('Startup: Taskbar hide failed after retries.');
  }

  static void registerHooks() {
    if (Globals.isStandaloneLauncher || user.page != TPage.quickmenu) return;
    final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
    if (!integrations.canStart(NativeIntegrationId.globalHooks)) {
      integrations.reportDisabled(
        NativeIntegrationId.globalHooks,
        reason: integrations.denialReason(NativeIntegrationId.globalHooks) ?? 'Global hooks are disabled.',
        reducedMode: true,
      );
      Debug.add('Global hooks are disabled; visible/manual summon remains available.');
      return;
    }
    if (Globals.debugHooks || kReleaseMode) {
      Debug.add("Registering Hooks");
      if (user.args.contains("-interface") && Boxes.remap.isEmpty) {
        NativeHooks.registerCallHandler();
      } else {
        NativeHooks.registerCallHandler();
      }
    }
  }

  static Future<void> setupWindow(List<String> arguments) async {
    late WindowOptions windowOptions;
    final bool elevatedQuickMenuRequested = user.args.contains(Globals.elevatedQuickMenuArgument);
    final bool quickMenuRequested = user.args.any((String argument) => argument.toLowerCase() == "-quickmenu");
    final bool elevatedReplacementRequested =
        elevatedQuickMenuRequested || user.args.contains(Globals.elevatedStartupArgument);
    final bool startInInterface = !Globals.isStandaloneLauncher &&
        !elevatedQuickMenuRequested &&
        !quickMenuRequested &&
        (user.page == TPage.interface || !AppPaths.hasSettingsFile || Boxes.remap.isEmpty);
    Globals.startInInterface = startInInterface;
    if (Globals.isStandaloneLauncher) {
      windowOptions = WindowOptions(
        size: Size(Boxes.launcherSizeWidth, Globals.launcherSize.height),
        minimumSize: Size(Globals.quickMenuSize.width, 200),
        maximumSize: const Size(32000, 32000),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        alwaysOnTop: false,
        title: "Tabame - Launcher - ${user.launcherSearchText.addDots(9)}",
      );
    } else if (startInInterface) {
      late String title;
      if (user.args.contains("-wizardly")) {
        title = "Wizardly";
      } else if (user.args.contains("-fancyshot")) {
        title = "Fancyshot";
      } else {
        title = "Interface";
      }
      windowOptions = WindowOptions(
        size: const Size(980, 600),
        center: false,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        alwaysOnTop: false,
        title: "Tabame - $title",
      );
    } else {
      final double size = Boxes.quickMenuWidth;
      windowOptions = WindowOptions(
        size: Size(size, Globals.quickMenuSize.height),
        minimumSize: Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height),
        maximumSize: const Size(32000, 32000),
        center: false,
        backgroundColor: Colors.transparent,
        skipTaskbar: true,
        alwaysOnTop: true,
        title: kDebugMode ? "Tabame - Debug" : "Tabame",
      );
    }
    Debug.add("Setting windowOptions");
    windowManager.setMinimizable(false);
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await Win32.fetchMainWindowHandle();
      if (!Globals.isStandaloneLauncher && user.page == TPage.quickmenu) {
        final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
        if (ClipboardHistoryStore.enabled && integrations.canStart(NativeIntegrationId.clipboardHistory)) {
          final bool started = await ClipboardHistoryCoordinator.instance.start();
          if (started) {
            integrations.reportRunning(NativeIntegrationId.clipboardHistory);
          } else {
            integrations.reportUnavailable(
              NativeIntegrationId.clipboardHistory,
              reason: ClipboardService.instance.unavailableReason,
            );
          }
        } else {
          integrations.reportDisabled(
            NativeIntegrationId.clipboardHistory,
            reason: integrations.denialReason(NativeIntegrationId.clipboardHistory) ??
                'Clipboard history is paused until you enable it.',
            reducedMode: true,
          );
        }
        WindowsBootstrap.refreshCapabilities();
        if (startInInterface) {
          await TaskbarVisibilityService.instance.restore();
        } else {
          unawaited(_applyStartupTaskbarVisibility());
        }
      }
      Globals.fullLoaded.value = true;
      final bool startupReplacementReady = _signalElevatedStartupReady();
      if (user.args.contains(Globals.elevatedStartupArgument)) {
        final File? readySignal = _elevatedStartupReadyFileFromArguments();
        if (!startupReplacementReady ||
            readySignal == null ||
            !await _waitForElevationReadyAcknowledgement(readySignal)) {
          Debug.add('Elevated replacement handoff was not acknowledged; closing the replacement process.');
          exit(1);
        }
      }
      if (elevatedReplacementRequested && (elevatedQuickMenuRequested || startupReplacementReady)) {
        // A persisted replacement should only replace the same role. The
        // explicit QuickMenu action retains its historical broad cleanup.
        if (elevatedQuickMenuRequested) {
          Future<void>.delayed(const Duration(milliseconds: 300), WinUtils.closeAllTabameExProcesses);
        } else {
          Future<void>.delayed(
            const Duration(milliseconds: 300),
            () => WinUtils.closeAllTabameExProcesses(
              closeInterface: startInInterface,
              closeQuickMenu: !startInInterface,
            ),
          );
        }
      }
      Debug.add("Set windowOptions");
    });
  }

  static void _configureNativeIntegrations() {
    NativeIntegrationCoordinator.configure(
      profile: DistributionProfileConfig.current,
      consentStore: SaveSettingsNativeIntegrationConsentStore(Boxes.pref),
    );
  }

  static Future<void> finalizeStartup() async {
    Debug.add("Setting transparency");
    await setWindowAsTransparent();
    if (Globals.isStandaloneLauncher) {
      Debug.add("Set transparency");
      return;
    }
    if (user.page == TPage.quickmenu &&
        user.quickClickEnabled &&
        NativeIntegrationCoordinator.instance.canStart(NativeIntegrationId.globalHooks)) {
      await QuickClick.registerQuickClick(user.quickClickConfig);
      await QuickClick.disableQuickClick();
    } else if (user.page == TPage.quickmenu && user.quickClickEnabled) {
      NativeIntegrationCoordinator.instance.reportDisabled(
        NativeIntegrationId.globalHooks,
        reason: NativeIntegrationCoordinator.instance.denialReason(NativeIntegrationId.globalHooks) ??
            'QuickClick is disabled with global hooks; use the visible/manual action instead.',
        reducedMode: true,
      );
    }
    Debug.add("Set transparency");
  }
}
