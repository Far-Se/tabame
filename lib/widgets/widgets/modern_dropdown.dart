import 'package:flutter/material.dart';

import 'custom_tooltip.dart';

class ModernDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;

  const ModernDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

class ModernDropdown<T> extends StatelessWidget {
  final T value;
  final List<ModernDropdownItem<T>> items;
  final void Function(T? newValue) onChanged;
  final String? labelText;
  final Widget? prefixIcon;
  final bool isExpanded;

  const ModernDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.prefixIcon,
    this.isExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    final ModernDropdownItem<T> selectedItem = items.firstWhere(
      (ModernDropdownItem<T> item) => item.value == value,
      orElse: () => items.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (labelText != null) ...<Widget>[
          Text(
            labelText!,
            style: texts.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Theme(
          data: Theme.of(context).copyWith(
            hoverColor: colors.primary.withAlpha(0),
            splashColor: colors.primary.withAlpha(0),
          ),
          child: CustomTooltip(
            message: labelText ?? "Select option",
            child: PopupMenuButton<T>(
              onSelected: onChanged,
              tooltip: "",
              offset: const Offset(0, 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant.withAlpha(100)),
              ),
              elevation: 8,
              shadowColor: Colors.black.withAlpha(100),
              position: PopupMenuPosition.under,
              itemBuilder: (BuildContext context) => items.map((ModernDropdownItem<T> item) {
                final bool isSelected = item.value == value;
                return PopupMenuItem<T>(
                  value: item.value,
                  height: 40,
                  child: Row(
                    children: <Widget>[
                      if (item.icon != null) ...<Widget>[
                        Icon(item.icon, size: 18, color: isSelected ? colors.primary : colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        item.label,
                        style: texts.bodyMedium?.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colors.primary : colors.onSurface,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected) Icon(Icons.check_rounded, size: 16, color: colors.primary),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant.withAlpha(100)),
                ),
                child: Row(
                  children: <Widget>[
                    if (prefixIcon != null) ...<Widget>[
                      prefixIcon!,
                      const SizedBox(width: 12),
                    ],
                    if (selectedItem.icon != null && prefixIcon == null) ...<Widget>[
                      Icon(selectedItem.icon, size: 18, color: colors.primary),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        selectedItem.label,
                        style: texts.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.unfold_more_rounded, size: 18, color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
