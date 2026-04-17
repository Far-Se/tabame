import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/emoji_picker_modal.dart';

class BookmarksPage extends StatefulWidget {
  const BookmarksPage({super.key});

  @override
  BookmarksPageState createState() => BookmarksPageState();
}

class BookmarksPageState extends State<BookmarksPage> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;
  final Set<String> _expandedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                "Bookmark Groups",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
              ),
              IconButton(
                onPressed: () async {
                  final List<String> emojis = <String>["✨", "📂", "💼", "🏢", "🏠", "🌟", "🛠️"];
                  final String randomEmoji = emojis[Random().nextInt(emojis.length)];
                  bookmarks
                      .add(BookmarkGroup(title: "New Project Group", emoji: randomEmoji, bookmarks: <BookmarkInfo>[]));
                  _expandedGroups.add(bookmarks.last.title); // Expand by default
                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                  setState(() {});
                },
                icon: const Icon(Icons.add_rounded),
                tooltip: "New Group",
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Groups List
        if (bookmarks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.bookmark_add_outlined, size: 64, color: accent.withAlpha(180)),
                const SizedBox(height: 20),
                Text(
                  "Organize with Bookmarks",
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: onSurface.withAlpha(220)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  "Bookmarks let you group useful files, folders, web URLs, or execution scripts (e.g., 'code C:\\project') under a single organized category.\nThey are accessible directly from the main view.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: onSurface.withAlpha(160), height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent.withAlpha(30),
                    foregroundColor: accent,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                  label: const Text("Create First Group", style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () async {
                    final List<String> emojis = <String>["✨", "📂", "💼", "🏢", "🏠", "🌟", "🛠️"];
                    final String randomEmoji = emojis[Random().nextInt(emojis.length)];
                    bookmarks.add(
                        BookmarkGroup(title: "New Project Group", emoji: randomEmoji, bookmarks: <BookmarkInfo>[]));
                    _expandedGroups.add(bookmarks.last.title); // Expand by default
                    await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                    setState(() {});
                  },
                ),
              ],
            ),
          )
        else
          ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            dragStartBehavior: DragStartBehavior.down,
            itemCount: bookmarks.length,
            physics: const NeverScrollableScrollPhysics(), // Scroll via parent
            itemBuilder: (BuildContext context, int mainIndex) {
              final BookmarkGroup project = bookmarks[mainIndex];
              final String groupKey = "${project.title}_$mainIndex";
              final bool isExpanded = _expandedGroups.contains(groupKey);

              return _BookmarkGroupCard(
                key: ValueKey<int>(mainIndex),
                project: project,
                accent: accent,
                onSurface: onSurface,
                isExpanded: isExpanded,
                index: mainIndex,
                onToggleExpand: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedGroups.remove(groupKey);
                    } else {
                      _expandedGroups.add(groupKey);
                    }
                  });
                },
                onEditGroup: () => _showDialogGroup(context, project, mainIndex),
                onAddBookmark: () async {
                  final List<String> emojis = <String>["🎀", "🌟", "🚀", "🎨", "🎬", "📚", "🎮"];
                  final String randomEmoji = emojis[Random().nextInt(emojis.length)];
                  project.bookmarks
                      .add(BookmarkInfo(emoji: randomEmoji, title: "New Project", stringToExecute: "C:\\"));
                  _expandedGroups.add(groupKey);
                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                  setState(() {});
                },
                onDeleteGroup: () async {
                  bookmarks.removeAt(mainIndex);
                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                  setState(() {});
                },
                onReorderBookmarks: (int oldIndex, int newIndex) async {
                  if (oldIndex < newIndex) newIndex -= 1;
                  final BookmarkInfo item = project.bookmarks.removeAt(oldIndex);
                  project.bookmarks.insert(newIndex, item);
                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                  setState(() {});
                },
                onEditBookmark: (int itemIndex) => _showDialogItem(context, project, itemIndex, groupKey),
                onDeleteBookmark: (int itemIndex) async {
                  project.bookmarks.removeAt(itemIndex);
                  await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                  setState(() {});
                },
                onExecuteBookmark: (BookmarkInfo item) {
                  WinUtils.open(item.stringToExecute, parseParamaters: true);
                },
              );
            },
            onReorder: (int oldIndex, int newIndex) async {
              if (oldIndex < newIndex) newIndex -= 1;
              final BookmarkGroup item = bookmarks.removeAt(oldIndex);
              bookmarks.insert(newIndex, item);
              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
              setState(() {});
            },
          ),
      ],
    );
  }

  // =======================================================================
  // Modal Dialogs
  // =======================================================================

  Future<void> _showDialogGroup(BuildContext context, BookmarkGroup project, int mainIndex) async {
    final TextEditingController emojiCtrl = TextEditingController(text: project.emoji);
    final TextEditingController titleCtrl = TextEditingController(text: project.title);
    final Color accent = Color(globalSettings.themeColors.accentColor);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Group Properties", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 350,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 100,
                  child: EmojiPickerTextField(
                    controller: emojiCtrl,
                    textAlign: TextAlign.center,
                    dialogTitle: "Choose Group Emoji",
                    decoration: _modernInputDecoration(context, "Symbol", accent, null),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: titleCtrl,
                    autofocus: true,
                    decoration: _modernInputDecoration(context, "Label", accent, null),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                project.emoji = emojiCtrl.text.isNotEmpty ? emojiCtrl.text : "";
                project.title = titleCtrl.text;
                await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                setState(() {});
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text("Apply"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDialogItem(BuildContext context, BookmarkGroup project, int itemIndex, String groupKey) async {
    final BookmarkInfo item = project.bookmarks[itemIndex];
    final TextEditingController emojiCtrl = TextEditingController(text: item.emoji);
    final TextEditingController titleCtrl = TextEditingController(text: item.title);
    final TextEditingController pathCtrl = TextEditingController(text: item.stringToExecute);
    final Color accent = Color(globalSettings.themeColors.accentColor);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Bookmark Properties", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 450,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    SizedBox(
                      width: 120,
                      child: EmojiPickerTextField(
                        controller: emojiCtrl,
                        textAlign: TextAlign.center,
                        dialogTitle: "Choose Bookmark Emoji",
                        decoration: _modernInputDecoration(context, "Symbol", accent, null),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: titleCtrl,
                        autofocus: true,
                        decoration: _modernInputDecoration(context, "Label", accent, null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: pathCtrl,
                        decoration: _modernInputDecoration(context, "Target", accent, null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.file_open_rounded, size: 18, color: accent),
                        onPressed: () {
                          final OpenFilePicker file = OpenFilePicker()
                            ..filterSpecification = <String, String>{'All Files': '*.*'}
                            ..defaultFilterIndex = 0
                            ..defaultExtension = 'exe'
                            ..title = 'Select any file';
                          final File? result = file.getFile();
                          if (result != null) {
                            pathCtrl.text = result.path;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.folder_open_rounded, size: 18, color: accent),
                        onPressed: () {
                          final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                          final Directory? dir = dirPicker.getDirectory();
                          if (dir != null && dir.path.isNotEmpty) {
                            pathCtrl.text = dir.path;
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    "Paths, URLs, or command strings (e.g. 'code .')",
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: "monospace",
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                item.emoji = emojiCtrl.text.isNotEmpty ? emojiCtrl.text : "";
                item.title = titleCtrl.text;
                item.stringToExecute = pathCtrl.text;
                await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                setState(() {});
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text("Apply"),
            ),
          ],
        );
      },
    );
  }

  // Helper for consistent modern text fields
  InputDecoration _modernInputDecoration(BuildContext context, String label, Color accent, IconData? icon) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent.withAlpha(20), width: 1)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(150)),
    );
  }
}

// =======================================================================
// Group Card Component
// =======================================================================

class _BookmarkGroupCard extends StatefulWidget {
  const _BookmarkGroupCard({
    required super.key,
    required this.project,
    required this.accent,
    required this.onSurface,
    required this.isExpanded,
    required this.index,
    required this.onToggleExpand,
    required this.onEditGroup,
    required this.onAddBookmark,
    required this.onDeleteGroup,
    required this.onReorderBookmarks,
    required this.onEditBookmark,
    required this.onDeleteBookmark,
    required this.onExecuteBookmark,
  });

  final BookmarkGroup project;
  final Color accent;
  final Color onSurface;
  final bool isExpanded;
  final int index;

  final VoidCallback onToggleExpand;
  final VoidCallback onEditGroup;
  final VoidCallback onAddBookmark;
  final VoidCallback onDeleteGroup;
  final void Function(int, int) onReorderBookmarks;
  final void Function(int) onEditBookmark;
  final void Function(int) onDeleteBookmark;
  final void Function(BookmarkInfo) onExecuteBookmark;

  @override
  State<_BookmarkGroupCard> createState() => _BookmarkGroupCardState();
}

class _BookmarkGroupCardState extends State<_BookmarkGroupCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.accent.withAlpha(widget.isExpanded ? 60 : 20), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withAlpha(10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Group Header (Hoverable and Clickable)
            MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              child: InkWell(
                onTap: widget.onToggleExpand,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isExpanded
                        ? widget.accent.withAlpha(15)
                        : (_isHovering ? widget.accent.withAlpha(8) : Colors.transparent),
                    border: Border(
                        bottom: BorderSide(color: widget.accent.withAlpha(widget.isExpanded ? 40 : 0), width: 1)),
                  ),
                  child: Row(
                    children: <Widget>[
                      // Drag Handle for Group
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: Container(
                          padding: const EdgeInsets.only(right: 12.0),
                          color: Colors.transparent, // Ensures hit detection
                          child: Icon(Icons.drag_indicator_rounded, size: 20, color: widget.onSurface.withAlpha(100)),
                        ),
                      ),
                      // Text Content
                      Text(widget.project.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.project.title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: widget.isExpanded ? widget.accent : widget.onSurface,
                              ),
                            ),
                            Text(
                              "${widget.project.bookmarks.length} saved bookmarks",
                              style: TextStyle(fontSize: 12, color: widget.onSurface.withAlpha(150)),
                            ),
                          ],
                        ),
                      ),
                      // Action Icons
                      IconButton(
                        tooltip: "Edit Group",
                        icon: Icon(Icons.edit_rounded, size: 18, color: widget.onSurface.withAlpha(180)),
                        onPressed: widget.onEditGroup,
                        splashRadius: 20,
                      ),
                      IconButton(
                        tooltip: "Delete Group",
                        icon: Icon(Icons.delete_outline_rounded,
                            size: 18, color: Theme.of(context).colorScheme.error.withAlpha(200)),
                        onPressed: () =>
                            _confirmDelete(context, widget.onDeleteGroup, "Group '${widget.project.title}'"),
                        splashRadius: 20,
                      ),
                      const SizedBox(width: 6),
                      // Add Bookmark Button
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accent.withAlpha(30),
                          foregroundColor: widget.accent,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text("Item", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                        onPressed: widget.onAddBookmark,
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        widget.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: widget.onSurface.withAlpha(150),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Embedded Bookmarks List
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOutBack,
              child: widget.isExpanded
                  ? Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      color: Theme.of(context).colorScheme.surface.withAlpha(80),
                      child: widget.project.bookmarks.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Center(
                                child: Text("No bookmarks inside this group yet.",
                                    style:
                                        TextStyle(color: widget.onSurface.withAlpha(100), fontStyle: FontStyle.italic)),
                              ),
                            )
                          : ReorderableListView.builder(
                              shrinkWrap: true,
                              buildDefaultDragHandles: false,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: widget.project.bookmarks.length,
                              itemBuilder: (BuildContext context, int itemIndex) {
                                final BookmarkInfo item = widget.project.bookmarks[itemIndex];
                                return _BookmarkItemRow(
                                  key: ValueKey<int>(itemIndex),
                                  item: item,
                                  accent: widget.accent,
                                  onSurface: widget.onSurface,
                                  index: itemIndex,
                                  onEdit: () => widget.onEditBookmark(itemIndex),
                                  onDelete: () => _confirmDelete(
                                      context, () => widget.onDeleteBookmark(itemIndex), "Bookmark '${item.title}'"),
                                  onExecute: () => widget.onExecuteBookmark(item),
                                );
                              },
                              onReorder: widget.onReorderBookmarks,
                            ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, VoidCallback onConfirm, String name) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Confirm Deletion"),
        content: Text("Permanently delete '$name'? This action cannot be undone."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            child: const Text("Delete Permanently"),
          ),
        ],
      ),
    );
  }
}

// =======================================================================
// Individual Bookmark Row
// =======================================================================

class _BookmarkItemRow extends StatefulWidget {
  const _BookmarkItemRow({
    required super.key,
    required this.item,
    required this.accent,
    required this.onSurface,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onExecute,
  });

  final BookmarkInfo item;
  final Color accent;
  final Color onSurface;
  final int index;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExecute;

  @override
  State<_BookmarkItemRow> createState() => _BookmarkItemRowState();
}

class _BookmarkItemRowState extends State<_BookmarkItemRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: widget.onEdit,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: _hovered ? widget.accent.withAlpha(12) : widget.onSurface.withAlpha(5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _hovered ? widget.accent.withAlpha(40) : Colors.transparent),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
                    color: Colors.transparent, // Ensures hit detection
                    child: Icon(Icons.drag_indicator_rounded, size: 16, color: widget.onSurface.withAlpha(80)),
                  ),
                ),
                Text(widget.item.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _hovered ? widget.accent : widget.onSurface,
                        ),
                      ),
                      Text(
                        widget.item.stringToExecute,
                        style: TextStyle(fontSize: 11, color: widget.onSurface.withAlpha(120)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Hover Actions
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1.0 : 0.0,
                  child: Row(
                    children: <Widget>[
                      IconButton(
                        tooltip: "Edit",
                        icon: Icon(Icons.edit_rounded, size: 16, color: widget.onSurface.withAlpha(200)),
                        onPressed: widget.onEdit,
                        splashRadius: 18,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        tooltip: "Launch",
                        icon: Icon(Icons.play_arrow_rounded, size: 18, color: widget.accent),
                        onPressed: widget.onExecute,
                        splashRadius: 18,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        tooltip: "Delete",
                        icon: Icon(Icons.close_rounded,
                            size: 16, color: Theme.of(context).colorScheme.error.withAlpha(200)),
                        onPressed: widget.onDelete,
                        splashRadius: 18,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
