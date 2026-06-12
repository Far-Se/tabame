import 'package:flutter/material.dart';

import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../../widgets/widgets/extracted_icon.dart';
import 'result_row.dart';

class WindowSearchListItem extends StatelessWidget {
  const WindowSearchListItem({
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
        child: buildExtractedIcon(
          WindowWatcher.icons[window.hWnd],
          width: 20,
          height: 20,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 18),
          fallback: const Icon(Icons.web_asset_sharp, size: 18),
        ),
      ),
      title: window.title,
      subtitle: window.process.exe.replaceFirst('.exe', ''),
      badge: LauncherKindBadge(
        icon: Icons.window_rounded,
        label: 'WIN',
        color: Colors.black45,
        accent: accent,
      ),
    );
  }
}
