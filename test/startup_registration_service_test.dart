import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/startup_registration_service.dart';

void main() {
  test('keeps startup independent from administrator preference', () async {
    final FakeStartupAdapter adapter = FakeStartupAdapter();
    final StartupRegistrationService service = StartupRegistrationService(
      profile: DistributionProfile.storeInstaller,
      adapter: adapter,
    );

    expect(service.profile, DistributionProfile.storeInstaller);
    expect((await service.read()).state, StartupRegistrationState.disabled);

    final StartupRegistrationStatus enabled = await service.setEnabled(true);
    expect(enabled.state, StartupRegistrationState.enabled);
    expect(adapter.requestedValues, <bool>[true]);
    expect(adapter.lastArguments, StartupLaunchArguments.quickMenu);
  });

  test('does not allow changes when Windows owns the startup state', () {
    const StartupRegistrationStatus byUser = StartupRegistrationStatus.disabledByUser('Windows Settings');
    const StartupRegistrationStatus byPolicy = StartupRegistrationStatus.disabledByPolicy('Policy');

    expect(byUser.isSystemControlled, isTrue);
    expect(byUser.canChange, isFalse);
    expect(byPolicy.isSystemControlled, isTrue);
    expect(byPolicy.canChange, isFalse);
  });

  test('propagates adapter errors without throwing', () async {
    final StartupRegistrationService service = StartupRegistrationService(
      profile: DistributionProfile.portable,
      adapter: FakeStartupAdapter(failure: true),
    );

    final StartupRegistrationStatus status = await service.setEnabled(true);
    expect(status.state, StartupRegistrationState.error);
    expect(status.message, contains('blocked'));
  });
}

class FakeStartupAdapter implements StartupRegistrationAdapter {
  FakeStartupAdapter({this.failure = false});

  final bool failure;
  final List<bool> requestedValues = <bool>[];
  String? lastArguments;
  bool enabled = false;

  @override
  Future<StartupRegistrationStatus> read() async {
    return enabled ? const StartupRegistrationStatus.enabled() : const StartupRegistrationStatus.disabled();
  }

  @override
  Future<StartupRegistrationStatus> setEnabled(bool value) async {
    requestedValues.add(value);
    lastArguments = StartupLaunchArguments.quickMenu;
    if (failure) return const StartupRegistrationStatus.error('startup blocked');
    enabled = value;
    return read();
  }

  @override
  Future<void> openSystemSettings() async {}
}
