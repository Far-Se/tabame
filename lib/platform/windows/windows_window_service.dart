import '../platform_models.dart';
import '../window_service.dart';
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
  Future<List<PlatformWindow>> enumerate() => bridge.enumerate();

  @override
  Future<bool> activate(PlatformWindow window) => bridge.activate(window);

  @override
  Future<String?> captureFocus() => bridge.captureFocus();

  @override
  Future<bool> restoreFocus(String? token) => bridge.restoreFocus(token);
}
