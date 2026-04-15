import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

String? decodeQrValueFromCapturedPng(String path) {
  final File file = File(path);
  if (!file.existsSync()) return null;

  final Uint8List bytes = file.readAsBytesSync();
  final img.Image? source = img.decodeImage(bytes);
  if (source == null) return null;

  for (final img.Image candidate in _buildQrCandidates(source)) {
    final String? result = _tryDecodeQrCandidate(candidate);
    if (result != null && result.trim().isNotEmpty) {
      return result.trim();
    }
  }
  return null;
}

String? decodeOtpUriFromCapturedPng(String path) {
  final String? decoded = decodeQrValueFromCapturedPng(path);
  if (decoded == null) return null;
  if (!decoded.toLowerCase().startsWith('otpauth://')) return null;
  return decoded;
}

Iterable<img.Image> _buildQrCandidates(img.Image source) sync* {
  yield source;

  if (source.width < 900 && source.height < 900) {
    yield img.copyResize(
      source,
      width: source.width * 2,
      height: source.height * 2,
      interpolation: img.Interpolation.nearest,
    );
  }

  yield img.invert(source.clone());

  if (source.width < 900 && source.height < 900) {
    yield img.copyResize(
      img.invert(source.clone()),
      width: source.width * 2,
      height: source.height * 2,
      interpolation: img.Interpolation.nearest,
    );
  }
}

String? _tryDecodeQrCandidate(img.Image source) {
  try {
    final Int32List pixels = Int32List(source.width * source.height);
    int index = 0;
    for (final img.Pixel pixel in source) {
      pixels[index++] = (pixel.a.toInt() << 24) | (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
    }

    final BinaryBitmap bitmap = BinaryBitmap(
      HybridBinarizer(
        RGBLuminanceSource(source.width, source.height, pixels),
      ),
    );

    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    return null;
  }
}
