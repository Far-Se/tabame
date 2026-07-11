import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import 'bookmarks_editor.dart';
import 'bookmarks_list.dart';

class BookmarksButton extends StatelessWidget {
  const BookmarksButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Bookmarks", icon: const Icon(Icons.folder_copy_outlined), child: () => const BookmarksPanel());
  }
}

class BookmarksPanel extends StatefulWidget {
  const BookmarksPanel({super.key});

  @override
  State<BookmarksPanel> createState() => _BookmarksPanelState();
}

class _BookmarksPanelState extends State<BookmarksPanel> {
  static const List<String> _groupEmojis = <String>["✨", "📂", "💼", "🏢", "🏠", "🌟", "🛠️"];
  static const List<String> _bookmarkEmojis = <String>["🎀", "🌟", "🚀", "🎨", "🎬", "📚", "🎮"];

  final Random _random = Random();
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;

  // Editor State
  BookmarkGroup? _editingGroup;
  BookmarkInfo? _editingBookmark;
  BookmarkGroup? _activeParentGroup;
  bool _isNew = false;

  Future<void> _persistBookmarks() async {
    await Boxes.updateSettings("projects", jsonEncode(bookmarks));
    if (mounted) setState(() {});
  }

  void _openGroupEditor([BookmarkGroup? group]) {
    setState(() {
      _editingGroup = group ?? BookmarkGroup(title: "", emoji: _randomGroupEmoji(), bookmarks: <BookmarkInfo>[]);
      _editingBookmark = null;
      _activeParentGroup = null;
      _isNew = group == null;
    });
  }

  void _openBookmarkEditor(BookmarkGroup parent, [BookmarkInfo? bookmark]) {
    setState(() {
      _activeParentGroup = parent;
      _editingBookmark = bookmark ?? BookmarkInfo(title: "", emoji: _randomBookmarkEmoji(), stringToExecute: "");
      _editingGroup = null;
      _isNew = bookmark == null;
    });
  }

  void _closeEditor() {
    setState(() {
      _editingGroup = null;
      _editingBookmark = null;
      _activeParentGroup = null;
    });
  }

  Future<void> _saveGroup(String title, String emoji, String viewMode) async {
    if (title.trim().isEmpty) return;

    if (_isNew) {
      bookmarks.add(BookmarkGroup(
        title: title.trim(),
        emoji: emoji.trim(),
        viewMode: viewMode,
        bookmarks: <BookmarkInfo>[],
      ));
    } else {
      _editingGroup!.title = title.trim();
      _editingGroup!.emoji = emoji.trim();
      _editingGroup!.viewMode = viewMode;
    }

    await _persistBookmarks();
    _closeEditor();
  }

  Future<void> _saveBookmark(
      String title, String emoji, String target, bool preferInputIcon, BookmarkGroup? targetGroup) async {
    if (title.trim().isEmpty || target.trim().isEmpty) return;

    if (_isNew) {
      _activeParentGroup!.bookmarks.add(BookmarkInfo(
        emoji: emoji.trim(),
        title: title.trim(),
        stringToExecute: target.trim(),
        preferInputIcon: preferInputIcon,
      ));
    } else {
      _editingBookmark!.title = title.trim();
      _editingBookmark!.emoji = emoji.trim();
      _editingBookmark!.stringToExecute = target.trim();
      _editingBookmark!.preferInputIcon = preferInputIcon;

      // Move the bookmark to a different category if one was selected.
      if (targetGroup != null && targetGroup != _activeParentGroup) {
        _activeParentGroup!.bookmarks.remove(_editingBookmark);
        targetGroup.bookmarks.add(_editingBookmark!);
      }
    }

    await _persistBookmarks();
    _closeEditor();
  }

  void _deleteGroup(BookmarkGroup group) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Delete Category", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to delete '${group.title}'?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      bookmarks.remove(group);
      await _persistBookmarks();
    }
  }

  void _deleteBookmark(BookmarkGroup group, BookmarkInfo bookmark) async {
    group.bookmarks.remove(bookmark);
    await _persistBookmarks();
  }

  void _openBookmark(BookmarkInfo mark) {
    WinUtils.open(mark.stringToExecute, parseParamaters: true);
    QuickMenuFunctions.hideQuickMenu();
  }

  String _randomGroupEmoji() => _groupEmojis[_random.nextInt(_groupEmojis.length)];
  String _randomBookmarkEmoji() => _bookmarkEmojis[_random.nextInt(_bookmarkEmojis.length)];

  void _handleDelete() {
    if (_editingGroup != null) {
      _deleteGroup(_editingGroup!);
    } else if (_editingBookmark != null) {
      _deleteBookmark(_activeParentGroup!, _editingBookmark!);
    }
    _closeEditor();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool isEditing = _editingGroup != null || _editingBookmark != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (isEditing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: accent.withAlpha(40)))),
            child: Row(
              children: <Widget>[
                InkWell(
                  onTap: _closeEditor,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.arrow_back_rounded, size: 14, color: accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _editingGroup != null
                        ? (_isNew ? "New Category" : "Edit Category")
                        : (_isNew ? "New Bookmark" : "Edit Bookmark"),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: onSurface),
                  ),
                ),
                if (!_isNew)
                  IconButton(
                    onPressed: _handleDelete,
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: onSurface.withAlpha(150)),
                    splashRadius: 20,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          )
        else
          PanelHeader(
            title: "Bookmarks",
            icon: Icons.bookmark_rounded,
            buttonIcon: Icons.add_rounded,
            buttonTooltip: "Create Category",
            buttonPressed: () => _openGroupEditor(),
          ),
        const SizedBox(height: 8),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: isEditing
                ? BookmarkEditor(
                    group: _editingGroup,
                    bookmark: _editingBookmark,
                    parentGroup: _activeParentGroup,
                    allGroups: bookmarks,
                    accent: accent,
                    isNew: _isNew,
                    onSaveGroup: _saveGroup,
                    onSaveBookmark: _saveBookmark,
                    onCancel: _closeEditor,
                    onDelete: _handleDelete,
                  )
                : body(accent, onSurface),
          ),
        ),
      ],
    );
  }

  Widget body(Color accent, Color onSurface) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Flexible(
          child: bookmarks.isEmpty
              ? _EmptyState(
                  accent: accent,
                  onCreateCategory: () => _openGroupEditor(),
                )
              : BookmarkList(
                  bookmarks: bookmarks,
                  accent: accent,
                  onAddBookmark: (BookmarkGroup group) => _openBookmarkEditor(group),
                  onEditGroup: (BookmarkGroup group) => _openGroupEditor(group),
                  onDeleteGroup: _deleteGroup,
                  onEditBookmark: (BookmarkGroup group, BookmarkInfo mark) => _openBookmarkEditor(group, mark),
                  onDeleteBookmark: _deleteBookmark,
                  onOpenBookmark: _openBookmark,
                ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.accent,
    required this.onCreateCategory,
  });

  final Color accent;
  final VoidCallback onCreateCategory;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bookmark_border_rounded, size: 48, color: onSurface.withAlpha(40)),
          const SizedBox(height: 16),
          Text(
            "No bookmarks folder created yet",
            style: TextStyle(
              fontSize: 13,
              color: onSurface.withAlpha(120),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: accent.withAlpha(30),
              foregroundColor: accent,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: onCreateCategory,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Create First Category", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
