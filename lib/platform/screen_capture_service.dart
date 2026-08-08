import 'dart:typed_data';

/// Encoded screen pixels returned by a platform capture adapter.
///
/// The bytes are deliberately kept encoded at this boundary. Native pixel
/// layouts, temporary files, display handles, and permission APIs belong to an
/// adapter rather than the shared feature layer.
class CapturedImage {
  const CapturedImage({
    required this.encodedBytes,
    this.mimeType = 'image/png',
    this.width,
    this.height,
  });

  final Uint8List encodedBytes;
  final String mimeType;
  final int? width;
  final int? height;

  bool get isEmpty => encodedBytes.isEmpty;
}

/// Neutral OCR output shared by the capture UI and platform adapters.
class OcrResult {
  const OcrResult(this.text);

  factory OcrResult.fromText(String text) => OcrResult(text.trim());

  final String text;

  bool get hasText => text.isNotEmpty;
}

/// Platform contract for an interactive screen selection.
abstract class ScreenCaptureService {
  static ScreenCaptureService _instance = const UnavailableScreenCaptureService();

  static ScreenCaptureService get instance => _instance;

  static void register(ScreenCaptureService service) {
    _instance = service;
  }

  const ScreenCaptureService();

  bool get isAvailable;
  String get unavailableReason;

  /// Captures a user-selected region without exposing how the selection is
  /// presented or which native display identifiers are involved.
  Future<CapturedImage?> captureSelection();
}

class UnavailableScreenCaptureService extends ScreenCaptureService {
  const UnavailableScreenCaptureService({
    this.reason = 'Screen capture is unavailable on this platform.',
  });

  final String reason;

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => reason;

  @override
  Future<CapturedImage?> captureSelection() async => null;
}

/// Platform contract for recognizing text from an encoded image.
abstract class OcrService {
  static OcrService _instance = const UnavailableOcrService();

  static OcrService get instance => _instance;

  static void register(OcrService service) {
    _instance = service;
  }

  const OcrService();

  bool get isAvailable;
  String get unavailableReason;
  Future<OcrResult?> recognizeImage(CapturedImage image);
}

class UnavailableOcrService extends OcrService {
  const UnavailableOcrService({
    this.reason = 'OCR is unavailable on this platform.',
  });

  final String reason;

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => reason;

  @override
  Future<OcrResult?> recognizeImage(CapturedImage image) async => null;
}

/// Shared capture-then-recognize orchestration.
///
/// The coordinator owns sequencing and empty-result handling. Capture and OCR
/// adapters own permissions, native calls, pixel conversion, and cancellation
/// behavior.
class CaptureOcrCoordinator {
  CaptureOcrCoordinator({
    ScreenCaptureService? captureService,
    OcrService? ocrService,
  })  : captureService = captureService ?? ScreenCaptureService.instance,
        ocrService = ocrService ?? OcrService.instance;

  final ScreenCaptureService captureService;
  final OcrService ocrService;

  bool get isAvailable => captureService.isAvailable && ocrService.isAvailable;

  String get unavailableReason {
    if (!captureService.isAvailable) return captureService.unavailableReason;
    if (!ocrService.isAvailable) return ocrService.unavailableReason;
    return '';
  }

  Future<OcrResult?> captureAndRecognize() async {
    if (!isAvailable) return null;

    final CapturedImage? image = await captureService.captureSelection();
    if (image == null || image.isEmpty) return null;

    final OcrResult? result = await ocrService.recognizeImage(image);
    if (result == null || !result.hasText) return null;
    return result;
  }
}
