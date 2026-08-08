import 'package:flutter/material.dart';

import '../../../platform/platform_models.dart';

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

  final PlatformWindow window;
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
          window.icon,
          width: 20,
          height: 20,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 18),
          fallback: const Icon(Icons.web_asset_sharp, size: 18),
        ),
      ),
      title: window.title,
      subtitle: (window.executable.isNotEmpty ? window.executable : window.applicationName).replaceFirst('.exe', ''),
      badge: LauncherKindBadge(
        icon: Icons.window_rounded,
        label: 'WINDOW',
        color: Colors.black45,
        accent: accent,
      ),
    );
  }
}
