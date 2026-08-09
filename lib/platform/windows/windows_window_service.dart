import '../platform_models.dart';
import '../window_service.dart';
import '../../services/native_integration_coordinator.dart';
import 'windows_window_bridge.dart';

/// Windows implementation of the neutral [WindowService] contract.
///
/// Keeping the bridge injectable makes the contract and capability behavior
/// testable without loading user32.dll on a non-Windows test runner.
class WindowsWindowService extends WindowService {
  WindowsWindowService({required this.bridge});

  final WindowsWindowBridge bridge;

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  String get unavailableReason => isAvailable ? '' : bridge.unavailableReason;

  @override
  bool get isPreviewAvailable => bridge.isPreviewAvailable;

  @override
  Future<List<PlatformWindow>> enumerate() async {
    final NativeIntegrationCoordinator integrations = NativeIntegrationCoordinator.instance;
    if (!integrations.canStart(NativeIntegrationId.windowAutomation)) {
      integrations.reportDisabled(
        NativeIntegrationId.windowAutomation,
        reason: integrations.denialReason(NativeIntegrationId.windowAutomation) ??
            'Window enumeration is disabled; the visible launcher remains available.',
        reducedMode: true,
      );
      return const <PlatformWindow>[];
    }
    final List<PlatformWindow> windows = await bridge.enumerate();
    integrations.reportRunning(NativeIntegrationId.windowAutomation);
    return windows;
  }

  @override
  Future<bool> activate(PlatformWindow window) async {
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.windowAutomation)) {
      return false;
    }
    return bridge.activate(window);
  }

  @override
  Future<String?> captureFocus() async {
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.windowAutomation)) {
      return null;
    }
    return bridge.captureFocus();
  }

  @override
  Future<bool> restoreFocus(String? token) async {
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.windowAutomation)) {
      return false;
    }
    return bridge.restoreFocus(token);
  }

  @override
  Future<PlatformWindowPreview?> capturePreview(PlatformWindow window) async {
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.windowAutomation)) {
      return null;
    }
    return bridge.capturePreview(window);
  }
}
