import '../platform_models.dart';

/// Testable boundary for the Windows window adapter.
///
/// The bridge exposes only neutral snapshots. Its concrete implementation is
/// the only place that translates Win32 data into [PlatformWindow].
abstract class WindowsWindowBridge {
  bool get isAvailable;
  String get unavailableReason;
  bool get isPreviewAvailable => false;
  Future<List<PlatformWindow>> enumerate();
  Future<bool> activate(PlatformWindow window);
  Future<String?> captureFocus();
  Future<bool> restoreFocus(String? token);
  Future<PlatformWindowPreview?> capturePreview(PlatformWindow window) async => null;
}
