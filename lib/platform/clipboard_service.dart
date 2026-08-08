import 'dart:typed_data';

import 'platform_models.dart';

/// Text-first clipboard monitoring contract.
abstract class ClipboardService {
  static ClipboardService _instance = const UnavailableClipboardService();

  static ClipboardService get instance => _instance;

  static void register(ClipboardService service) {
    _instance = service;
  }

  const ClipboardService();

  /// Whether this adapter can perform at least text clipboard operations.
  bool get isAvailable;

  /// Whether a watcher is currently active and can emit clipboard changes.
  bool get isMonitoringAvailable => isAvailable;

  /// Format capabilities are explicit so UI does not probe a native channel.
  bool get supportsRichText => false;
  bool get supportsImages => false;
  bool get supportsFileClipboard => false;

  String get unavailableReason;
  Stream<PlatformClipboardText> get changes;
  Future<bool> start();
  Future<void> stop();
  Future<PlatformClipboardContent?> readContent();
  Future<bool> writeContent(PlatformClipboardContent content);
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) async => null;
  Future<Uint8List?> readImage() async => null;
  Future<bool> writeFiles(List<String> paths) async => false;
  Future<bool> writeFile(String path) => writeFiles(<String>[path]);
  Future<bool> revealFile(String path) async => false;

  Future<String?> readText() async => (await readContent())?.text;
  Future<bool> writeText(String text) => writeContent(PlatformClipboardContent(text: text));
}

class UnavailableClipboardService extends ClipboardService {
  const UnavailableClipboardService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Clipboard monitoring is unavailable on this platform.';

  @override
  Stream<PlatformClipboardText> get changes => const Stream<PlatformClipboardText>.empty();

  @override
  Future<bool> start() async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<PlatformClipboardContent?> readContent() async => null;

  @override
  Future<bool> writeContent(PlatformClipboardContent content) async => false;
}
