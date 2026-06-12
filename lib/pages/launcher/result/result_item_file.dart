import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../widgets/itzy/quickmenu/bookmark_icon.dart';
import 'result_row.dart';

// ---------------------------------------------------------------------------
// File icon helper
// ---------------------------------------------------------------------------

class FileResultIcon extends StatelessWidget {
  const FileResultIcon({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: BookmarkIcon(
        mark: BookmarkInfo(
          emoji: '',
          title: path,
          stringToExecute: path,
          preferInputIcon: true,
        ),
        size: 20,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// File result list item
// ---------------------------------------------------------------------------

class LauncherListItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final String path = entity.path;
    final int sepIdx = path.lastIndexOf(Platform.pathSeparator);
    final String name = sepIdx >= 0 ? path.substring(sepIdx + 1) : path;
    return LauncherResultRow(
      isSelected: isSelected,
      isRepeating: isRepeating,
      accent: accent,
      onSurface: onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: SizedBox(
        width: 20,
        height: 20,
        child: FileResultIcon(path: path),
      ),
      title: name.replaceFirst('.lnk', ''),
      subtitle: path,
      badge: _FileKindBadge(
        isDirectory: entity.path.split('.').length != 2,
        accent: userSettings.themeColors.accent,
        onSurface: onSurface,
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withAlpha(22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isDirectory ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
            size: 9,
            color: accent.withAlpha(180),
          ),
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
    );
  }
}
