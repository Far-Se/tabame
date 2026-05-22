import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
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

class QuickmenuBookmarksSettingsPage extends StatefulWidget {
  const QuickmenuBookmarksSettingsPage({super.key});

  @override
  State<QuickmenuBookmarksSettingsPage> createState() => _QuickmenuBookmarksSettingsPageState();
}

class _QuickmenuBookmarksSettingsPageState extends State<QuickmenuBookmarksSettingsPage> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;
  final Set<String> _expandedGroups = <String>{};

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final double horizontalPadding = isWide ? 16 : 8;

        return WindowsScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: <Widget>[
                    _buildHeaderCard(context, accent, onSurface),
                    const SizedBox(height: 16),
                    if (bookmarks.isEmpty)
                      _buildEmptyState(context, accent, onSurface)
                    else
                      ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        shrinkWrap: true,
                        dragStartBehavior: DragStartBehavior.down,
                        itemCount: bookmarks.length,
                        physics: const NeverScrollableScrollPhysics(),
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
                              if (context.mounted) {
                                _showDialogItem(context, project, project.bookmarks.length - 1, groupKey);
                              }
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
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCard(BuildContext context, Color accent, Color onSurface) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.bookmarks_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Bookmark Groups",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Group useful files, URLs, and scripts for quick access",
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () async {
              final List<String> emojis = <String>["✨", "📂", "💼", "🏢", "🏠", "🌟", "🛠️"];
              final String randomEmoji = emojis[Random().nextInt(emojis.length)];
              final BookmarkGroup newGroup =
                  BookmarkGroup(title: "New Group", emoji: randomEmoji, bookmarks: <BookmarkInfo>[]);
              bookmarks.add(newGroup);
              final int newIndex = bookmarks.length - 1;
              _expandedGroups.add("${newGroup.title}_$newIndex");
              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
              setState(() {});
              if (context.mounted) {
                _showDialogGroup(context, newGroup, newIndex);
              }
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("New Group"),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: <Widget>[
          Icon(Icons.bookmark_add_outlined, size: 64, color: onSurface.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          Text(
            "No Bookmarks Yet",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Create groups to organize your workspace and access everything from the main panel.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }

  // --- Modal Dialogs (Copied and slightly adjusted from bookmarks.dart) ---

  Future<void> _showDialogGroup(BuildContext context, BookmarkGroup project, int mainIndex) async {
    String currentEmoji = project.emoji;
    String currentTitle = project.title;
    String currentViewMode = project.viewMode;
    final Color accent = userSettings.themeColors.accentColor;
    final ThemeData theme = Theme.of(context);

    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Center(
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  width: min(MediaQuery.of(context).size.width * 0.9, 420),
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
                        "Group Configuration",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 24),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Padding(
                                  padding: EdgeInsets.only(left: 4, bottom: 8),
                                  child: Text(
                                    "SYMBOL",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  onTap: () async {
                                    final String? emoji = await showEmojiPickerModal(context,
                                        initialValue: project.emoji, title: "Pick an emoji for ${project.title}");
                                    if (emoji != null) {
                                      setModalState(() {
                                        currentEmoji = emoji;
                                      });
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    width: 60,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: accent.withValues(alpha: 0.2)),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(currentEmoji, style: const TextStyle(fontSize: 28)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: CustomTextInput(
                                labelText: "Label",
                                value: currentTitle,
                                showLabelSeparated: true,
                                onChanged: (String val) => currentTitle = val,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Padding(
                        padding: EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(
                          "VIEW MODE",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _buildModeToggle(
                              icon: Icons.view_list_rounded,
                              label: "LIST",
                              isSelected: currentViewMode == 'list',
                              accent: accent,
                              onTap: () => setModalState(() => currentViewMode = 'list'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildModeToggle(
                              icon: Icons.grid_view_rounded,
                              label: "GRID",
                              isSelected: currentViewMode == 'grid',
                              accent: accent,
                              onTap: () => setModalState(() => currentViewMode = 'grid'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text("Cancel"),
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
                              if (title.isEmpty) return;
                              project.emoji = currentEmoji;
                              project.title = title;
                              project.viewMode = currentViewMode;
                              await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                              setState(() {});
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: const Text("Update Group"),
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
      },
    );
  }

  Widget _buildModeToggle({
    required IconData icon,
    required String label,
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accent.withValues(alpha: 0.4) : onSurface.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(icon, color: isSelected ? accent : onSurface.withValues(alpha: 0.5), size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: isSelected ? accent : onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDialogItem(BuildContext context, BookmarkGroup project, int itemIndex, String groupKey) async {
    final BookmarkInfo item = project.bookmarks[itemIndex];
    String currentEmoji = item.emoji;
    String currentTitle = item.title;
    String currentPath = item.stringToExecute;
    bool currentPreferInputIcon = item.preferInputIcon;
    final Color accent = userSettings.themeColors.accentColor;
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
                    "Bookmark Configuration",
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
                                initialValue: item.emoji, title: "Pick an emoji for ${item.title}");
                            if (emoji != null) {
                              setState(() {
                                item.emoji = emoji;
                              });
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
                            labelText: "Label",
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
                          labelText: "Target Path, URL, or Command",
                          value: currentPath,
                          onChanged: (String val) => currentPath = val,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Row(
                        children: <Widget>[
                          _buildMiniPickerButton(
                            icon: Icons.file_open_rounded,
                            tooltip: "Pick File",
                            accent: accent,
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
                            tooltip: "Pick Folder",
                            accent: accent,
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
                        label: "PREFER INPUT ICONS",
                        subtitle: "Try use favicon or file icons",
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
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () async {
                          final String title = currentTitle.trim();
                          final String path = currentPath.trim();
                          if (title.isEmpty || path.isEmpty) return;
                          item.emoji = currentEmoji;
                          item.title = title;
                          item.stringToExecute = path;
                          item.preferInputIcon = currentPreferInputIcon;
                          await Boxes.updateSettings("projects", jsonEncode(bookmarks));
                          setState(() {});
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          foregroundColor: theme.colorScheme.onPrimaryContainer,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                          ),
                        ).copyWith(
                          overlayColor: WidgetStateProperty.all(theme.colorScheme.primary.withValues(alpha: 0.1)),
                        ),
                        child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
                      )
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
                      fontSize: 10,
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
    final ThemeData theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color:
                userSettings.themeColors.accentColor.withValues(alpha: widget.isExpanded || _isHovering ? 0.3 : 0.08),
            width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Group Header
            MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: widget.onToggleExpand,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: (widget.isExpanded || _isHovering)
                        ? userSettings.themeColors.accentColor.withValues(alpha: 0.05)
                        : Colors.transparent,
                    border: Border(
                        bottom: BorderSide(
                            color: userSettings.themeColors.accentColor.withValues(alpha: widget.isExpanded ? 0.15 : 0),
                            width: 1)),
                  ),
                  child: Row(
                    children: <Widget>[
                      ReorderableDragStartListener(
                        index: widget.index,
                        child: Container(
                          padding: const EdgeInsets.only(right: 12.0),
                          color: Colors.transparent,
                          child: Icon(Icons.drag_indicator_rounded, size: 20, color: widget.onSurface.withAlpha(100)),
                        ),
                      ),
                      Text(widget.project.emoji, style: const TextStyle(fontSize: 18)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              widget.project.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: widget.isExpanded ? userSettings.themeColors.accentColor : widget.onSurface,
                              ),
                            ),
                            Text(
                              "${widget.project.bookmarks.length} saved bookmarks",
                              style: TextStyle(fontSize: 11, color: widget.onSurface.withValues(alpha: 0.4)),
                            ),
                          ],
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isHovering ? 1.0 : 0.0,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              icon: Icon(Icons.add_circle_outline_rounded,
                                  size: 20, color: widget.onSurface.withValues(alpha: 0.4)),
                              onPressed: widget.onAddBookmark,
                              tooltip: "Add Bookmark",
                            ),
                            IconButton(
                              icon: Icon(Icons.settings_outlined,
                                  size: 20, color: widget.onSurface.withValues(alpha: 0.4)),
                              onPressed: widget.onEditGroup,
                              tooltip: "Group Settings",
                            ),
                            IconButton(
                              icon: Icon(Icons.delete_outline_rounded,
                                  size: 20, color: Colors.red.withValues(alpha: 0.6)),
                              onPressed: () {
                                showDialog<void>(
                                  context: context,
                                  builder: (BuildContext context) => AlertDialog(
                                    title: const Text("Delete Group?"),
                                    content:
                                        Text("Permanently delete '${widget.project.title}' and all its bookmarks?"),
                                    actions: <Widget>[
                                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
                                      FilledButton(
                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                        onPressed: () {
                                          widget.onDeleteGroup();
                                          Navigator.pop(context);
                                        },
                                        child: const Text("Delete"),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              tooltip: "Delete Group",
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        widget.isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: widget.onSurface.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Expanded List
            if (widget.isExpanded)
              Container(
                color: widget.onSurface.withValues(alpha: 0.02),
                child: widget.project.bookmarks.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            "This group is empty.",
                            style: TextStyle(fontSize: 12, color: widget.onSurface.withValues(alpha: 0.3)),
                          ),
                        ),
                      )
                    : ReorderableListView.builder(
                        shrinkWrap: true,
                        buildDefaultDragHandles: false,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.project.bookmarks.length,
                        onReorder: widget.onReorderBookmarks,
                        itemBuilder: (BuildContext context, int index) {
                          final BookmarkInfo item = widget.project.bookmarks[index];
                          return _BookmarkItemTile(
                            key: ValueKey<String>("${widget.project.title}_bookmark_$index"),
                            item: item,
                            index: index,
                            accent: userSettings.themeColors.accentColor,
                            onSurface: widget.onSurface,
                            onEdit: () => widget.onEditBookmark(index),
                            onDelete: () => widget.onDeleteBookmark(index),
                            onExecute: () => widget.onExecuteBookmark(item),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkItemTile extends StatefulWidget {
  const _BookmarkItemTile({
    required super.key,
    required this.item,
    required this.index,
    required this.accent,
    required this.onSurface,
    required this.onEdit,
    required this.onDelete,
    required this.onExecute,
  });

  final BookmarkInfo item;
  final int index;
  final Color accent;
  final Color onSurface;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onExecute;

  @override
  State<_BookmarkItemTile> createState() => _BookmarkItemTileState();
}

class _BookmarkItemTileState extends State<_BookmarkItemTile> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: widget.onSurface.withValues(alpha: 0.05))),
          color: _isHovering ? userSettings.themeColors.accentColor.withValues(alpha: 0.05) : Colors.transparent,
        ),
        child: Row(
          children: <Widget>[
            ReorderableDragStartListener(
              index: widget.index,
              child: Icon(Icons.drag_handle_rounded, size: 16, color: widget.onSurface.withValues(alpha: 0.2)),
            ),
            const SizedBox(width: 12),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: widget.onSurface.withValues(alpha: 0.05),
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
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    widget.item.stringToExecute,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: widget.onSurface.withValues(alpha: 0.4)),
                  ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isHovering ? 1.0 : 0.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    onPressed: widget.onExecute,
                    tooltip: "Launch",
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    onPressed: widget.onEdit,
                    tooltip: "Edit",
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    onPressed: widget.onDelete,
                    tooltip: "Delete",
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
