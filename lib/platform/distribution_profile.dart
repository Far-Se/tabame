import 'dart:io';

import 'windows/windows_package_identity.dart';

enum DistributionProfile {
  portable,
  storeInstaller,
  storeMsix,
}

extension DistributionProfileName on DistributionProfile {
  String get value => name;

  DistributionCapabilities get capabilities {
    switch (this) {
      case DistributionProfile.portable:
        return const DistributionCapabilities(
          packageManaged: false,
          storeManagedUpdates: false,
          runtimeElevation: true,
          automaticElevation: false,
          allowElevation: true,
          startupRegistration: StartupRegistration.shortcut,
          appDataProvider: AppDataProvider.localAppData,
          executablePlugins: true,
          selfUpdate: true,
          customInstallLifecycle: true,
          customUninstall: true,
        );
      case DistributionProfile.storeInstaller:
        return const DistributionCapabilities(
          packageManaged: false,
          storeManagedUpdates: false,
          runtimeElevation: true,
          automaticElevation: false,
          allowElevation: true,
          startupRegistration: StartupRegistration.shortcut,
          appDataProvider: AppDataProvider.localAppData,
          executablePlugins: false,
          selfUpdate: false,
          customInstallLifecycle: false,
          customUninstall: false,
        );
      case DistributionProfile.storeMsix:
        return const DistributionCapabilities(
          packageManaged: true,
          storeManagedUpdates: true,
          runtimeElevation: false,
          automaticElevation: false,
          allowElevation: false,
          startupRegistration: StartupRegistration.startupTask,
          appDataProvider: AppDataProvider.packageAppData,
          executablePlugins: false,
          selfUpdate: false,
          customInstallLifecycle: false,
          customUninstall: false,
        );
    }
  }
}

enum StartupRegistration {
  shortcut,
  startupTask,
}

enum AppDataProvider {
  localAppData,
  packageAppData,
}

class DistributionCapabilities {
  const DistributionCapabilities({
    required this.packageManaged,
    required this.storeManagedUpdates,
    required this.runtimeElevation,
    required this.automaticElevation,
    required this.allowElevation,
    required this.startupRegistration,
    required this.appDataProvider,
    required this.executablePlugins,
    required this.selfUpdate,
    required this.customInstallLifecycle,
    required this.customUninstall,
  });

  final bool packageManaged;
  final bool storeManagedUpdates;
  final bool runtimeElevation;
  final bool automaticElevation;

  /// Restricted MSIX elevation is deliberately false until approved.
  final bool allowElevation;
  final StartupRegistration startupRegistration;
  final AppDataProvider appDataProvider;
  final bool executablePlugins;
  final bool selfUpdate;
  final bool customInstallLifecycle;
  final bool customUninstall;
}

class DistributionProfileConfig {
  DistributionProfileConfig._();

  static const String rawValue = String.fromEnvironment(
    'TABAME_DISTRIBUTION_PROFILE',
    defaultValue: 'portable',
  );

  static DistributionProfile get current => fromValue(rawValue);

  static DistributionProfile fromValue(String value) {
    switch (value.trim()) {
      case 'portable':
        return DistributionProfile.portable;
      case 'storeInstaller':
        return DistributionProfile.storeInstaller;
      case 'storeMsix':
        return DistributionProfile.storeMsix;
      default:
        throw FormatException(
          'Unknown TABAME_DISTRIBUTION_PROFILE "$value". '
          'Expected portable, storeInstaller, or storeMsix.',
        );
    }
  }

  static void validate() {
    fromValue(rawValue);
  }
}

enum PackageIdentityStatus {
  notWindows,
  notPackaged,
  packaged,
  unavailable,
}

class DistributionRuntimeReport {
  const DistributionRuntimeReport({
    required this.profile,
    required this.packageIdentityStatus,
    required this.packageFullName,
    required this.profileMatchesPackageIdentity,
    required this.diagnostic,
  });

  final DistributionProfile profile;
  final PackageIdentityStatus packageIdentityStatus;
  final String? packageFullName;
  final bool profileMatchesPackageIdentity;
  final String diagnostic;
}

class DistributionRuntime {
  DistributionRuntime._();

  static DistributionRuntimeReport inspect({
    DistributionProfile? profile,
    PackageIdentityProbeResult? packageIdentity,
    bool? isWindows,
  }) {
    final DistributionProfile selectedProfile = profile ?? DistributionProfileConfig.current;
    final bool runningOnWindows = isWindows ?? Platform.isWindows;
    if (!runningOnWindows) {
      return DistributionRuntimeReport(
        profile: selectedProfile,
        packageIdentityStatus: PackageIdentityStatus.notWindows,
        packageFullName: null,
        profileMatchesPackageIdentity: true,
        diagnostic: 'Package identity checks are Windows-only.',
      );
    }

    final PackageIdentityProbeResult identity = packageIdentity ?? WindowsPackageIdentity.probe();
    if (identity.status == PackageIdentityStatus.unavailable) {
      return DistributionRuntimeReport(
        profile: selectedProfile,
        packageIdentityStatus: identity.status,
        packageFullName: null,
        profileMatchesPackageIdentity: selectedProfile != DistributionProfile.storeMsix,
        diagnostic: identity.diagnostic,
      );
    }

    final bool packaged = identity.status == PackageIdentityStatus.packaged;
    final bool expectsPackage = selectedProfile == DistributionProfile.storeMsix;
    final bool matches = packaged == expectsPackage;
    return DistributionRuntimeReport(
      profile: selectedProfile,
      packageIdentityStatus: identity.status,
      packageFullName: identity.packageFullName,
      profileMatchesPackageIdentity: matches,
      diagnostic: matches
          ? 'Distribution profile matches runtime package identity.'
          : 'Distribution profile ${selectedProfile.value} does not match '
              '${packaged ? 'packaged' : 'unpackaged'} runtime identity.',
    );
  }
}
