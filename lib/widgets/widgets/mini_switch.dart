import 'package:flutter/material.dart';

import '../../models/settings.dart';

class MiniToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Active color
  final Color? activeThumbColor;
  final Color? activeTrackColor;

  /// Optional custom sizing
  final double width;
  final double height;

  const MiniToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeThumbColor,
    this.activeTrackColor,
    this.width = 32,
    this.height = 18,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged != null ? () => onChanged!(!value) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: width,
            height: height,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: value
                  ? (activeTrackColor ?? activeThumbColor ?? Design.accent).withAlpha(40)
                  : colors.onSurface.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: value ? (activeThumbColor ?? Design.accent).withAlpha(100) : colors.outlineVariant.withAlpha(40),
              ),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: value ? (activeThumbColor ?? Design.accent) : colors.onSurfaceVariant.withAlpha(100),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
