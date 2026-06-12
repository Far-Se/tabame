import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/win32/win_utils.dart';
import '../../launcher_search_models.dart';
import 'result_row.dart';

class AppResultIcon extends StatelessWidget {
  const AppResultIcon({
    super.key,
    required this.app,
    this.size = 20,
  });

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
        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Icon(
      Icons.apps_rounded,
      size: size,
      color: Colors.white70,
    );
  }
}

class LauncherAppListItem extends StatelessWidget {
  const LauncherAppListItem({
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
    return LauncherResultRow(
      isSelected: isSelected,
      isRepeating: isRepeating,
      accent: accent,
      onSurface: onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: AppResultIcon(app: app),
      title: app.name,
      subtitle: app.subtitle,
      badge: LauncherKindBadge(
        icon: Icons.apps_rounded,
        label: 'APP',
        color: const Color(0xff0078D6),
        accent: accent,
      ),
    );
  }
}
