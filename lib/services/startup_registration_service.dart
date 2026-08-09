import 'dart:io';

import '../models/win32/win_utils.dart';
import '../platform/distribution_profile.dart';
import '../platform/windows/windows_startup_task.dart';

enum StartupRegistrationState {
  enabled,
  disabled,
  disabledByUser,
  disabledByPolicy,
  unavailable,
  error,
}

class StartupRegistrationStatus {
  const StartupRegistrationStatus({required this.state, this.message = ''});

  const StartupRegistrationStatus.enabled([this.message = '']) : state = StartupRegistrationState.enabled;

  const StartupRegistrationStatus.disabled([this.message = '']) : state = StartupRegistrationState.disabled;

  const StartupRegistrationStatus.disabledByUser([this.message = '']) : state = StartupRegistrationState.disabledByUser;

  const StartupRegistrationStatus.disabledByPolicy([this.message = ''])
      : state = StartupRegistrationState.disabledByPolicy;

  const StartupRegistrationStatus.unavailable([this.message = '']) : state = StartupRegistrationState.unavailable;

  const StartupRegistrationStatus.error(this.message) : state = StartupRegistrationState.error;

  final StartupRegistrationState state;
  final String message;

  bool get isEnabled => state == StartupRegistrationState.enabled;
  bool get isSystemControlled =>
      state == StartupRegistrationState.disabledByUser || state == StartupRegistrationState.disabledByPolicy;
  bool get canChange => state == StartupRegistrationState.enabled || state == StartupRegistrationState.disabled;
}

abstract interface class StartupRegistrationAdapter {
  Future<StartupRegistrationStatus> read();
  Future<StartupRegistrationStatus> setEnabled(bool enabled);
  Future<void> openSystemSettings();
}

class StartupLaunchArguments {
  StartupLaunchArguments._();

  /// Startup must launch the quick-menu process, never the settings/interface
  /// process. Keep this explicit even though the default app mode is quick menu.
  static const String quickMenu = '-quickmenu';
}

class StartupRegistrationService {
  StartupRegistrationService({required this.profile, required this.adapter});

  factory StartupRegistrationService.forCurrentProfile({StartupRegistrationAdapter? adapter}) {
    final DistributionProfile profile = DistributionProfileConfig.current;
    return StartupRegistrationService(
      profile: profile,
      adapter: adapter ?? _defaultAdapter(profile),
    );
  }

  final DistributionProfile profile;
  final StartupRegistrationAdapter adapter;

  Future<StartupRegistrationStatus> read() => adapter.read();

  Future<StartupRegistrationStatus> setEnabled(bool enabled) => adapter.setEnabled(enabled);

  Future<void> openSystemSettings() => adapter.openSystemSettings();

  static StartupRegistrationAdapter _defaultAdapter(DistributionProfile profile) {
    if (profile == DistributionProfile.storeMsix) return const WindowsStartupTaskAdapter();
    return const WindowsShortcutStartupAdapter();
  }
}

class WindowsShortcutStartupAdapter implements StartupRegistrationAdapter {
  const WindowsShortcutStartupAdapter();

  @override
  Future<StartupRegistrationStatus> read() async {
    if (!Platform.isWindows) {
      return const StartupRegistrationStatus.unavailable('Windows login startup is unavailable on this platform.');
    }
    try {
      return WinUtils.checkIfRegisterAsStartup()
          ? const StartupRegistrationStatus.enabled()
          : const StartupRegistrationStatus.disabled();
    } catch (error) {
      return StartupRegistrationStatus.error('Could not read Windows startup registration: $error');
    }
  }

  @override
  Future<StartupRegistrationStatus> setEnabled(bool enabled) async {
    if (!Platform.isWindows) {
      return const StartupRegistrationStatus.unavailable('Windows login startup is unavailable on this platform.');
    }
    try {
      await WinUtils.setStartUpShortcut(
        enabled,
        args: StartupLaunchArguments.quickMenu,
        exePath: Platform.resolvedExecutable,
      );
      final StartupRegistrationStatus status = await read();
      if (status.state == StartupRegistrationState.error) return status;
      return enabled && !status.isEnabled
          ? const StartupRegistrationStatus.error('Windows did not confirm the startup shortcut.')
          : !enabled && status.isEnabled
              ? const StartupRegistrationStatus.error('Windows did not remove the startup shortcut.')
              : status;
    } catch (error) {
      return StartupRegistrationStatus.error('Could not update Windows startup registration: $error');
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (Platform.isWindows) WinUtils.open('ms-settings:startupapps');
  }
}

class WindowsStartupTaskAdapter implements StartupRegistrationAdapter {
  const WindowsStartupTaskAdapter({this.bridge = const WindowsStartupTaskBridge()});

  final WindowsStartupTaskBridge bridge;

  @override
  Future<StartupRegistrationStatus> read() async {
    return _status(await bridge.read());
  }

  @override
  Future<StartupRegistrationStatus> setEnabled(bool enabled) async {
    try {
      final WindowsStartupTaskState state = enabled ? await bridge.requestEnable() : await bridge.disable();
      return _status(state);
    } catch (error) {
      return StartupRegistrationStatus.error('Could not update the Windows StartupTask: $error');
    }
  }

  @override
  Future<void> openSystemSettings() async {
    if (Platform.isWindows) WinUtils.open('ms-settings:startupapps');
  }

  StartupRegistrationStatus _status(WindowsStartupTaskState state) {
    switch (state) {
      case WindowsStartupTaskState.enabled:
        return const StartupRegistrationStatus.enabled();
      case WindowsStartupTaskState.disabled:
        return const StartupRegistrationStatus.disabled();
      case WindowsStartupTaskState.disabledByUser:
        return const StartupRegistrationStatus.disabledByUser(
          'Windows disabled this startup task. Enable it in Windows Startup Apps.',
        );
      case WindowsStartupTaskState.disabledByPolicy:
        return const StartupRegistrationStatus.disabledByPolicy(
          'Windows policy disabled this startup task.',
        );
      case WindowsStartupTaskState.unavailable:
        return const StartupRegistrationStatus.unavailable(
          'The MSIX StartupTask is unavailable. Confirm the manifest declaration.',
        );
    }
  }
}
