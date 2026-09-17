import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/classes/boxes/boxes_base.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import 'panel_header.dart';

class BMACDialog extends StatelessWidget {
  final bool center;
  const BMACDialog({super.key, required this.center});

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final ThemeData theme = Theme.of(context);
    final Color surface = theme.colorScheme.surface;

    return Align(
      alignment: center == true ? AlignmentGeometry.center : AlignmentGeometry.topCenter,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: center == true ? const EdgeInsets.all(0) : const EdgeInsets.only(top: 70),
            child: Container(
              width: 320,
              decoration: BoxDecoration(
                color: surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.3), width: 1),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const PanelHeader(
                    title: "Support Tabame",
                    icon: Icons.favorite_rounded,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      children: <Widget>[
                        Text(
                          "Tabame is provided for free. If you find it useful, your support helps maintain the project.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _BuyMeACoffeeButton(
                          onTap: () {
                            WinUtils.open("https://www.buymeacoffee.com/far.se");
                            Boxes.pref.setBool("bmacPopup", true);
                            Navigator.of(context).pop();
                          },
                        ),
                        const SizedBox(height: 12),
                        Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              Boxes.pref.setBool("bmacPopup", true);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                "Don't show again",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: Design.baseFontSize + 1,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BuyMeACoffeeButton extends StatefulWidget {
  const _BuyMeACoffeeButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BuyMeACoffeeButton> createState() => _BuyMeACoffeeButtonState();
}

class _BuyMeACoffeeButtonState extends State<_BuyMeACoffeeButton> with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);

    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion || !hovered) {
      _sweepController.stop();
    } else {
      _sweepController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedBuilder(
          animation: _sweepController,
          builder: (BuildContext context, Widget? child) {
            return CustomPaint(
              painter: _CoffeeButtonPainter(
                accent: Design.accent,
                hovered: _hovered,
                progress: reduceMotion ? 0 : _sweepController.value,
              ),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.coffee_rounded, size: 18, color: Design.accent),
                const SizedBox(width: 10),
                Text(
                  "Buy me a Coffee",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Design.accent,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoffeeButtonPainter extends CustomPainter {
  const _CoffeeButtonPainter({
    required this.accent,
    required this.hovered,
    required this.progress,
  });

  final Color accent;
  final bool hovered;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final RRect shape = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    final Paint fill = Paint()..color = accent.withValues(alpha: hovered ? 0.15 : 0.1);
    canvas.drawRRect(shape, fill);

    if (hovered) {
      final double sweepPosition = (progress * 2.4) - 0.7;
      final Rect sweepBounds = Rect.fromLTWH(
        size.width * sweepPosition,
        -size.height,
        size.width * 0.9,
        size.height * 3,
      );
      final Paint sweep = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.transparent,
            const Color(0xFF9A5C38).withValues(alpha: 0.1),
            const Color(0xFFE7B76D).withValues(alpha: 0.24),
            Colors.transparent,
          ],
          stops: const <double>[0, 0.35, 0.54, 1],
        ).createShader(sweepBounds);
      canvas.drawRRect(shape, sweep);
      _paintSteam(canvas, size);
    }

    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = hovered ? 1.1 : 1
      ..color = hovered ? const Color(0xFFDDA568).withValues(alpha: 0.65) : accent.withValues(alpha: 0.4);
    canvas.drawRRect(shape.deflate(border.strokeWidth / 2), border);
  }

  void _paintSteam(Canvas canvas, Size size) {
    final double coffeeCenter = size.width * 0.28;
    final Rect steamBounds = Rect.fromLTWH(coffeeCenter - 9, 3, 20, 20);
    final Paint steam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: <Color>[
          const Color(0xFFB66A3C).withValues(alpha: 0.18),
          const Color(0xFFF1CB8C).withValues(alpha: 0.7),
        ],
      ).createShader(steamBounds);

    for (int index = 0; index < 3; index++) {
      final double phase = progress * math.pi * 2 + index * 1.9;
      final double x = coffeeCenter + (index - 1) * 3.5;
      final double drift = math.sin(phase) * 1.2;
      final Path wisp = Path()
        ..moveTo(x, 21)
        ..cubicTo(x - 2 + drift, 17, x + 2 - drift, 14, x + drift, 11)
        ..cubicTo(x + 2 + drift, 8, x + 1 - drift, 6, x + 1, 4);
      canvas.drawPath(wisp, steam);
    }
  }

  @override
  bool shouldRepaint(covariant _CoffeeButtonPainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.hovered != hovered || oldDelegate.progress != progress;
  }
}
