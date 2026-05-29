// ignore_for_file: always_specify_types

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/win32/win_utils.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../../widgets/itzy/quickmenu/bookmark_icon.dart';
import '../../../widgets/widgets/extracted_icon.dart';
import '../../launcher_search_models.dart';
import 'result_item_bookmark.dart' show BookmarkResultKind, BookmarkSearchResult;

// ---------------------------------------------------------------------------
// Design-level constants
// ---------------------------------------------------------------------------

/// Shared visual tokens for the Serene design.
///
/// All magic numbers live here so tweaking the look stays in one place.
abstract final class _SereneTokens {
  // Row geometry
  static const double rowHPad = 12;
  static const double rowVPad = 7;
  static const double rowRadius = 10.0;
  static const double rowVMargin = 1.5;

  // Icon well
  static const double iconWellSize = 30;
  static const double iconWellRadius = 7;
  static const double iconSize = 17;

  // Typography
  static const double titleSize = 13;
  static const double subtitleSize = 11;

  // Badge
  static const double badgeFontSize = 9;
  static const double badgeRadius = 5;

  // Selection fill opacity (0-255)
  static const int selectionFillAlpha = 40;
  // static const int hoverFillAlpha = 22;

  // Animation
  static const Duration fastAnim = Duration(milliseconds: 80);
  static const Duration normalAnim = Duration(milliseconds: 180);
  static const Curve animCurve = Curves.easeInOut;
}

// ---------------------------------------------------------------------------
// Small reusable building blocks
// ---------------------------------------------------------------------------

/// A rounded square "well" that wraps an icon — mimics macOS Spotlight icon
/// presentation.
class _SereneIconWell extends StatelessWidget {
  const _SereneIconWell({
    required this.child,
    required this.accent,
    this.isSelected = false,
  });

  final Widget child;
  final Color accent;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SereneTokens.iconWellSize,
      height: _SereneTokens.iconWellSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(isSelected ? 36 : 20),
        borderRadius: BorderRadius.circular(_SereneTokens.iconWellRadius),
      ),
      child: child,
    );
  }
}

/// The two-line title / subtitle text column shared by every result row.
class _SereneTitleSubtitle extends StatelessWidget {
  const _SereneTitleSubtitle({
    required this.title,
    required this.subtitle,
    required this.onSurface,
    required this.isSelected,
  });

  final String title;
  final String subtitle;
  final Color onSurface;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _SereneTokens.titleSize,
            fontWeight: FontWeight.w500,
            color: isSelected ? onSurface : onSurface.withAlpha(210),
            letterSpacing: -0.1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _SereneTokens.subtitleSize,
            color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// A small pill badge – cleaner than the classic one: no border, pure
/// translucent fill, SF-style mono label.
class _SereneBadge extends StatelessWidget {
  const _SereneBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(_SereneTokens.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: color.withAlpha(180)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: _SereneTokens.badgeFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: color.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}

/// The translucent row container that reacts to selection / hover state.
/// Selection is expressed as a diffuse fill (no coloured left bar).
class _SereneRowContainer extends StatelessWidget {
  const _SereneRowContainer({
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.child,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration dur = isRepeating ? _SereneTokens.fastAnim : _SereneTokens.normalAnim;
    return AnimatedContainer(
      duration: dur,
      curve: _SereneTokens.animCurve,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: _SereneTokens.rowVMargin),
      padding: const EdgeInsets.symmetric(
        horizontal: _SereneTokens.rowHPad,
        vertical: _SereneTokens.rowVPad,
      ),
      decoration: BoxDecoration(
        color: isSelected ? accent.withAlpha(_SereneTokens.selectionFillAlpha) : Colors.transparent,
        borderRadius: BorderRadius.circular(_SereneTokens.rowRadius),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// App result item
// ---------------------------------------------------------------------------

/// Serene-style launcher row for a Windows application result.
class SereneAppListItem extends StatelessWidget {
  const SereneAppListItem({
    super.key,
    required this.app,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final LauncherAppResult app;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent e) {
        if (e.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: _SereneRowContainer(
          isSelected: isSelected,
          isRepeating: isRepeating,
          accent: accent,
          child: Row(
            children: <Widget>[
              _SereneIconWell(
                accent: accent,
                isSelected: isSelected,
                child: _AppIcon(app: app, size: _SereneTokens.iconSize),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SereneTitleSubtitle(
                  title: app.name,
                  subtitle: app.subtitle,
                  onSurface: onSurface,
                  isSelected: isSelected,
                ),
              ),
              const SizedBox(width: 6),
              _SereneBadge(
                label: 'App',
                icon: Icons.apps_rounded,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// App icon helper (same logic as the classic AppResultIcon).
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.app, required this.size});

  final LauncherAppResult app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final File file = File('${WinUtils.getTabameAppDataFolder()}/cache/icon_cache/app_${app.iconCacheKey}.png');
    if (file.existsSync()) {
      return Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Icon(Icons.apps_rounded, size: size, color: Colors.white54);
}

// ---------------------------------------------------------------------------
// File result item
// ---------------------------------------------------------------------------

/// Serene-style launcher row for a file-system entity.
class SereneLauncherFileListItem extends StatelessWidget {
  const SereneLauncherFileListItem({
    super.key,
    required this.entity,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final FileSystemEntity entity;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final String path = entity.path;
    final int sepIdx = path.lastIndexOf(Platform.pathSeparator);
    final String name = (sepIdx >= 0 ? path.substring(sepIdx + 1) : path).replaceFirst('.lnk', '');
    final bool isDir = entity is Directory;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent e) {
          if (e.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: _SereneRowContainer(
            isSelected: isSelected,
            isRepeating: isRepeating,
            accent: accent,
            child: Row(
              children: <Widget>[
                _SereneIconWell(
                  accent: accent,
                  isSelected: isSelected,
                  child: RepaintBoundary(
                    child: BookmarkIcon(
                      mark: BookmarkInfo(
                        emoji: '',
                        title: path,
                        stringToExecute: path,
                        preferInputIcon: true,
                      ),
                      size: _SereneTokens.iconSize,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SereneTitleSubtitle(
                    title: name,
                    subtitle: path,
                    onSurface: onSurface,
                    isSelected: isSelected,
                  ),
                ),
                const SizedBox(width: 6),
                _SereneBadge(
                  label: isDir ? 'Folder' : 'File',
                  icon: isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bookmark / CLI / App-item result
// ---------------------------------------------------------------------------

/// Serene-style launcher row for bookmarks, CLI commands, and app-item results.
class SereneBookmarkSearchListItem extends StatefulWidget {
  const SereneBookmarkSearchListItem({
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
  State<SereneBookmarkSearchListItem> createState() => _SereneBookmarkSearchListItemState();
}

class _SereneBookmarkSearchListItemState extends State<SereneBookmarkSearchListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = _hovered || widget.isSelected;
    final BookmarkSearchResult result = widget.result;
    final Color accent = widget.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent e) {
        if (e.delta != Offset.zero) {
          if (!_hovered) setState(() => _hovered = true);
          widget.onHover();
        }
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: _SereneRowContainer(
          isSelected: highlighted,
          isRepeating: widget.isRepeating,
          accent: accent,
          child: Row(
            children: <Widget>[
              _SereneIconWell(
                accent: accent,
                isSelected: highlighted,
                child: _bookmarkIcon(result, accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SereneTitleSubtitle(
                  title: result.title,
                  subtitle: result.subtitle,
                  onSurface: widget.onSurface,
                  isSelected: highlighted,
                ),
              ),
              const SizedBox(width: 6),
              _bookmarkBadge(result.kind, accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookmarkIcon(BookmarkSearchResult result, Color accent) {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        return BookmarkIcon(mark: result.bookmark!, size: _SereneTokens.iconSize);
      case BookmarkResultKind.cliBook:
        return Icon(Icons.terminal_rounded, size: _SereneTokens.iconSize, color: accent.withAlpha(200));
      case BookmarkResultKind.appItem:
        return BookmarkIcon(
          mark: BookmarkInfo(
            emoji: '',
            title: result.app!.name,
            stringToExecute: result.app!.path,
            preferInputIcon: true,
          ),
          size: _SereneTokens.iconSize,
        );
    }
  }

  Widget _bookmarkBadge(BookmarkResultKind kind, Color accent) {
    switch (kind) {
      case BookmarkResultKind.bookmark:
        return const _SereneBadge(label: 'Bookmark', icon: Icons.bookmark_rounded, color: Color(0xFF8F83D8));
      case BookmarkResultKind.cliBook:
        return const _SereneBadge(label: 'CLI', icon: Icons.terminal_rounded, color: Colors.brown);
      case BookmarkResultKind.appItem:
        return const _SereneBadge(label: 'App', icon: Icons.apps_rounded, color: Colors.green);
    }
  }
}

// ---------------------------------------------------------------------------
// Window result item
// ---------------------------------------------------------------------------

/// Serene-style launcher row for an open Window.
///
/// Like the classic [WindowSearchListItem] this widget is fully stateless:
/// selection is driven entirely by the parent's [isSelected] prop.
class SereneWindowSearchListItem extends StatelessWidget {
  const SereneWindowSearchListItem({
    super.key,
    required this.window,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final Window window;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent e) {
        if (e.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: _SereneRowContainer(
          isSelected: isSelected,
          isRepeating: isRepeating,
          accent: accent,
          child: Row(
            children: <Widget>[
              _SereneIconWell(
                accent: accent,
                isSelected: isSelected,
                child: SizedBox(
                  width: _SereneTokens.iconSize,
                  height: _SereneTokens.iconSize,
                  child: buildExtractedIcon(
                    WindowWatcher.icons[window.hWnd],
                    width: _SereneTokens.iconSize,
                    height: _SereneTokens.iconSize,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 15),
                    fallback: const Icon(Icons.web_asset_sharp, size: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SereneTitleSubtitle(
                  title: window.title,
                  subtitle: window.process.exe.replaceFirst('.exe', ''),
                  onSurface: onSurface,
                  isSelected: isSelected,
                ),
              ),
              // Pin dot — small and unobtrusive
              if (window.isPinned)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.push_pin_rounded,
                    size: 10,
                    color: accent.withAlpha(160),
                  ),
                ),
              _SereneBadge(
                label: 'Window',
                icon: Icons.window_rounded,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
