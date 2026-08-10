import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/elevation_service.dart';

void main() {
  group('PrivilegeStatus', () {
    test('distinguishes a standard user from an administrator account', () {
      expect(
        PrivilegeStatus.fromToken(isAdministratorAccount: false, isElevated: false).level,
        PrivilegeLevel.standardUser,
      );
      expect(
        PrivilegeStatus.fromToken(isAdministratorAccount: true, isElevated: false).level,
        PrivilegeLevel.administratorMediumIntegrity,
      );
    });

    test('reports an elevated session separately from group membership', () {
      final PrivilegeStatus status = PrivilegeStatus.fromToken(isAdministratorAccount: true, isElevated: true);

      expect(status.level, PrivilegeLevel.elevated);
      expect(status.isElevated, isTrue);
    });
  });

  group('ElevationService', () {
    test('exposes opt-in startup elevation for supported profiles', () {
      expect(ElevationService.forCurrentProfile().capability.canStartAutomatically, isTrue);
      expect(
        ElevationService(
          profile: DistributionProfile.storeMsix,
          adapter: FakeElevationAdapter(const PrivilegeStatus.standardUser()),
        ).capability.canStartAutomatically,
        isFalse,
      );
    });

    test('allows an explicit restart from a standard-user session', () async {
      final FakeElevationAdapter adapter = FakeElevationAdapter(const PrivilegeStatus.standardUser());
      final ElevationService service = ElevationService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final ElevationRequestResult result = await service.restartCurrentSessionElevated(
        executable: r'C:\Apps\Tabame\tabame.exe',
        arguments: const <String>['-interface'],
      );

      expect(result.state, ElevationRequestState.launched);
      expect(adapter.launchCount, 1);
      expect(adapter.lastArguments, '-interface');
    });

    test('allows an explicit restart from a medium-integrity administrator account', () async {
      final FakeElevationAdapter adapter = FakeElevationAdapter(const PrivilegeStatus.administratorMediumIntegrity());
      final ElevationService service = ElevationService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final ElevationRequestResult result = await service.restartCurrentSessionElevated(
        executable: 'tabame.exe',
        arguments: const <String>[],
      );

      expect(result.state, ElevationRequestState.launched);
      expect(adapter.launchCount, 1);
    });

    test('does not relaunch an already elevated session', () async {
      final FakeElevationAdapter adapter = FakeElevationAdapter(const PrivilegeStatus.elevated());
      final ElevationService service = ElevationService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final ElevationRequestResult result = await service.restartCurrentSessionElevated(
        executable: 'tabame.exe',
        arguments: const <String>[],
      );

      expect(result.state, ElevationRequestState.alreadyElevated);
      expect(adapter.launchCount, 0);
    });

    test('keeps the current session alive when UAC is cancelled', () async {
      final FakeElevationAdapter adapter = FakeElevationAdapter(
        const PrivilegeStatus.administratorMediumIntegrity(),
        launchResult: const ElevationRequestResult.cancelled(),
      );
      final ElevationService service = ElevationService(
        profile: DistributionProfile.storeInstaller,
        adapter: adapter,
      );

      final ElevationRequestResult result = await service.restartCurrentSessionElevated(
        executable: 'tabame.exe',
        arguments: const <String>[],
      );

      expect(result.state, ElevationRequestState.cancelled);
      expect(result.shouldCloseCurrentProcess, isFalse);
      expect(adapter.launchCount, 1);
    });

    test('blocks elevation-dependent actions in MSIX without allowElevation approval', () async {
      final FakeElevationAdapter adapter = FakeElevationAdapter(const PrivilegeStatus.administratorMediumIntegrity());
      final ElevationService service = ElevationService(
        profile: DistributionProfile.storeMsix,
        adapter: adapter,
      );

      final ElevationRequestResult result = await service.launchApplicationElevated(
        executable: 'selected-app.exe',
      );

      expect(result.state, ElevationRequestState.blocked);
      expect(result.message, contains('allowElevation'));
      expect(adapter.launchCount, 0);
    });
  });
}

class FakeElevationAdapter implements ElevationAdapter {
  FakeElevationAdapter(this.status, {this.launchResult = const ElevationRequestResult.launched()});

  final PrivilegeStatus status;
  final ElevationRequestResult launchResult;
  int launchCount = 0;
  String? lastArguments;

  @override
  PrivilegeStatus readPrivilegeStatus() => status;

  @override
  Future<ElevationRequestResult> launchElevated({required String executable, String? arguments}) async {
    launchCount++;
    lastArguments = arguments;
    return launchResult;
  }
}
