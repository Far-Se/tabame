import 'package:flutter/material.dart';

class HoverScaleButton extends StatefulWidget {
  final VoidCallback? onTap;
  final double zoom;
  final Widget child;

  const HoverScaleButton({super.key, this.onTap, required this.zoom, required this.child});

  @override
  State<HoverScaleButton> createState() => _HoverScaleButtonState();
}

class _HoverScaleButtonState extends State<HoverScaleButton> {
  double _targetScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      onHover: (bool hovering) {
        setState(() {
          _targetScale = hovering ? widget.zoom : 1.0;
        });
      },
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        tween: Tween<double>(begin: 1.0, end: _targetScale),
        builder: (_, double value, Widget? child) => Transform.scale(scale: value, child: child),
        child: widget.child,
      ),
    );
  }
}
