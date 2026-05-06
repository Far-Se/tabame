import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

List<Display> enumerateDisplays() {
  final List<Display> displays = <Display>[];
  final Pointer<DISPLAY_DEVICE> device = calloc<DISPLAY_DEVICE>()..ref.cb = sizeOf<DISPLAY_DEVICE>();

  int index = 0;
  try {
    while (EnumDisplayDevices(nullptr.cast<Utf16>(), index, device, 0) != 0) {
      displays.add(
        Display(
          deviceName: device.ref.DeviceName,
          stateFlags: device.ref.StateFlags,
        ),
      );
      index++;
    }
  } finally {
    calloc.free(device);
  }

  return displays;
}

final class Display {
  const Display({
    required this.deviceName,
    required this.stateFlags,
  });

  final String deviceName;
  final int stateFlags;

  bool get isActive => (stateFlags & DISPLAY_DEVICE_ACTIVE) == DISPLAY_DEVICE_ACTIVE;

  void captureToBmp(String path) {
    final BitmapCapture capture = captureDisplayBitmap(deviceName: deviceName);
    File(path).writeAsBytesSync(encodeBitmapToBmp(capture), flush: true);
  }
}

final class BitmapCapture {
  const BitmapCapture({
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

final class MonitorBitmapCapture {
  const MonitorBitmapCapture({
    required this.deviceName,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });

  final String deviceName;
  final int left;
  final int top;
  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

BitmapCapture captureDisplayBitmap({
  required String deviceName,
  int? width,
  int? height,
}) {
  final Pointer<Utf16> deviceNamePtr = deviceName.toNativeUtf16();
  final int hdcScreen = CreateDC(
    nullptr.cast<Utf16>(),
    deviceNamePtr,
    nullptr.cast<Utf16>(),
    nullptr.cast<DEVMODE>(),
  );
  calloc.free(deviceNamePtr);

  if (hdcScreen == 0) {
    throw Exception('Failed to create a device context for $deviceName');
  }

  try {
    final int bitmap = captureScreenBitmap(
      hdcScreen,
      width: width,
      height: height,
    );
    try {
      return readBitmapCapture(hdc: hdcScreen, bitmap: bitmap);
    } finally {
      DeleteObject(bitmap);
    }
  } finally {
    DeleteDC(hdcScreen);
  }
}

MonitorBitmapCapture? captureMonitorBitmapByHandle(int monitorHandle) {
  final Pointer<MONITORINFOEX> monitorInfo = calloc<MONITORINFOEX>();
  monitorInfo.ref.monitorInfo.cbSize = sizeOf<MONITORINFOEX>();

  try {
    if (GetMonitorInfo(monitorHandle, monitorInfo.cast()) == 0) {
      return null;
    }

    final RECT rect = monitorInfo.ref.monitorInfo.rcMonitor;
    final int width = rect.right - rect.left;
    final int height = rect.bottom - rect.top;
    if (width <= 0 || height <= 0) return null;

    final BitmapCapture capture = captureDisplayBitmap(
      deviceName: monitorInfo.ref.szDevice,
      width: width,
      height: height,
    );

    return MonitorBitmapCapture(
      deviceName: monitorInfo.ref.szDevice,
      left: rect.left,
      top: rect.top,
      width: capture.width,
      height: capture.height,
      rgbaBytes: capture.rgbaBytes,
    );
  } finally {
    calloc.free(monitorInfo);
  }
}

int captureScreenBitmap(
  int hdcScreen, {
  int? width,
  int? height,
}) {
  final int bitmapWidth = width ?? GetDeviceCaps(hdcScreen, HORZRES);
  final int bitmapHeight = height ?? GetDeviceCaps(hdcScreen, VERTRES);

  final int hdcMem = CreateCompatibleDC(hdcScreen);
  if (hdcMem == 0) {
    throw Exception('Failed to create a memory device context');
  }

  try {
    final int bitmap = CreateCompatibleBitmap(hdcScreen, bitmapWidth, bitmapHeight);
    if (bitmap == 0) {
      throw Exception('Failed to create a compatible bitmap');
    }

    SelectObject(hdcMem, bitmap);
    if (BitBlt(hdcMem, 0, 0, bitmapWidth, bitmapHeight, hdcScreen, 0, 0, SRCCOPY) == 0) {
      DeleteObject(bitmap);
      throw Exception('BitBlt failed while capturing the display');
    }

    return bitmap;
  } finally {
    DeleteDC(hdcMem);
  }
}

BitmapCapture readBitmapCapture({
  required int hdc,
  required int bitmap,
}) {
  final Pointer<BITMAP> bmp = calloc<BITMAP>();
  final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();

  try {
    GetObject(bitmap, sizeOf<BITMAP>(), bmp);

    final int width = bmp.ref.bmWidth;
    final int height = bmp.ref.bmHeight;
    final int imageSize = width * height * 4;

    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = width;
    bmi.ref.bmiHeader.biHeight = -height;
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    final Pointer<Uint8> bgra = calloc<Uint8>(imageSize);
    try {
      if (GetDIBits(hdc, bitmap, 0, height, bgra.cast(), bmi, DIB_RGB_COLORS) == 0) {
        throw Exception('GetDIBits failed to retrieve bitmap data');
      }

      final Uint8List src = bgra.asTypedList(imageSize);
      final Uint8List rgba = Uint8List(imageSize);
      for (int i = 0; i < imageSize; i += 4) {
        rgba[i] = src[i + 2];
        rgba[i + 1] = src[i + 1];
        rgba[i + 2] = src[i];
        rgba[i + 3] = 255;
      }

      return BitmapCapture(
        width: width,
        height: height,
        rgbaBytes: rgba,
      );
    } finally {
      calloc.free(bgra);
    }
  } finally {
    calloc.free(bmp);
    calloc.free(bmi);
  }
}

Uint8List encodeBitmapToBmp(BitmapCapture capture) {
  final Uint8List bgraBytes = Uint8List(capture.rgbaBytes.length);
  for (int i = 0; i < capture.rgbaBytes.length; i += 4) {
    bgraBytes[i] = capture.rgbaBytes[i + 2];
    bgraBytes[i + 1] = capture.rgbaBytes[i + 1];
    bgraBytes[i + 2] = capture.rgbaBytes[i];
    bgraBytes[i + 3] = capture.rgbaBytes[i + 3];
  }

  const int fileHeaderSize = 14;
  const int infoHeaderSize = 40;
  final int imageSize = bgraBytes.length;
  final ByteData header = ByteData(fileHeaderSize + infoHeaderSize);

  header.setUint8(0, 0x42);
  header.setUint8(1, 0x4D);
  header.setUint32(2, fileHeaderSize + infoHeaderSize + imageSize, Endian.little);
  header.setUint32(10, fileHeaderSize + infoHeaderSize, Endian.little);

  header.setUint32(14, infoHeaderSize, Endian.little);
  header.setInt32(18, capture.width, Endian.little);
  header.setInt32(22, -capture.height, Endian.little);
  header.setUint16(26, 1, Endian.little);
  header.setUint16(28, 32, Endian.little);
  header.setUint32(30, BI_RGB, Endian.little);
  header.setUint32(34, imageSize, Endian.little);

  return Uint8List.fromList(<int>[
    ...header.buffer.asUint8List(),
    ...bgraBytes,
  ]);
}

sealed class ScreenshotResult {
  const ScreenshotResult();
}

final class ScreenshotSuccess extends ScreenshotResult {
  const ScreenshotSuccess({
    required this.display,
    required this.path,
  });

  final Display display;
  final String path;
}

final class ScreenshotFailure extends ScreenshotResult {
  const ScreenshotFailure({
    required this.display,
    required this.error,
  });

  final Display display;
  final Object error;
}

final class ScreenshotCaptureOptions {
  const ScreenshotCaptureOptions({
    this.outputDirectory,
    this.fileNameBuilder,
    this.createOutputDirectory = true,
    this.overwriteExisting = true,
  });

  final String? outputDirectory;
  final String Function(Display display, int index)? fileNameBuilder;
  final bool createOutputDirectory;
  final bool overwriteExisting;
}

final class ScreenshotService {
  const ScreenshotService();

  List<ScreenshotResult> captureAll({
    ScreenshotCaptureOptions options = const ScreenshotCaptureOptions(),
  }) {
    final List<ScreenshotResult> results = <ScreenshotResult>[];
    final String outputDirPath = options.outputDirectory ?? Directory.current.path;
    final Directory dir = Directory(outputDirPath);
    if (!dir.existsSync()) {
      if (!options.createOutputDirectory) {
        throw StateError('Output directory does not exist: $outputDirPath');
      }
      dir.createSync(recursive: true);
    }

    int index = 0;
    for (final Display display in enumerateDisplays()) {
      if (!display.isActive) continue;

      final String fileName = options.fileNameBuilder?.call(display, index) ?? 'display_${index + 1}.bmp';
      final String path = '${dir.path}\\$fileName';

      try {
        if (!options.overwriteExisting && File(path).existsSync()) {
          throw StateError('File already exists: $path');
        }

        display.captureToBmp(path);
        results.add(ScreenshotSuccess(display: display, path: path));
      } catch (error) {
        results.add(ScreenshotFailure(display: display, error: error));
      }

      index++;
    }

    return results;
  }
}
