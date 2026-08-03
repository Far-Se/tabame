part of '../launcher_design_builder.dart';

class _OrbitSearchBar extends StatelessWidget {
  const _OrbitSearchBar({
    required this.accent,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final TextStyle microLabel = OrbitTokens.tele(
      fontSize: Design.baseFontSize - 3.5,
      color: OrbitTokens.dim(isDark),
      fontWeight: FontWeight.w500,
      letterSpacing: 1.8,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Telemetry micro-labels above the field.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
          child: Row(
            children: <Widget>[
              Text('NAV · TARGET ACQUISITION', style: microLabel),
              const Spacer(),
              Text('CH·01', style: microLabel),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
          child: Row(
            children: <Widget>[
              // Radar scope glyph (also the window drag handle).
              dragHandle,
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[
                    textField,
                    if (trailingBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: trailingBadge!,
                      ),
                  ],
                ),
              ),
              // Acquisition scope — sweeps while the query resolves, holds an
              // idle crosshair otherwise.
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _OrbitScanScope(accent: accent, active: isSearching),
              ),
            ],
          ),
        ),
        // Graduation strip — the measured underline of the input.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: SizedBox(
            height: 8,
            width: double.infinity,
            child: CustomPaint(painter: _OrbitTickStripPainter(color: accent)),
          ),
        ),
      ],
    );
  }
}

/// A miniature radar scope: an idle crosshair that spins a sweep beam (with a
/// short fading trail) while a search is in flight.
class _OrbitScanScope extends StatefulWidget {
  const _OrbitScanScope({required this.accent, required this.active});

  final Color accent;
  final bool active;

  @override
  State<_OrbitScanScope> createState() => _OrbitScanScopeState();
}

class _OrbitScanScopeState extends State<_OrbitScanScope> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_OrbitScanScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            size: const Size(18, 18),
            painter: _OrbitScopeIconPainter(
              color: widget.accent,
              sweep: widget.active ? _controller.value : null,
            ),
          );
        },
      ),
    );
  }
}

/// The scope glyph: outer ring, cardinal ticks, center dot, and — while
/// sweeping — a beam with a dim trailing edge.
class _OrbitScopeIconPainter extends CustomPainter {
  const _OrbitScopeIconPainter({required this.color, this.sweep});

  final Color color;

  /// Sweep position in turns (0..1); null paints the idle crosshair.
  final double? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2 - 1;
    final bool active = sweep != null;

    final Paint ring = Paint()
      ..color = color.withAlpha(active ? 150 : 90)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, r, ring);

    final Paint tick = Paint()
      ..color = color.withAlpha(active ? 130 : 70)
      ..strokeWidth = 1;
    canvas.drawLine(c + Offset(0, -r), c + Offset(0, 3 - r), tick);
    canvas.drawLine(c + Offset(0, r), c + Offset(0, r - 3), tick);
    canvas.drawLine(c + Offset(-r, 0), c + Offset(3 - r, 0), tick);
    canvas.drawLine(c + Offset(r, 0), c + Offset(r - 3, 0), tick);

    canvas.drawCircle(c, 1.2, Paint()..color = color.withAlpha(180));

    if (active) {
      final double angle = sweep! * 2 * math.pi;
      final Paint beam = Paint()
        ..color = color.withAlpha(220)
        ..strokeWidth = 1.2;
      canvas.drawLine(c, c + Offset(math.cos(angle) * r, math.sin(angle) * r), beam);
      final double trail = angle - 0.55;
      final Paint trailPaint = Paint()
        ..color = color.withAlpha(70)
        ..strokeWidth = 1.2;
      canvas.drawLine(c, c + Offset(math.cos(trail) * r, math.sin(trail) * r), trailPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitScopeIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.sweep != sweep;
}

/// A graduation strip: a baseline with ticks — taller every 5th — like the
/// scale along a flight instrument's bezel.
class _OrbitTickStripPainter extends CustomPainter {
  const _OrbitTickStripPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withAlpha(90)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);

    final Paint tick = Paint()
      ..color = color.withAlpha(70)
      ..strokeWidth = 1;
    int i = 0;
    for (double x = 0.5; x <= size.width; x += 7) {
      final double h = i % 5 == 0 ? 6 : 3;
      canvas.drawLine(Offset(x, 1), Offset(x, 1 + h), tick);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitTickStripPainter oldDelegate) => oldDelegate.color != color;
}

/// The guidance scope — forced HUD palette, faint range rings radiating from
/// beyond the top-right corner, bearing ticks down the left edge, and a
/// telemetry strip along the bottom.
class OrbitLauncherFrame extends StatelessWidget {
  const OrbitLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.orbit),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.orbit.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              // Range rings + bearing ticks.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _OrbitRangePainter(ink: accent, isDark: isDark)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _OrbitTelemetryFooter(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Concentric range rings radiating from an off-canvas origin at the
/// top-right, a small origin crosshair, and bearing ticks down the left edge.
class _OrbitRangePainter extends CustomPainter {
  const _OrbitRangePainter({required this.ink, required this.isDark});

  final Color ink;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ring = Paint()
      ..color = ink.withAlpha(isDark ? 13 : 16)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Offset origin = Offset(size.width * 1.02, -size.height * 0.06);
    for (double r = 46; r < size.width * 1.1; r += 46) {
      canvas.drawCircle(origin, r, ring);
    }

    final Paint cross = Paint()
      ..color = ink.withAlpha(isDark ? 40 : 46)
      ..strokeWidth = 1;
    canvas.drawLine(origin + const Offset(-6, 0), origin + const Offset(6, 0), cross);
    canvas.drawLine(origin + const Offset(0, -6), origin + const Offset(0, 6), cross);

    final Paint tick = Paint()
      ..color = ink.withAlpha(isDark ? 26 : 30)
      ..strokeWidth = 1;
    int i = 0;
    for (double y = 24; y < size.height; y += 22) {
      final double len = i % 4 == 0 ? 7 : 4;
      canvas.drawLine(Offset(0.5, y), Offset(0.5 + len, y), tick);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRangePainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.isDark != isDark;
}

/// The telemetry strip: a blinking status lamp, flight-control hints, and the
/// locked-target count readout.
class _OrbitTelemetryFooter extends StatelessWidget {
  const _OrbitTelemetryFooter({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  Widget _hint(String key, String caption) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key,
          style: OrbitTokens.tele(
            fontSize: Design.baseFontSize - 1,
            color: accent.withAlpha(220),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        Text(
          ' $caption',
          style: OrbitTokens.tele(
            fontSize: Design.baseFontSize - 1,
            color: OrbitTokens.dim(isDark),
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: OrbitTokens.chrome(isDark),
        border: Border(top: BorderSide(color: accent.withAlpha(50))),
      ),
      child: Row(
        children: <Widget>[
          _OrbitStatusDot(color: accent),
          const SizedBox(width: 9),
          _hint('↵', 'ENGAGE'),
          const SizedBox(width: 14),
          _hint('→', 'ACTIONS'),
          const SizedBox(width: 14),
          _hint('ESC', 'ABORT'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : 'TGT ${resultCount.toString().padLeft(2, '0')}',
            style: OrbitTokens.tele(
              fontSize: Design.baseFontSize - 1,
              color: accent.withAlpha(190),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The blinking status lamp in the telemetry strip — lit ~60% of the cycle.
class _OrbitStatusDot extends StatefulWidget {
  const _OrbitStatusDot({required this.color});

  final Color color;

  @override
  State<_OrbitStatusDot> createState() => _OrbitStatusDotState();
}

class _OrbitStatusDotState extends State<_OrbitStatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final bool lit = _controller.value < 0.62;
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit ? widget.color : widget.color.withAlpha(50),
          ),
        );
      },
    );
  }
}

/// A dashed track line used by the Orbit section header.
class _OrbitTrackPainter extends CustomPainter {
  const _OrbitTrackPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const double dash = 4;
    const double gap = 5;
    final double y = size.height / 2;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitTrackPainter oldDelegate) => oldDelegate.color != color;
}
