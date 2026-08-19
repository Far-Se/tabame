import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/platform_models.dart';
import 'package:tabame/platform/windows/windows_clipboard_service.dart';

void main() {
  test('Windows clipboard adapter owns watcher lifecycle and maps events', () async {
    final _FakeWindowsClipboardBridge bridge = _FakeWindowsClipboardBridge(
      content: const PlatformClipboardContent(text: 'from Windows'),
    );
    final WindowsClipboardService service = WindowsClipboardService(bridge: bridge);

    expect(await service.start(), isTrue);
    expect(await service.start(), isTrue);
    expect(bridge.startCalls, 1);
    expect(service.isMonitoringAvailable, isTrue);

    final Future<PlatformClipboardText> event = service.changes.first;
    bridge.emitChange(1);
    final PlatformClipboardText change = await event;
    expect(change.text, isEmpty);
    expect(change.changeCount, 1);
    expect(change.isSnapshot, isFalse);
    expect(bridge.readContentCalls, 0);

    final List<PlatformClipboardText> coalesced = <PlatformClipboardText>[];
    final StreamSubscription<PlatformClipboardText> subscription = service.changes.listen(coalesced.add);
    bridge.emitChange(2);
    bridge.emitChange(2);
    await Future<void>.delayed(Duration.zero);
    expect(coalesced, hasLength(1));
    await subscription.cancel();

    await service.stop();
    await service.stop();
    expect(bridge.stopCalls, 1);
    expect(service.isMonitoringAvailable, isFalse);
  });

  test('Windows clipboard adapter keeps rich/image operations behind the bridge', () async {
    final _FakeWindowsClipboardBridge bridge = _FakeWindowsClipboardBridge(
      content: const PlatformClipboardContent(text: 'text', html: '<b>text</b>'),
    );
    final WindowsClipboardService service = WindowsClipboardService(bridge: bridge);

    expect(service.supportsRichText, isTrue);
    expect(service.supportsImages, isTrue);
    expect(service.supportsFileClipboard, isTrue);
    expect((await service.readContent())?.html, '<b>text</b>');

    final bool copied = await service.writeContent(
      const PlatformClipboardContent(text: 'text', html: '<i>text</i>'),
    );
    expect(copied, isTrue);
    expect(bridge.lastWrite?.html, '<i>text</i>');

    final bool copiedFile = await service.writeFile(r'C:\demo.txt');
    expect(copiedFile, isTrue);
    expect(bridge.lastFile, r'C:\demo.txt');
    expect(await service.revealFile(r'C:\demo.txt'), isTrue);

    bridge.capture = const PlatformClipboardFileCapture(
      captured: true,
      textPreview: 'preview',
      textLength: 30000,
      byteLength: 30000,
      contentHash: 'hash',
    );
    final PlatformClipboardFileCapture? capture = await service.captureClipboardToFiles(
      textPath: r'C:\text.txt',
      htmlPath: r'C:\html.txt',
    );
    expect(capture?.textPreview, 'preview');
    expect(capture?.textLength, 30000);

    expect(
      await service.writeContentFromFiles(textPath: r'C:\text.txt'),
      isTrue,
    );
    expect(bridge.lastTextPath, r'C:\text.txt');
  });

  test('unavailable Windows adapter returns safe capability state', () async {
    final WindowsClipboardService service = WindowsClipboardService(
      bridge: _FakeWindowsClipboardBridge(available: false),
    );

    expect(service.isAvailable, isFalse);
    expect(service.isMonitoringAvailable, isFalse);
    expect(await service.start(), isFalse);
    expect(service.unavailableReason, isNotEmpty);
  });
}

class _FakeWindowsClipboardBridge implements WindowsClipboardBridge {
  _FakeWindowsClipboardBridge({this.content, this.available = true});

  final bool available;
  final StreamController<int?> _events = StreamController<int?>.broadcast();
  PlatformClipboardContent? content;
  PlatformClipboardContent? lastWrite;
  PlatformClipboardFileCapture? capture;
  String? lastFile;
  String? lastTextPath;
  int readContentCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  bool started = false;

  @override
  bool get isAvailable => available;

  @override
  Stream<int?> get changes => _events.stream;

  @override
  Future<bool> start() async {
    startCalls++;
    started = available;
    return available;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    started = false;
  }

  @override
  Future<PlatformClipboardContent?> readContent() async {
    readContentCalls++;
    return content;
  }

  @override
  Future<bool> writeContent(PlatformClipboardContent content) async {
    lastWrite = content;
    return available;
  }

  @override
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) async => null;

  @override
  Future<PlatformClipboardFileCapture?> captureClipboardToFiles({
    required String textPath,
    required String htmlPath,
    int previewLimit = 5000,
  }) async =>
      capture;

  @override
  Future<bool> writeContentFromFiles({
    String textPath = '',
    String htmlPath = '',
    String imagePath = '',
  }) async {
    lastTextPath = textPath;
    return available;
  }

  @override
  Future<Uint8List?> readImage() async => null;

  @override
  Future<bool> writeFiles(List<String> paths) async {
    lastFile = paths.single;
    return available;
  }

  @override
  Future<bool> revealFile(String path) async => available;

  void emitChange([int? sequence]) => _events.add(sequence);
}
