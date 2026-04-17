import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class BookmarksButton extends StatelessWidget {
  const BookmarksButton({super.key});
  @override
  Widget build(BuildContext context) {
    return const ModalButton(actionName: "Bookmarks", icon: Icon(Icons.folder_copy_outlined), child: BookmarksPanel());
  }
}

// ---------------------------------------------------------------------------
// Main panel
// ---------------------------------------------------------------------------

class BookmarksPanel extends StatefulWidget {
  const BookmarksPanel({super.key});
  @override
  State<BookmarksPanel> createState() => _BookmarksPanelState();
}

class _BookmarksPanelState extends State<BookmarksPanel> {
  final List<BookmarkGroup> bookmarks = Boxes().bookmarks;

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final bool boldFont = globalSettings.theme.quickMenuBoldFont;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // ── Header bar ──────────────────────────────────────────
        PanelHeader(title: "Bookmarks", accent: accent, boldFont: boldFont, icon: Icons.bookmark_rounded),
        // ── Scrollable body ─────────────────────────────────────
        Flexible(
          child: bookmarks.isEmpty
              ? _EmptyState(accent: accent)
              : _BookmarkList(
                  bookmarks: bookmarks,
                  accent: accent,
                  boldFont: boldFont,
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent});
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.bookmark_border_rounded, size: 32, color: accent.withAlpha(100)),
          const SizedBox(height: 8),
          Text(
            "No bookmarks yet",
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookmark list
// ---------------------------------------------------------------------------

class _BookmarkList extends StatelessWidget {
  const _BookmarkList({
    required this.bookmarks,
    required this.accent,
    required this.boldFont,
  });
  final List<BookmarkGroup> bookmarks;
  final Color accent;
  final bool boldFont;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int i = 0; i < bookmarks.length; i++) ...<Widget>[
            _BookmarkGroup(
              group: bookmarks[i],
              accent: accent,
              boldFont: boldFont,
            ),
            if (i < bookmarks.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(18),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single bookmark group (header + items)
// ---------------------------------------------------------------------------

class _BookmarkGroup extends StatelessWidget {
  const _BookmarkGroup({
    required this.group,
    required this.accent,
    required this.boldFont,
  });
  final BookmarkGroup group;
  final Color accent;
  final bool boldFont;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Group header row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              children: <Widget>[
                // Emoji badge
                if (group.emoji.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(group.emoji, style: const TextStyle(fontSize: 13)),
                  ),
                Expanded(
                  child: Text(
                    group.title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: accent.withAlpha(220),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Count pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(28),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${group.bookmarks.length}",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent.withAlpha(180),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Items
          ...group.bookmarks.map(
            (BookmarkInfo mark) => _BookmarkItem(
              mark: mark,
              accent: accent,
              boldFont: boldFont,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// A single bookmark row
// ---------------------------------------------------------------------------

class _BookmarkItem extends StatefulWidget {
  const _BookmarkItem({
    required this.mark,
    required this.accent,
    required this.boldFont,
  });
  final BookmarkInfo mark;
  final Color accent;
  final bool boldFont;

  @override
  State<_BookmarkItem> createState() => _BookmarkItemState();
}

class _BookmarkItemState extends State<_BookmarkItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color textColor = Theme.of(context).colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(22) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            WinUtils.open(widget.mark.stringToExecute, parseParamaters: true);
            QuickMenuFunctions.toggleQuickMenu(visible: false);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                // Left accent bar (visible on hover)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _hovered ? 2.5 : 0,
                  height: 14,
                  margin: EdgeInsets.only(right: _hovered ? 8 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Emoji
                if (widget.mark.emoji.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      widget.mark.emoji,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                // Title
                Expanded(
                  child: Text(
                    widget.mark.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: widget.boldFont ? FontWeight.w500 : FontWeight.w300,
                      color: _hovered ? textColor : textColor.withAlpha(200),
                      height: 1.3,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Arrow icon on hover
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1 : 0,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 9,
                    color: widget.accent.withAlpha(170),
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
