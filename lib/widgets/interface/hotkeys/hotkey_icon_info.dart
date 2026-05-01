import 'package:flutter/material.dart';

import '../../widgets/custom_tooltip.dart';

class IconInfo extends StatelessWidget {
  final IconData icon;
  final String name;
  final double horizontal;
  final double vertical;
  const IconInfo({
    super.key,
    required this.icon,
    required this.name,
    this.horizontal = 2,
    this.vertical = 0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: name,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: vertical),
        child: Icon(icon, size: 16),
      ),
    );
  }
}
