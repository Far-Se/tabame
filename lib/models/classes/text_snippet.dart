import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../clipboard_history.dart';
import '../../platform/clipboard_service.dart';
import '../../platform/windows/tabamewin32_api.dart';
import 'boxes.dart';
import 'snippet_template.dart';

class TextSnippet {
  TextSnippet({
    String? id,
    String? name,
    required this.trigger,
    required this.text,
    this.enabled = true,
    this.pinned = false,
    this.tags = const <String>[],
    this.caseSensitive = true,
    this.wordBoundary = true,
    this.appMode = 'any',
    this.apps = const <String>[],
    this.windowTitle = '',
    this.allowShell = false,
    this.html = '',
    this.templateEnabled = true,
  })  : id = id ?? const Uuid().v4(),
        name = name ?? (trigger.isEmpty ? 'Untitled snippet' : trigger);

  final String id;
  final String name;
  final String trigger;
  final String text;
  final bool enabled;
  final bool pinned;
  final List<String> tags;
  final bool caseSensitive;
  final bool wordBoundary;
  final String appMode;
  final List<String> apps;
  final String windowTitle;
  final bool allowShell;
  final String html;
  final bool templateEnabled;
  late final String _searchText = '$name $trigger $text ${tags.join(' ')}'.toLowerCase();

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'name': name,
        'trigger': trigger,
        'text': text,
        'enabled': enabled,
        'pinned': pinned,
        'tags': tags,
        'caseSensitive': caseSensitive,
        'wordBoundary': wordBoundary,
        'appMode': appMode,
        'apps': apps,
        'windowTitle': windowTitle,
        'allowShell': allowShell,
        'html': html,
        'templateEnabled': templateEnabled,
      };

  String toJson() => jsonEncode(toMap());

  factory TextSnippet.fromMap(Map<String, dynamic> map) => TextSnippet(
        id: map['id'] as String? ?? 'legacy-${sha256.convert(utf8.encode(jsonEncode(map)))}',
        name: (map['name'] ?? map['title']) as String?,
        trigger: (map['trigger'] ?? map['keyword']) as String? ?? '',
        text: (map['text'] ?? map['content']) as String? ?? '',
        enabled: map['enabled'] as bool? ?? true,
        pinned: map['pinned'] as bool? ?? false,
        tags: _strings(map['tags']),
        caseSensitive: map['caseSensitive'] as bool? ?? true,
        // Legacy hotkey rules matched suffixes within words.
        wordBoundary: map['wordBoundary'] as bool? ?? !map.containsKey('trigger'),
        appMode: map['appMode'] as String? ?? 'any',
        apps: _strings(map['apps']), windowTitle: map['windowTitle'] as String? ?? '',
        allowShell: map['allowShell'] as bool? ?? false,
        html: htmlFragment(map['html'] as String? ?? ''),
        templateEnabled: map['templateEnabled'] as bool? ??
            (map.containsKey('name') || map.containsKey('title') || map.containsKey('keyword')),
      );

  static List<String> _strings(dynamic value) {
    if (value == null) return <String>[];
    final Iterable<String> strings = value is String ? value.split(',') : (value as List<dynamic>).cast<String>();
    return strings.map((String s) => s.trim()).where((String s) => s.isNotEmpty).toSet().toList();
  }

  factory TextSnippet.fromJson(String source) => TextSnippet.fromMap(jsonDecode(source) as Map<String, dynamic>);

  TextSnippet copyWith({
    String? id,
    String? name,
    String? trigger,
    String? text,
    bool? enabled,
    bool? pinned,
    List<String>? tags,
    bool? caseSensitive,
    bool? wordBoundary,
    String? appMode,
    List<String>? apps,
    String? windowTitle,
    bool? allowShell,
    String? html,
    bool? templateEnabled,
  }) =>
      TextSnippet(
          id: id ?? this.id,
          name: name ?? this.name,
          trigger: trigger ?? this.trigger,
          text: text ?? this.text,
          enabled: enabled ?? this.enabled,
          pinned: pinned ?? this.pinned,
          tags: tags ?? this.tags,
          caseSensitive: caseSensitive ?? this.caseSensitive,
          wordBoundary: wordBoundary ?? this.wordBoundary,
          appMode: appMode ?? this.appMode,
          apps: apps ?? this.apps,
          windowTitle: windowTitle ?? this.windowTitle,
          allowShell: allowShell ?? this.allowShell,
          html: html ?? this.html,
          templateEnabled: templateEnabled ?? this.templateEnabled);

  static String htmlFragment(String html) {
    final int start = html.indexOf('<!--StartFragment-->');
    final int end = html.indexOf('<!--EndFragment-->');
    if (start >= 0 && end > start) return html.substring(start + '<!--StartFragment-->'.length, end);
    if (html.startsWith('Version:')) {
      final RegExpMatch? startOffset = RegExp(r'StartFragment:(\d+)').firstMatch(html);
      final RegExpMatch? endOffset = RegExp(r'EndFragment:(\d+)').firstMatch(html);
      if (startOffset != null && endOffset != null) {
        final int begin = int.parse(startOffset.group(1)!);
        final int end = int.parse(endOffset.group(1)!);
        final List<int> bytes = utf8.encode(html);
        if (begin >= 0 && end > begin && end <= bytes.length) return utf8.decode(bytes.sublist(begin, end));
      }
      return '';
    }
    return html;
  }

  bool matches(String query) {
    return query.toLowerCase().trim().split(RegExp(r'\s+')).every(_searchText.contains);
  }
}

class SnippetPreferences {
  const SnippetPreferences(
      {this.autoExpand = false,
      this.mode = 'immediate',
      this.delayMs = 30,
      this.pasteDelayMs = 100,
      this.restoreClipboard = true,
      this.undoOnEscape = true,
      this.completionSound = false,
      this.excludedApps = const <String>['1password.exe', 'keepass.exe', 'keepassxc.exe', 'bitwarden.exe']});

  final bool autoExpand;
  final String mode;
  final int delayMs;
  final int pasteDelayMs;
  final bool restoreClipboard;
  final bool undoOnEscape;
  final bool completionSound;
  final List<String> excludedApps;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'autoExpand': autoExpand,
        'mode': mode,
        'delayMs': delayMs,
        'pasteDelayMs': pasteDelayMs,
        'restoreClipboard': restoreClipboard,
        'undoOnEscape': undoOnEscape,
        'completionSound': completionSound,
        'excludedApps': excludedApps
      };

  factory SnippetPreferences.fromMap(Map<String, dynamic> map) => SnippetPreferences(
        autoExpand: map['autoExpand'] as bool? ?? false,
        mode: <String>['immediate', 'delimiterKeep', 'delimiterDiscard'].contains(map['mode'])
            ? map['mode'] as String
            : 'immediate',
        delayMs: ((map['delayMs'] as num?)?.toInt() ?? 30).clamp(0, 1000),
        pasteDelayMs: ((map['pasteDelayMs'] as num?)?.toInt() ?? 100).clamp(30, 1000),
        restoreClipboard: map['restoreClipboard'] as bool? ?? true,
        undoOnEscape: map['undoOnEscape'] as bool? ?? true,
        completionSound: map['completionSound'] as bool? ?? false,
        excludedApps: map['excludedApps'] == null
            ? const SnippetPreferences().excludedApps
            : TextSnippet._strings(map['excludedApps']),
      );
}

class SnippetImportPlan {
  const SnippetImportPlan(this.snippets, this.issues);
  final List<TextSnippet> snippets;
  final List<String> issues;
}

class TextSnippetsManager {
  static const String settingsKey = 'textSnippets';
  static const String preferencesKey = 'textSnippetPreferences';

  /// Reading a damaged library never erases the saved data.
  static List<TextSnippet> load() {
    final String raw = Boxes.pref.getString(settingsKey) ?? '';
    if (raw.isEmpty) return <TextSnippet>[];
    final dynamic decoded = jsonDecode(raw);
    final List<dynamic> entries = (decoded is Map ? decoded['snippets'] : decoded) as List<dynamic>;
    return entries
        .map((dynamic row) => TextSnippet.fromMap((row is String ? jsonDecode(row) : row) as Map<String, dynamic>))
        .toList();
  }

  static SnippetPreferences preferences() {
    final String raw = Boxes.pref.getString(preferencesKey) ?? '';
    return raw.isEmpty
        ? const SnippetPreferences()
        : SnippetPreferences.fromMap(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> save(List<TextSnippet> snippets) async {
    await Boxes.updateSettings(
        settingsKey,
        jsonEncode(<String, dynamic>{
          'version': 2,
          'snippets': snippets.map((TextSnippet s) => s.toMap()).toList(),
        }));
    await pushToNative(snippets);
  }

  static Future<void> savePreferences(SnippetPreferences value) async {
    await Boxes.updateSettings(preferencesKey, jsonEncode(value.toMap()));
    await pushToNative();
  }

  static String _templateText(TextSnippet snippet) =>
      snippet.templateEnabled ? snippet.text : snippet.text.replaceAll('{', r'\{').replaceAll('}', r'\}');

  static SnippetTemplate template(TextSnippet snippet, List<TextSnippet> library) => SnippetTemplate(
        _templateText(snippet),
        allowShell: snippet.allowShell,
        snippets: <String, SnippetTemplateSource>{
          for (final TextSnippet s in library) s.name: SnippetTemplateSource(_templateText(s), allowShell: s.allowShell)
        },
      );

  static String? validate(TextSnippet snippet, List<TextSnippet> library) {
    if (snippet.name.trim().isEmpty) return 'Give this snippet a name.';
    if (snippet.text.isEmpty) return 'Add some snippet text.';
    if (snippet.text.length > 65536) return 'Snippet text is limited to 65,536 characters.';
    if (snippet.html.length > SnippetTemplate.maxLength) return 'Rich text is limited to 256K characters.';
    if (snippet.trigger.length > 128 || RegExp(r'\s').hasMatch(snippet.trigger))
      return 'Keywords must be at most 128 characters with no spaces.';
    if (!<String>['any', 'only', 'except'].contains(snippet.appMode)) return 'Choose a valid application rule.';
    if (snippet.appMode != 'any' && snippet.apps.isEmpty) return 'Add at least one application executable.';
    for (final TextSnippet other in library) {
      if (other.id == snippet.id) continue;
      if (other.name.toLowerCase() == snippet.name.toLowerCase())
        return 'A snippet named "${other.name}" already exists.';
      if (snippet.trigger.isNotEmpty &&
          other.trigger.isNotEmpty &&
          snippet.enabled &&
          other.enabled &&
          (snippet.caseSensitive && other.caseSensitive
              ? snippet.trigger == other.trigger
              : snippet.trigger.toLowerCase() == other.trigger.toLowerCase())) {
        final bool separateApps = snippet.appMode == 'only' &&
            other.appMode == 'only' &&
            !snippet.apps
                .any((String app) => other.apps.any((String otherApp) => app.toLowerCase() == otherApp.toLowerCase()));
        if (!separateApps) return 'Keyword "${snippet.trigger}" conflicts with "${other.name}".';
      }
    }
    try {
      template(snippet, library);
    } on FormatException catch (error) {
      return error.message;
    }
    return null;
  }

  static Future<void> pushToNative([List<TextSnippet>? snippets]) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return;
    }
    TextSnippets.onExpansionRequested = _onExpansionRequested;
    final List<TextSnippet> library = snippets ?? load();
    await TextSnippets.setSnippets(
        library.where((TextSnippet s) => s.enabled && s.trigger.isNotEmpty).map((TextSnippet s) => s.toMap()).toList(),
        preferences: preferences().toMap());
  }

  static Future<bool> expand() => TextSnippets.expand();

  static Future<void> _onExpansionRequested(String id, int request) async {
    try {
      final List<TextSnippet> library = load();
      final TextSnippet snippet = library.firstWhere((TextSnippet s) => s.id == id && s.enabled);
      final SnippetTemplate parsed = template(snippet, library);
      // Required inputs never disappear silently during keyword expansion.
      if (parsed.needsInput) return;
      final SnippetExpansion expansion = await render(snippet, library);
      final SnippetPreferences settings = preferences();
      await Future<void>.delayed(Duration(milliseconds: settings.delayMs));
      await TextSnippets.complete(
          request: request,
          text: expansion.text,
          cursorLeft: expansion.cursorLeft,
          characterCount: expansion.characterCount,
          html: expansion.html);
    } catch (_) {
      // Keep the original keyword intact if a template or command fails.
    } finally {
      await TextSnippets.cancel(request);
    }
  }

  static Future<Map<int, String>> clipboardFor(SnippetTemplate parsed) async {
    if (parsed.clipboardOffsets.isEmpty) return <int, String>{};
    final Map<int, String> result = <int, String>{0: await ClipboardService.instance.readText() ?? ''};
    if (parsed.clipboardOffsets.any((int offset) => offset > 0)) {
      if (!ClipboardHistoryStore.enabled)
        throw const FormatException('Enable Clipboard History to use older clipboard entries.');
      final List<ClipboardHistoryEntry> history = await ClipboardHistoryStore.loadPaged(limit: 102);
      final List<ClipboardHistoryEntry> older = history.toList();
      if (older.isNotEmpty) {
        final ClipboardHistoryEntry? newest = await ClipboardHistoryStore.getFullEntry(older.first.id);
        if (newest?.text == result[0]) older.removeAt(0);
      }
      for (final int offset in parsed.clipboardOffsets.where((int n) => n > 0)) {
        result[offset] =
            offset > older.length ? '' : (await ClipboardHistoryStore.getFullEntry(older[offset - 1].id))?.text ?? '';
      }
    }
    return result;
  }

  static Future<SnippetExpansion> render(
    TextSnippet snippet,
    List<TextSnippet> library, {
    Map<String, String> values = const <String, String>{},
    bool preview = false,
    Map<int, String>? clipboard,
  }) async {
    final SnippetTemplate parsed = template(snippet, library);
    final SnippetExpansion expansion = await parsed.render(
        values: values, clipboard: clipboard ?? await clipboardFor(parsed), preview: preview, runShell: _runShell);
    // Captured HTML belongs to the original static text. Dynamic templates use
    // the rendered plain text rather than pasting stale formatted content.
    return SnippetExpansion(expansion.text,
        cursorOffset: expansion.cursorOffset, html: parsed.isDynamic ? '' : snippet.html);
  }

  static Future<String> _runShell(String code) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      throw const FormatException('Shell placeholders are available on Windows.');
    }
    final Process process = await Process.start('powershell.exe', <String>[
      '-NoLogo',
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-Command',
      r'$OutputEncoding = [Console]::OutputEncoding = [Text.UTF8Encoding]::new(); ' + code,
    ]);
    final StringBuffer output = StringBuffer();
    int length = 0;
    bool tooLarge = false;
    bool decodingError = false;
    final Completer<void> outputDone = Completer<void>();
    final Completer<void> errorDone = Completer<void>();
    Future<void>? termination;
    Future<void> terminate() => termination ??= () async {
          try {
            await Process.run('taskkill.exe', <String>['/PID', '${process.pid}', '/T', '/F'])
                .timeout(const Duration(seconds: 1));
          } catch (_) {/* Fall back to terminating the shell directly. */}
          process.kill();
        }();
    final StreamSubscription<String> stdout = process.stdout.transform(utf8.decoder).listen((String chunk) {
      length += chunk.length;
      if (length > SnippetTemplate.maxLength) {
        tooLarge = true;
        unawaited(terminate());
      } else {
        output.write(chunk);
      }
    }, onError: (Object _) {
      decodingError = true;
      unawaited(terminate());
    }, onDone: outputDone.complete);
    final StreamSubscription<List<int>> stderr = process.stderr.listen((List<int> _) {}, onDone: errorDone.complete);
    try {
      int exit = 0;
      await Future.wait<void>(<Future<void>>[
        process.exitCode.then<void>((int value) {
          exit = value;
        }),
        outputDone.future,
        errorDone.future,
      ]).timeout(const Duration(seconds: 2));
      if (tooLarge) throw const FormatException('Shell output exceeds 256K characters.');
      if (decodingError) throw const FormatException('Shell output was not valid UTF-8 text.');
      if (exit != 0) throw FormatException('Shell command exited with code $exit.');
      return output.toString().replaceFirst(RegExp(r'[\r\n]+$'), '');
    } on TimeoutException {
      await terminate();
      throw const FormatException('Shell command exceeded its 2 second limit.');
    } finally {
      await stdout.cancel();
      await stderr.cancel();
    }
  }

  static String exportJson(List<TextSnippet> snippets) => const JsonEncoder.withIndent('  ')
      .convert(snippets.map((TextSnippet s) => <String, dynamic>{...s.toMap(), 'keyword': s.trigger}).toList());

  static SnippetImportPlan planImport(String source, List<TextSnippet> existing) {
    if (source.length > 10 * 1024 * 1024) throw const FormatException('Import files must be smaller than 10 MB.');
    final dynamic decoded = jsonDecode(source);
    final dynamic rows = decoded is Map ? decoded['snippets'] : decoded;
    if (rows is! List || rows.length > 5000)
      throw const FormatException('Expected a JSON array with at most 5,000 snippets.');
    final List<TextSnippet> imported = <TextSnippet>[];
    final List<String> issues = <String>[];
    final Set<String> rejectedReferences = <String>{};
    for (int i = 0; i < rows.length; i++) {
      try {
        final dynamic row = rows[i] is String ? jsonDecode(rows[i] as String) : rows[i];
        final TextSnippet snippet =
            TextSnippet.fromMap(row as Map<String, dynamic>).copyWith(id: const Uuid().v4(), allowShell: false);
        imported.add(snippet);
      } catch (_) {
        issues.add('Row ${i + 1}: invalid snippet data.');
      }
    }
    bool changed;
    do {
      changed = false;
      for (final TextSnippet snippet in imported.toList()) {
        final List<TextSnippet> candidates = <TextSnippet>[...existing, ...imported]
            .where((TextSnippet s) => !rejectedReferences.contains(s.name))
            .toList();
        final String? issue = rejectedReferences.contains(snippet.name)
            ? 'The import contains conflicting snippets with this name.'
            : validate(snippet, candidates);
        if (issue != null) {
          imported.remove(snippet);
          if (!existing
              .any((TextSnippet s) => s.name == snippet.name && s.text == snippet.text && s.html == snippet.html)) {
            rejectedReferences.add(snippet.name);
          }
          issues.add('${snippet.name}: $issue');
          changed = true;
        }
      }
    } while (changed);
    return SnippetImportPlan(imported, issues);
  }
}
