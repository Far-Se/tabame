import 'package:flutter/material.dart';

import 'custom_tooltip.dart';

class QuickActionItem extends StatefulWidget {
  final String message;
  final Widget icon;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onTertiaryTapUp;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureTapDownCallback? onTertiaryTapDown;
  final Color? hoverColor;

  const QuickActionItem({
    super.key,
    required this.message,
    required this.icon,
    this.onTap,
    this.onSecondaryTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.hoverColor,
  });

  @override
  State<QuickActionItem> createState() => _QuickActionItemState();
}

class _QuickActionItemState extends State<QuickActionItem> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return _buildSmall(context);
  }

  Widget _buildSmall(BuildContext context) {
    return SizedBox(
      width: 20,
      child: _wrap(
        borderRadius: BorderRadius.circular(5),
        child: CustomTooltip(
          message: widget.message,
          child: SizedBox(width: 20, child: _buildIcon()),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final Color? color = _hovered ? widget.hoverColor : null;
    if (color == null) return widget.icon;

    return IconTheme(
      data: IconTheme.of(context).copyWith(color: color),
      child: widget.icon,
    );
  }

  Widget _wrap({required BorderRadius borderRadius, required Widget child}) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        onVerticalDragStart: widget.onVerticalDragStart,
        onVerticalDragUpdate: widget.onVerticalDragUpdate,
        onVerticalDragEnd: widget.onVerticalDragEnd,
        onTertiaryTapDown: widget.onTertiaryTapDown,
        onTertiaryTapUp: widget.onTertiaryTapUp,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _pressed
                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)
                : (_hovered ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2) : Colors.transparent),
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      ),
    );
  }
}
