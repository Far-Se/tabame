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

  /// Monotonically increases whenever a visibility operation is queued.
  /// Startup retries use it to stop after an explicit competing operation.
  int get operationGeneration;

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
  int get operationGeneration => 0;

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
  TaskbarVisibilityController({required this.adapter})
      : _initialVisibility = adapter.isVisible,
        _visible = adapter.isVisible;

  final TaskbarVisibilityAdapter adapter;
  final bool _initialVisibility;
  bool? _previousVisibility;
  bool _visible;
  int _operationGeneration = 0;
  Future<void> _operationTail = Future<void>.value();

  @override
  int get operationGeneration => _operationGeneration;

  @override
  bool get isAvailable => adapter.isAvailable;

  @override
  bool get isVisible => _visible;

  @override
  String get unavailableReason => adapter.unavailableReason;

  @override
  Future<ShellIntegrationResult> setVisible(bool visible) {
    _operationGeneration++;
    return _enqueue(() async {
      if (!isAvailable) {
        return ShellIntegrationResult.failure(visible: _visible, message: unavailableReason);
      }
      // Explorer can recreate or reset the taskbar after a successful native
      // call. Re-read it before treating a repeated request as a no-op.
      if (_visible == visible && adapter.isVisible == visible) {
        return ShellIntegrationResult.success(visible: _visible);
      }

      _previousVisibility ??= _initialVisibility;
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
    });
  }

  @override
  Future<ShellIntegrationResult> restore() {
    _operationGeneration++;
    return _enqueue(() async {
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
    });
  }

  Future<ShellIntegrationResult> _enqueue(Future<ShellIntegrationResult> Function() operation) {
    final Future<ShellIntegrationResult> next = _operationTail.then((_) => operation());
    _operationTail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}

/// Injectable seam for tests and Windows-specific adapters.
abstract interface class TaskbarVisibilityAdapter {
  bool get isAvailable;
  bool get isVisible;
  String get unavailableReason;
  Future<bool> setVisible(bool visible);
}
