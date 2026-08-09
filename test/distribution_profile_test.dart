import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/platform/windows/windows_package_identity.dart';

void main() {
  group('DistributionProfileConfig', () {
    test('uses portable as the safe default', () {
      expect(DistributionProfileConfig.rawValue, 'portable');
      expect(DistributionProfileConfig.current, DistributionProfile.portable);
    });

    test('parses every supported profile', () {
      expect(DistributionProfileConfig.fromValue('portable'), DistributionProfile.portable);
      expect(DistributionProfileConfig.fromValue('storeInstaller'), DistributionProfile.storeInstaller);
      expect(DistributionProfileConfig.fromValue('storeMsix'), DistributionProfile.storeMsix);
    });

    test('rejects unknown profiles', () {
      expect(
        () => DistributionProfileConfig.fromValue('release'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DistributionCapabilities', () {
    test('portable keeps existing mutable and executable behavior', () {
      final DistributionCapabilities capabilities = DistributionProfile.portable.capabilities;

      expect(capabilities.packageManaged, isFalse);
      expect(capabilities.runtimeElevation, isTrue);
      expect(capabilities.automaticElevation, isFalse);
      expect(capabilities.allowElevation, isTrue);
      expect(capabilities.startupRegistration, StartupRegistration.shortcut);
      expect(capabilities.appDataProvider, AppDataProvider.localAppData);
      expect(capabilities.executablePlugins, isTrue);
      expect(capabilities.selfUpdate, isTrue);
      expect(capabilities.customUninstall, isTrue);
    });

    test('storeInstaller keeps Win32 UAC but disables mutable lifecycle', () {
      final DistributionCapabilities capabilities = DistributionProfile.storeInstaller.capabilities;

      expect(capabilities.packageManaged, isFalse);
      expect(capabilities.runtimeElevation, isTrue);
      expect(capabilities.automaticElevation, isFalse);
      expect(capabilities.allowElevation, isTrue);
      expect(capabilities.startupRegistration, StartupRegistration.shortcut);
      expect(capabilities.appDataProvider, AppDataProvider.localAppData);
      expect(capabilities.executablePlugins, isFalse);
      expect(capabilities.selfUpdate, isFalse);
      expect(capabilities.customInstallLifecycle, isFalse);
      expect(capabilities.customUninstall, isFalse);
    });

    test('storeMsix requires package-managed behavior', () {
      final DistributionCapabilities capabilities = DistributionProfile.storeMsix.capabilities;

      expect(capabilities.packageManaged, isTrue);
      expect(capabilities.storeManagedUpdates, isTrue);
      expect(capabilities.runtimeElevation, isFalse);
      expect(capabilities.automaticElevation, isFalse);
      expect(capabilities.allowElevation, isFalse);
      expect(capabilities.startupRegistration, StartupRegistration.startupTask);
      expect(capabilities.appDataProvider, AppDataProvider.packageAppData);
      expect(capabilities.executablePlugins, isFalse);
      expect(capabilities.selfUpdate, isFalse);
      expect(capabilities.customUninstall, isFalse);
    });
  });

  group('DistributionRuntime', () {
    const PackageIdentityProbeResult unpackaged = PackageIdentityProbeResult(
      status: PackageIdentityStatus.notPackaged,
      diagnostic: 'test unpackaged process',
    );
    const PackageIdentityProbeResult packaged = PackageIdentityProbeResult(
      status: PackageIdentityStatus.packaged,
      packageFullName: 'FarSe.Tabame_2.0.0.0_x64__example',
      diagnostic: 'test packaged process',
    );

    test('accepts an unpackaged portable process', () {
      final DistributionRuntimeReport report = DistributionRuntime.inspect(
        profile: DistributionProfile.portable,
        packageIdentity: unpackaged,
        isWindows: true,
      );

      expect(report.profileMatchesPackageIdentity, isTrue);
      expect(report.packageIdentityStatus, PackageIdentityStatus.notPackaged);
    });

    test('accepts an unpackaged installer process', () {
      final DistributionRuntimeReport report = DistributionRuntime.inspect(
        profile: DistributionProfile.storeInstaller,
        packageIdentity: unpackaged,
        isWindows: true,
      );

      expect(report.profileMatchesPackageIdentity, isTrue);
    });

    test('accepts a packaged MSIX process', () {
      final DistributionRuntimeReport report = DistributionRuntime.inspect(
        profile: DistributionProfile.storeMsix,
        packageIdentity: packaged,
        isWindows: true,
      );

      expect(report.profileMatchesPackageIdentity, isTrue);
      expect(report.packageFullName, packaged.packageFullName);
    });

    test('reports profile and identity mismatches without throwing', () {
      final DistributionRuntimeReport report = DistributionRuntime.inspect(
        profile: DistributionProfile.storeMsix,
        packageIdentity: unpackaged,
        isWindows: true,
      );

      expect(report.profileMatchesPackageIdentity, isFalse);
      expect(report.diagnostic, contains('does not match'));
    });

    test('does not require package identity off Windows', () {
      final DistributionRuntimeReport report = DistributionRuntime.inspect(
        profile: DistributionProfile.storeMsix,
        isWindows: false,
      );

      expect(report.packageIdentityStatus, PackageIdentityStatus.notWindows);
      expect(report.profileMatchesPackageIdentity, isTrue);
    });
  });
}
