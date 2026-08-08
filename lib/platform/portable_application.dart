import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'app_paths.dart';
import 'notification_service.dart';
import '../services/clipboard_history_coordinator.dart';
import 'platform_bootstrap.dart';
import 'window_service.dart';
import 'macos/macos_bootstrap.dart';
import 'linux/linux_bootstrap.dart';
import 'portable_settings.dart';
import 'portable_shell.dart';
import 'portable_window_service.dart';

Future<void> startPortableApplication([List<String> arguments = const <String>[]]) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppPaths.isInitialized) await AppPaths.initialize();
  await PlatformBootstrap.initialize();
  await PortableWindowService.initialize();
  // LinuxBootstrap already performs the initial capability probe. Do not repeat
  // optional D-Bus setup before the first frame; show() retries on demand.
  if (!Platform.isLinux) await NotificationService.instance.initialize();

  if (Platform.isMacOS) {
    String? focusToken;
    Future<void> summon() async {
      final bool visible = await windowManager.isVisible();
      if (visible) {
        await windowManager.hide();
        await WindowService.instance.restoreFocus(focusToken);
        focusToken = null;
      } else {
        focusToken = await WindowService.instance.captureFocus();
        await PortableWindowService.show();
      }
    }

    Future<void> showLauncher() async {
      if (!await windowManager.isVisible()) {
        focusToken = await WindowService.instance.captureFocus();
      }
      await PortableWindowService.show();
    }

    await MacOSBootstrap.startCoreServices(
      onSummon: summon,
      onConfiguredAction: (String action) => action == 'ToggleQuickMenu' ? summon() : showLauncher(),
    );
  } else if (Platform.isLinux) {
    String? focusToken;
    await LinuxBootstrap.startCoreServices(onSummon: () async {
      final bool visible = await windowManager.isVisible();
      if (visible) {
        await windowManager.hide();
        await WindowService.instance.restoreFocus(focusToken);
        focusToken = null;
      } else {
        focusToken = await WindowService.instance.captureFocus();
        await PortableWindowService.show();
      }
    });
  }

  // The coordinator is shared with the Windows QuickMenu path. Target OSes
  // receive the same text-history orchestration after their adapter starts.
  await ClipboardHistoryCoordinator.instance.start();

  final PortableSettings settings = await PortableSettings.load();
  final String initialQuery = _initialQuery(arguments);
  runApp(PortableShell(settings: settings, initialQuery: initialQuery));

  // Secret Service may be missing or locked on Linux. Probe it only after the
  // first shell has been scheduled so launcher startup never depends on it.
  if (Platform.isLinux) unawaited(LinuxBootstrap.initializeOptionalServices());
}

String _initialQuery(List<String> arguments) {
  final int launcherIndex = arguments.indexOf('-launcher');
  if (launcherIndex >= 0 && launcherIndex + 1 < arguments.length) return arguments[launcherIndex + 1];
  return arguments.where((String argument) => !argument.startsWith('-')).join(' ');
}
