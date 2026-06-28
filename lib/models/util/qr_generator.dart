import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

img.Image? buildQrImage(String content, {int moduleSize = 8, int border = 4}) {
  if (content.isEmpty) return null;

  final QRCode qrCode = Encoder.encode(content, ErrorCorrectionLevel.m);
  if (qrCode.matrix == null) return null;

  final int matrixWidth = qrCode.matrix!.width;
  final int matrixHeight = qrCode.matrix!.height;
  final int size = (matrixWidth + border * 2) * moduleSize;
  final img.Image image = img.Image(width: size, height: size, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));

  final img.ColorRgb8 black = img.ColorRgb8(0, 0, 0);
  for (int y = 0; y < matrixHeight; y++) {
    for (int x = 0; x < matrixWidth; x++) {
      if (qrCode.matrix!.get(x, y) != 1) continue;
      img.fillRect(
        image,
        x1: (x + border) * moduleSize,
        y1: (y + border) * moduleSize,
        x2: (x + border + 1) * moduleSize - 1,
        y2: (y + border + 1) * moduleSize - 1,
        color: black,
      );
    }
  }

  return image;
}
