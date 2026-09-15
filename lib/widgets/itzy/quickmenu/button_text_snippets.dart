import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/hotkeys.dart';
import '../../../models/classes/snippet_template.dart';
import '../../../models/classes/text_snippet.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../platform/clipboard_service.dart';
import '../../../platform/file_picker_service.dart';
import '../../../platform/platform_models.dart';
import '../../../platform/windows/tabamewin32_api.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class TextSnippetsButton extends StatelessWidget {
  const TextSnippetsButton({super.key});

  @override
  Widget build(BuildContext context) => ModalButton(
        actionName: 'Text Snippets',
        icon: const Icon(Icons.short_text_rounded),
        child: () => const TextSnippetsPanel(),
      );
}

enum _SnippetView { library, editor, use, preferences, importReview }

class TextSnippetsPanel extends StatefulWidget {
  const TextSnippetsPanel({super.key});

  @override
  State<TextSnippetsPanel> createState() => _TextSnippetsPanelState();
}

class _TextSnippetsPanelState extends State<TextSnippetsPanel> {
  List<TextSnippet> _snippets = <TextSnippet>[];
  SnippetPreferences _preferences = const SnippetPreferences();
  SnippetPreferences _settingsDraft = const SnippetPreferences();
  _SnippetView _view = _SnippetView.library;
  final TextEditingController _search = TextEditingController();
  final TextEditingController _excluded = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _bodyFocus = FocusNode();
  final ScrollController _listScroll = ScrollController();
  int _highlighted = 0;
  final Map<String, TextEditingController> _fields = <String, TextEditingController>{
    for (final String field in <String>['name', 'keyword', 'text', 'tags', 'apps', 'window'])
      field: TextEditingController(),
  };
  final Map<String, TextEditingController> _argumentFields = <String, TextEditingController>{};
  List<SnippetArgument> _arguments = <SnippetArgument>[];
  TextSnippet? _draft;
  TextSnippet? _selected;
  TextSnippet? _deleted;
  int _deletedIndex = 0;
  SnippetImportPlan? _importPlan;
  SnippetExpansion? _preview;
  String _previewError = '';
  String? _tag;
  bool _pinnedOnly = false;
  bool _busy = false;
  bool _loadFailed = false;
  bool _syncing = false;
  String _message = '';
  bool _messageIsError = false;
  Timer? _previewTimer;
  int _previewRequest = 0;
  late final int _targetWindow;
  Map<int, String> _clipboard = <int, String>{};

  static const Map<String, String> _placeholders = <String, String>{
    'Date': '{date}',
    'Time': '{time}',
    'Date & time': '{datetime}',
    'Weekday': '{day}',
    'ISO date': '{date format="yyyy-MM-dd"}',
    'Tomorrow': '{date offset="+1d"}',
    'Clipboard': '{clipboard}',
    'Previous clipboard': '{clipboard offset=1}',
    'UUID': '{uuid}',
    'Cursor position': '{cursor}',
    'Input field': '{argument name="name"}',
    'Optional input': '{argument name="name" default="friend"}',
    'Choice': '{argument name="tone" options="friendly,formal" default="friendly"}',
    'Nested snippet': '{snippet name="Signature"}',
    'Trim + uppercase': '{clipboard | trim | uppercase}',
    'URL encode': '{clipboard | percent-encode}',
    'JSON string': '{clipboard | json-stringify}',
    'Calculator': '{calculator expression="(120 * 1.2) / 4"}',
    'PowerShell': '{shell code="Get-Date -Format yyyy-MM-dd"}',
  };

  @override
  void initState() {
    super.initState();
    _targetWindow = Globals.lastFocusedWinHWND;
    _load();
    _search.addListener(() {
      _highlighted = 0;
      _refresh();
    });
    _searchFocus.addListener(_refresh);
    for (final TextEditingController field in _fields.values) {
      field.addListener(_draftChanged);
    }
  }

  void _load() {
    try {
      _snippets = TextSnippetsManager.load();
      _preferences = TextSnippetsManager.preferences();
      _loadFailed = false;
    } catch (error) {
      _loadFailed = true;
      _message = 'Could not read the snippet library. Saved data has been kept. $error';
      _messageIsError = true;
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _search.dispose();
    _excluded.dispose();
    _searchFocus.dispose();
    _bodyFocus.dispose();
    _listScroll.dispose();
    for (final TextEditingController field in <TextEditingController>[..._fields.values, ..._argumentFields.values]) {
      field.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = '';
    });
    try {
      await action();
    } catch (error) {
      if (mounted)
        setState(() {
          _message = error is FormatException ? error.message : error.toString();
          _messageIsError = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message, {bool canUndo = false}) {
    if (mounted)
      setState(() {
        _message = message;
        _messageIsError = false;
        if (!canUndo) _deleted = null;
      });
  }

  List<TextSnippet> get _filtered {
    final List<TextSnippet> results = _snippets
        .where((TextSnippet s) =>
            s.matches(_search.text) && (_tag == null || s.tags.contains(_tag)) && (!_pinnedOnly || s.pinned))
        .toList();
    results.sort((TextSnippet a, TextSnippet b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return results;
  }

  double get _rowExtent => MediaQuery.textScalerOf(context).scale(Design.baseFontSize + 2) * 4 + 26;

  void _moveHighlight(int delta) {
    final int count = _filtered.length;
    if (count == 0) return;
    setState(() => _highlighted = (_highlighted + delta).clamp(0, count - 1));
    if (_listScroll.hasClients) {
      final double top = _highlighted * _rowExtent;
      final double bottom = top + _rowExtent;
      final double offset = _listScroll.offset;
      final double viewport = _listScroll.position.viewportDimension;
      if (top < offset || bottom > offset + viewport) {
        _listScroll.jumpTo((top < offset ? top : bottom - viewport).clamp(0.0, _listScroll.position.maxScrollExtent));
      }
    }
  }

  String _uniqueName(String base) {
    String name = base;
    int suffix = 2;
    while (_snippets.any((TextSnippet s) => s.name.toLowerCase() == name.toLowerCase())) {
      name = '$base ${suffix++}';
    }
    return name;
  }

  void _edit([TextSnippet? snippet]) {
    if (_busy || _loadFailed) return;
    for (final TextEditingController field in _argumentFields.values) {
      field.dispose();
    }
    _argumentFields.clear();
    _arguments = <SnippetArgument>[];
    _syncing = true;
    _draft = snippet ?? TextSnippet(name: '', trigger: '', text: '');
    _fields['name']!.text = _draft!.name;
    _fields['keyword']!.text = _draft!.trigger;
    _fields['text']!.text = _draft!.text;
    _fields['tags']!.text = _draft!.tags.join(', ');
    _fields['apps']!.text = _draft!.apps.join(', ');
    _fields['window']!.text = _draft!.windowTitle;
    _syncing = false;
    setState(() {
      _view = _SnippetView.editor;
      _message = '';
      _preview = null;
      _previewError = '';
    });
    _schedulePreview();
  }

  List<String> _csv(String value) =>
      value.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toSet().toList();

  TextSnippet get _edited => _draft!.copyWith(
      name: _fields['name']!.text.trim(),
      trigger: _fields['keyword']!.text.trim(),
      text: _fields['text']!.text,
      tags: _csv(_fields['tags']!.text),
      apps: _csv(_fields['apps']!.text),
      windowTitle: _fields['window']!.text.trim());

  List<TextSnippet> _withDraft(TextSnippet snippet) => <TextSnippet>[
        ..._snippets.where((TextSnippet s) => s.id != snippet.id),
        snippet,
      ];

  void _draftChanged() {
    if (_syncing || _view != _SnippetView.editor) return;
    if (_draft!.html.isNotEmpty && _fields['text']!.text != _draft!.text) _draft = _draft!.copyWith(html: '');
    _refresh();
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    final int request = ++_previewRequest;
    _previewTimer = Timer(const Duration(milliseconds: 180), () async {
      try {
        final TextSnippet snippet = _view == _SnippetView.editor ? _edited : _selected!;
        final List<TextSnippet> library = _view == _SnippetView.editor ? _withDraft(snippet) : _snippets;
        final SnippetTemplate parsed = TextSnippetsManager.template(snippet, library);
        final Map<int, String> clipboard =
            _view == _SnippetView.editor ? await TextSnippetsManager.clipboardFor(parsed) : _clipboard;
        final SnippetExpansion preview =
            await parsed.render(preview: true, clipboard: clipboard, values: <String, String>{
          for (final MapEntry<String, TextEditingController> entry in _argumentFields.entries)
            if (entry.value.text.isNotEmpty) entry.key: entry.value.text
        });
        if (!mounted || request != _previewRequest) return;
        setState(() {
          _preview = preview;
          _previewError = '';
        });
      } catch (error) {
        if (!mounted || request != _previewRequest) return;
        setState(() {
          _preview = null;
          _previewError = error is FormatException ? error.message : '$error';
        });
      }
    });
  }

  void _back() {
    if (_busy) return;
    _previewTimer?.cancel();
    ++_previewRequest;
    setState(() {
      _view = _SnippetView.library;
      _message = '';
    });
  }

  Future<void> _persist(List<TextSnippet> snippets) async {
    try {
      await TextSnippetsManager.save(snippets);
    } catch (_) {
      if (mounted) setState(() => _snippets = TextSnippetsManager.load());
      rethrow;
    }
    if (mounted)
      setState(() {
        _snippets = snippets;
        if (_tag != null && !snippets.any((TextSnippet s) => s.tags.contains(_tag))) _tag = null;
      });
  }

  Future<void> _saveEdit() => _run(() async {
        final TextSnippet snippet = _edited;
        final List<TextSnippet> next = _withDraft(snippet);
        final String? issue = TextSnippetsManager.validate(snippet, next);
        if (issue != null) throw FormatException(issue);
        // Catch renames or edits that break a referencing template before saving.
        for (final TextSnippet other in next) {
          TextSnippetsManager.template(other, next);
        }
        await _persist(next);
        if (mounted) setState(() => _view = _SnippetView.library);
        _notice('Saved ${snippet.name}.');
      });

  Future<void> _replace(TextSnippet snippet) => _run(() async {
        final List<TextSnippet> next = _snippets.map((TextSnippet s) => s.id == snippet.id ? snippet : s).toList();
        final String? issue = TextSnippetsManager.validate(snippet, next);
        if (issue != null) throw FormatException(issue);
        await _persist(next);
      });

  Future<void> _delete(TextSnippet snippet) => _run(() async {
        final List<TextSnippet> next = _snippets.where((TextSnippet s) => s.id != snippet.id).toList();
        for (final TextSnippet other in next) {
          try {
            TextSnippetsManager.template(other, next);
          } on FormatException {
            throw FormatException('Update references in "${other.name}" before deleting this snippet.');
          }
        }
        final int index = _snippets.indexOf(snippet);
        await _persist(next);
        _deleted = snippet;
        _deletedIndex = index;
        _notice('Deleted ${snippet.name}.', canUndo: true);
      });

  Future<void> _undoDelete() => _run(() async {
        if (_deleted == null) return;
        final List<TextSnippet> next = <TextSnippet>[..._snippets]
          ..insert(_deletedIndex.clamp(0, _snippets.length), _deleted!);
        final String? issue = TextSnippetsManager.validate(_deleted!, next);
        if (issue != null) throw FormatException(issue);
        await _persist(next);
        _deleted = null;
        _notice('Snippet restored.');
      });

  void _duplicate(TextSnippet snippet) => _edit(TextSnippet(
      name: _uniqueName('${snippet.name} copy'),
      trigger: '',
      text: snippet.text,
      tags: snippet.tags,
      caseSensitive: snippet.caseSensitive,
      wordBoundary: snippet.wordBoundary,
      appMode: snippet.appMode,
      apps: snippet.apps,
      windowTitle: snippet.windowTitle,
      html: snippet.html,
      templateEnabled: snippet.templateEnabled));

  Future<void> _openUse(TextSnippet snippet) => _run(() async {
        final SnippetTemplate parsed = TextSnippetsManager.template(snippet, _snippets);
        final Map<int, String> clipboard = await TextSnippetsManager.clipboardFor(parsed);
        if (!mounted) return;
        for (final TextEditingController field in _argumentFields.values) {
          field.dispose();
        }
        _argumentFields.clear();
        _arguments = parsed.arguments;
        for (final SnippetArgument argument in _arguments) {
          _argumentFields[argument.name] = TextEditingController(text: argument.defaultValue ?? '')
            ..addListener(_schedulePreview);
        }
        setState(() {
          _selected = snippet;
          _clipboard = clipboard;
          _view = _SnippetView.use;
          _preview = null;
          _previewError = '';
        });
        _schedulePreview();
      });

  Future<void> _quickUse(TextSnippet snippet, {required bool paste}) async {
    try {
      if (TextSnippetsManager.template(snippet, _snippets).arguments.isNotEmpty) {
        await _openUse(snippet);
        return;
      }
    } catch (_) {
      await _openUse(snippet);
      return;
    }
    await _use(snippet, paste: paste);
  }

  Future<void> _use(TextSnippet snippet, {required bool paste, bool fromForm = false}) => _run(() async {
        if (paste && (!Platform.isWindows || _targetWindow == 0))
          throw const FormatException('Open Snippets from the app where you want to paste, or use Copy.');
        final SnippetExpansion expansion = await TextSnippetsManager.render(snippet, _snippets,
            values: fromForm
                ? <String, String>{
                    for (final MapEntry<String, TextEditingController> entry in _argumentFields.entries)
                      entry.key: entry.value.text
                  }
                : const <String, String>{},
            clipboard: fromForm ? _clipboard : null);
        if (!paste) {
          final bool copied = expansion.html.isNotEmpty && Platform.isWindows
              ? await TextSnippets.copyRichText(expansion.text, expansion.html)
              : await ClipboardService.instance
                  .writeContent(PlatformClipboardContent(text: expansion.text, html: expansion.html));
          if (!copied) throw const FormatException('Could not copy to the clipboard. Try again.');
          _notice('Copied ${snippet.name}.');
          return;
        }
        await QuickMenuFunctions.hideQuickMenu(launcherActivateLastWin: false);
        Win32.activateWindow(_targetWindow);
        await Future<void>.delayed(const Duration(milliseconds: 80));
        final bool pasted = await TextSnippets.paste(
            target: _targetWindow,
            text: expansion.text,
            cursorLeft: expansion.cursorLeft,
            characterCount: expansion.characterCount,
            html: expansion.html);
        if (!pasted) {
          await Future<void>.delayed(const Duration(milliseconds: 180));
          await QuickMenuFunctions.toggleQuickMenu(visible: true);
          throw const FormatException('The target app could not accept the paste. Check app exclusions or use Copy.');
        }
      });

  void _insertPlaceholder(String value) {
    _draft = _draft!.copyWith(templateEnabled: true);
    final TextEditingController field = _fields['text']!;
    final TextSelection selection = field.selection;
    int start = selection.isValid ? selection.start : field.text.length;
    final int end = selection.isValid ? selection.end : field.text.length;
    if (start == end && start > 0 && field.text[start - 1] == '{') start--;
    field.value = TextEditingValue(
        text: field.text.replaceRange(start, end, value),
        selection: TextSelection.collapsed(offset: start + value.length));
    _bodyFocus.requestFocus();
  }

  Future<void> _fromClipboard() async {
    try {
      final PlatformClipboardContent? content = await ClipboardService.instance.readContent();
      if (!mounted || _busy) return;
      _edit(TextSnippet(
          name: _uniqueName('Clipboard snippet'),
          trigger: '',
          text: content?.text ?? '',
          html: TextSnippet.htmlFragment(content?.html ?? ''),
          templateEnabled: false));
    } catch (error) {
      if (mounted)
        setState(() {
          _message = 'Could not read the clipboard: $error';
          _messageIsError = true;
        });
    }
  }

  Future<void> _import() => _run(() async {
        final bool keepOpen = QuickMenuFunctions.keepOpen;
        QuickMenuFunctions.keepOpen = true;
        try {
          final OpenFilePicker picker = OpenFilePicker()
            ..title = 'Import snippets'
            ..filterSpecification = <String, String>{'Snippet JSON': '*.json'};
          final File? file = await picker.getFileAsync();
          if (file == null) return;
          if (await file.length() > 10 * 1024 * 1024)
            throw const FormatException('Import files must be smaller than 10 MB.');
          final SnippetImportPlan plan = TextSnippetsManager.planImport(await file.readAsString(), _snippets);
          if (mounted)
            setState(() {
              _importPlan = plan;
              _view = _SnippetView.importReview;
            });
        } finally {
          QuickMenuFunctions.keepOpen = keepOpen;
        }
      });

  Future<void> _export() => _run(() async {
        final bool keepOpen = QuickMenuFunctions.keepOpen;
        QuickMenuFunctions.keepOpen = true;
        try {
          final SaveFilePicker picker = SaveFilePicker()
            ..title = 'Export snippets'
            ..fileName = 'tabame-snippets.json'
            ..defaultExtension = 'json'
            ..filterSpecification = <String, String>{'Snippet JSON': '*.json'};
          final File? file = await picker.getFileAsync();
          if (file == null) return;
          await file.writeAsString(TextSnippetsManager.exportJson(_snippets), flush: true);
          _notice('Exported ${_snippets.length} snippets.');
        } finally {
          QuickMenuFunctions.keepOpen = keepOpen;
        }
      });

  void _openSettings() {
    _settingsDraft = _preferences;
    _excluded.text = _preferences.excludedApps.join(', ');
    setState(() {
      _view = _SnippetView.preferences;
      _message = '';
    });
  }

  void _setPreference(String key, dynamic value) => setState(() {
        _settingsDraft = SnippetPreferences.fromMap(<String, dynamic>{..._settingsDraft.toMap(), key: value});
      });

  Future<void> _savePreferences(SnippetPreferences value) => _run(() async {
        await TextSnippetsManager.savePreferences(value);
        if (mounted)
          setState(() {
            _preferences = value;
            _view = _SnippetView.library;
          });
        _notice('Expansion settings saved.');
      });

  String get _hotkey {
    for (final Hotkeys hotkey in Boxes.remap) {
      for (final KeyMap map in hotkey.keymaps) {
        if (map.actions.any((KeyAction a) => a.type == ActionType.tabameFunction && a.value == 'ExpandSnippet'))
          return hotkey.displayHotkey;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) => Focus(
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape && _view != _SnippetView.library) {
            _back();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => _edit(),
              const SingleActivator(LogicalKeyboardKey.keyF, control: true): () {
                if (_view == _SnippetView.library) _searchFocus.requestFocus();
              },
              const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
                if (_view == _SnippetView.editor) {
                  _saveEdit();
                } else if (_view == _SnippetView.use) {
                  _use(_selected!, paste: true, fromForm: true);
                }
              },
            },
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  PanelHeader(
                      title: switch (_view) {
                        _SnippetView.library => 'Snippets',
                        _SnippetView.editor =>
                          _snippets.any((TextSnippet s) => s.id == _draft?.id) ? 'Edit snippet' : 'New snippet',
                        _SnippetView.use => _selected?.name ?? 'Use snippet',
                        _SnippetView.preferences => 'Expansion settings',
                        _SnippetView.importReview => 'Review import',
                      },
                      icon: Icons.short_text_rounded,
                      buttonPressed: _busy || _loadFailed
                          ? null
                          : _view == _SnippetView.library
                              ? () => _edit()
                              : _back,
                      buttonIcon: _view == _SnippetView.library ? Icons.add_rounded : Icons.arrow_back_rounded,
                      buttonTooltip: _view == _SnippetView.library ? 'New snippet · Ctrl+N' : 'Back · Esc',
                      extraActions: _view == _SnippetView.library
                          ? <Widget>[
                              IconButton(
                                  onPressed: _busy || _loadFailed ? null : _openSettings,
                                  icon: const Icon(Icons.tune_rounded),
                                  tooltip: 'Expansion settings'),
                              PopupMenuButton<String>(
                                  enabled: !_busy && !_loadFailed,
                                  tooltip: 'Library actions',
                                  icon: const Icon(Icons.more_horiz_rounded),
                                  onSelected: (String action) {
                                    switch (action) {
                                      case 'clipboard':
                                        _fromClipboard();
                                      case 'import':
                                        _import();
                                      case 'export':
                                        _export();
                                    }
                                  },
                                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                        const PopupMenuItem<String>(
                                            value: 'clipboard', child: Text('Create from clipboard')),
                                        const PopupMenuItem<String>(value: 'import', child: Text('Import JSON…')),
                                        const PopupMenuItem<String>(value: 'export', child: Text('Export JSON…')),
                                      ]),
                            ]
                          : null),
                  if (_busy)
                    LinearProgressIndicator(
                        minHeight: 2, color: Design.accent, backgroundColor: Design.accent.withAlpha(15)),
                  if (_message.isNotEmpty) _messageStrip(),
                  Flexible(
                      child: Material(
                          type: MaterialType.transparency,
                          child: KeyedSubtree(
                              key: ValueKey<String>('$_view:${_selected?.id}:${_draft?.id}'),
                              child: switch (_view) {
                                _SnippetView.library => _buildLibrary(),
                                _SnippetView.editor => _buildEditor(),
                                _SnippetView.use => _buildUse(),
                                _SnippetView.preferences => _buildPreferences(),
                                _SnippetView.importReview => _buildImport(),
                              }))),
                ])),
      );

  Widget _messageStrip() => Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      color: (_messageIsError ? Colors.redAccent : Design.accent).withAlpha(12),
      child: Row(children: <Widget>[
        Icon(_messageIsError ? Icons.error_outline_rounded : Icons.check_rounded,
            size: 15, color: _messageIsError ? Colors.redAccent : Design.accent),
        const SizedBox(width: 7),
        Expanded(
            child: Text(_message,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text))),
        if (_deleted != null && !_messageIsError)
          TextButton(onPressed: _busy ? null : _undoDelete, child: const Text('Undo')),
        IconButton(
            onPressed: () => setState(() => _message = ''),
            tooltip: 'Dismiss',
            icon: const Icon(Icons.close_rounded, size: 14)),
      ]));

  Widget _buildLibrary() {
    final List<TextSnippet> results = _filtered;
    final List<String> tags = _snippets.expand((TextSnippet s) => s.tags).toSet().toList()..sort();
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: CallbackShortcuts(
              bindings: <ShortcutActivator, VoidCallback>{
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => _moveHighlight(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => _moveHighlight(-1),
              },
              child: _field(_search, 'Search name, keyword, text, or tag…',
                  focus: _searchFocus, autofocus: true, icon: Icons.search_rounded, onSubmitted: (String _) {
                if (results.isNotEmpty)
                  _quickUse(results[_highlighted.clamp(0, results.length - 1)], paste: Platform.isWindows);
              }))),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(children: <Widget>[
            Expanded(
                child: DropdownButton<String>(
                    value: _tag ?? '',
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
                    items: <DropdownMenuItem<String>>[
                      DropdownMenuItem<String>(value: '', child: Text('All tags · ${_snippets.length}')),
                      ...tags.map((String tag) =>
                          DropdownMenuItem<String>(value: tag, child: Text(tag, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (String? value) => setState(() {
                          _tag = value == '' ? null : value;
                          _highlighted = 0;
                        }))),
            const SizedBox(width: 8),
            FilterChip(
                label: const Text('Pinned'),
                selected: _pinnedOnly,
                visualDensity: VisualDensity.compact,
                selectedColor: Design.accent.withAlpha(18),
                onSelected: (bool value) => setState(() {
                      _pinnedOnly = value;
                      _highlighted = 0;
                    })),
          ])),
      Flexible(
          child: results.isEmpty
              ? _emptyLibrary()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  controller: _listScroll,
                  itemExtent: _rowExtent,
                  itemCount: results.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _snippetRow(results[index], highlighted: _searchFocus.hasFocus && index == _highlighted))),
      Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
          child: Row(children: <Widget>[
            Icon(Icons.keyboard_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 7),
            Expanded(
                child: Text(
                    !Platform.isWindows
                        ? 'Copy snippets on this platform'
                        : _preferences.autoExpand
                            ? 'Keyword expansion on'
                            : _hotkey.isEmpty
                                ? 'Auto-expansion off · set up in settings'
                                : 'Manual expansion · $_hotkey',
                    style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(170)))),
            if (Platform.isWindows)
              MiniToggleSwitch(
                  value: _preferences.autoExpand,
                  onChanged: (bool value) {
                    if (!_busy && !_loadFailed)
                      _savePreferences(
                          SnippetPreferences.fromMap(<String, dynamic>{..._preferences.toMap(), 'autoExpand': value}));
                  }),
          ])),
    ]);
  }

  Widget _snippetRow(TextSnippet snippet, {bool highlighted = false}) => Container(
        margin: const EdgeInsets.only(bottom: 5),
        decoration: BoxDecoration(
            color: highlighted ? Design.accent.withAlpha(15) : Design.text.withAlpha(7),
            border: Border.all(color: highlighted ? Design.accent.withAlpha(75) : Design.text.withAlpha(16)),
            borderRadius: BorderRadius.circular(9)),
        child: InkWell(
            onTap: _busy ? null : () => _openUse(snippet),
            borderRadius: BorderRadius.circular(9),
            hoverColor: Design.accent.withAlpha(15),
            child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 7, 3, 7),
                child: Row(children: <Widget>[
                  _iconButton(snippet.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      snippet.pinned ? 'Unpin' : 'Pin', () => _replace(snippet.copyWith(pinned: !snippet.pinned)),
                      active: snippet.pinned),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                        Text(snippet.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 2,
                                fontWeight: FontWeight.w600,
                                color: Design.text.withAlpha(snippet.enabled ? 240 : 130))),
                        const SizedBox(height: 3),
                        Text(snippet.text.replaceAll(RegExp(r'\s+'), ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(130))),
                        if (snippet.trigger.isNotEmpty ||
                            snippet.tags.isNotEmpty ||
                            snippet.html.isNotEmpty ||
                            !snippet.enabled) ...<Widget>[
                          const SizedBox(height: 5),
                          Text(
                              <String>[
                                if (snippet.trigger.isNotEmpty) snippet.trigger,
                                ...snippet.tags.map((String tag) => '#$tag'),
                                if (snippet.html.isNotEmpty) 'formatted',
                                if (!snippet.enabled) 'expansion paused'
                              ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent.withAlpha(200))),
                        ],
                      ])),
                  _iconButton(Icons.copy_rounded, 'Copy expanded text', () => _quickUse(snippet, paste: false)),
                  if (Platform.isWindows)
                    _iconButton(Icons.input_rounded, 'Paste into previous app', () => _quickUse(snippet, paste: true)),
                  PopupMenuButton<String>(
                      enabled: !_busy,
                      tooltip: 'Snippet actions',
                      icon: Icon(Icons.more_vert_rounded, size: 16, color: Design.text.withAlpha(170)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 170),
                      onSelected: (String action) {
                        switch (action) {
                          case 'edit':
                            _edit(snippet);
                          case 'duplicate':
                            _duplicate(snippet);
                          case 'toggle':
                            _replace(snippet.copyWith(enabled: !snippet.enabled));
                          case 'delete':
                            _delete(snippet);
                          case 'raw':
                            _run(() async {
                              if (!await ClipboardService.instance.writeText(snippet.text))
                                throw const FormatException('Could not copy the template.');
                              _notice('Copied template text.');
                            });
                        }
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(value: 'edit', child: Text('Edit')),
                            const PopupMenuItem<String>(value: 'duplicate', child: Text('Duplicate')),
                            const PopupMenuItem<String>(value: 'raw', child: Text('Copy template')),
                            PopupMenuItem<String>(
                                value: 'toggle', child: Text(snippet.enabled ? 'Pause expansion' : 'Enable expansion')),
                            const PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
                          ]),
                ]))),
      );

  Widget _emptyLibrary() => WindowsScrollView(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(Icons.short_text_rounded, size: 34, color: Design.accent.withAlpha(140)),
            const SizedBox(height: 10),
            Text(
                _loadFailed
                    ? 'Library unavailable'
                    : _snippets.isEmpty
                        ? 'Your words, a few keys away'
                        : 'No matching snippets',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 3, fontWeight: FontWeight.w600, color: Design.text)),
            const SizedBox(height: 6),
            Text(_snippets.isEmpty ? 'Save replies, addresses, code, and templates.' : 'Try another search or tag.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150))),
            const SizedBox(height: 12),
            if (!_loadFailed && _snippets.isEmpty)
              Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: <Widget>[
                OutlinedButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add_rounded, size: 15),
                    label: const Text('Create snippet')),
                TextButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.file_download_outlined, size: 15),
                    label: const Text('Import JSON')),
                _starterMenu(),
              ]),
            if (_loadFailed) TextButton(onPressed: () => setState(_load), child: const Text('Retry')),
          ])));

  Widget _starterMenu() => PopupMenuButton<String>(
      tooltip: 'Start from a template',
      onSelected: (String name) {
        final Map<String, String> examples = <String, String>{
          'Email reply': 'Hi {argument name="name"},\n\nThanks for reaching out. {cursor}\n\nBest regards',
          'Meeting notes':
              '# {argument name="meeting" default="Meeting"}\n{date format="yyyy-MM-dd"} · {time}\n\nAttendees\n{cursor}\n\nActions\n',
          'Code log': 'console.log({cursor});',
          'Clipboard as JSON': '{clipboard | trim | json-stringify}',
          'Follow-up date': 'Let’s follow up on {date offset="+1w" format="EEEE, MMM d"}.',
          'New UUID': '{uuid}',
        };
        _edit(TextSnippet(
            name: _uniqueName(name), trigger: '', text: examples[name]!, tags: const <String>['templates']));
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            for (final String name in <String>[
              'Email reply',
              'Meeting notes',
              'Code log',
              'Clipboard as JSON',
              'Follow-up date',
              'New UUID'
            ])
              PopupMenuItem<String>(value: name, child: Text(name)),
          ],
      child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text('Use a starter template', style: TextStyle(color: Design.accent))));

  Widget _buildEditor() => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Flexible(
            child: WindowsScrollView(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      if (_fields['text']!.text.isEmpty) Align(alignment: Alignment.centerLeft, child: _starterMenu()),
                      _label('Name'),
                      _field(_fields['name']!, 'e.g. Support reply', autofocus: true),
                      const SizedBox(height: 10),
                      _label('Keyword · optional'),
                      _field(_fields['keyword']!, 'e.g. ;reply'),
                      const SizedBox(height: 10),
                      Row(children: <Widget>[
                        Expanded(child: _label('Template')),
                        PopupMenuButton<String>(
                            tooltip: 'Insert a dynamic placeholder',
                            onSelected: _insertPlaceholder,
                            itemBuilder: (BuildContext context) => _placeholders.entries
                                .map((MapEntry<String, String> entry) =>
                                    PopupMenuItem<String>(value: entry.value, child: Text(entry.key)))
                                .toList(),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                child: Text('{ } Insert placeholder',
                                    style: TextStyle(color: Design.accent, fontSize: Design.baseFontSize + 1)))),
                      ]),
                      _field(_fields['text']!, 'Write your snippet. Type { to add dynamic content.',
                          minLines: 5, maxLines: 12, focus: _bodyFocus, monospace: true),
                      if (_draft!.html.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                            'Clipboard formatting is preserved. Editing the text or using placeholders pastes plain text.',
                            style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                                onPressed: () => setState(() => _draft = _draft!.copyWith(html: '')),
                                child: const Text('Clear formatting'))),
                      ],
                      if (_fields['text']!.selection.isValid &&
                          _fields['text']!.selection.baseOffset > 0 &&
                          _fields['text']!.text[_fields['text']!.selection.baseOffset - 1] == '{')
                        Wrap(
                            spacing: 5,
                            children: _placeholders.entries
                                .take(10)
                                .map((MapEntry<String, String> entry) => ActionChip(
                                    label: Text(entry.key),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => _insertPlaceholder(entry.value)))
                                .toList()),
                      const SizedBox(height: 10),
                      _previewCard(),
                      const SizedBox(height: 10),
                      _label('Tags · comma separated'),
                      _field(_fields['tags']!, 'work, support, code'),
                      const SizedBox(height: 10),
                      _card(Column(children: <Widget>[
                        _toggleRow(
                            'Dynamic placeholders',
                            'Expand dates, clipboard text, inputs, and other placeholders.',
                            _draft!.templateEnabled, (bool value) {
                          setState(() => _draft = _draft!.copyWith(templateEnabled: value));
                          _schedulePreview();
                        }),
                        _toggleRow('Match case', 'Treat ;Mail and ;mail as different keywords.', _draft!.caseSensitive,
                            (bool value) => setState(() => _draft = _draft!.copyWith(caseSensitive: value))),
                        _toggleRow('Whole keyword', 'Only expand at the start of a word.', _draft!.wordBoundary,
                            (bool value) => setState(() => _draft = _draft!.copyWith(wordBoundary: value))),
                        _toggleRow('Enable expansion', 'Keep this snippet available for keyword expansion.',
                            _draft!.enabled, (bool value) => setState(() => _draft = _draft!.copyWith(enabled: value))),
                      ])),
                      const SizedBox(height: 10),
                      _label('Keyword expansion · application rules'),
                      _dropdown(
                          _draft!.appMode,
                          const <String, String>{
                            'any': 'All applications',
                            'only': 'Only these applications',
                            'except': 'Except these applications'
                          },
                          (String value) => setState(() => _draft = _draft!.copyWith(appMode: value))),
                      if (_draft!.appMode != 'any') ...<Widget>[
                        const SizedBox(height: 7),
                        _field(_fields['apps']!, 'code.exe, notepad.exe')
                      ],
                      const SizedBox(height: 8),
                      _field(_fields['window']!, 'Window title contains… (optional)'),
                      const SizedBox(height: 10),
                      if (_fields['text']!.text.contains('{shell'))
                        _card(_toggleRow(
                            'Allow shell commands',
                            'Runs PowerShell as your user on use, with a 2 second limit. Preview never runs commands.',
                            _draft!.allowShell, (bool value) {
                          setState(() => _draft = _draft!.copyWith(allowShell: value));
                          _schedulePreview();
                        })),
                      const SizedBox(height: 8),
                      Text(
                          'Inputs without defaults are filled in from the library. Escape a literal placeholder with \\{. Text limit: 65,536 characters.',
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
                    ])))),
        _footer(<Widget>[
          Expanded(child: _action('Cancel', _back)),
          const SizedBox(width: 8),
          Expanded(child: _action('Save snippet', _saveEdit, primary: true))
        ]),
      ]);

  Widget _buildUse() => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Flexible(
            child: WindowsScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      if (_arguments.isNotEmpty) ...<Widget>[
                        Text('Fill in this template',
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600, color: Design.text)),
                        const SizedBox(height: 10),
                        for (final SnippetArgument argument in _arguments) ...<Widget>[
                          _label('${argument.name}${argument.defaultValue == null ? ' · required' : ' · optional'}'),
                          if (argument.options.isEmpty)
                            _field(_argumentFields[argument.name]!, argument.defaultValue ?? 'Enter ${argument.name}',
                                autofocus: argument == _arguments.first)
                          else
                            DropdownButtonFormField<String>(
                                initialValue: _argumentFields[argument.name]!.text.isEmpty
                                    ? null
                                    : _argumentFields[argument.name]!.text,
                                isExpanded: true,
                                decoration: _decoration('Choose ${argument.name}'),
                                items: argument.options
                                    .map((String value) => DropdownMenuItem<String>(value: value, child: Text(value)))
                                    .toList(),
                                onChanged: (String? value) => _argumentFields[argument.name]!.text = value ?? ''),
                          const SizedBox(height: 12),
                        ],
                      ],
                      _previewCard(),
                      const SizedBox(height: 10),
                      Text(
                          _selected!.trigger.isEmpty ? 'Available from the library.' : 'Keyword: ${_selected!.trigger}',
                          style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150))),
                      if (_selected!.tags.isNotEmpty)
                        Text(_selected!.tags.map((String tag) => '#$tag').join('  '),
                            style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
                    ])))),
        _footer(<Widget>[
          _iconButton(Icons.edit_rounded, 'Edit template', () => _edit(_selected)),
          Expanded(child: _action('Copy', () => _use(_selected!, paste: false, fromForm: true))),
          if (Platform.isWindows) ...<Widget>[
            const SizedBox(width: 8),
            Expanded(
                child:
                    _action('Paste · Ctrl+Enter', () => _use(_selected!, paste: true, fromForm: true), primary: true))
          ],
        ]),
      ]);

  Widget _previewCard() {
    final SnippetExpansion? preview = _preview;
    final int cursor = preview?.cursorOffset ?? -1;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: _label('Live preview')),
        if (preview != null)
          Text('${preview.characterCount} characters',
              style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(120)))
      ]),
      if (_previewError.isNotEmpty)
        Text(_previewError, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent))
      else if (preview == null)
        Text('Preparing preview…',
            style: TextStyle(color: Design.text.withAlpha(130), fontSize: Design.baseFontSize + 1))
      else
        SelectableText.rich(
            TextSpan(
                style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: Design.text.withAlpha(210)),
                children: <InlineSpan>[
                  TextSpan(text: cursor < 0 ? preview.text : preview.text.substring(0, cursor)),
                  if (cursor >= 0) ...<InlineSpan>[
                    TextSpan(text: '│', style: TextStyle(color: Design.accent, fontWeight: FontWeight.w700)),
                    TextSpan(text: preview.text.substring(cursor))
                  ],
                ]),
            maxLines: 12),
    ]));
  }

  Widget _buildPreferences() => Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Flexible(
            child: WindowsScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                      _card(_toggleRow('Automatic expansion', 'Expand keywords as you type in other applications.',
                          _settingsDraft.autoExpand, (bool value) => _setPreference('autoExpand', value))),
                      const SizedBox(height: 12),
                      _label('Expand keywords'),
                      _dropdown(
                          _settingsDraft.mode,
                          const <String, String>{
                            'immediate': 'Immediately',
                            'delimiterKeep': 'After space/punctuation · keep delimiter',
                            'delimiterDiscard': 'After space/punctuation · discard delimiter',
                          },
                          (String value) => _setPreference('mode', value)),
                      const SizedBox(height: 12),
                      _label('Wait before expanding · ${_settingsDraft.delayMs} ms'),
                      Slider(
                          value: _settingsDraft.delayMs.toDouble(),
                          max: 1000,
                          divisions: 100,
                          label: '${_settingsDraft.delayMs} ms',
                          onChanged: (double value) => _setPreference('delayMs', value.round())),
                      _label('App paste delay · ${_settingsDraft.pasteDelayMs} ms'),
                      Slider(
                          value: _settingsDraft.pasteDelayMs.toDouble(),
                          min: 30,
                          max: 1000,
                          divisions: 97,
                          label: '${_settingsDraft.pasteDelayMs} ms',
                          onChanged: (double value) => _setPreference('pasteDelayMs', value.round())),
                      Text('Increase the paste delay if cursor placement is too early in a slower app.',
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
                      const SizedBox(height: 12),
                      _card(Column(children: <Widget>[
                        _toggleRow(
                            'Restore clipboard',
                            'Restore its previous formats after pasting, unless you copy something else.',
                            _settingsDraft.restoreClipboard,
                            (bool value) => _setPreference('restoreClipboard', value)),
                        _toggleRow(
                            'Escape to undo',
                            'Restore the keyword after a short, single-line expansion. Typing or moving the mouse cancels undo.',
                            _settingsDraft.undoOnEscape,
                            (bool value) => _setPreference('undoOnEscape', value)),
                        _toggleRow('Completion sound', 'Play the system sound after an expansion.',
                            _settingsDraft.completionSound, (bool value) => _setPreference('completionSound', value)),
                      ])),
                      const SizedBox(height: 12),
                      _label('Excluded applications'),
                      _field(_excluded, '1password.exe, keepass.exe', minLines: 2, maxLines: 4),
                      const SizedBox(height: 6),
                      Text(
                          'Use executable names separated by commas. App exclusions also apply to manual pasting. Enter and Tab remain navigation keys.',
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(140))),
                      const SizedBox(height: 12),
                      _card(Text(
                          _hotkey.isEmpty
                              ? 'For manual keyword expansion, bind “Insert snippet” in Interface → Hotkeys.'
                              : 'Manual expansion: type a keyword, then press $_hotkey.',
                          style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(180)))),
                    ])))),
        _footer(<Widget>[
          Expanded(
              child: _action(
                  'Save settings',
                  () => _savePreferences(SnippetPreferences.fromMap(
                      <String, dynamic>{..._settingsDraft.toMap(), 'excludedApps': _csv(_excluded.text)})),
                  primary: true))
        ]),
      ]);

  Widget _buildImport() {
    final SnippetImportPlan plan = _importPlan!;
    return Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
      Flexible(
          child: ListView(padding: const EdgeInsets.all(12), children: <Widget>[
        _label('${plan.snippets.length} ready to import'),
        Text('Adds to your library. Existing snippets are kept. Imported shell commands start disabled.',
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(160))),
        const SizedBox(height: 10),
        for (final TextSnippet snippet in plan.snippets)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${snippet.name}${snippet.trigger.isEmpty ? '' : '  ·  ${snippet.trigger}'}',
                  style: TextStyle(color: Design.text, fontSize: Design.baseFontSize + 1))),
        if (plan.issues.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _label('${plan.issues.length} skipped'),
          for (final String issue in plan.issues)
            Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(issue, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(160)))),
        ],
      ])),
      _footer(<Widget>[
        Expanded(child: _action('Cancel', _back)),
        const SizedBox(width: 8),
        Expanded(
            child: _action(
                'Import ${plan.snippets.length}',
                plan.snippets.isEmpty
                    ? null
                    : () => _run(() async {
                          await _persist(<TextSnippet>[..._snippets, ...plan.snippets]);
                          if (mounted) setState(() => _view = _SnippetView.library);
                          _notice('Imported ${plan.snippets.length} snippets.');
                        }),
                primary: true))
      ]),
    ]);
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback action, {bool active = false}) => IconButton(
      onPressed: _busy ? null : action,
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 15, color: active ? Design.accent : Design.text.withAlpha(155)));

  Widget _label(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Design.text.withAlpha(155))));

  InputDecoration _decoration(String hint, {IconData? icon}) => InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: TextStyle(color: Design.text.withAlpha(95), fontSize: Design.baseFontSize + 1),
      prefixIcon: icon == null ? null : Icon(icon, size: 17, color: Design.text.withAlpha(140)),
      filled: true,
      fillColor: Design.text.withAlpha(7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(20))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(20))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.accent.withAlpha(100))));

  Widget _field(TextEditingController controller, String hint,
          {int minLines = 1,
          int maxLines = 1,
          FocusNode? focus,
          bool autofocus = false,
          IconData? icon,
          bool monospace = false,
          ValueChanged<String>? onSubmitted}) =>
      TextField(
          controller: controller,
          focusNode: focus,
          autofocus: autofocus,
          minLines: minLines,
          maxLines: maxLines,
          readOnly: _busy,
          onSubmitted: onSubmitted,
          style: TextStyle(
              fontSize: Design.baseFontSize + 1.5, color: Design.text, fontFamily: monospace ? 'monospace' : null),
          decoration: _decoration(hint, icon: icon));

  Widget _dropdown(String value, Map<String, String> options, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: _decoration(''),
          style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
          items: options.entries
              .map((MapEntry<String, String> entry) =>
                  DropdownMenuItem<String>(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: _busy
              ? null
              : (String? value) {
                  if (value != null) onChanged(value);
                });

  Widget _card(Widget child) => Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
          color: Design.text.withAlpha(7),
          border: Border.all(color: Design.text.withAlpha(16)),
          borderRadius: BorderRadius.circular(10)),
      child: child);

  Widget _toggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: <Widget>[
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title,
              style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w600, color: Design.text)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(145))),
        ])),
        const SizedBox(width: 12),
        MiniToggleSwitch(
            value: value,
            onChanged: (bool value) {
              if (!_busy) onChanged(value);
            }),
      ]));

  Widget _footer(List<Widget> children) => Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
      child: Row(children: children));

  Widget _action(String label, VoidCallback? action, {bool primary = false}) => OutlinedButton(
      onPressed: _busy ? null : action,
      style: OutlinedButton.styleFrom(
          foregroundColor: primary ? Design.accent : Design.text.withAlpha(190),
          backgroundColor: primary ? Design.accent.withAlpha(18) : Colors.transparent,
          side: BorderSide(color: primary ? Design.accent.withAlpha(75) : Design.text.withAlpha(25)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12)),
      child: Text(label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600)));
}
