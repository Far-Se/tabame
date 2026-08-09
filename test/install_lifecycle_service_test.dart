import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/install_lifecycle_service.dart';
import 'package:tabame/services/update_service.dart';

void main() {
  group('InstallLifecycleCapabilities', () {
    test('keeps portable lifecycle behavior available', () {
      final InstallLifecycleCapabilities capabilities =
          InstallLifecycleCapabilities.forProfile(DistributionProfile.portable);

      expect(capabilities.management, InstallLifecycleManagement.portable);
      expect(capabilities.canCustomInstall, isTrue);
      expect(capabilities.canCustomUninstall, isTrue);
      expect(capabilities.preservesAppDataOnManagedUninstall, isFalse);
    });

    test('makes Store installer lifecycle installer-owned and data-preserving', () {
      final InstallLifecycleCapabilities capabilities =
          InstallLifecycleCapabilities.forProfile(DistributionProfile.storeInstaller);

      expect(capabilities.management, InstallLifecycleManagement.installer);
      expect(capabilities.canCustomInstall, isFalse);
      expect(capabilities.canCustomUninstall, isFalse);
      expect(capabilities.preservesAppDataOnManagedUninstall, isTrue);
      expect(capabilities.message, contains('signed Store-listed installer'));
    });

    test('makes MSIX lifecycle Store-owned', () {
      final InstallLifecycleCapabilities capabilities =
          InstallLifecycleCapabilities.forProfile(DistributionProfile.storeMsix);

      expect(capabilities.management, InstallLifecycleManagement.store);
      expect(capabilities.canCustomInstall, isFalse);
      expect(capabilities.canCustomUninstall, isFalse);
    });
  });

  group('InstallLifecycleService', () {
    test('blocks managed uninstall without invoking the adapter', () async {
      final FakeInstallLifecycleAdapter adapter = FakeInstallLifecycleAdapter();
      final InstallLifecycleService service = InstallLifecycleService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final LifecycleOperationResult result = await service.uninstall();

      expect(result.state, LifecycleOperationState.blocked);
      expect(result.message, contains('installer owns'));
      expect(adapter.uninstallCount, 0);
    });

    test('delegates portable uninstall to the adapter', () async {
      final FakeInstallLifecycleAdapter adapter = FakeInstallLifecycleAdapter(
        const LifecycleOperationResult.completed('portable uninstall started'),
      );
      final InstallLifecycleService service = InstallLifecycleService(
        profile: DistributionProfile.portable,
        adapter: adapter,
      );

      final LifecycleOperationResult result = await service.uninstall();

      expect(result.state, LifecycleOperationState.completed);
      expect(adapter.uninstallCount, 1);
    });
  });

  group('VersionPolicy', () {
    test('accepts upgrades and equivalent versions', () {
      expect(VersionPolicy.compare('2.0.0', '2.1.0'), VersionComparison.upgradeAvailable);
      expect(VersionPolicy.compare('v2.1.0', '2.1.0'), VersionComparison.same);
    });

    test('rejects downgrades and invalid versions', () {
      expect(VersionPolicy.compare('2.1.0', '2.0.9'), VersionComparison.downgrade);
      expect(VersionPolicy.compare('2.1.0', 'preview'), VersionComparison.invalid);
    });
  });

  group('UpdateService', () {
    test('does not query GitHub for installer-managed updates', () async {
      final FakeUpdateServiceAdapter adapter = FakeUpdateServiceAdapter(
        const UpdateRelease(version: '2.1.0', downloadUrl: 'https://example.invalid/update.zip'),
      );
      final UpdateService service = UpdateService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final UpdateCheckResult result = await service.checkForUpdates(currentVersion: '2.0.0');

      expect(result.state, UpdateCheckState.managedByInstaller);
      expect(adapter.fetchCount, 0);
      expect(adapter.installCount, 0);
    });

    test('returns a portable upgrade without installing unless requested', () async {
      final FakeUpdateServiceAdapter adapter = FakeUpdateServiceAdapter(
        const UpdateRelease(version: '2.1.0', downloadUrl: 'https://example.invalid/update.zip'),
      );
      final UpdateService service = UpdateService(
        profile: DistributionProfile.portable,
        adapter: adapter,
      );

      final UpdateCheckResult result = await service.checkForUpdates(currentVersion: '2.0.0');

      expect(result.state, UpdateCheckState.available);
      expect(result.release?.version, '2.1.0');
      expect(adapter.fetchCount, 1);
      expect(adapter.installCount, 0);
    });
  });
}

class FakeInstallLifecycleAdapter implements InstallLifecycleAdapter {
  FakeInstallLifecycleAdapter([this.result = const LifecycleOperationResult.completed()]);

  final LifecycleOperationResult result;
  int uninstallCount = 0;

  @override
  Future<LifecycleOperationResult> uninstall() async {
    uninstallCount++;
    return result;
  }
}

class FakeUpdateServiceAdapter implements UpdateServiceAdapter {
  FakeUpdateServiceAdapter(this.release);

  final UpdateRelease release;
  int fetchCount = 0;
  int installCount = 0;

  @override
  Future<UpdateRelease?> fetchLatestRelease() async {
    fetchCount++;
    return release;
  }

  @override
  Future<UpdateInstallResult> install(UpdateRelease release) async {
    installCount++;
    return const UpdateInstallResult.started();
  }
}
