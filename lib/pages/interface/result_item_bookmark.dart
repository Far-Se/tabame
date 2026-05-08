import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/classes/app_items.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../widgets/itzy/quickmenu/bookmark_icon.dart';
import '../../widgets/widgets/custom_tooltip.dart';

// ---------------------------------------------------------------------------
// Bookmark search result union type
// ---------------------------------------------------------------------------

enum BookmarkResultKind { bookmark, cliBook, appItem }

class BookmarkSearchResult {
  const BookmarkSearchResult.bookmark(BookmarkInfo b)
      : kind = BookmarkResultKind.bookmark,
        _bookmark = b,
        _cli = null,
        _app = null;

  const BookmarkSearchResult.cli(CliBookItem c)
      : kind = BookmarkResultKind.cliBook,
        _bookmark = null,
        _cli = c,
        _app = null;

  const BookmarkSearchResult.app(AppItem a)
      : kind = BookmarkResultKind.appItem,
        _bookmark = null,
        _cli = null,
        _app = a;

  final BookmarkResultKind kind;
  final BookmarkInfo? _bookmark;
  final CliBookItem? _cli;
  final AppItem? _app;

  BookmarkInfo? get bookmark => _bookmark;
  CliBookItem? get cli => _cli;
  AppItem? get app => _app;

  String get title => _bookmark?.title ?? _cli?.key ?? _app?.name ?? '';
  String get subtitle => _bookmark?.stringToExecute ?? _cli?.value ?? _app?.path ?? '';

  String get id {
    switch (kind) {
      case BookmarkResultKind.bookmark:
        return 'bm:${_bookmark!.title}';
      case BookmarkResultKind.cliBook:
        return 'cli:${_cli!.key}';
      case BookmarkResultKind.appItem:
        return 'app:${_app!.path}';
    }
  }
}

// ---------------------------------------------------------------------------
// Bookmark / CLI / App search list item widget
// ---------------------------------------------------------------------------

class BookmarkSearchListItem extends StatefulWidget {
  const BookmarkSearchListItem({
    super.key,
    required this.result,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final BookmarkSearchResult result;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  State<BookmarkSearchListItem> createState() => _BookmarkSearchListItemState();
}

class _BookmarkSearchListItemState extends State<BookmarkSearchListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = _hovered || widget.isSelected;
    final int animMs = widget.isRepeating ? 50 : 200;
    final BookmarkSearchResult result = widget.result;

    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          setState(() => _hovered = true);
          widget.onHover();
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: animMs),
        curve: widget.isRepeating ? Curves.linear : Curves.easeIn,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? globalSettings.themeColors.accentColor.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  width: highlighted ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: highlighted ? 7 : 0),
                  decoration: BoxDecoration(
                    color: globalSettings.themeColors.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildIcon(result, globalSettings.themeColors.accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        result.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: highlighted ? widget.onSurface : widget.onSurface.withAlpha(200),
                          fontFamily: globalSettings.themeColors.entryFontFamily,
                          fontStyle: globalSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                          fontWeight: FontWeight(globalSettings.themeColors.entryFontWeight),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: highlighted ? widget.onSurface.withAlpha(170) : widget.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                // Kind badge
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _KindBadge(
                      kind: result.kind, accent: globalSettings.themeColors.accentColor, onSurface: widget.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BookmarkSearchResult result, Color accent) {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        return BookmarkIcon(mark: result.bookmark!, size: 16);
      case BookmarkResultKind.cliBook:
        return Icon(Icons.terminal_rounded, size: 16, color: accent.withAlpha(200));
      case BookmarkResultKind.appItem:
        // Use a file-based icon via BookmarkInfo wrapper
        return BookmarkIcon(
          mark: BookmarkInfo(
            emoji: '',
            title: result.app!.name,
            stringToExecute: result.app!.path,
            preferInputIcon: true,
          ),
          size: 16,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Small kind badge chip
// ---------------------------------------------------------------------------

class _KindBadge extends StatelessWidget {
  const _KindBadge({
    required this.kind,
    required this.accent,
    required this.onSurface,
  });

  final BookmarkResultKind kind;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    final Color color;
    switch (kind) {
      case BookmarkResultKind.bookmark:
        label = 'BM';
        icon = Icons.bookmark_rounded;
        color = Colors.deepPurple;
      case BookmarkResultKind.cliBook:
        label = 'CLI';
        icon = Icons.terminal_rounded;
        color = Colors.brown;
      case BookmarkResultKind.appItem:
        label = 'APP';
        icon = Icons.apps_rounded;
        color = Colors.green;
    }
    return CustomTooltip(
      verticalOffset: 45,
      message: switch (kind) {
        BookmarkResultKind.bookmark => 'Bookmark \n press Enter to open',
        BookmarkResultKind.cliBook => 'CLI command \n press Enter to copy',
        BookmarkResultKind.appItem => 'App \n press Enter to launch',
      },
      child: Container(
        decoration: BoxDecoration(
          color: color.withAlpha(60),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withAlpha(40)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withAlpha(22),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withAlpha(40)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 9, color: accent.withAlpha(180)),
              const SizedBox(width: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: accent.withAlpha(200),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
