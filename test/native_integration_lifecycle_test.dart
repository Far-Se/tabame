import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/shell_integration_service.dart';

void main() {
  test('taskbar failure preserves the last confirmed state and restores it', () async {
    final _FakeTaskbarAdapter adapter = _FakeTaskbarAdapter(initialVisible: true);
    final TaskbarVisibilityController service = TaskbarVisibilityController(adapter: adapter);

    expect((await service.setVisible(false)).success, isTrue);
    expect(service.isVisible, isFalse);

    adapter.failWrites = true;
    final ShellIntegrationResult failed = await service.setVisible(true);
    expect(failed.success, isFalse);
    expect(service.isVisible, isFalse);
    expect(adapter.visible, isFalse);

    adapter.failWrites = false;
    expect((await service.restore()).success, isTrue);
    expect(service.isVisible, isTrue);
    expect(adapter.visible, isTrue);
  });

  test('unavailable shell integration is an explicit reduced-mode result', () async {
    final TaskbarVisibilityController service = TaskbarVisibilityController(
      adapter: _FakeTaskbarAdapter(available: false),
    );

    final ShellIntegrationResult result = await service.setVisible(false);
    expect(result.success, isFalse);
    expect(result.visible, isTrue);
    expect(result.message, contains('unavailable'));
    expect(service.isVisible, isTrue);
  });
}

class _FakeTaskbarAdapter implements TaskbarVisibilityAdapter {
  _FakeTaskbarAdapter({this.available = true, bool initialVisible = true}) : visible = initialVisible;

  final bool available;
  bool visible;
  bool failWrites = false;

  @override
  bool get isAvailable => available;

  @override
  bool get isVisible => visible;

  @override
  String get unavailableReason => 'Taskbar integration is unavailable.';

  @override
  Future<bool> setVisible(bool value) async {
    if (!available || failWrites) return false;
    visible = value;
    return true;
  }
}
