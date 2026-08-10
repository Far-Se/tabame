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
import '../services/browser_bridge_service.dart';
import '../services/clipboard_history_coordinator.dart';
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
      if (interfaceRequested) {
        user.page = TPage.interface;
        // This process is the Interface: bump the reload marker on settings writes so the
        // running QuickMenu process live-reloads (see SavedStore + QuickMenu file watcher).
        SavedStore.signalOnWrite = true;
      }
    }
    Debug.add("Parsed arguments ${user.page}");
  }

  static Future<void> registerServices() async {
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
      return;
    }
    await registerAll();
    if (user.page == TPage.quickmenu) {
      await BrowserBridgeService.instance.initialize();
      Debug.add("Registered: Browser bridge");
    }
    if (File(AppPaths.resolvePath('enable_debug.txt')).existsSync()) {
      Debug.methodDebug(clean: true);
    }
    Debug.add("Registered All");
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
    final bool startInInterface = !Globals.isStandaloneLauncher &&
        !elevatedQuickMenuRequested &&
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
      if (user.args.contains(Globals.elevatedQuickMenuArgument)) {
        // The elevated replacement owns the session; close the old QuickMenu
        // and any Interface window after the new native window is ready.
        Future<void>.delayed(const Duration(milliseconds: 300), WinUtils.closeAllTabameExProcesses);
      }
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
      }
      Globals.fullLoaded.value = true;
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
