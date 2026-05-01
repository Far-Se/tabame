import 'package:flutter/material.dart';

import 'custom_tooltip.dart';

class InkWellButton extends StatelessWidget {
  const InkWellButton({
    super.key,
    required this.onTap,
    this.label,
    this.icon,
    this.child,
    required this.color,
    this.padding = const EdgeInsets.symmetric(vertical: 9, horizontal: 32),
    this.borderRadius = 8,
    this.fontSize = 11.5,
    this.fontWeight = FontWeight.w700,
    this.mainAxisSize = MainAxisSize.min,
    this.tooltip,
  });

  final VoidCallback onTap;
  final String? label;
  final IconData? icon;
  final Widget? child;
  final Color color;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double fontSize;
  final FontWeight fontWeight;
  final MainAxisSize mainAxisSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget current = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(borderRadius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: padding,
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: color.withAlpha(80), width: 1),
        ),
        child: child ??
            Row(
              mainAxisSize: mainAxisSize,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: fontSize + 3, color: color),
                  const SizedBox(width: 8),
                ],
                if (label != null)
                  Flexible(
                    child: Text(
                      label!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        letterSpacing: 0.5,
                        color: color,
                      ),
                    ),
                  ),
              ],
            ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      current = CustomTooltip(
        message: tooltip!,
        child: current,
      );
    }

    return current;
  }
}
