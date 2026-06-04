import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/mix_widgets.dart';
import 'bookmark_icon.dart';

class BookmarkList extends StatelessWidget {
  const BookmarkList({
    super.key,
    required this.bookmarks,
    required this.accent,
    required this.onAddBookmark,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onEditBookmark,
    required this.onDeleteBookmark,
    required this.onOpenBookmark,
  });

  final List<BookmarkGroup> bookmarks;
  final Color accent;
  final ValueChanged<BookmarkGroup> onAddBookmark;
  final ValueChanged<BookmarkGroup> onEditGroup;
  final ValueChanged<BookmarkGroup> onDeleteGroup;
  final void Function(BookmarkGroup group, BookmarkInfo mark) onEditBookmark;
  final void Function(BookmarkGroup group, BookmarkInfo mark) onDeleteBookmark;
  final ValueChanged<BookmarkInfo> onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int index = 0; index < bookmarks.length; index++) ...<Widget>[
            _BookmarkGroupSection(
              group: bookmarks[index],
              accent: accent,
              onAddBookmark: () => onAddBookmark(bookmarks[index]),
              onEditGroup: () => onEditGroup(bookmarks[index]),
              onDeleteGroup: () => onDeleteGroup(bookmarks[index]),
              onEditBookmark: (BookmarkInfo mark) => onEditBookmark(bookmarks[index], mark),
              onDeleteBookmark: (BookmarkInfo mark) => onDeleteBookmark(bookmarks[index], mark),
              onOpenBookmark: onOpenBookmark,
            ),
            if (index < bookmarks.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _BookmarkGroupSection extends StatelessWidget {
  const _BookmarkGroupSection({
    required this.group,
    required this.accent,
    required this.onAddBookmark,
    required this.onEditGroup,
    required this.onDeleteGroup,
    required this.onEditBookmark,
    required this.onDeleteBookmark,
    required this.onOpenBookmark,
  });

  final BookmarkGroup group;
  final Color accent;
  final VoidCallback onAddBookmark;
  final VoidCallback onEditGroup;
  final VoidCallback onDeleteGroup;
  final ValueChanged<BookmarkInfo> onEditBookmark;
  final ValueChanged<BookmarkInfo> onDeleteBookmark;
  final ValueChanged<BookmarkInfo> onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        CancelTraversal(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
            child: Row(
              children: <Widget>[
                Text(
                  group.emoji.isNotEmpty ? group.emoji : "📂",
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                Text(
                  group.title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: onSurface.withAlpha(180),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(28),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "${group.bookmarks.length}",
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Divider(height: 1, color: onSurface.withAlpha(25))),
                const SizedBox(width: 8),
                _GroupHeaderAction(
                  icon: Icons.edit_rounded,
                  tooltip: "Configure Category",
                  onTap: onEditGroup,
                  color: onSurface.withAlpha(100),
                ),
                const SizedBox(width: 4),
                _GroupHeaderAction(
                  icon: Icons.add_rounded,
                  tooltip: "Add Bookmark",
                  onTap: onAddBookmark,
                  color: accent.withAlpha(200),
                ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: group.bookmarks.isEmpty
              ? _EmptyGroupState(
                  key: ValueKey<String>("${group.title}_empty"),
                  accent: accent,
                  onAddBookmark: onAddBookmark,
                )
              : group.viewMode == 'grid'
                  ? _BookmarkGrid(
                      key: ValueKey<String>("${group.title}_grid"),
                      group: group,
                      accent: accent,
                      onEditBookmark: onEditBookmark,
                      onOpenBookmark: onOpenBookmark,
                    )
                  : _BookmarkRows(
                      key: ValueKey<String>("${group.title}_list"),
                      group: group,
                      accent: accent,
                      onEditBookmark: onEditBookmark,
                      onDeleteBookmark: onDeleteBookmark,
                      onOpenBookmark: onOpenBookmark,
                    ),
        ),
      ],
    );
  }
}

class _GroupHeaderAction extends StatelessWidget {
  const _GroupHeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withAlpha(30)),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
      ),
    );
  }
}

class _EmptyGroupState extends StatelessWidget {
  const _EmptyGroupState({
    super.key,
    required this.accent,
    required this.onAddBookmark,
  });

  final Color accent;
  final VoidCallback onAddBookmark;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onAddBookmark,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: onSurface.withAlpha(6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: onSurface.withAlpha(12), style: BorderStyle.solid),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.add_box_outlined, size: 14, color: onSurface.withAlpha(100)),
              const SizedBox(width: 8),
              Text(
                "TAP TO ADD FIRST BOOKMARK",
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: onSurface.withAlpha(120),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookmarkRows extends StatelessWidget {
  const _BookmarkRows({
    super.key,
    required this.group,
    required this.accent,
    required this.onEditBookmark,
    required this.onDeleteBookmark,
    required this.onOpenBookmark,
  });

  final BookmarkGroup group;
  final Color accent;
  final ValueChanged<BookmarkInfo> onEditBookmark;
  final ValueChanged<BookmarkInfo> onDeleteBookmark;
  final ValueChanged<BookmarkInfo> onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: group.bookmarks
          .map(
            (BookmarkInfo mark) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
              child: _BookmarkRowItem(
                mark: mark,
                accent: accent,
                onOpen: () => onOpenBookmark(mark),
                onEdit: () => onEditBookmark(mark),
                onDelete: () => onDeleteBookmark(mark),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _BookmarkRowItem extends StatefulWidget {
  const _BookmarkRowItem({
    required this.mark,
    required this.accent,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final BookmarkInfo mark;
  final Color accent;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_BookmarkRowItem> createState() => _BookmarkRowItemState();
}

class _BookmarkRowItemState extends State<_BookmarkRowItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 1.5),
        decoration: BoxDecoration(
          color: _hovered ? userSettings.themeColors.accent.withAlpha(25) : onSurface.withAlpha(5),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: _hovered ? userSettings.themeColors.accent.withAlpha(60) : onSurface.withAlpha(12),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: widget.onOpen,
          onSecondaryTap: widget.onEdit,
          onSecondaryTapDown: (_) {
            QuickMenuFunctions.keepOpen = true;
            Timer(const Duration(milliseconds: 500), () => QuickMenuFunctions.keepOpen = false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: <Widget>[
                BookmarkIcon(
                  mark: widget.mark,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.mark.title,
                    style: entryStyle(_hovered, fontSize: 11.5, letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IgnorePointer(
                  ignoring: !_hovered,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _hovered ? 0.8 : 0,
                    child: _RowAction(
                      icon: Icons.edit_rounded,
                      onTap: widget.onEdit,
                      color: onSurface.withAlpha(160),
                    ),
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

class _BookmarkGrid extends StatelessWidget {
  const _BookmarkGrid({
    super.key,
    required this.group,
    required this.accent,
    required this.onEditBookmark,
    required this.onOpenBookmark,
  });

  final BookmarkGroup group;
  final Color accent;
  final ValueChanged<BookmarkInfo> onEditBookmark;
  final ValueChanged<BookmarkInfo> onOpenBookmark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 4),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 48,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1,
        ),
        itemCount: group.bookmarks.length,
        itemBuilder: (BuildContext context, int index) {
          final BookmarkInfo mark = group.bookmarks[index];
          return _BookmarkGridItem(
            mark: mark,
            accent: accent,
            fallbackEmoji: group.emoji,
            onTap: () => onOpenBookmark(mark),
            onEdit: () => onEditBookmark(mark),
          );
        },
      ),
    );
  }
}

class _BookmarkGridItem extends StatefulWidget {
  const _BookmarkGridItem({
    required this.mark,
    required this.accent,
    required this.fallbackEmoji,
    required this.onTap,
    required this.onEdit,
  });

  final BookmarkInfo mark;
  final Color accent;
  final String fallbackEmoji;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  State<_BookmarkGridItem> createState() => _BookmarkGridItemState();
}

class _BookmarkGridItemState extends State<_BookmarkGridItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return CustomTooltip(
      message: widget.mark.title,
      waitDuration: const Duration(milliseconds: 140),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: widget.onTap,
          onDoubleTap: widget.onEdit,
          onSecondaryTap: widget.onEdit,
          onSecondaryTapDown: (_) {
            QuickMenuFunctions.keepOpen = true;
            Timer(const Duration(milliseconds: 500), () => QuickMenuFunctions.keepOpen = false);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _hovered ? userSettings.themeColors.accent.withAlpha(35) : onSurface.withAlpha(10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                  color: _hovered ? userSettings.themeColors.accent.withAlpha(110) : onSurface.withAlpha(18), width: 1),
            ),
            child: Center(
              child: BookmarkIcon(
                mark: widget.mark,
                fallbackEmoji: widget.fallbackEmoji,
                size: _hovered ? 23 : 21,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.icon,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(30)),
        ),
        child: Icon(icon, size: 12, color: color),
      ),
    );
  }
}
