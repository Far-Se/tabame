import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tabame/platform/screen_capture_service.dart';
import 'package:tabame/platform/windows/windows_ocr_service.dart';
import 'package:tabame/platform/windows/windows_screen_capture_service.dart';

void main() {
  test('capture/OCR coordinator keeps native sequencing in the adapters', () async {
    final List<String> events = <String>[];
    final _FakeCaptureService capture = _FakeCaptureService(
      CapturedImage(encodedBytes: _pngBytes()),
      onCapture: () => events.add('capture'),
    );
    final _FakeOcrService ocr = _FakeOcrService(
      OcrResult.fromText('  recognized text  '),
      onRecognize: () => events.add('ocr'),
    );

    final OcrResult? result = await CaptureOcrCoordinator(
      captureService: capture,
      ocrService: ocr,
    ).captureAndRecognize();

    expect(result?.text, 'recognized text');
    expect(events, <String>['capture', 'ocr']);
    expect(capture.captureCalls, 1);
    expect(ocr.recognizeCalls, 1);
  });

  test('coordinator treats cancelled capture and empty OCR as safe no-result paths', () async {
    final _FakeCaptureService cancelled = _FakeCaptureService(null);
    final _FakeOcrService ocr = _FakeOcrService(OcrResult.fromText('ignored'));

    expect(
      await CaptureOcrCoordinator(captureService: cancelled, ocrService: ocr).captureAndRecognize(),
      isNull,
    );
    expect(ocr.recognizeCalls, 0);

    final _FakeCaptureService capture = _FakeCaptureService(
      CapturedImage(encodedBytes: _pngBytes()),
    );
    final _FakeOcrService empty = _FakeOcrService(OcrResult.fromText('  '));
    expect(
      await CaptureOcrCoordinator(captureService: capture, ocrService: empty).captureAndRecognize(),
      isNull,
    );
  });

  test('unavailable target capability does not invoke either adapter', () async {
    final _FakeCaptureService capture = _FakeCaptureService(
      CapturedImage(encodedBytes: _pngBytes()),
      available: false,
    );
    final _FakeOcrService ocr = _FakeOcrService(OcrResult.fromText('not used'));

    final CaptureOcrCoordinator coordinator = CaptureOcrCoordinator(
      captureService: capture,
      ocrService: ocr,
    );

    expect(coordinator.isAvailable, isFalse);
    expect(coordinator.unavailableReason, 'Screen capture is unavailable on this platform.');
    expect(await coordinator.captureAndRecognize(), isNull);
    expect(capture.captureCalls, 0);
    expect(ocr.recognizeCalls, 0);
  });

  test('Windows capture adapter removes its temporary image after success', () async {
    final Directory directory = await Directory.systemTemp.createTemp('tabame-capture-ocr-');
    addTearDown(() => directory.delete(recursive: true));
    final String outputPath = p.join(directory.path, 'capture.png');
    final Uint8List bytes = _pngBytes();
    final _FakeWindowsCaptureBridge bridge = _FakeWindowsCaptureBridge(bytes);

    final CapturedImage? result = await WindowsScreenCaptureService(
      bridge: bridge,
      capturePath: () => outputPath,
    ).captureSelection();

    expect(result?.encodedBytes, orderedEquals(bytes));
    expect(bridge.captureCalls, 1);
    expect(File(outputPath).existsSync(), isFalse);
  });

  test('Windows OCR adapter receives decoded BGRA pixels and dimensions', () async {
    final _FakeWindowsOcrBridge bridge = _FakeWindowsOcrBridge('OCR result');
    final OcrResult? result = await WindowsOcrService(bridge: bridge).recognizeImage(
      CapturedImage(encodedBytes: _pngBytes()),
    );

    expect(result?.text, 'OCR result');
    expect(bridge.width, 1);
    expect(bridge.height, 1);
    expect(bridge.pixels.length, 4);
    expect(bridge.pixels[3], 255);
  });

  test('deferred adapters expose an intentional reason instead of throwing', () async {
    const UnavailableScreenCaptureService capture = UnavailableScreenCaptureService(
      reason: 'macOS screen capture and OCR are deferred.',
    );
    const UnavailableOcrService ocr = UnavailableOcrService(
      reason: 'macOS OCR is deferred.',
    );

    expect(capture.isAvailable, isFalse);
    expect(ocr.isAvailable, isFalse);
    expect(await capture.captureSelection(), isNull);
    expect(
      await ocr.recognizeImage(CapturedImage(encodedBytes: _pngBytes())),
      isNull,
    );
  });
}

Uint8List _pngBytes() {
  final img.Image image = img.Image(width: 1, height: 1);
  return Uint8List.fromList(img.encodePng(image));
}

class _FakeCaptureService extends ScreenCaptureService {
  _FakeCaptureService(this.image, {this.available = true, this.onCapture});

  final CapturedImage? image;
  final bool available;
  final void Function()? onCapture;
  int captureCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  String get unavailableReason => 'Screen capture is unavailable on this platform.';

  @override
  Future<CapturedImage?> captureSelection() async {
    captureCalls++;
    onCapture?.call();
    return image;
  }
}

class _FakeOcrService extends OcrService {
  _FakeOcrService(this.result, {this.onRecognize});

  final OcrResult? result;
  final void Function()? onRecognize;
  int recognizeCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => 'OCR is unavailable on this platform.';

  @override
  Future<OcrResult?> recognizeImage(CapturedImage image) async {
    recognizeCalls++;
    onRecognize?.call();
    return result;
  }
}

class _FakeWindowsCaptureBridge implements WindowsScreenCaptureBridge {
  _FakeWindowsCaptureBridge(this.bytes);

  final Uint8List bytes;
  int captureCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<bool> captureSelection(String outputPath) async {
    captureCalls++;
    await File(outputPath).writeAsBytes(bytes);
    return true;
  }
}

class _FakeWindowsOcrBridge implements WindowsOcrBridge {
  _FakeWindowsOcrBridge(this.text);

  final String text;
  Uint8List pixels = Uint8List(0);
  int width = 0;
  int height = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<String> recognizeBgraPixels(Uint8List pixels, int width, int height) async {
    this.pixels = pixels;
    this.width = width;
    this.height = height;
    return text;
  }
}
