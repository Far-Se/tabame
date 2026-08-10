import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';

import '../clipboard_service.dart';
import '../platform_models.dart';
import 'tabamewin32_api.dart';
import 'win32_api.dart';

/// Testable native seam for the Windows clipboard implementation.
///
/// The rest of the application only sees [ClipboardService]. Windows method
/// channels, clipboard format identifiers, and listener ownership stay below
/// this bridge.
abstract class WindowsClipboardBridge {
  bool get isAvailable;
  Stream<int?> get changes;
  Future<bool> start();
  Future<void> stop();
  Future<PlatformClipboardContent?> readContent();
  Future<bool> writeContent(PlatformClipboardContent content);
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path);
  Future<PlatformClipboardFileCapture?> captureClipboardToFiles({
    required String textPath,
    required String htmlPath,
    int previewLimit = 5000,
  });
  Future<bool> writeContentFromFiles({
    String textPath = '',
    String htmlPath = '',
    String imagePath = '',
  });
  Future<Uint8List?> readImage();
  Future<bool> writeFiles(List<String> paths);
  Future<bool> revealFile(String path);
}

class WindowsClipboardService extends ClipboardService {
  WindowsClipboardService({WindowsClipboardBridge? bridge})
      : bridge = bridge ?? WindowsTabameClipboardBridge(),
        _changes = StreamController<PlatformClipboardText>.broadcast();

  final WindowsClipboardBridge bridge;
  final StreamController<PlatformClipboardText> _changes;
  StreamSubscription<int?>? _nativeSubscription;
  bool _started = false;

  @override
  bool get isAvailable => bridge.isAvailable;

  @override
  bool get isMonitoringAvailable => _started && isAvailable;

  @override
  bool get supportsRichText => isAvailable;

  @override
  bool get supportsImages => isAvailable;

  @override
  bool get supportsFileClipboard => isAvailable;

  @override
  bool get supportsClipboardFileCapture => isAvailable;

  @override
  String get unavailableReason => isAvailable
      ? 'Windows clipboard monitoring could not be started.'
      : 'The Windows clipboard service is unavailable.';

  @override
  Stream<PlatformClipboardText> get changes => _changes.stream;

  @override
  Future<bool> start() async {
    if (_started) return true;
    if (!isAvailable) return false;

    int? lastSequence;
    _nativeSubscription = bridge.changes.listen(
      (int? sequence) {
        if (sequence != null && sequence == lastSequence) return;
        if (sequence != null) lastSequence = sequence;
        _emitClipboardNotification(sequence);
      },
      onError: (_) {},
    );
    final bool started = await bridge.start();
    if (!started) {
      await _nativeSubscription?.cancel();
      _nativeSubscription = null;
      return false;
    }
    _started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_started && _nativeSubscription == null) return;
    _started = false;
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    await bridge.stop();
  }

  @override
  Future<PlatformClipboardContent?> readContent() => bridge.readContent();

  @override
  Future<bool> writeContent(PlatformClipboardContent content) => bridge.writeContent(content);

  @override
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) => bridge.saveImageToFile(path);

  @override
  Future<PlatformClipboardFileCapture?> captureClipboardToFiles({
    required String textPath,
    required String htmlPath,
    int previewLimit = 5000,
  }) {
    return bridge.captureClipboardToFiles(
      textPath: textPath,
      htmlPath: htmlPath,
      previewLimit: previewLimit,
    );
  }

  @override
  Future<bool> writeContentFromFiles({
    String textPath = '',
    String htmlPath = '',
    String imagePath = '',
  }) {
    return bridge.writeContentFromFiles(
      textPath: textPath,
      htmlPath: htmlPath,
      imagePath: imagePath,
    );
  }

  @override
  Future<Uint8List?> readImage() => bridge.readImage();

  @override
  Future<bool> writeFiles(List<String> paths) => bridge.writeFiles(paths);

  @override
  Future<bool> revealFile(String path) => bridge.revealFile(path);

  void _emitClipboardNotification(int? sequence) {
    // The event is intentionally notification-only. Reading a large clipboard
    // value here would block the platform thread and force the history path to
    // read it a second time. The store performs one file-backed capture after
    // receiving this marker.
    _changes.add(PlatformClipboardText(text: '', changeCount: sequence, isSnapshot: false));
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }
}

/// Production bridge for the existing tabamewin32 clipboard implementation.
class WindowsTabameClipboardBridge implements WindowsClipboardBridge {
  WindowsTabameClipboardBridge({bool? available}) : _available = available ?? Platform.isWindows;

  final bool _available;
  final StreamController<int?> _changes = StreamController<int?>.broadcast();
  late final ClipboardEventListener _listener = _ClipboardEventRelay((int? sequence) => _changes.add(sequence));
  bool _started = false;

  @override
  bool get isAvailable => _available;

  @override
  Stream<int?> get changes => _changes.stream;

  @override
  Future<bool> start() async {
    if (!_available) return false;
    if (_started) return true;
    ClipboardHooks.addListener(_listener);
    final bool started = await ClipboardHooks.start();
    if (!started) {
      ClipboardHooks.removeListener(_listener);
      return false;
    }
    _started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    ClipboardHooks.removeListener(_listener);
    await ClipboardHooks.stop();
  }

  @override
  Future<PlatformClipboardContent?> readContent() async {
    final Map<String, dynamic> data = await ClipboardExtended.pasteRichText();
    final String text = (data['text'] ?? '').toString();
    final String html = (data['html'] ?? '').toString();
    if (text.isEmpty && html.isEmpty) return null;
    return PlatformClipboardContent(text: text, html: html);
  }

  @override
  Future<bool> writeContent(PlatformClipboardContent content) {
    final Uint8List? imageBytes = content.imageBytes;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      return ClipboardExtended.copyImage(imageBytes);
    }
    if (content.html.isNotEmpty) {
      return ClipboardExtended.copyRichText(text: content.text, html: content.html);
    }
    return ClipboardExtended.copy(content.text);
  }

  @override
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) async {
    final ClipboardImageInfo? info = await ClipboardExtended.saveImageToFile(path);
    if (info == null) return null;
    return PlatformClipboardImageInfo(path: info.path, byteLength: info.byteLength, hash: info.hash);
  }

  @override
  Future<PlatformClipboardFileCapture?> captureClipboardToFiles({
    required String textPath,
    required String htmlPath,
    int previewLimit = 5000,
  }) async {
    final ClipboardFileCapture? capture = await ClipboardExtended.captureTextToFiles(
      textPath: textPath,
      htmlPath: htmlPath,
      previewLimit: previewLimit,
    );
    if (capture == null) return null;
    return PlatformClipboardFileCapture(
      captured: capture.captured,
      textPreview: capture.textPreview,
      htmlPreview: capture.htmlPreview,
      textLength: capture.textLength,
      htmlLength: capture.htmlLength,
      byteLength: capture.byteLength,
      contentHash: capture.contentHash,
    );
  }

  @override
  Future<bool> writeContentFromFiles({
    String textPath = '',
    String htmlPath = '',
    String imagePath = '',
  }) {
    return ClipboardExtended.copyContentFromFiles(
      textPath: textPath,
      htmlPath: htmlPath,
      imagePath: imagePath,
    );
  }

  @override
  Future<Uint8List?> readImage() => ClipboardExtended.pasteImage();

  @override
  Future<bool> writeFiles(List<String> paths) async {
    await _copyPathsToWindowsClipboard(paths);
    return true;
  }

  @override
  Future<bool> revealFile(String path) async {
    try {
      await Process.start(
        'explorer.exe',
        <String>['/select,"$path"'],
        mode: ProcessStartMode.detached,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }
}

class _ClipboardEventRelay extends ClipboardEventListener {
  _ClipboardEventRelay(this.onUpdate);

  final void Function(int? sequence) onUpdate;

  @override
  void onClipboardUpdate(int? sequence) => onUpdate(sequence);
}

/// Writes one or more paths as CF_HDROP without importing the shared WinUtils
/// module. This small FFI edge is intentionally kept in the Windows adapter.
Future<void> _copyPathsToWindowsClipboard(List<String> paths) async {
  if (paths.isEmpty) throw ArgumentError('At least one clipboard path is required.');
  final List<int> pathUnits = <int>[];
  for (final String path in paths) {
    final String normalized = path.endsWith(Platform.pathSeparator) ? path.substring(0, path.length - 1) : path;
    pathUnits.addAll(normalized.codeUnits);
    pathUnits.add(0);
  }
  pathUnits.add(0);
  final int bytesNeeded = sizeOf<DROPFILES>() + (pathUnits.length * sizeOf<Uint16>());
  final Pointer<NativeType> memory = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, bytesNeeded);
  if (memory.address == 0) throw Exception('Failed to allocate clipboard memory.');

  final Pointer<DROPFILES> dropFiles = GlobalLock(memory).cast<DROPFILES>();
  if (dropFiles.address == 0) {
    GlobalFree(memory);
    throw Exception('Failed to lock clipboard memory.');
  }

  try {
    dropFiles.ref.pFiles = sizeOf<DROPFILES>();
    dropFiles.ref.pt.x = 0;
    dropFiles.ref.pt.y = 0;
    dropFiles.ref.fNC = 0;
    dropFiles.ref.fWide = 1;
    final Pointer<Uint16> fileList = (dropFiles.cast<Uint8>() + sizeOf<DROPFILES>()).cast<Uint16>();
    for (int index = 0; index < pathUnits.length; index++) {
      fileList[index] = pathUnits[index];
    }
  } finally {
    GlobalUnlock(memory);
  }

  if (OpenClipboard(0) == 0) {
    GlobalFree(memory);
    throw Exception('Failed to open clipboard.');
  }

  try {
    EmptyClipboard();
    if (SetClipboardData(CF_HDROP, memory.address) == 0) {
      GlobalFree(memory);
      throw Exception('Failed to set clipboard file data.');
    }
  } finally {
    CloseClipboard();
  }
}
