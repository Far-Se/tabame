import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/win32/win_utils.dart';
import '../platform/distribution_profile.dart';

enum InstallLifecycleManagement {
  portable,
  installer,
  store,
}

class InstallLifecycleCapabilities {
  const InstallLifecycleCapabilities({
    required this.management,
    required this.canCustomInstall,
    required this.canCustomUninstall,
    required this.preservesAppDataOnManagedUninstall,
    required this.message,
  });

  factory InstallLifecycleCapabilities.forProfile(DistributionProfile profile) {
    switch (profile) {
      case DistributionProfile.portable:
        return const InstallLifecycleCapabilities(
          management: InstallLifecycleManagement.portable,
          canCustomInstall: true,
          canCustomUninstall: true,
          preservesAppDataOnManagedUninstall: false,
          message: 'Portable ZIP users manage installation and removal of the extracted folder.',
        );
      case DistributionProfile.storeInstaller:
        return const InstallLifecycleCapabilities(
          management: InstallLifecycleManagement.installer,
          canCustomInstall: false,
          canCustomUninstall: false,
          preservesAppDataOnManagedUninstall: true,
          message: 'The signed Store-listed installer owns install, upgrade, repair, and uninstall.',
        );
      case DistributionProfile.storeMsix:
        return const InstallLifecycleCapabilities(
          management: InstallLifecycleManagement.store,
          canCustomInstall: false,
          canCustomUninstall: false,
          preservesAppDataOnManagedUninstall: false,
          message: 'Microsoft Store and MSIX own install, upgrade, repair, and uninstall.',
        );
    }
  }

  final InstallLifecycleManagement management;
  final bool canCustomInstall;
  final bool canCustomUninstall;
  final bool preservesAppDataOnManagedUninstall;
  final String message;
}

enum LifecycleOperationState {
  completed,
  blocked,
  unavailable,
  failed,
}

class LifecycleOperationResult {
  const LifecycleOperationResult({required this.state, required this.message});

  const LifecycleOperationResult.completed([
    this.message = 'The lifecycle operation completed.',
  ]) : state = LifecycleOperationState.completed;

  const LifecycleOperationResult.blocked(this.message) : state = LifecycleOperationState.blocked;

  const LifecycleOperationResult.unavailable(this.message) : state = LifecycleOperationState.unavailable;

  const LifecycleOperationResult.failed(this.message) : state = LifecycleOperationState.failed;

  final LifecycleOperationState state;
  final String message;
}

abstract interface class InstallLifecycleAdapter {
  Future<LifecycleOperationResult> uninstall();
}

class InstallLifecycleService {
  InstallLifecycleService({required this.profile, required this.adapter});

  factory InstallLifecycleService.forCurrentProfile({InstallLifecycleAdapter? adapter}) {
    final DistributionProfile profile = DistributionProfileConfig.current;
    return InstallLifecycleService(
      profile: profile,
      adapter: adapter ?? const WindowsInstallLifecycleAdapter(),
    );
  }

  final DistributionProfile profile;
  final InstallLifecycleAdapter adapter;

  InstallLifecycleCapabilities get capabilities => InstallLifecycleCapabilities.forProfile(profile);

  Future<LifecycleOperationResult> uninstall() async {
    if (!capabilities.canCustomUninstall) {
      return LifecycleOperationResult.blocked(capabilities.message);
    }
    return adapter.uninstall();
  }
}

class WindowsInstallLifecycleAdapter implements InstallLifecycleAdapter {
  const WindowsInstallLifecycleAdapter();

  @override
  Future<LifecycleOperationResult> uninstall() async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return const LifecycleOperationResult.unavailable('Custom Windows uninstall is unavailable on this platform.');
    }
    if (!kReleaseMode) {
      return const LifecycleOperationResult.unavailable('Custom uninstall is available only in a release build.');
    }

    try {
      await WinUtils.performUninstall();
      return const LifecycleOperationResult.completed('The portable uninstall process has been started.');
    } catch (error) {
      return LifecycleOperationResult.failed('Could not start the portable uninstall process: $error');
    }
  }
}
