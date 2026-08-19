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
    bridge.emitChange();
    expect((await event).text, 'from Windows');

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
  final StreamController<void> _events = StreamController<void>.broadcast();
  PlatformClipboardContent? content;
  PlatformClipboardContent? lastWrite;
  String? lastFile;
  int startCalls = 0;
  int stopCalls = 0;
  bool started = false;

  @override
  bool get isAvailable => available;

  @override
  Stream<void> get changes => _events.stream;

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
  Future<PlatformClipboardContent?> readContent() async => content;

  @override
  Future<bool> writeContent(PlatformClipboardContent content) async {
    lastWrite = content;
    return available;
  }

  @override
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) async => null;

  @override
  Future<Uint8List?> readImage() async => null;

  @override
  Future<bool> writeFiles(List<String> paths) async {
    lastFile = paths.single;
    return available;
  }

  @override
  Future<bool> revealFile(String path) async => available;

  void emitChange() => _events.add(null);
}
