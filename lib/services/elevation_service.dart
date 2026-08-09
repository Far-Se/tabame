import 'dart:io';

import '../models/win32/win_utils.dart';
import '../platform/distribution_profile.dart';

enum PrivilegeLevel {
  standardUser,
  administratorMediumIntegrity,
  elevated,
  unavailable,
}

class PrivilegeStatus {
  const PrivilegeStatus({required this.level, required this.message});

  const PrivilegeStatus.standardUser([
    this.message = 'This is a standard-user session. Some actions may require UAC.',
  ]) : level = PrivilegeLevel.standardUser;

  const PrivilegeStatus.administratorMediumIntegrity([
    this.message = 'This administrator account is running at medium integrity. UAC is required for privileged actions.',
  ]) : level = PrivilegeLevel.administratorMediumIntegrity;

  const PrivilegeStatus.elevated([
    this.message = 'This Tabame session is elevated for the current session.',
  ]) : level = PrivilegeLevel.elevated;

  const PrivilegeStatus.unavailable([
    this.message = 'Windows privilege state is unavailable. Privileged actions remain disabled.',
  ]) : level = PrivilegeLevel.unavailable;

  final PrivilegeLevel level;
  final String message;

  bool get isElevated => level == PrivilegeLevel.elevated;
  bool get isAvailable => level != PrivilegeLevel.unavailable;

  static PrivilegeStatus fromToken({required bool isAdministratorAccount, required bool isElevated}) {
    if (isElevated) return const PrivilegeStatus.elevated();
    if (isAdministratorAccount) return const PrivilegeStatus.administratorMediumIntegrity();
    return const PrivilegeStatus.standardUser();
  }
}

class ElevationCapabilityResult {
  const ElevationCapabilityResult({required this.profile, required this.isAvailable, required this.message});

  factory ElevationCapabilityResult.forProfile(DistributionProfile profile) {
    final DistributionCapabilities capabilities = profile.capabilities;
    if (!capabilities.runtimeElevation || !capabilities.allowElevation) {
      return ElevationCapabilityResult(
        profile: profile,
        isAvailable: false,
        message: profile == DistributionProfile.storeMsix
            ? 'Elevation is disabled in the MSIX profile because the restricted allowElevation capability is not approved.'
            : 'Elevation is unavailable in this distribution profile.',
      );
    }
    return ElevationCapabilityResult(
      profile: profile,
      isAvailable: true,
      message: 'Explicit UAC actions are available for this profile.',
    );
  }

  final DistributionProfile profile;
  final bool isAvailable;
  final String message;
}

enum ElevationRequestState {
  launched,
  alreadyElevated,
  cancelled,
  blocked,
  failed,
}

class ElevationRequestResult {
  const ElevationRequestResult({required this.state, required this.message});

  const ElevationRequestResult.launched([
    this.message = 'Windows started the elevated application.',
  ]) : state = ElevationRequestState.launched;

  const ElevationRequestResult.alreadyElevated([
    this.message = 'This Tabame session is already elevated.',
  ]) : state = ElevationRequestState.alreadyElevated;

  const ElevationRequestResult.cancelled([
    this.message = 'UAC was cancelled. Tabame will continue at normal user integrity.',
  ]) : state = ElevationRequestState.cancelled;

  const ElevationRequestResult.blocked(this.message) : state = ElevationRequestState.blocked;

  const ElevationRequestResult.failed(this.message) : state = ElevationRequestState.failed;

  final ElevationRequestState state;
  final String message;

  bool get didLaunch => state == ElevationRequestState.launched;
  bool get shouldCloseCurrentProcess => didLaunch;
}

abstract interface class ElevationAdapter {
  PrivilegeStatus readPrivilegeStatus();

  Future<ElevationRequestResult> launchElevated({
    required String executable,
    String? arguments,
  });
}

class ElevationService {
  ElevationService({required this.profile, required this.adapter});

  factory ElevationService.forCurrentProfile({ElevationAdapter? adapter}) {
    final DistributionProfile profile = DistributionProfileConfig.current;
    return ElevationService(
      profile: profile,
      adapter: adapter ?? const WindowsElevationAdapter(),
    );
  }

  final DistributionProfile profile;
  final ElevationAdapter adapter;

  ElevationCapabilityResult get capability => ElevationCapabilityResult.forProfile(profile);

  PrivilegeStatus readPrivilegeStatus() => adapter.readPrivilegeStatus();

  Future<ElevationRequestResult> restartCurrentSessionElevated({
    required String executable,
    required Iterable<String> arguments,
  }) async {
    final ElevationRequestResult? blocked = _blockedResult();
    if (blocked != null) return blocked;

    final PrivilegeStatus status = readPrivilegeStatus();
    if (status.level == PrivilegeLevel.unavailable) {
      return ElevationRequestResult.failed(status.message);
    }
    if (status.isElevated) return const ElevationRequestResult.alreadyElevated();

    return adapter.launchElevated(
      executable: executable,
      arguments: WindowsCommandLine.join(arguments),
    );
  }

  Future<ElevationRequestResult> launchApplicationElevated({
    required String executable,
    String? arguments,
  }) async {
    final ElevationRequestResult? blocked = _blockedResult();
    if (blocked != null) return blocked;

    return adapter.launchElevated(executable: executable, arguments: arguments);
  }

  ElevationRequestResult? _blockedResult() {
    if (capability.isAvailable) return null;
    return ElevationRequestResult.blocked(capability.message);
  }
}

/// Windows adapter for explicit UAC launches.
///
/// This is intentionally a direct ShellExecute request for a selected
/// executable. It is not a general elevated command runner or privileged IPC
/// helper.
class WindowsElevationAdapter implements ElevationAdapter {
  const WindowsElevationAdapter();

  @override
  PrivilegeStatus readPrivilegeStatus() {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return const PrivilegeStatus.unavailable('Windows privilege detection is unavailable on this platform.');
    }
    try {
      return PrivilegeStatus.fromToken(
        isAdministratorAccount: WinUtils.isAdministratorAccount(),
        isElevated: WinUtils.isProcessElevated(),
      );
    } catch (error) {
      return PrivilegeStatus.unavailable('Could not determine the Windows privilege state: $error');
    }
  }

  @override
  Future<ElevationRequestResult> launchElevated({required String executable, String? arguments}) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return const ElevationRequestResult.blocked('Elevated application launches are unavailable on this platform.');
    }
    try {
      final int result = WinUtils.runAsAdmin(executable, arguments: arguments);
      if (result > 32) return const ElevationRequestResult.launched();

      // ShellExecute reports access-denied for several UAC rejection paths;
      // surface those as a non-destructive cancellation rather than exiting.
      if (result == 5 || result == 1223) {
        return const ElevationRequestResult.cancelled();
      }
      return ElevationRequestResult.failed(
        'Windows could not start the elevated application (ShellExecute code $result).',
      );
    } catch (error) {
      return ElevationRequestResult.failed('Windows could not request elevation: $error');
    }
  }
}

class WindowsCommandLine {
  WindowsCommandLine._();

  static String join(Iterable<String> arguments) {
    return arguments.map(_quote).join(' ');
  }

  static String _quote(String value) {
    if (value.isEmpty) return '""';
    if (!value.contains(RegExp(r'[\s"]'))) return value;
    return '"${value.replaceAll('"', r'\"')}"';
  }
}
