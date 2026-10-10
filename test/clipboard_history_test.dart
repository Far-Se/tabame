import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/models/clipboard_history.dart';
import 'package:tabame/platform/app_paths.dart';
import 'package:tabame/platform/clipboard_service.dart';
import 'package:tabame/platform/platform_capabilities.dart';
import 'package:tabame/platform/platform_models.dart';
import 'package:tabame/platform/portable_clipboard_history.dart';
import 'package:tabame/services/clipboard_history_coordinator.dart';

void main() {
  late Directory workspace;
  late _FakeClipboardService service;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('tabame_clipboard_history_test_');
    AppPaths.resetForTesting();
    await AppPaths.initialize(
      applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
      applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
      temporaryDirectory: () async => Directory(p.join(workspace.path, 'temp')),
      rootOverride: p.join(workspace.path, 'support', 'Tabame'),
      legacyRootOverride: p.join(workspace.path, 'legacy', 'Tabame'),
      migrateLegacyData: false,
    );
    ClipboardHistoryStore.resetForTesting();
    service = _FakeClipboardService();
    ClipboardService.register(service);
    await ClipboardHistoryCoordinator.instance.stop();
  });

  tearDown(() async {
    await ClipboardHistoryCoordinator.instance.stop();
    ClipboardService.register(const UnavailableClipboardService());
    ClipboardHistoryStore.resetForTesting();
    AppPaths.resetForTesting();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  test('history records neutral text changes and deduplicates recent content', () async {
    service.content = const PlatformClipboardContent(text: 'hello');

    await ClipboardHistoryStore.recordCurrentClipboard();
    await ClipboardHistoryStore.recordClipboardChange(const PlatformClipboardText(text: 'hello'));

    final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(limit: 20);
    expect(entries, hasLength(1));
    expect(entries.single.text, 'hello');
    expect(File(ClipboardHistoryStore.historyFilePath).existsSync(), isTrue);
  });

  test('large text is stored in a bounded metadata line and a sidecar', () async {
    final String largeText = '${List<String>.filled(3000, 'clipboard-data-0123456789\\n').join()}TAIL-SENTINEL';
    service.content = PlatformClipboardContent(text: largeText);

    await ClipboardHistoryStore.recordCurrentClipboard();

    final String metadata = await File(ClipboardHistoryStore.historyFilePath).readAsString();
    expect(metadata.length, lessThan(10000));
    expect(metadata, contains('textPath'));

    final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(limit: 20);
    expect(entries, hasLength(1));
    expect(entries.single.text.length, lessThanOrEqualTo(5000));

    final ClipboardHistoryEntry? full = await ClipboardHistoryStore.getFullEntry(entries.single.id);
    expect(full, isNotNull);
    expect(full!.text, largeText);
    expect(await File(full.textPath).readAsString(), largeText);

    await ClipboardHistoryStore.copyEntry(entries.single);
    expect(service.lastWrite?.text, largeText);
  });

  test('deduplication expires after ten newer clipboard entries', () async {
    await ClipboardHistoryStore.recordClipboardChange(const PlatformClipboardText(text: 'first'));
    for (int index = 0; index < 10; index++) {
      await ClipboardHistoryStore.recordClipboardChange(PlatformClipboardText(text: 'unique-$index'));
    }
    await ClipboardHistoryStore.recordClipboardChange(const PlatformClipboardText(text: 'first'));

    final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(limit: 30);
    expect(entries, hasLength(12));
    expect(entries.where((ClipboardHistoryEntry entry) => entry.text == 'first'), hasLength(2));
  });

  test('debug startup does not prune shared history using its shorter retention', () async {
    final File settings = File(AppPaths.settingsPath('settings.json', forWrite: true));
    await settings.parent.create(recursive: true);
    await settings.writeAsString(jsonEncode(<String, Object>{
      'flutter.clipboardHistoryEnabled': true,
      'flutter.clipboardHistoryCacheDays': 1,
    }));
    final ClipboardHistoryEntry older = ClipboardHistoryEntry(
      id: 'older',
      type: ClipboardHistoryType.text,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
      text: 'still within the release retention period',
    );
    final File history = File(ClipboardHistoryStore.historyFilePath);
    await history.parent.create(recursive: true);
    final String original = '${jsonEncode(older.toMap())}\n';
    await history.writeAsString(original);

    await ClipboardHistoryStore.clearCache(automatic: true);

    expect(await history.readAsString(), original);
    // Explicit pruning still applies the selected retention period.
    await ClipboardHistoryStore.clearCache();
    expect(await ClipboardHistoryStore.loadPaged(), isEmpty);
  });

  test('manual pruning keeps the full retention period and pinned entries', () async {
    final File settings = File(AppPaths.settingsPath('settings.json', forWrite: true));
    await settings.parent.create(recursive: true);
    await settings.writeAsString(jsonEncode(<String, Object>{
      'flutter.clipboardHistoryCacheDays': 30,
    }));
    final File history = File(ClipboardHistoryStore.historyFilePath);
    await history.parent.create(recursive: true);
    final List<ClipboardHistoryEntry> entries = <ClipboardHistoryEntry>[
      for (final int age in <int>[40, 31, 20, 1])
        ClipboardHistoryEntry(
          id: 'age-$age',
          type: ClipboardHistoryType.text,
          createdAt: DateTime.now().subtract(Duration(days: age)),
          text: 'copied $age days ago',
        ),
    ];
    await history
        .writeAsString('${entries.map((ClipboardHistoryEntry entry) => jsonEncode(entry.toMap())).join('\n')}\n');
    await ClipboardHistoryStore.setPinned(entries.first, true);

    await ClipboardHistoryStore.clearCache();

    expect((await ClipboardHistoryStore.loadPaged()).map((ClipboardHistoryEntry entry) => entry.id),
        <String>['age-1', 'age-20']);
    expect((await ClipboardHistoryStore.loadPinned()).single.id, 'age-40');
  });

  test('clear waits for an in-flight capture before deleting its metadata and payload', () async {
    final Completer<void> started = Completer<void>();
    final Completer<void> release = Completer<void>();
    service.content = const PlatformClipboardContent(text: 'captured before clear');
    service.readStarted = started;
    service.readGate = release.future;
    final Future<void> capture = ClipboardHistoryStore.recordCurrentClipboard();
    await started.future;

    bool cleared = false;
    final Future<void> clearing = ClipboardHistoryStore.clear().then((_) => cleared = true);
    try {
      // Give an incorrectly unqueued clear time to run while capture is held.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(cleared, isFalse);
    } finally {
      release.complete();
      await Future.wait<void>(<Future<void>>[capture, clearing]);
    }

    expect(await ClipboardHistoryStore.loadPaged(), isEmpty);
    expect(Directory(ClipboardHistoryStore.payloadDirectoryPath).listSync(), isEmpty);
  });

  test('coordinator subscribes once and records target adapter events', () async {
    expect(await ClipboardHistoryCoordinator.instance.start(), isTrue);
    expect(await ClipboardHistoryCoordinator.instance.start(), isTrue);
    expect(service.startCalls, 1);

    service.content = null;
    service.emit(const PlatformClipboardText(text: 'from Linux X11'));
    await _waitForHistoryEntry();

    final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(limit: 20);
    expect(entries.single.text, 'from Linux X11');
  });

  testWidgets('portable history explains when monitoring is unavailable', (WidgetTester tester) async {
    PlatformCapabilities.register(const PlatformCapabilities());
    ClipboardService.register(const UnavailableClipboardService());

    await tester.pumpWidget(const MaterialApp(home: PortableClipboardHistoryPanel()));

    expect(find.textContaining('unavailable'), findsOneWidget);
  });

  test('copying an entry delegates to the neutral service', () async {
    final ClipboardHistoryEntry entry = ClipboardHistoryEntry(
      id: 'entry',
      type: ClipboardHistoryType.text,
      createdAt: DateTime.now(),
      text: 'copy me',
    );

    await ClipboardHistoryStore.copyEntry(entry);

    expect(service.lastWrite?.text, 'copy me');
    expect(service.lastWrite?.html, isEmpty);
  });
}

Future<void> _waitForHistoryEntry() async {
  for (int attempt = 0; attempt < 20; attempt++) {
    final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(limit: 20);
    if (entries.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('clipboard history event was not recorded');
}

class _FakeClipboardService extends ClipboardService {
  _FakeClipboardService() : _changes = StreamController<PlatformClipboardText>.broadcast();

  final StreamController<PlatformClipboardText> _changes;
  PlatformClipboardContent? content;
  PlatformClipboardContent? lastWrite;
  Completer<void>? readStarted;
  Future<void>? readGate;
  int startCalls = 0;
  bool started = false;

  @override
  bool get isAvailable => true;

  @override
  bool get isMonitoringAvailable => started;

  @override
  String get unavailableReason => '';

  @override
  Stream<PlatformClipboardText> get changes => _changes.stream;

  @override
  Future<bool> start() async {
    startCalls++;
    started = true;
    return true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<PlatformClipboardContent?> readContent() async {
    readStarted?.complete();
    await readGate;
    return content;
  }

  @override
  Future<bool> writeContent(PlatformClipboardContent content) async {
    lastWrite = content;
    return true;
  }

  @override
  Future<PlatformClipboardImageInfo?> saveImageToFile(String path) async => null;

  void emit(PlatformClipboardText change) => _changes.add(change);
}
