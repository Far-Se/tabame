import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';

enum _MemoMode { library, editor, preview }

bool _memoWidthTry = false;

class MemosButton extends StatelessWidget {
  const MemosButton({super.key});

  @override
  Widget build(BuildContext context) => QuickActionItem(
        message: "Memos",
        icon: const Icon(Icons.note_alt_outlined),
        hoverColor: Theme.of(context).colorScheme.primary,
        onTap: () {
          final ({int height, int width}) size = Win32.getSize();
          if (_memoWidthTry == false && (Globals.quickMenuPage == QuickMenuPage.quickMenu || size.width < 640)) {
            _memoWidthTry = true;
            QuickMenuFunctions.openQuickMenuWithAction("memos", center: true);
            return;
          }
          _memoWidthTry = false;
          showQuickMenuModal(
            context: context,
            heightFactor: 0.9,
            child: const MemosWidget(),
          );
        },
      );
}

class MemosWidget extends StatefulWidget {
  const MemosWidget({super.key});

  @override
  State<MemosWidget> createState() => _MemosWidgetState();
}

class _MemosWidgetState extends State<MemosWidget> {
  static const String _generalCategory = 'General';

  late final List<List<String>> _memos;
  late final List<String> _categories;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();

  _MemoMode _mode = _MemoMode.library;
  int? _selectedIndex;
  int? _editingIndex;
  String? _selectedCategory;
  String _editingCategory = _generalCategory;
  bool _confirmingDelete = false;

  @override
  void initState() {
    super.initState();
    _memos = Boxes().runMemos.map(_normalizeMemo).toList();
    _categories = _normaliseCategories(Boxes().runMemoCategories);
    for (final List<String> memo in _memos) {
      if (!_categories.contains(memo[2])) _categories.add(memo[2]);
    }
    if (_memos.isNotEmpty) _selectedIndex = 0;
    _searchController.addListener(_refresh);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refresh)
      ..dispose();
    _titleController.dispose();
    _bodyController.dispose();
    _categoryController.dispose();
    _titleFocusNode.dispose();
    super.dispose();
  }

  List<String> _normalizeMemo(List<String> memo) => <String>[
        memo.isNotEmpty ? memo[0] : '',
        memo.length > 1 ? memo[1] : '',
        memo.length > 2 && memo[2].trim().isNotEmpty ? memo[2].trim() : _generalCategory,
      ];

  List<String> _normaliseCategories(List<String> saved) {
    final List<String> categories = <String>[_generalCategory];
    for (final String category in saved) {
      final String trimmed = category.trim();
      if (trimmed.isNotEmpty && !categories.contains(trimmed)) categories.add(trimmed);
    }
    return categories;
  }

  void _refresh() {
    if (mounted) {
      setState(() {
        if (_mode == _MemoMode.preview) _mode = _MemoMode.library;
      });
    }
  }

  void _persist() {
    Boxes()
      ..runMemos = _memos.map((List<String> memo) => List<String>.from(memo)).toList()
      ..runMemoCategories = List<String>.from(_categories);
  }

  List<int> get _visibleIndexes {
    final String query = _searchController.text.trim().toLowerCase();
    return <int>[
      for (int index = 0; index < _memos.length; index++)
        if ((_selectedCategory == null || _memos[index][2] == _selectedCategory) &&
            (query.isEmpty ||
                _memos[index][0].toLowerCase().contains(query) ||
                _memos[index][1].toLowerCase().contains(query)))
          index,
    ];
  }

  void _selectCategory(String? category) {
    final List<int> visible = _visibleIndexesFor(category);
    setState(() {
      _selectedCategory = category;
      _selectedIndex = visible.isEmpty ? null : visible.first;
      _mode = _MemoMode.library;
    });
  }

  List<int> _visibleIndexesFor(String? category) => <int>[
        for (int index = 0; index < _memos.length; index++)
          if (category == null || _memos[index][2] == category) index,
      ];

  void _createMemo() {
    _titleController.clear();
    _bodyController.clear();
    setState(() {
      _editingIndex = null;
      _editingCategory = _selectedCategory ?? _generalCategory;
      _confirmingDelete = false;
      _mode = _MemoMode.editor;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _titleFocusNode.requestFocus());
  }

  void _openPreview(int index) {
    final List<String> memo = _memos[index];
    _titleController.text = memo[0];
    _bodyController.text = memo[1];
    setState(() {
      _selectedIndex = index;
      _editingIndex = index;
      _editingCategory = memo[2];
      _confirmingDelete = false;
      _mode = _MemoMode.preview;
    });
  }

  void _previewDraft() => setState(() => _mode = _MemoMode.preview);

  void _save() {
    final String title = _titleController.text.trim();
    final String body = _bodyController.text.trimRight();
    if (title.isEmpty && body.isEmpty) {
      _cancelEditing();
      return;
    }
    final List<String> memo = <String>[title, body, _editingCategory];
    setState(() {
      if (_editingIndex == null) {
        _memos.insert(0, memo);
        _selectedIndex = 0;
      } else {
        _memos[_editingIndex!] = memo;
        _selectedIndex = _editingIndex;
      }
      _selectedCategory = _editingCategory;
      _editingIndex = null;
      _mode = _MemoMode.library;
    });
    _persist();
  }

  void _cancelEditing() => setState(() {
        _editingIndex = null;
        _confirmingDelete = false;
        _mode = _MemoMode.library;
      });

  void _deleteEditing() {
    final int? index = _editingIndex;
    if (index == null) {
      _cancelEditing();
      return;
    }
    if (!_confirmingDelete) return setState(() => _confirmingDelete = true);
    setState(() {
      _memos.removeAt(index);
      final List<int> visible = _visibleIndexes;
      _selectedIndex = visible.isEmpty ? null : visible.first;
      _editingIndex = null;
      _confirmingDelete = false;
      _mode = _MemoMode.library;
    });
    _persist();
  }

  Future<void> _addCategory() async {
    _categoryController.clear();
    final String? category = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('New memo category'),
        content: TextField(
          controller: _categoryController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Category name'),
          onSubmitted: (String value) => Navigator.of(context).pop(value),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(_categoryController.text), child: const Text('Add')),
        ],
      ),
    );
    final String name = category?.trim() ?? '';
    if (name.isEmpty || _categories.contains(name)) return;
    setState(() => _categories.add(name));
    _persist();
  }

  void _deleteCategory(String category) {
    if (category == _generalCategory) return;
    setState(() {
      for (final List<String> memo in _memos) {
        if (memo[2] == category) memo[2] = _generalCategory;
      }
      _categories.remove(category);
      if (_selectedCategory == category) _selectedCategory = _generalCategory;
      final List<int> visible = _visibleIndexes;
      _selectedIndex = visible.isEmpty ? null : visible.first;
    });
    _persist();
  }

  Future<void> _openLink(String text, String? href, String title) async {
    if (href != null) WinUtils.open(href);
  }

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 560, maxWidth: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            PanelHeader(
              title: switch (_mode) {
                _MemoMode.library => 'Notes & Memos',
                _MemoMode.editor => _editingIndex == null ? 'New memo' : 'Edit memo',
                _MemoMode.preview => (_editingIndex != null)
                    ? "${_memos[_editingIndex!][1]} (${_memos[_editingIndex!][2]})"
                    : 'Memo preview',
              },
              icon: _mode == _MemoMode.library ? Icons.notes_rounded : Icons.edit_note_rounded,
              buttonIcon: switch (_mode) {
                _MemoMode.library => Icons.add_rounded,
                _MemoMode.editor => Icons.check_rounded,
                _MemoMode.preview => Icons.edit_rounded,
              },
              buttonTooltip: switch (_mode) {
                _MemoMode.library => 'New memo',
                _MemoMode.editor => 'Save memo',
                _MemoMode.preview => 'Edit memo',
              },
              buttonPressed: switch (_mode) {
                _MemoMode.library => _createMemo,
                _MemoMode.editor => _save,
                _MemoMode.preview => () => setState(() => _mode = _MemoMode.editor),
              },
              extraActions: _mode == _MemoMode.library
                  ? null
                  : _mode == _MemoMode.editor
                      ? <Widget>[
                          IconButton(
                            tooltip: 'Preview memo',
                            onPressed: _previewDraft,
                            icon: const Icon(Icons.visibility_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Discard changes',
                            onPressed: _cancelEditing,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ]
                      : <Widget>[
                          IconButton(
                            tooltip: 'Back to memos',
                            onPressed: _cancelEditing,
                            icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          ),
                          IconButton(
                            tooltip: _confirmingDelete ? 'Click again to delete' : 'Delete memo',
                            onPressed: _deleteEditing,
                            icon: Icon(
                              _confirmingDelete ? Icons.warning_amber_rounded : Icons.delete_outline_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
            ),
            Flexible(
              child: Material(
                type: MaterialType.transparency,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: switch (_mode) {
                    _MemoMode.library => _buildLibrary(),
                    _MemoMode.editor => _buildEditor(),
                    _MemoMode.preview => _buildPreview(),
                  },
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildLibrary() => Padding(
        key: const ValueKey<String>('library'),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Row(children: <Widget>[
          SizedBox(width: 250, child: _buildSidebar()),
          const SizedBox(width: 8),
          Expanded(child: _buildMemoList()),
        ]),
      );

  Widget _buildSidebar() => Container(
        decoration: _surfaceDecoration(),
        child: Column(children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: TextField(
              controller: _searchController,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
              decoration: _fieldDecoration('Search memos', Icons.search_rounded),
            ),
          ),
          _sidebarHeading('CATEGORIES', Icons.folder_outlined, onAdd: _addCategory),
          _CategoryRow(
            label: 'All memos',
            icon: Icons.library_books_outlined,
            count: _memos.length,
            selected: _selectedCategory == null,
            onTap: () => _selectCategory(null),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
              itemCount: _categories.length,
              itemBuilder: (BuildContext context, int index) {
                final String category = _categories[index];
                return _CategoryRow(
                  label: category,
                  icon: category == _generalCategory ? Icons.inbox_outlined : Icons.folder_outlined,
                  count: _memos.where((List<String> memo) => memo[2] == category).length,
                  selected: _selectedCategory == category,
                  onTap: () => _selectCategory(category),
                  onDelete: category == _generalCategory ? null : () => _deleteCategory(category),
                );
              },
            ),
          ),
        ]),
      );

  Widget _buildMemoList() {
    final List<int> visible = _visibleIndexes;
    return Container(
      decoration: _surfaceDecoration(active: true),
      child: Column(children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 7),
          child: Row(children: <Widget>[
            Icon(Icons.notes_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 6),
            Expanded(child: Text((_selectedCategory ?? 'ALL MEMOS').toUpperCase(), style: _sectionStyle())),
            _countChip(visible.length),
          ]),
        ),
        Expanded(
          child: visible.isEmpty
              ? Center(child: Text('No memos here', style: TextStyle(color: Design.text.withAlpha(120))))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                  itemCount: visible.length,
                  itemBuilder: (BuildContext context, int listIndex) => _MemoListItem(
                    memo: _memos[visible[listIndex]],
                    selected: _selectedIndex == visible[listIndex],
                    onTap: () => _openPreview(visible[listIndex]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _buildEditor() => Padding(
        key: const ValueKey<String>('editor'),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Container(
          decoration: _surfaceDecoration(active: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  style: _titleStyle(),
                  decoration: _fieldDecoration('Memo title', Icons.title_rounded)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: DropdownButtonFormField<String>(
                initialValue: _editingCategory,
                isExpanded: true,
                decoration: _fieldDecoration('Category', Icons.folder_outlined),
                items: _categories
                    .map((String category) => DropdownMenuItem<String>(value: category, child: Text(category)))
                    .toList(),
                onChanged: (String? category) => category == null ? null : setState(() => _editingCategory = category),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: TextField(
                  controller: _bodyController,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  keyboardType: TextInputType.multiline,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, height: 1.45, color: Design.text),
                  decoration: _fieldDecoration('Write a memo… Markdown is supported', Icons.notes_rounded)
                      .copyWith(alignLabelWithHint: true),
                ),
              ),
            ),
            _editorBar(),
          ]),
        ),
      );

  Widget _buildPreview() => Padding(
        key: const ValueKey<String>('preview'),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Container(
          decoration: _surfaceDecoration(active: true),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(14, 12, 10, 4),
            //   child: Row(children: <Widget>[
            //     Expanded(child: Text(_displayTitle(_titleController.text), style: _titleStyle())),
            //     _DetailAction(
            //       icon: Icons.edit_outlined,
            //       tooltip: 'Edit memo',
            //       onTap: () => setState(() => _mode = _MemoMode.editor),
            //     ),
            //     _DetailAction(icon: Icons.delete_outline_rounded, tooltip: 'Delete memo', onTap: _deleteEditing),
            //   ]),
            // ),
            // Padding(
            //   padding: const EdgeInsets.symmetric(horizontal: 14),
            //   child: _metaLabel(Icons.folder_outlined, _editingCategory),
            // ),
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            //   child: Divider(height: 1, color: Design.text.withAlpha(22)),
            // ),
            Expanded(child: _memoBody(_bodyController.text)),
          ]),
        ),
      );

  Widget _editorBar() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
        child: Row(children: <Widget>[
          Text('Markdown supported',
              style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(110))),
          const Spacer(),
          if (_editingIndex != null)
            TextButton.icon(
              onPressed: _deleteEditing,
              icon: Icon(_confirmingDelete ? Icons.warning_amber_rounded : Icons.delete_outline_rounded, size: 16),
              label: Text(_confirmingDelete ? 'Confirm delete' : 'Delete'),
              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            ),
          const SizedBox(width: 6),
          TextButton(
              onPressed: _mode == _MemoMode.editor ? _previewDraft : () => setState(() => _mode = _MemoMode.editor),
              child: Text(_mode == _MemoMode.editor ? 'Preview' : 'Edit')),
          const SizedBox(width: 6),
          _PrimaryAction(label: 'Save memo', icon: Icons.check_rounded, onTap: _save),
        ]),
      );

  Widget _memoBody(String body) => body.trim().isEmpty
      ? Center(child: Text('This memo is empty.', style: TextStyle(color: Design.text.withAlpha(130))))
      : ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 18), children: <Widget>[_markdown(body)]);

  Widget _sidebarHeading(String label, IconData icon, {required VoidCallback onAdd}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 5),
        child: Row(children: <Widget>[
          Icon(icon, size: 14, color: Design.accent),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: _sectionStyle())),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 15),
            label: const Text('New'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ]),
      );

  Widget _markdown(String body) => MarkdownBody(
        data: body,
        selectable: true,
        onTapLink: _openLink,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(fontSize: Design.baseFontSize + 2, height: 1.45, color: Design.text),
          a: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.accent, decoration: TextDecoration.underline),
          h1: TextStyle(fontSize: Design.baseFontSize + 7, fontWeight: FontWeight.w700, color: Design.text),
          h2: TextStyle(fontSize: Design.baseFontSize + 5, fontWeight: FontWeight.w700, color: Design.text),
          h3: TextStyle(fontSize: Design.baseFontSize + 3, fontWeight: FontWeight.w600, color: Design.text),
          code: TextStyle(
              fontSize: Design.baseFontSize, color: Design.accent, backgroundColor: Design.accent.withAlpha(18)),
        ),
      );

  InputDecoration _fieldDecoration(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(105)),
        prefixIcon: Icon(icon, size: 17, color: Design.accent.withAlpha(190)),
        isDense: true,
        filled: true,
        fillColor: Design.text.withAlpha(7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.text.withAlpha(18))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Design.accent.withAlpha(100))),
      );

  BoxDecoration _surfaceDecoration({bool active = false}) => BoxDecoration(
        color: active ? Design.accent.withAlpha(8) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? Design.accent.withAlpha(48) : Design.text.withAlpha(16)),
      );

  TextStyle _sectionStyle() => TextStyle(
      fontSize: Design.baseFontSize - .5,
      fontWeight: FontWeight.w700,
      letterSpacing: .5,
      color: Design.text.withAlpha(185));
  TextStyle _titleStyle() =>
      TextStyle(fontSize: Design.baseFontSize + 3, fontWeight: FontWeight.w700, color: Design.text);
  Widget _countChip(int count) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Design.accent.withAlpha(22), borderRadius: BorderRadius.circular(99)),
      child: Text('$count',
          style: TextStyle(fontSize: Design.baseFontSize - 1, fontWeight: FontWeight.w700, color: Design.accent)));
  // Widget _metaLabel(IconData icon, String label) => Row(
  //       mainAxisSize: MainAxisSize.min,
  //       children: <Widget>[
  //         Icon(icon, size: 13, color: Design.text.withAlpha(105)),
  //         const SizedBox(width: 4),
  //         Text(label,
  //             overflow: TextOverflow.ellipsis,
  //             style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(115))),
  //       ],
  //     );

  // String _displayTitle(String title) => title.trim().isEmpty ? 'Untitled memo' : title.trim();
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow(
      {required this.label,
      required this.icon,
      required this.count,
      required this.selected,
      required this.onTap,
      this.onDelete});
  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
          decoration: BoxDecoration(
              color: selected ? Design.accent.withAlpha(18) : Colors.transparent,
              borderRadius: BorderRadius.circular(7)),
          child: Row(children: <Widget>[
            Icon(icon, size: 14, color: selected ? Design.accent : Design.text.withAlpha(130)),
            const SizedBox(width: 6),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.baseFontSize,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: Design.text))),
            Text('$count', style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(120))),
            if (onDelete != null)
              IconButton(
                  tooltip: 'Delete category and move its memos to General',
                  onPressed: onDelete,
                  icon: Icon(Icons.close_rounded, size: 13, color: Design.text.withAlpha(115)),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 20, height: 20)),
          ]),
        ),
      );
}

class _MemoListItem extends StatelessWidget {
  const _MemoListItem({required this.memo, required this.selected, required this.onTap});
  final List<String> memo;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String title = memo[0].trim().isEmpty ? 'Untitled memo' : memo[0].trim();
    final String preview = memo[1].replaceAll(RegExp(r'\s+'), ' ').trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
        decoration: BoxDecoration(
            color: selected ? Design.accent.withAlpha(22) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border(
                left: BorderSide(color: selected ? Design.accent.withAlpha(180) : Colors.transparent, width: 2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: Design.baseFontSize + 1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: Design.text)),
          const SizedBox(height: 2),
          Text(preview.isEmpty ? 'Empty memo' : preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize - 1, height: 1.25, color: Design.text.withAlpha(125))),
        ]),
      ),
    );
  }
}

// class _DetailAction extends StatelessWidget {
//   const _DetailAction({required this.icon, required this.tooltip, required this.onTap});
//   final IconData icon;
//   final String tooltip;
//   final VoidCallback onTap;
//   @override
//   Widget build(BuildContext context) => IconButton(
//       tooltip: tooltip,
//       onPressed: onTap,
//       icon: Icon(icon, size: 17, color: Design.text.withAlpha(170)),
//       visualDensity: VisualDensity.compact);
// }

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
              color: Design.accent.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Design.accent.withAlpha(85))),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(icon, size: 16, color: Design.accent),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w700, color: Design.accent))
          ])));
}
