import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:tabamewin32/tabamewin32.dart';

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

OcrPixelBuffer? buildBgraPixelBufferFromCapturedPng(String path) {
  final File file = File(path);
  if (!file.existsSync()) return null;

  final Uint8List bytes = file.readAsBytesSync();
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

Future<String?> recognizeTextFromCapturedPng(String path) async {
  final OcrPixelBuffer? buffer = await compute<String, OcrPixelBuffer?>(
    buildBgraPixelBufferFromCapturedPng,
    path,
  );
  if (buffer == null) return null;

  final String text = await recognizeBgraPixels(buffer.pixels, buffer.width, buffer.height);
  final String trimmed = text.trim();
  return trimmed.isEmpty ? null : trimmed;
}
