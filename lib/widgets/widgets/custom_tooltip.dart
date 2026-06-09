import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/settings.dart';
import '../../models/theme.dart';

class CustomTooltip extends StatefulWidget {
  final String message;
  final String? shortcut;
  final Widget child;
  final double verticalOffset;
  final Duration waitDuration;
  final bool preferBelow;

  const CustomTooltip({
    super.key,
    required this.message,
    this.shortcut,
    required this.child,
    this.verticalOffset = 30.0,
    this.waitDuration = const Duration(milliseconds: 110),
    this.preferBelow = false,
  });

  @override
  State<CustomTooltip> createState() => _CustomTooltipState();
}

class _CustomTooltipState extends State<CustomTooltip> {
  OverlayEntry? _overlayEntry;
  Timer? _showTimer;

  void _showTooltip() {
    _removeTooltip();

    final RenderObject? renderObject = context.findRenderObject();
    if (renderObject == null || renderObject is! RenderBox) return;

    final RenderBox renderBox = renderObject;
    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    final double screenWidth = MediaQuery.of(context).size.width;
    const double screenMargin = 8.0;

    _overlayEntry = OverlayEntry(
      builder: (BuildContext context) {
        return _TooltipOverlay(
          message: widget.message,
          shortcut: widget.shortcut,
          targetCenter: offset.dx + size.width / 2,
          targetTop: offset.dy,
          targetHeight: size.height,
          screenWidth: screenWidth,
          screenMargin: screenMargin,
          verticalOffset: widget.verticalOffset,
          preferBelow: widget.preferBelow,
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeTooltip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _showTimer?.cancel();
  }

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _showTimer = Timer(
          widget.waitDuration,
          _showTooltip,
        );
      },
      onExit: (_) => _removeTooltip(),
      child: widget.child,
    );
  }
}

class _TooltipOverlay extends StatefulWidget {
  final String message;
  final String? shortcut;
  final double targetCenter;
  final double targetTop;
  final double targetHeight;
  final double screenWidth;
  final double screenMargin;
  final double verticalOffset;
  final bool preferBelow;

  const _TooltipOverlay({
    required this.message,
    this.shortcut,
    required this.targetCenter,
    required this.targetTop,
    required this.targetHeight,
    required this.screenWidth,
    required this.screenMargin,
    required this.verticalOffset,
    required this.preferBelow,
  });

  @override
  State<_TooltipOverlay> createState() => _TooltipOverlayState();
}

class _TooltipOverlayState extends State<_TooltipOverlay> with SingleTickerProviderStateMixin {
  // final GlobalKey<State<StatefulWidget>> _key = GlobalKey();
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  double _left = 0;
  bool _positioned = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );

    _slideAnimation = Tween<Offset>(
      begin: widget.preferBelow ? const Offset(0, -4) : const Offset(0, 4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    ));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? box = context.findRenderObject() as RenderBox?;
      if (box == null) return;
      final double tooltipWidth = box.size.width;
      final double x = (widget.targetCenter - tooltipWidth / 2).clamp(
        widget.screenMargin,
        widget.screenWidth - tooltipWidth - widget.screenMargin,
      );
      setState(() {
        _left = x;
        _positioned = true;
      });
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.message.isEmpty) return const SizedBox();

    final double left = _positioned ? _left : -9999;
    final double top = widget.preferBelow
        ? widget.targetTop + widget.targetHeight + widget.verticalOffset
        : widget.targetTop - widget.verticalOffset;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: AnimatedBuilder(
            animation: _slideAnimation,
            builder: (BuildContext context, Widget? child) {
              return Transform.translate(
                offset: _slideAnimation.value,
                child: child,
              );
            },
            child: Material(
              // key: _key,
              color: Colors.transparent,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: onSurface.withValues(alpha: 0.05),
                        width: 0.5,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.getFont(
                              userSettings.themeColors.entryFontFamily,
                              fontSize: Design.baseFontSize + 1.5,
                              letterSpacing: 0.2,
                              height: 1.2,
                              color: onSurface.withValues(alpha: 0.9),
                              fontStyle: userSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                              fontWeight: AppTheme.getFontWeight(
                                userSettings.themeColors.entryFontWeight,
                              ),
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.shortcut != null) ...<Widget>[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: onSurface.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.shortcut!,
                              style: GoogleFonts.getFont(
                                userSettings.themeColors.entryFontFamily,
                                fontSize: Design.baseFontSize,
                                letterSpacing: 0.5,
                                color: onSurface.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
