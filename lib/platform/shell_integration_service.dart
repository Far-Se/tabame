/// Result of a reversible shell integration operation.
class ShellIntegrationResult {
  const ShellIntegrationResult({
    required this.success,
    required this.visible,
    required this.message,
  });

  const ShellIntegrationResult.success({required bool visible})
      : this(
          success: true,
          visible: visible,
          message: '',
        );

  const ShellIntegrationResult.failure({required bool visible, required String message})
      : this(
          success: false,
          visible: visible,
          message: message,
        );

  final bool success;
  final bool visible;
  final String message;
}

/// Platform-neutral taskbar/shell lifecycle boundary.
///
/// Implementations must not update their cached state until the native call has
/// completed successfully. This keeps a failed or policy-blocked shell call in
/// reduced mode instead of claiming that Windows changed.
abstract class TaskbarVisibilityService {
  static TaskbarVisibilityService _instance = const UnavailableTaskbarVisibilityService();

  static TaskbarVisibilityService get instance => _instance;

  static void register(TaskbarVisibilityService service) {
    _instance = service;
  }

  const TaskbarVisibilityService();

  bool get isAvailable;
  bool get isVisible;
  String get unavailableReason;

  Future<ShellIntegrationResult> setVisible(bool visible);
  Future<ShellIntegrationResult> restore();
}

class UnavailableTaskbarVisibilityService extends TaskbarVisibilityService {
  const UnavailableTaskbarVisibilityService();

  @override
  bool get isAvailable => false;

  @override
  bool get isVisible => true;

  @override
  String get unavailableReason => 'Taskbar shell integration is unavailable; the normal taskbar remains visible.';

  @override
  Future<ShellIntegrationResult> setVisible(bool visible) async => ShellIntegrationResult.failure(
        visible: true,
        message: unavailableReason,
      );

  @override
  Future<ShellIntegrationResult> restore() async => const ShellIntegrationResult.success(visible: true);
}

/// Owns the reversible state around a native taskbar adapter.
class TaskbarVisibilityController extends TaskbarVisibilityService {
  TaskbarVisibilityController({required this.adapter}) : _visible = adapter.isVisible;

  final TaskbarVisibilityAdapter adapter;
  bool? _previousVisibility;
  bool _visible;

  @override
  bool get isAvailable => adapter.isAvailable;

  @override
  bool get isVisible => _visible;

  @override
  String get unavailableReason => adapter.unavailableReason;

  @override
  Future<ShellIntegrationResult> setVisible(bool visible) async {
    if (!isAvailable) {
      return ShellIntegrationResult.failure(visible: _visible, message: unavailableReason);
    }
    if (_visible == visible) return ShellIntegrationResult.success(visible: _visible);

    _previousVisibility ??= adapter.isVisible;
    try {
      final bool changed = await adapter.setVisible(visible);
      if (!changed) {
        return ShellIntegrationResult.failure(
          visible: _visible,
          message: 'Windows did not confirm the requested taskbar state; the previous state was kept.',
        );
      }
      _visible = visible;
      return ShellIntegrationResult.success(visible: _visible);
    } catch (_) {
      return ShellIntegrationResult.failure(
        visible: _visible,
        message: 'The taskbar could not be changed; the previous state was kept.',
      );
    }
  }

  @override
  Future<ShellIntegrationResult> restore() async {
    final bool? previous = _previousVisibility;
    if (previous == null) return ShellIntegrationResult.success(visible: _visible);

    try {
      final bool restored = await adapter.setVisible(previous);
      if (!restored) {
        return ShellIntegrationResult.failure(
          visible: _visible,
          message: 'The taskbar could not be restored; Windows kept its current state.',
        );
      }
      _visible = previous;
      _previousVisibility = null;
      return ShellIntegrationResult.success(visible: _visible);
    } catch (_) {
      return ShellIntegrationResult.failure(
        visible: _visible,
        message: 'The taskbar could not be restored; Windows kept its current state.',
      );
    }
  }
}

/// Injectable seam for tests and Windows-specific adapters.
abstract interface class TaskbarVisibilityAdapter {
  bool get isAvailable;
  bool get isVisible;
  String get unavailableReason;
  Future<bool> setVisible(bool visible);
}
