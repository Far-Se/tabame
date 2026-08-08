import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pixel buffer used only by the platform OCR adapter that needs BGRA input.
/// The model itself is platform-neutral and contains no native identifiers.
class OcrPixelBuffer {
  const OcrPixelBuffer({
    required this.pixels,
    required this.width,
    required this.height,
  });

  /// Raw BGRA pixels, four bytes per pixel, straight (non-premultiplied) alpha.
  final Uint8List pixels;
  final int width;
  final int height;
}

OcrPixelBuffer? buildBgraPixelBufferFromPngBytes(Uint8List bytes) {
  if (bytes.isEmpty) return null;

  final img.Image? source = img.decodeImage(bytes);
  if (source == null) return null;

  final Uint8List pixels = Uint8List(source.width * source.height * 4);
  int index = 0;
  for (final img.Pixel pixel in source) {
    pixels[index++] = pixel.b.toInt();
    pixels[index++] = pixel.g.toInt();
    pixels[index++] = pixel.r.toInt();
    pixels[index++] = 255;
  }

  return OcrPixelBuffer(pixels: pixels, width: source.width, height: source.height);
}

/// Kept as a portable file helper for existing image-processing callers.
OcrPixelBuffer? buildBgraPixelBufferFromCapturedPng(String path) {
  final File file = File(path);
  if (!file.existsSync()) return null;
  return buildBgraPixelBufferFromPngBytes(file.readAsBytesSync());
}
