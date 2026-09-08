import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

class NotesButton extends StatelessWidget {
  const NotesButton({super.key});

  @override
  Widget build(BuildContext context) => QuickActionItem(
        message: 'Notes',
        icon: const Icon(Icons.note_alt_outlined),
        onTap: () => showQuickMenuModal(context: context, maxWidth: 820, child: const MemosWidget()),
      );
}

// Keep existing pinned actions and launcher integrations working.
class MemosButton extends NotesButton {
  const MemosButton({super.key});
}

class MemosWidget extends StatefulWidget {
  const MemosWidget({super.key});

  @override
  State<MemosWidget> createState() => _MemosWidgetState();
}

class _MemosWidgetState extends State<MemosWidget> {
  static const String _general = 'General';
  List<List<String>> _notes = <List<String>>[];
  List<String> _categories = <String>[_general];
  final TextEditingController _search = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  final TextEditingController _categoryName = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final FocusNode _titleFocus = FocusNode();
  int? _selected;
  String? _filter;
  String _category = _general;
  String? _renaming;
  String? _error;
  bool _opened = false;
  bool _preview = false;
  bool _managing = false;
  bool _busy = false;
  bool _loadFailed = false;
  bool _confirmDelete = false;
  bool _askingDiscard = false;

  bool get _dirty {
    if (!_opened) return false;
    final List<String>? saved = _selected == null ? null : _notes[_selected!];
    return saved == null
        ? _title.text.isNotEmpty || _body.text.isNotEmpty
        : _title.text != saved[0] || _body.text != saved[1] || _category != saved[2];
  }

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(_refresh);
    _title.addListener(_refresh);
    _body.addListener(_refresh);
  }

  void _load() {
    try {
      _notes = Boxes().runMemos.map((List<String> note) => List<String>.from(note)).toList();
      _categories = <String>{
        _general,
        ...Boxes().runMemoCategories.where((String c) => c.trim().isNotEmpty),
        ..._notes.map((List<String> n) => n[2])
      }.toList();
      _loadFailed = false;
      _error = null;
    } catch (_) {
      _loadFailed = true;
      _error = 'Could not load your notes. Close and reopen to try again.';
    }
  }

  void _refresh() {
    if (mounted) setState(() => _confirmDelete = false);
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[_search, _title, _body, _categoryName]) {
      controller.dispose();
    }
    _searchFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  List<int> get _visible {
    final List<String> terms = _search.text.trim().toLowerCase().split(RegExp(r'\s+'));
    return <int>[
      for (int i = 0; i < _notes.length; i++)
        if ((_filter == null || _notes[i][2] == _filter) &&
            terms.every((String term) => _notes[i].join(' ').toLowerCase().contains(term)))
          i,
    ];
  }

  Future<void> _navigate(VoidCallback action) async {
    if (_busy || _askingDiscard) return;
    if (_dirty) {
      _askingDiscard = true;
      final bool? discard = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text('Your changes have not been saved.'),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep editing')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Discard')),
          ],
        ),
      );
      _askingDiscard = false;
      if (!mounted || discard != true) return;
    }
    if (mounted) action();
  }

  void _open([int? index]) {
    _navigate(() {
      final List<String>? note = index == null ? null : _notes[index];
      setState(() {
        _opened = false;
        _selected = index;
        _title.text = note?[0] ?? '';
        _body.text = note?[1] ?? '';
        _category = note?[2] ?? _filter ?? _general;
        _opened = true;
        _preview = index != null;
        _managing = false;
        _confirmDelete = false;
        _error = null;
      });
      if (index == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _titleFocus.requestFocus();
        });
      }
    });
  }

  // Commit first; only replace the panel's in-memory data after persistence succeeds.
  Future<bool> _commit(List<List<String>> notes, List<String> categories) async {
    if (_busy || _loadFailed) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Boxes.updateSettings('runMemoCategories', jsonEncode(categories));
      await Boxes.updateSettings('runMemos', jsonEncode(notes));
      if (!mounted) return false;
      setState(() {
        _notes = notes;
        _categories = categories;
      });
      return true;
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save. Your changes are still here; please try again.');
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_opened || _busy) return;
    if (_title.text.trim().isEmpty && _body.text.trim().isEmpty) {
      setState(() => _error = 'Add a title or some text before saving.');
      return;
    }
    final List<List<String>> next = List<List<String>>.from(_notes);
    final List<String> note = <String>[_title.text, _body.text, _category];
    final int index = _selected ?? 0;
    if (_selected == null) {
      next.insert(0, note);
    } else {
      next[index] = note;
    }
    if (await _commit(next, List<String>.from(_categories))) {
      setState(() {
        _selected = index;
        _confirmDelete = false;
      });
    }
  }

  Future<void> _delete() async {
    if (_selected == null || _busy) return;
    final List<List<String>> next = List<List<String>>.from(_notes)..removeAt(_selected!);
    // Avoid comparing the draft with an index that may no longer exist during the commit.
    final int index = _selected!;
    setState(() {
      _opened = false;
      _selected = null;
    });
    if (await _commit(next, List<String>.from(_categories))) {
      setState(() => _confirmDelete = false);
    } else if (mounted) {
      setState(() {
        _opened = true;
        _selected = index;
      });
    }
  }

  Future<void> _saveCategory() async {
    final String name = _categoryName.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    if (_categories.any((String c) => c != _renaming && c.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'A category with that name already exists.');
      return;
    }
    final String? old = _renaming;
    final List<String> categories = <String>[for (final String c in _categories) c == old ? name : c];
    if (old == null) categories.add(name);
    final List<List<String>> notes = <List<String>>[
      for (final List<String> n in _notes) <String>[n[0], n[1], n[2] == old ? name : n[2]],
    ];
    if (await _commit(notes, categories)) {
      setState(() {
        if (old != null && _filter == old) _filter = name;
        _renaming = null;
        _categoryName.clear();
      });
    }
  }

  Future<void> _removeCategory(String category) async {
    final List<List<String>> notes = <List<String>>[
      for (final List<String> n in _notes) <String>[n[0], n[1], n[2] == category ? _general : n[2]],
    ];
    if (await _commit(notes, List<String>.from(_categories)..remove(category))) {
      setState(() {
        if (_filter == category) _filter = _general;
        if (_renaming == category) {
          _renaming = null;
          _categoryName.clear();
        }
      });
    }
  }

  void _back() => _navigate(() => setState(() {
        _opened = false;
        _managing = false;
        _confirmDelete = false;
      }));

  @override
  Widget build(BuildContext context) => PopScope<void>(
        canPop: !_dirty && !_busy,
        onPopInvokedWithResult: (bool didPop, _) {
          if (!didPop && !_busy) {
            _navigate(() {
              setState(() => _opened = false);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).pop();
              });
            });
          }
        },
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
            const SingleActivator(LogicalKeyboardKey.keyN, control: true): () {
              if (!_loadFailed) _open();
            },
            const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _navigate(() {
                  setState(() {
                    _opened = false;
                    _managing = false;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _searchFocus.requestFocus();
                  });
                }),
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PanelHeader(
                title: _managing ? 'Notes / Categories' : 'Notes',
                icon: Icons.note_alt_outlined,
                buttonIcon: _managing ? Icons.arrow_back_rounded : Icons.create_new_folder_outlined,
                buttonTooltip: _managing ? 'Back to notes' : 'Manage categories',
                buttonPressed: _loadFailed || _busy
                    ? null
                    : () => _navigate(() => setState(() {
                          _opened = false;
                          _managing = !_managing;
                          _error = null;
                        })),
              ),
              Flexible(
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(children: <Widget>[
                    if (_busy) LinearProgressIndicator(minHeight: 2, color: Design.accent),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(_error!, style: TextStyle(color: Design.text, fontSize: Design.baseFontSize)),
                      ),
                    Expanded(
                        child: AbsorbPointer(
                      absorbing: _busy || _loadFailed,
                      child: _managing
                          ? _categoryManager()
                          : LayoutBuilder(
                              builder: (BuildContext context, BoxConstraints constraints) {
                                final bool wide = constraints.maxWidth >= 620;
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                                  child: wide
                                      ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                                          SizedBox(width: 235, child: _library()),
                                          const SizedBox(width: 8),
                                          Expanded(
                                              child: _opened
                                                  ? _detail()
                                                  : _empty(
                                                      'A place for your thoughts', 'Select a note or start a new one.',
                                                      action: true)),
                                        ])
                                      : _opened
                                          ? _detail()
                                          : _library(),
                                );
                              },
                            ),
                    )),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _library() {
    final List<int> visible = _visible;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Row(children: <Widget>[
        Expanded(child: Text('LIBRARY', style: _labelStyle)),
        _action('New note', Icons.add_rounded, () => _open(), primary: true),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: _search,
        focusNode: _searchFocus,
        style: _textStyle,
        decoration: _input('Search notes', icon: Icons.search_rounded).copyWith(
          suffixIcon: _search.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search', onPressed: _search.clear, icon: const Icon(Icons.close_rounded, size: 15)),
        ),
      ),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        key: ValueKey<String?>(_filter),
        initialValue: _filter ?? '',
        isExpanded: true,
        style: _textStyle,
        decoration: _input('Category', icon: Icons.folder_outlined),
        items: <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: '', child: Text('All notes · ${_notes.length}')),
          for (final String c in _categories)
            DropdownMenuItem<String>(
                value: c,
                child: Text('$c · ${_notes.where((List<String> n) => n[2] == c).length}',
                    overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (String? value) => setState(() => _filter = value == '' ? null : value),
      ),
      Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Text('${visible.length} ${visible.length == 1 ? 'NOTE' : 'NOTES'}', style: _labelStyle)),
      Expanded(
          child: visible.isEmpty
              ? _empty(_search.text.isNotEmpty ? 'No matches' : 'No notes yet',
                  _search.text.isNotEmpty ? 'Try another search or category.' : 'Capture an idea with New note.')
              : ListView.separated(
                  itemCount: visible.length,
                  padding: EdgeInsets.zero,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (BuildContext context, int position) {
                    final int index = visible[position];
                    final List<String> note = _notes[index];
                    final bool selected = _opened && _selected == index;
                    return Material(
                      color: selected ? Design.accent.withAlpha(18) : Design.text.withAlpha(7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(color: selected ? Design.accent.withAlpha(80) : Design.text.withAlpha(16))),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => _open(index),
                        hoverColor: Design.accent.withAlpha(18),
                        child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                              Text(note[0].trim().isEmpty ? 'Untitled note' : note[0],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _textStyle.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(note[1].trim().isEmpty ? 'No text' : note[1].replaceAll(RegExp(r'\s+'), ' '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _textStyle.copyWith(color: Design.text.withAlpha(155), height: 1.4)),
                              const SizedBox(height: 7),
                              Text(note[2],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _labelStyle.copyWith(color: Design.accent)),
                            ])),
                      ),
                    );
                  },
                )),
    ]);
  }

  Widget _detail() => Container(
        decoration: BoxDecoration(
            border: Border.all(color: Design.text.withAlpha(18)), borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Row(children: <Widget>[
                _icon('Back to notes', Icons.arrow_back_rounded, _back),
                Expanded(
                    child: Text(
                        _dirty
                            ? 'UNSAVED CHANGES'
                            : _selected == null
                                ? 'NEW NOTE'
                                : 'SAVED',
                        style: _labelStyle)),
                _icon(
                    _preview ? 'Edit note' : 'Preview Markdown',
                    _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                    () => setState(() => _preview = !_preview)),
                if (_selected != null)
                  _icon('Delete note', Icons.delete_outline_rounded,
                      () => setState(() => _confirmDelete = !_confirmDelete)),
              ])),
          if (_confirmDelete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              color: Design.accent.withAlpha(12),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: <Widget>[
                Text('Delete this note permanently?', style: _textStyle),
                _action('Cancel', Icons.close_rounded, () => setState(() => _confirmDelete = false)),
                _action('Delete', Icons.delete_outline_rounded, _delete, primary: true),
              ]),
            ),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _preview
                  ? SelectableText(_title.text.trim().isEmpty ? 'Untitled note' : _title.text,
                      maxLines: 2,
                      style: _textStyle.copyWith(fontSize: Design.baseFontSize + 5, fontWeight: FontWeight.w700))
                  : TextField(
                      controller: _title,
                      focusNode: _titleFocus,
                      maxLines: 1,
                      style: _textStyle.copyWith(fontSize: Design.baseFontSize + 5, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                          hintText: 'Untitled note',
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Design.text.withAlpha(100))))),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
              child: _preview
                  ? Text(_category, style: _labelStyle.copyWith(color: Design.accent))
                  : DropdownButtonFormField<String>(
                      key: ValueKey<String>(_category),
                      initialValue: _category,
                      isExpanded: true,
                      style: _textStyle,
                      decoration: _input('Category', icon: Icons.folder_outlined),
                      items: _categories
                          .map((String c) =>
                              DropdownMenuItem<String>(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (String? c) {
                        if (c != null)
                          setState(() {
                            _category = c;
                            _confirmDelete = false;
                          });
                      },
                    )),
          Divider(height: 1, color: Design.text.withAlpha(18)),
          Expanded(
              child: _preview
                  ? _body.text.trim().isEmpty
                      ? _empty('No text in this note', 'Use Edit to start writing.')
                      : ListView(padding: const EdgeInsets.all(12), children: <Widget>[
                          MarkdownBody(
                              data: _body.text,
                              selectable: true,
                              onTapLink: (String text, String? href, String title) {
                                if (href == null) return;
                                _navigate(() {
                                  WinUtils.open(href);
                                  QuickMenuFunctions.hideQuickMenu();
                                });
                              },
                              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                                p: _textStyle.copyWith(height: 1.6),
                                a: _textStyle.copyWith(color: Design.accent),
                                code: _textStyle.copyWith(
                                    fontFamily: 'monospace', backgroundColor: Design.text.withAlpha(8)),
                              )),
                        ])
                  : TextField(
                      controller: _body,
                      expands: true,
                      maxLines: null,
                      minLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      keyboardType: TextInputType.multiline,
                      style: _textStyle.copyWith(height: 1.6),
                      decoration: InputDecoration(
                          hintText: 'Write something worth keeping…',
                          hintStyle: _textStyle.copyWith(color: Design.text.withAlpha(100)),
                          contentPadding: const EdgeInsets.all(12),
                          border: InputBorder.none))),
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
              child: Row(children: <Widget>[
                Expanded(
                    child: Text(
                        _preview
                            ? '${_body.text.trim().isEmpty ? 0 : _body.text.trim().split(RegExp(r'\s+')).length} words'
                            : 'Markdown · Ctrl+S to save',
                        style: _labelStyle)),
                _action('Save', Icons.check_rounded, _save, primary: true),
              ])),
        ]),
      );

  Widget _categoryManager() => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Text('Keep related notes together', style: _textStyle.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Removing a category moves its notes to General.',
              style: _textStyle.copyWith(color: Design.text.withAlpha(155))),
          const SizedBox(height: 10),
          Row(children: <Widget>[
            Expanded(
                child: TextField(
                    controller: _categoryName,
                    style: _textStyle,
                    decoration: _input(_renaming == null ? 'New category name' : 'Rename category',
                        icon: Icons.folder_outlined),
                    onSubmitted: (_) => _saveCategory())),
            const SizedBox(width: 6),
            _action(_renaming == null ? 'Add' : 'Save', _renaming == null ? Icons.add_rounded : Icons.check_rounded,
                _saveCategory,
                primary: true),
            if (_renaming != null)
              _icon(
                  'Cancel rename',
                  Icons.close_rounded,
                  () => setState(() {
                        _renaming = null;
                        _categoryName.clear();
                        _error = null;
                      })),
          ]),
          const SizedBox(height: 10),
          Expanded(
              child: ListView.separated(
            itemCount: _categories.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: Design.text.withAlpha(16)),
            itemBuilder: (BuildContext context, int index) {
              final String c = _categories[index];
              return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: <Widget>[
                    Icon(c == _general ? Icons.inbox_outlined : Icons.folder_outlined, size: 16, color: Design.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c, overflow: TextOverflow.ellipsis, style: _textStyle)),
                    Text('${_notes.where((List<String> n) => n[2] == c).length}', style: _labelStyle),
                    if (c != _general) ...<Widget>[
                      _icon(
                          'Rename category',
                          Icons.edit_outlined,
                          () => setState(() {
                                _renaming = c;
                                _categoryName.text = c;
                              })),
                      _icon('Remove category; keep its notes', Icons.delete_outline_rounded, () => _removeCategory(c)),
                    ] else
                      const SizedBox(width: 64),
                  ]));
            },
          )),
        ]),
      );

  Widget _empty(String title, String hint, {bool action = false}) => Center(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(16), children: <Widget>[
          Icon(Icons.notes_rounded, size: 28, color: Design.accent.withAlpha(150)),
          const SizedBox(height: 10),
          Text(title, textAlign: TextAlign.center, style: _textStyle.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(hint, textAlign: TextAlign.center, style: _textStyle.copyWith(color: Design.text.withAlpha(145))),
          if (action)
            Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(child: _action('New note', Icons.add_rounded, () => _open(), primary: true))),
        ]),
      );

  TextStyle get _textStyle => TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text);
  TextStyle get _labelStyle => TextStyle(
      fontSize: Design.baseFontSize - 1,
      color: Design.text.withAlpha(145),
      fontWeight: FontWeight.w600,
      letterSpacing: .4);

  InputDecoration _input(String hint, {required IconData icon}) => InputDecoration(
        hintText: hint,
        hintStyle: _textStyle.copyWith(color: Design.text.withAlpha(120)),
        prefixIcon: Icon(icon, size: 16, color: Design.accent),
        isDense: true,
        filled: true,
        fillColor: Design.text.withAlpha(7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(18))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.accent.withAlpha(90))),
      );

  Widget _icon(String tooltip, IconData icon, VoidCallback onTap) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Design.text.withAlpha(180)),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 30),
        visualDensity: VisualDensity.compact,
      );

  Widget _action(String label, IconData icon, VoidCallback onTap, {bool primary = false}) => Material(
        color: primary ? Design.accent.withAlpha(22) : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(7),
            side: BorderSide(color: primary ? Design.accent.withAlpha(80) : Design.text.withAlpha(18))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            hoverColor: Design.accent.withAlpha(18),
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(icon, size: 14, color: primary ? Design.accent : Design.text),
                  const SizedBox(width: 5),
                  Text(label,
                      style: _textStyle.copyWith(
                          fontWeight: FontWeight.w600, color: primary ? Design.accent : Design.text)),
                ]))),
      );
}
