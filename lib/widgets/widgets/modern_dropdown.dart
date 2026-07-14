import 'package:flutter/material.dart';
import 'custom_tooltip.dart';
import 'windows_scroll.dart';

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
  final double height;
  final double itemHeight;

  // Shows a search field on top of the popup that filters the visible results.
  final bool showSearch;

  // Custom decoration parameters
  final BoxDecoration? decoration;
  final ShapeBorder? dropdownMenuEntriesShape;

  const ModernDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.labelText,
    this.prefixIcon,
    this.height = 48,
    this.itemHeight = 40,
    this.isExpanded = true,
    this.showSearch = false,
    this.decoration,
    this.dropdownMenuEntriesShape,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final TextTheme texts = Theme.of(context).textTheme;

    final ModernDropdownItem<T> selectedItem = items.firstWhere(
      (ModernDropdownItem<T> item) => item.value == value,
      orElse: () => items.first,
    );

    // Default decoration if none is passed via parameters
    final BoxDecoration defaultDecoration = BoxDecoration(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: colors.outlineVariant.withAlpha(100)),
    );

    // Default popup menu border if none is passed via parameters
    final ShapeBorder defaultMenuShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: colors.outlineVariant.withAlpha(100)),
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
        CustomTooltip(
          message: labelText ?? "Select option",
          child: PopupMenuButton<T>(
            onSelected: onChanged,
            tooltip: "",
            offset: const Offset(0, 0),
            shape: dropdownMenuEntriesShape ?? defaultMenuShape,
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            shadowColor: Colors.black.withAlpha(100),
            position: PopupMenuPosition.under,
            itemBuilder: (BuildContext context) {
              if (showSearch) {
                return <PopupMenuEntry<T>>[
                  PopupMenuItem<T>(
                    enabled: false,
                    padding: EdgeInsets.zero,
                    child: _SearchableDropdownContent<T>(
                      items: items,
                      value: value,
                      itemHeight: itemHeight,
                      colors: colors,
                      texts: texts,
                      onSelected: (T selected) {
                        Navigator.of(context).pop();
                        onChanged(selected);
                      },
                    ),
                  ),
                ];
              }
              return items.map((ModernDropdownItem<T> item) {
                final bool isSelected = item.value == value;
                return PopupMenuItem<T>(
                  value: item.value,
                  height: itemHeight,
                  child: Row(
                    children: <Widget>[
                      if (item.icon != null) ...<Widget>[
                        Icon(
                          item.icon,
                          size: 18,
                          color: isSelected ? colors.primary : colors.onSurfaceVariant,
                        ),
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
              }).toList();
            },
            child: Container(
              height: height,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: decoration ?? defaultDecoration,
              child: Row(
                mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
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
      ],
    );
  }
}

class _SearchableDropdownContent<T> extends StatefulWidget {
  final List<ModernDropdownItem<T>> items;
  final T value;
  final double itemHeight;
  final ColorScheme colors;
  final TextTheme texts;
  final void Function(T selected) onSelected;

  const _SearchableDropdownContent({
    super.key,
    required this.items,
    required this.value,
    required this.itemHeight,
    required this.colors,
    required this.texts,
    required this.onSelected,
  });

  @override
  State<_SearchableDropdownContent<T>> createState() => _SearchableDropdownContentState<T>();
}

class _SearchableDropdownContentState<T> extends State<_SearchableDropdownContent<T>> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _query = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Measures the widest label so the popup is wide enough to avoid ellipsis,
  // clamped to a sensible min/max range.
  double _contentWidth(TextTheme texts) {
    double widest = 0;
    final TextStyle? style = texts.bodyMedium;
    for (final ModernDropdownItem<T> item in widget.items) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: item.label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // label + optional icon (18 + 12) + trailing check (16) + row/container padding.
      double itemWidth = painter.width + 24 + 16 + 8;
      if (item.icon != null) itemWidth += 30;
      if (itemWidth > widest) widest = itemWidth;
    }
    return widest.clamp(200.0, 400.0);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = widget.colors;
    final TextTheme texts = widget.texts;

    final List<ModernDropdownItem<T>> filtered = _query.isEmpty
        ? widget.items
        : widget.items.where((ModernDropdownItem<T> item) => item.label.toLowerCase().contains(_query.toLowerCase())).toList();

    return SizedBox(
      width: _contentWidth(texts),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: texts.bodyMedium,
              onChanged: (String value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                hintText: "Search...",
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: colors.onSurfaceVariant),
                prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.outlineVariant.withAlpha(100)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.outlineVariant.withAlpha(100)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      "No results",
                      style: texts.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  )
                : WindowsScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: filtered.map((ModernDropdownItem<T> item) {
                        final bool isSelected = item.value == widget.value;
                        return InkWell(
                          onTap: () => widget.onSelected(item.value),
                          child: Container(
                            height: widget.itemHeight,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: <Widget>[
                                if (item.icon != null) ...<Widget>[
                                  Icon(
                                    item.icon,
                                    size: 18,
                                    color: isSelected ? colors.primary : colors.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: texts.bodyMedium?.copyWith(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      color: isSelected ? colors.primary : colors.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected) Icon(Icons.check_rounded, size: 16, color: colors.primary),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
