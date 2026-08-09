import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/distribution_profile.dart';
import 'package:tabame/services/native_integration_coordinator.dart';

void main() {
  group('NativeIntegrationCoordinator consent', () {
    test('Store profiles require and can revoke high-risk consent', () async {
      final InMemoryNativeIntegrationConsentStore store = InMemoryNativeIntegrationConsentStore();
      final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
        profile: DistributionProfile.storeInstaller,
        consentStore: store,
      );

      expect(coordinator.hasConsent(NativeIntegrationId.clipboardHistory), isFalse);
      expect(coordinator.isAllowed(NativeIntegrationId.clipboardHistory), isFalse);
      expect(coordinator.isAllowed(NativeIntegrationId.notifications), isTrue);

      await coordinator.setConsent(NativeIntegrationId.clipboardHistory, true);
      expect(coordinator.hasConsent(NativeIntegrationId.clipboardHistory), isTrue);
      expect(coordinator.isAllowed(NativeIntegrationId.clipboardHistory), isTrue);

      coordinator.reportAvailable(NativeIntegrationId.clipboardHistory);
      expect(coordinator.canStart(NativeIntegrationId.clipboardHistory), isTrue);

      await coordinator.setConsent(NativeIntegrationId.clipboardHistory, false);
      expect(coordinator.hasConsent(NativeIntegrationId.clipboardHistory), isFalse);
      expect(coordinator.isAllowed(NativeIntegrationId.clipboardHistory), isFalse);
      expect(
        coordinator.diagnosticsSnapshot.forId(NativeIntegrationId.clipboardHistory)?.status,
        NativeIntegrationStatus.blockedByUser,
      );
    });

    test('portable keeps legacy behavior unless consent is requested', () {
      final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
        profile: DistributionProfile.portable,
        consentStore: InMemoryNativeIntegrationConsentStore(),
      );

      expect(coordinator.isAllowed(NativeIntegrationId.screenCapture), isTrue);
      expect(coordinator.canStart(NativeIntegrationId.screenCapture), isTrue);
      expect(
        coordinator.isAllowed(NativeIntegrationId.screenCapture, requireConsent: true),
        isFalse,
      );
    });
  });

  test('MSIX policy denies only the elevation-sensitive integration', () async {
    final InMemoryNativeIntegrationConsentStore store = InMemoryNativeIntegrationConsentStore();
    final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
      profile: DistributionProfile.storeMsix,
      consentStore: store,
    );

    await coordinator.setConsent(NativeIntegrationId.processActions, true);
    expect(coordinator.isAllowed(NativeIntegrationId.processActions), isFalse);
    expect(coordinator.canStart(NativeIntegrationId.processActions), isFalse);
    expect(coordinator.isAllowed(NativeIntegrationId.notifications), isTrue);
    expect(
      coordinator.diagnosticsSnapshot.forId(NativeIntegrationId.processActions)?.status,
      NativeIntegrationStatus.blockedByPolicy,
    );
  });

  test('reports unavailable integrations as reduced and not startable', () {
    final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
      profile: DistributionProfile.portable,
      consentStore: InMemoryNativeIntegrationConsentStore(),
    );

    coordinator.reportUnavailable(
      NativeIntegrationId.screenCapture,
      reason: 'No capture backend is available',
    );
    final NativeIntegrationDiagnostic unavailable =
        coordinator.diagnosticsSnapshot.forId(NativeIntegrationId.screenCapture)!;

    expect(unavailable.status, NativeIntegrationStatus.unavailable);
    expect(unavailable.reducedMode, isTrue);
    expect(unavailable.reason, contains('No capture backend'));
    expect(unavailable.canStart, isFalse);

    coordinator.reportAvailable(NativeIntegrationId.screenCapture);
    final NativeIntegrationDiagnostic available =
        coordinator.diagnosticsSnapshot.forId(NativeIntegrationId.screenCapture)!;
    expect(available.status, NativeIntegrationStatus.available);
    expect(available.reducedMode, isFalse);
  });

  test('diagnostics JSON redacts credentials, clipboard data, and paths', () {
    final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
      profile: DistributionProfile.portable,
      consentStore: InMemoryNativeIntegrationConsentStore(),
    );

    coordinator.reportError(
      NativeIntegrationId.browserBridge,
      reason: 'token=top-secret clipboard=private clipboard text',
    );
    coordinator.reportError(
      NativeIntegrationId.screenRecording,
      reason: r'Capture failed at C:\Users\Alice\Videos\private.mp4',
    );

    final String json = coordinator.diagnosticsJson;
    final Object decoded = jsonDecode(json);
    expect(decoded, isA<Map<String, dynamic>>());
    expect(json, contains('browserBridge'));
    expect(json, contains('Browser bridge'));
    expect(json, contains('status'));
    expect(json, contains('reason'));
    expect(json, contains('reducedMode'));
    expect(json, contains('consent'));
    expect(json, isNot(contains('top-secret')));
    expect(json, isNot(contains('private clipboard text')));
    expect(json, isNot(contains(r'C:\Users\Alice\Videos\private.mp4')));
  });

  test('emits a safe snapshot when runtime state changes', () async {
    final NativeIntegrationCoordinator coordinator = NativeIntegrationCoordinator(
      profile: DistributionProfile.portable,
      consentStore: InMemoryNativeIntegrationConsentStore(),
    );
    final Future<NativeIntegrationDiagnosticsSnapshot> nextChange = coordinator.changes.first;

    coordinator.reportRunning(NativeIntegrationId.globalHooks);
    final NativeIntegrationDiagnosticsSnapshot snapshot = await nextChange;

    expect(snapshot.changedId, NativeIntegrationId.globalHooks);
    expect(snapshot.forId(NativeIntegrationId.globalHooks)?.status, NativeIntegrationStatus.running);
  });
}
