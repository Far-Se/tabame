import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/util/ocr_capture_decoder.dart';
import '../screen_capture_service.dart';
import 'tabamewin32_api.dart' as win32;

/// Native seam for Windows OCR. The shared layer passes only encoded image
/// data; BGRA conversion and the method-channel call stay in this adapter.
abstract class WindowsOcrBridge {
  bool get isAvailable;
  Future<String> recognizeBgraPixels(Uint8List pixels, int width, int height);
}

class WindowsOcrService extends OcrService {
  WindowsOcrService({WindowsOcrBridge? bridge}) : bridge = bridge ?? const WindowsNativeOcrBridge();

  final WindowsOcrBridge bridge;

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  String get unavailableReason =>
      isAvailable ? 'Windows OCR returned no recognized text.' : 'Windows OCR is unavailable.';

  @override
  Future<OcrResult?> recognizeImage(CapturedImage image) async {
    if (!isAvailable || image.isEmpty) return null;

    try {
      final OcrPixelBuffer? buffer = await compute<Uint8List, OcrPixelBuffer?>(
        buildBgraPixelBufferFromPngBytes,
        image.encodedBytes,
      );
      if (buffer == null) return null;

      final String text = await bridge.recognizeBgraPixels(buffer.pixels, buffer.width, buffer.height);
      final OcrResult result = OcrResult.fromText(text);
      return result.hasText ? result : null;
    } catch (_) {
      return null;
    }
  }
}

class WindowsNativeOcrBridge implements WindowsOcrBridge {
  const WindowsNativeOcrBridge();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Future<String> recognizeBgraPixels(Uint8List pixels, int width, int height) {
    return win32.recognizeBgraPixels(pixels, width, height);
  }
}
