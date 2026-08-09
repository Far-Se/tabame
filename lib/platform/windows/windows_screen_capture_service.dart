import 'dart:io';
import 'dart:typed_data';

import '../app_paths.dart';
import '../screen_capture_service.dart';
import '../../models/win32/win32.dart';
import '../../services/native_integration_coordinator.dart';
import '../../models/win32/win_utils.dart';
import 'win32_api.dart';

/// Native seam for the Windows interactive clipping flow.
///
/// The output path is an adapter detail. Tests can provide a fake bridge that
/// writes a deterministic PNG without loading user32.dll or launching the
/// Windows clipping UI.
abstract class WindowsScreenCaptureBridge {
  bool get isAvailable;
  Future<bool> captureSelection(String outputPath);
}

class WindowsScreenCaptureService extends ScreenCaptureService {
  WindowsScreenCaptureService({
    WindowsScreenCaptureBridge? bridge,
    String Function()? capturePath,
  })  : bridge = bridge ?? const WindowsNativeScreenCaptureBridge(),
        _capturePath = capturePath ?? (() => AppPaths.temporaryPath('capture.png'));

  final WindowsScreenCaptureBridge bridge;
  final String Function() _capturePath;

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  String get unavailableReason => isAvailable
      ? 'The Windows screen clipping service did not return an image.'
      : 'The Windows screen clipping service is unavailable.';

  @override
  Future<CapturedImage?> captureSelection() async {
    if (!isAvailable) return null;
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.screenCapture)) {
      NativeIntegrationCoordinator.instance.reportUnavailable(
        NativeIntegrationId.screenCapture,
        reason: 'Screen capture is unavailable in the current distribution profile.',
      );
      return null;
    }

    final String path = _capturePath();
    final File file = File(path);
    try {
      if (await file.exists()) await file.delete();
      if (!await bridge.captureSelection(path) || !await file.exists()) return null;

      final Uint8List bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      return CapturedImage(encodedBytes: bytes);
    } catch (_) {
      return null;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A locked temporary file should not turn a completed capture into a
        // UI failure. The next capture removes it before writing.
      }
    }
  }
}

/// Compatibility adapter for the existing Windows clipping URI workflow.
class WindowsNativeScreenCaptureBridge implements WindowsScreenCaptureBridge {
  const WindowsNativeScreenCaptureBridge();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Future<bool> captureSelection(String outputPath) async {
    if (!isAvailable) return false;

    final int hwnd = Win32.getMainHandle();
    if (hwnd != 0) ShowWindow(hwnd, SW_HIDE);
    try {
      final bool captured = await WinUtils.screenCapture();
      final String nativeOutputPath = AppPaths.temporaryPath('capture.png');
      if (!captured) return false;

      // The current native helper writes to the canonical temporary path. Keep
      // the bridge tolerant of an injected or future path provider.
      if (nativeOutputPath != outputPath && await File(nativeOutputPath).exists()) {
        await File(nativeOutputPath).copy(outputPath);
      }
      return await File(outputPath).exists();
    } finally {
      if (hwnd != 0) ShowWindow(hwnd, SW_SHOW);
    }
  }
}
