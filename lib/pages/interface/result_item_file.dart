import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../widgets/itzy/quickmenu/bookmark_icon.dart';

// ---------------------------------------------------------------------------
// File icon helper
// ---------------------------------------------------------------------------

class FileResultIcon extends StatelessWidget {
  const FileResultIcon({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return BookmarkIcon(
      mark: BookmarkInfo(
        emoji: '',
        title: path,
        stringToExecute: path,
        preferInputIcon: true,
      ),
      size: 20,
    );
  }
}

// ---------------------------------------------------------------------------
// File result list item
// ---------------------------------------------------------------------------

class LauncherListItem extends StatefulWidget {
  const LauncherListItem({
    super.key,
    required this.entity,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.isInHistory,
    required this.onTap,
    required this.onHover,
    required this.onRemoveFromHistory,
  });

  final FileSystemEntity entity;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final bool isInHistory;
  final VoidCallback onTap;
  final VoidCallback onHover;
  final VoidCallback onRemoveFromHistory;

  @override
  State<LauncherListItem> createState() => _LauncherListItemState();
}

class _LauncherListItemState extends State<LauncherListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    // Use lastIndexOf instead of split to avoid list allocation.
    final String path = widget.entity.path;
    final int sepIdx = path.lastIndexOf(Platform.pathSeparator);
    final String name = sepIdx >= 0 ? path.substring(sepIdx + 1) : path;
    final bool highlighted = _hovered || widget.isSelected;
    final int animMs = widget.isRepeating ? 50 : 200;
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
                FileResultIcon(path: path),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        name.replaceFirst('.lnk', ''),
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
                        _hovered ? path.lastChars(40) : path,
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
                // File/Dir badge
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _FileKindBadge(
                    isDirectory: widget.entity.path.split('.').length != 2,
                    accent: globalSettings.themeColors.accentColor,
                    onSurface: widget.onSurface,
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

class _FileKindBadge extends StatelessWidget {
  const _FileKindBadge({
    required this.isDirectory,
    required this.accent,
    required this.onSurface,
  });

  final bool isDirectory;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        // color: Colors.green.withAlpha(70),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(color: accent.withAlpha(22)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
                size: 9, color: accent.withAlpha(180)),
            const SizedBox(width: 2),
            Text(
              isDirectory ? 'Folder' : 'File',
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
    );
  }
}
