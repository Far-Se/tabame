import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/util/app_opacity.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/emoji_picker_modal.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/text_input.dart';
import '../../widgets/windows_scroll.dart';

// ─────────────────────────────────────────────
//  Page
// ─────────────────────────────────────────────

class InterfaceQMBookmarksSettingsPage extends StatefulWidget {
  const InterfaceQMBookmarksSettingsPage({super.key});

  @override
  State<InterfaceQMBookmarksSettingsPage> createState() => _InterfaceQMBookmarksSettingsPageState();
}

class _InterfaceQMBookmarksSettingsPageState extends State<InterfaceQMBookmarksSettingsPage> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;

  /// Which group is currently open in the builder panel. null = none.
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 720;

        if (isWide) {
          return _buildSplitLayout(context, accent);
        } else {
          return _buildNarrowLayout(context, accent);
        }
      },
    );
  }

  // ── Wide: sidebar list + persistent builder panel ──
  Widget _buildSplitLayout(BuildContext context, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        // LEFT – list
        SizedBox(
          width: 280,
          child: _BookmarkSidebar(
            bookmarks: bookmarks,
            selectedIndex: _selectedIndex,
            accent: accent,
            onSelect: (int i) => setState(() => _selectedIndex = i),
            onReorder: (int oldIndex, int newIndex) async {
              if (oldIndex < newIndex) newIndex -= 1;
              final BookmarkGroup item = bookmarks.removeAt(oldIndex);
              bookmarks.insert(newIndex, item);
              if (_selectedIndex != null) {
                if (_selectedIndex == oldIndex) {
                  _selectedIndex = newIndex;
                } else if (oldIndex < _selectedIndex! && newIndex >= _selectedIndex!) {
                  _selectedIndex = _selectedIndex! - 1;
                } else if (oldIndex > _selectedIndex! && newIndex <= _selectedIndex!) {
                  _selectedIndex = _selectedIndex! + 1;
                }
              }
              await _saveAndRefresh();
            },
            onAdd: _addGroup,
          ),
        ),
        // divider
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: AppOpacity.border),
        ),
        // RIGHT – builder panel
        Expanded(
          child: _selectedIndex != null
              ? BookmarkGroupBuilder(
                  key: ValueKey<int>(_selectedIndex!),
                  groupIndex: _selectedIndex!,
                  bookmarks: bookmarks,
                  accent: accent,
                  onSaved: (BookmarkGroup g) async {
                    bookmarks[_selectedIndex!] = g;
                    await _saveAndRefresh();
                  },
                  onDeleted: () async {
                    bookmarks.removeAt(_selectedIndex!);
                    _selectedIndex = bookmarks.isEmpty
                        ? null
                        : (_selectedIndex! >= bookmarks.length ? bookmarks.length - 1 : _selectedIndex);
                    await _saveAndRefresh();
                  },
                )
              : _buildWelcomePane(context, accent),
        ),
      ],
    );
  }

  // ── Narrow: list only, builder opens as bottom sheet ──
  Widget _buildNarrowLayout(BuildContext context, Color accent) {
    return _BookmarkSidebar(
      bookmarks: bookmarks,
      selectedIndex: null,
      accent: accent,
      onSelect: (int i) => _openBottomSheet(context, i),
      onReorder: (int oldIndex, int newIndex) async {
        if (oldIndex < newIndex) newIndex -= 1;
        final BookmarkGroup item = bookmarks.removeAt(oldIndex);
        bookmarks.insert(newIndex, item);
        await _saveAndRefresh();
      },
      onAdd: _addGroup,
    );
  }

  void _openBottomSheet(BuildContext context, int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (BuildContext ctx, ScrollController sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: BookmarkGroupBuilder(
            key: ValueKey<int>(index),
            groupIndex: index,
            bookmarks: bookmarks,
            accent: Design.accent,
            scrollController: sc,
            onSaved: (BookmarkGroup g) async {
              bookmarks[index] = g;
              await _saveAndRefresh();
              if (context.mounted) Navigator.pop(context);
            },
            onDeleted: () async {
              bookmarks.removeAt(index);
              await _saveAndRefresh();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePane(BuildContext context, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bookmarks_rounded, color: accent, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            bookmarks.isEmpty ? 'No bookmark groups yet' : 'Select a group',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            bookmarks.isEmpty ? 'Tap "New Group" to get started' : 'Choose one from the list to edit it',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          if (bookmarks.isEmpty) ...<Widget>[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addGroup,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Group'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addGroup() async {
    final List<String> emojis = <String>['✨', '📂', '💼', '🏢', '🏠', '🌟', '🛠️'];
    final String randomEmoji = emojis[Random().nextInt(emojis.length)];
    bookmarks.add(BookmarkGroup(title: 'New Group', emoji: randomEmoji, bookmarks: <BookmarkInfo>[]));
    await _saveAndRefresh();
    setState(() => _selectedIndex = bookmarks.length - 1);
  }

  Future<void> _saveAndRefresh() async {
    await Boxes.updateSettings('projects', jsonEncode(bookmarks));
    if (mounted) setState(() {});
  }
}

// ─────────────────────────────────────────────
//  Sidebar (list of bookmark groups)
// ─────────────────────────────────────────────

class _BookmarkSidebar extends StatelessWidget {
  const _BookmarkSidebar({
    required this.bookmarks,
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
    required this.onReorder,
    required this.onAdd,
  });

  final List<BookmarkGroup> bookmarks;
  final int? selectedIndex;
  final Color accent;
  final void Function(int) onSelect;
  final void Function(int, int) onReorder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Design.background.withAlpha(150),
      ),
      child: Column(
        children: <Widget>[
          // top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Bookmark Groups',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'New Group',
                  child: FilledButton(
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.add_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // list
          Expanded(
            child: bookmarks.isEmpty
                ? _buildEmpty(context)
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: bookmarks.length,
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: (BuildContext context, int i) {
                      return _SidebarTile(
                        key: ValueKey<int>(i),
                        group: bookmarks[i],
                        index: i,
                        isSelected: selectedIndex == i,
                        accent: accent,
                        onTap: () => onSelect(i),
                      );
                    },
                    onReorderItem: onReorder,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bookmarks_outlined, size: 40, color: fg.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text(
            'No groups',
            style: TextStyle(
              fontSize: 13,
              color: fg.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sidebar tile
// ─────────────────────────────────────────────

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required super.key,
    required this.group,
    required this.index,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final BookmarkGroup group;
  final int index;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.accent.withValues(alpha: 0.12)
              : (_hover ? fg.withValues(alpha: 0.04) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected ? widget.accent.withValues(alpha: 0.35) : Colors.transparent,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 16,
                      color: fg.withValues(alpha: _hover ? 0.35 : 0.15),
                    ),
                  ),
                ),
                Text(widget.group.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.isSelected ? widget.accent : fg,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${widget.group.bookmarks.length} bookmark${widget.group.bookmarks.length == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: 0.45),
                        ),
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

// ─────────────────────────────────────────────
//  Bookmark Group Builder (replaces modal editor)
// ─────────────────────────────────────────────

class BookmarkGroupBuilder extends StatefulWidget {
  const BookmarkGroupBuilder({
    super.key,
    required this.groupIndex,
    required this.bookmarks,
    required this.accent,
    required this.onSaved,
    required this.onDeleted,
    this.scrollController,
  });

  final int groupIndex;
  final List<BookmarkGroup> bookmarks;
  final Color accent;
  final void Function(BookmarkGroup) onSaved;
  final VoidCallback onDeleted;
  final ScrollController? scrollController;

  @override
  State<BookmarkGroupBuilder> createState() => _BookmarkGroupBuilderState();
}

class _BookmarkGroupBuilderState extends State<BookmarkGroupBuilder> {
  late BookmarkGroup _group;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _group = widget.bookmarks[widget.groupIndex];
  }

  void _save() {
    widget.onSaved(_group);
    setState(() => _dirty = false);
  }

  void _markDirty() => setState(() => _dirty = true);

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent;

    return Container(
      decoration: BoxDecoration(
        color: Design.background.withAlpha(150),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: <Widget>[
            // ── top bar ──
            _BuilderTopBar(
              group: _group,
              accent: accent,
              dirty: _dirty,
              onSave: _save,
              onDelete: widget.onDeleted,
            ),

            // ── scrollable body ──
            Expanded(
              child: WindowsScrollView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionLabel(label: 'Group Identity', accent: accent),
                    const SizedBox(height: 8),
                    _GroupIdentityEditor(
                      group: _group,
                      accent: accent,
                      onChanged: _markDirty,
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: 'View Mode', accent: accent),
                    const SizedBox(height: 8),
                    _ViewModeSelector(
                      value: _group.viewMode,
                      accent: accent,
                      onChanged: (String v) {
                        _group.viewMode = v;
                        _markDirty();
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: <Widget>[
                        Expanded(child: _SectionLabel(label: 'Bookmarks (${_group.bookmarks.length})', accent: accent)),
                        _AddButton(
                          icon: Icons.add_rounded,
                          label: 'Add Bookmark',
                          accent: accent,
                          onTap: _addBookmark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_group.bookmarks.isEmpty)
                      _buildEmptyBookmarks(context)
                    else
                      ReorderableListView.builder(
                        shrinkWrap: true,
                        buildDefaultDragHandles: false,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _group.bookmarks.length,
                        onReorderItem: (int oldIndex, int newIndex) async {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final BookmarkInfo item = _group.bookmarks.removeAt(oldIndex);
                          _group.bookmarks.insert(newIndex, item);
                          _markDirty();
                        },
                        itemBuilder: (BuildContext context, int index) {
                          return _BookmarkItemTile(
                            key: ValueKey<String>('${_group.title}_bookmark_$index'),
                            item: _group.bookmarks[index],
                            index: index,
                            accent: accent,
                            onEdit: () => _showDialogItem(context, index),
                            onDelete: () {
                              _group.bookmarks.removeAt(index);
                              _markDirty();
                            },
                            onExecute: () =>
                                WinUtils.open(_group.bookmarks[index].stringToExecute, parseParamaters: true),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBookmarks(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.bookmark_add_outlined, size: 36, color: fg.withValues(alpha: 0.15)),
            const SizedBox(height: 12),
            Text(
              'No bookmarks in this group',
              style: TextStyle(fontSize: 13, color: fg.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }

  void _addBookmark() async {
    final List<String> emojis = <String>['🎀', '🌟', '🚀', '🎨', '🎬', '📚', '🎮'];
    final String randomEmoji = emojis[Random().nextInt(emojis.length)];
    _group.bookmarks.add(BookmarkInfo(emoji: randomEmoji, title: 'New Bookmark', stringToExecute: 'C:\\'));
    _markDirty();
    if (mounted) {
      _showDialogItem(context, _group.bookmarks.length - 1);
    }
  }

  Future<void> _showDialogItem(BuildContext context, int itemIndex) async {
    final BookmarkInfo item = _group.bookmarks[itemIndex];
    String currentEmoji = item.emoji;
    String currentTitle = item.title;
    String currentPath = item.stringToExecute;
    bool currentPreferInputIcon = item.preferInputIcon;
    final Color accent = widget.accent;
    final ThemeData theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              width: min(MediaQuery.of(context).size.width * 0.95, 500),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: accent.withValues(alpha: 0.2), width: 1.5),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 32,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Bookmark Configuration',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Material(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        InkWell(
                          onTap: () async {
                            final String? emoji = await showEmojiPickerModal(context,
                                initialValue: item.emoji, title: 'Pick an emoji for ${item.title}');
                            if (emoji != null) {
                              setState(() => item.emoji = emoji);
                              currentEmoji = emoji;
                              (context as Element).markNeedsBuild();
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: accent.withValues(alpha: 0.2)),
                            ),
                            alignment: Alignment.center,
                            child: Text(currentEmoji, style: const TextStyle(fontSize: 25)),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: CustomTextInput(
                            labelText: 'Label',
                            value: currentTitle,
                            onChanged: (String val) => currentTitle = val,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: CustomTextInput(
                          labelText: 'Target Path, URL, or Command',
                          value: currentPath,
                          onChanged: (String val) => currentPath = val,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: <Widget>[
                          _buildMiniPickerButton(
                            icon: Icons.file_open_rounded,
                            tooltip: 'Pick File',
                            accent: accent,
                            context: context,
                            onPressed: () {
                              final OpenFilePicker file = OpenFilePicker()
                                ..filterSpecification = <String, String>{'All Files': '*.*'}
                                ..defaultFilterIndex = 0
                                ..defaultExtension = 'exe'
                                ..title = 'Select any file';
                              final File? result = file.getFile();
                              if (result != null) {
                                currentPath = result.path;
                                (context as Element).markNeedsBuild();
                              }
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildMiniPickerButton(
                            icon: Icons.folder_open_rounded,
                            tooltip: 'Pick Folder',
                            accent: accent,
                            context: context,
                            onPressed: () {
                              final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select any folder';
                              final Directory? dir = dirPicker.getDirectory();
                              if (dir != null && dir.path.isNotEmpty) {
                                currentPath = dir.path;
                                (context as Element).markNeedsBuild();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  StatefulBuilder(
                    builder: (BuildContext context, StateSetter setModalState) {
                      return _buildBetterToggle(
                        icon: Icons.auto_awesome_rounded,
                        label: 'PREFER INPUT ICONS',
                        subtitle: 'Try use favicon or file icons',
                        isSelected: currentPreferInputIcon,
                        accent: accent,
                        onTap: () => setModalState(() => currentPreferInputIcon = !currentPreferInputIcon),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        onPressed: () async {
                          final String title = currentTitle.trim();
                          final String path = currentPath.trim();
                          if (title.isEmpty || path.isEmpty) return;
                          item.emoji = currentEmoji;
                          item.title = title;
                          item.stringToExecute = path;
                          item.preferInputIcon = currentPreferInputIcon;
                          _markDirty();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniPickerButton({
    required IconData icon,
    required String tooltip,
    required Color accent,
    required BuildContext context,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: CustomTooltip(
        message: tooltip,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 18, color: accent),
          onPressed: onPressed,
          splashRadius: 18,
        ),
      ),
    );
  }

  Widget _buildBetterToggle({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.1) : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accent.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected ? accent.withValues(alpha: 0.2) : onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: isSelected ? accent : onSurface.withValues(alpha: 0.4), size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: isSelected ? accent : onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 9,
                      color: onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            MiniToggleSwitch(
              value: isSelected,
              onChanged: (_) => onTap(),
              activeThumbColor: accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Builder Top Bar
// ─────────────────────────────────────────────

class _BuilderTopBar extends StatelessWidget {
  const _BuilderTopBar({
    required this.group,
    required this.accent,
    required this.dirty,
    required this.onSave,
    required this.onDelete,
  });

  final BookmarkGroup group;
  final Color accent;
  final bool dirty;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: AppOpacity.border),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.bookmarks_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  group.title.isEmpty ? 'Group' : '${group.emoji} ${group.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  dirty ? 'Unsaved changes' : 'Up to date',
                  style: TextStyle(
                    fontSize: 11,
                    color: dirty
                        ? Design.accent.withValues(alpha: 0.9)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Delete',
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: theme.colorScheme.error.withValues(alpha: 0.7)),
            onPressed: () => _confirmDelete(context),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: dirty ? onSave : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: accent.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              'Save',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: dirty ? Colors.white : accent.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('"${group.title}" and all its bookmarks will be permanently removed.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Section label
// ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
//  Group Identity Editor
// ─────────────────────────────────────────────

class _GroupIdentityEditor extends StatefulWidget {
  const _GroupIdentityEditor({
    required this.group,
    required this.accent,
    required this.onChanged,
  });

  final BookmarkGroup group;
  final Color accent;
  final VoidCallback onChanged;

  @override
  State<_GroupIdentityEditor> createState() => _GroupIdentityEditorState();
}

class _GroupIdentityEditorState extends State<_GroupIdentityEditor> {
  late TextEditingController _titleCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.group.title);
    _titleCtrl.addListener(() {
      widget.group.title = _titleCtrl.text;
      widget.onChanged();
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = widget.accent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        // emoji picker
        GestureDetector(
          onTap: () async {
            final String? emoji = await showEmojiPickerModal(context,
                initialValue: widget.group.emoji, title: 'Pick an emoji for ${widget.group.title}');
            if (emoji != null) {
              setState(() => widget.group.emoji = emoji);
              widget.onChanged();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.25), width: 1.5),
            ),
            alignment: Alignment.center,
            child: Text(widget.group.emoji, style: const TextStyle(fontSize: 26)),
          ),
        ),
        const SizedBox(width: 16),
        // title field
        Expanded(
          child: TextField(
            controller: _titleCtrl,
            style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Group name',
              hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              prefixIcon: Icon(Icons.label_outline_rounded, size: 20, color: accent.withValues(alpha: 0.7)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLow,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  View Mode Selector
// ─────────────────────────────────────────────

class _ViewModeSelector extends StatelessWidget {
  const _ViewModeSelector({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String value;
  final Color accent;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ModeTab(
            icon: Icons.view_list_rounded,
            label: 'List',
            selected: value == 'list',
            accent: accent,
            onTap: () => onChanged('list'),
          ),
          _ModeTab(
            icon: Icons.grid_view_rounded,
            label: 'Grid',
            selected: value == 'grid',
            accent: accent,
            onTap: () => onChanged('grid'),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 14, color: selected ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Add button
// ─────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Bookmark Item Tile
// ─────────────────────────────────────────────

class _BookmarkItemTile extends StatefulWidget {
  const _BookmarkItemTile({
    required super.key,
    required this.item,
    required this.index,
    required this.accent,
    required this.onEdit,
    required this.onDelete,
    required this.onExecute,
  });

  final BookmarkInfo item;
  final int index;
  final Color accent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExecute;

  @override
  State<_BookmarkItemTile> createState() => _BookmarkItemTileState();
}

class _BookmarkItemTileState extends State<_BookmarkItemTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color fg = theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: () {
        widget.onEdit();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _hover ? widget.accent.withValues(alpha: 0.07) : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.accent.withValues(alpha: 0.25) : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              ReorderableDragStartListener(
                index: widget.index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 16,
                    color: fg.withValues(alpha: _hover ? 0.35 : 0.15),
                  ),
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(widget.item.emoji, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.item.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      widget.item.stringToExecute,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: fg.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_rounded, size: 14, color: fg.withValues(alpha: _hover ? 0.5 : 0.2)),
              if (_hover) ...<Widget>[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.play_arrow_rounded, size: 18, color: widget.accent),
                  onPressed: widget.onExecute,
                  tooltip: 'Launch',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  onPressed: widget.onEdit,
                  tooltip: 'Edit',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 16, color: theme.colorScheme.error.withValues(alpha: 0.7)),
                  onPressed: widget.onDelete,
                  tooltip: 'Delete',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
