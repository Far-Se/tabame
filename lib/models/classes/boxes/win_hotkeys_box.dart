import 'package:flutter/foundation.dart';

import '../../../platform/hotkey_binding_factory.dart';
import '../../../platform/hotkey_service.dart';
import '../../../platform/platform_models.dart';
import '../../../services/native_integration_coordinator.dart';
import '../../globals.dart';
import '../boxes.dart';

// --------------------------------------------------------------------------
// WinHotkeys
// --------------------------------------------------------------------------

class WinHotkeys {
  static Future<void> update() async {
    if (!Globals.debugHooks && !kReleaseMode) return;
    final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
    if (!integrations.canStart(NativeIntegrationId.globalHooks)) {
      await HotkeyService.instance.unregisterBindings();
      integrations.reportDisabled(
        NativeIntegrationId.globalHooks,
        reason: integrations.denialReason(NativeIntegrationId.globalHooks) ??
            'Global hotkeys are disabled; use the visible Tabame window instead.',
        reducedMode: true,
      );
      return;
    }
    final HotkeyRegistrationResult result = await HotkeyService.instance.registerBindings(
      HotkeyBindingFactory.fromModels(Boxes.remap),
    );
    if (result.registered) {
      integrations.reportRunning(NativeIntegrationId.globalHooks);
    } else {
      integrations.reportUnavailable(
        NativeIntegrationId.globalHooks,
        reason: result.reason.isEmpty ? HotkeyService.instance.unavailableReason : result.reason,
      );
    }
  }
}
