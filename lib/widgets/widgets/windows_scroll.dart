import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WindowsScrollView extends StatefulWidget {
  const WindowsScrollView({
    super.key,
    required this.child,
    this.scrollSpeed = 100.0,
    this.friction = 0.92,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.controller,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;

  /// Pixels scrolled per wheel "line" (one detent on a standard mouse wheel).
  final double scrollSpeed;

  /// Per-frame velocity multiplier. 0.92 ≈ Windows default feel.
  /// Higher values (0.95+) give a longer, silkier glide.
  /// Lower values (0.85-) give a quicker stop.
  final double friction;

  final Axis scrollDirection;
  final bool reverse;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final Clip clipBehavior;

  @override
  State<WindowsScrollView> createState() => _WindowsScrollViewState();
}

class _WindowsScrollViewState extends State<WindowsScrollView> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  bool _ownsController = false;

  // Current momentum velocity in px/frame.
  double _velocity = 0.0;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _scrollController = widget.controller!;
    } else {
      _scrollController = ScrollController();
      _ownsController = true;
    }
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker?.dispose();
    if (_ownsController) _scrollController.dispose();
    super.dispose();
  }

  // ── Wheel / trackpad input ────────────────────────────────────────────────

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;

    // Ignore events that aren't on the relevant axis.
    final double delta = widget.scrollDirection == Axis.vertical ? event.scrollDelta.dy : event.scrollDelta.dx;

    if (delta == 0.0) return;

    // Normalise to "lines" then scale to pixels.
    // PointerScrollEvent gives raw pixels; divide by a standard line height
    // (typically 40 px on Windows at 96 dpi) to get lines, then re-scale.
    const double lineHeight = 40.0;
    final double lines = delta / lineHeight;
    final double pixelDelta = lines * widget.scrollSpeed * (widget.reverse ? -1 : 1);

    // Add to existing velocity (allows rapid successive scrolls to accumulate).
    _velocity += pixelDelta * 0.35; // blend factor keeps it from blowing up

    _clampVelocity();
    _ensureTickerRunning();
  }

  // ── Animation tick ────────────────────────────────────────────────────────

  void _onTick(Duration _) {
    if (!_scrollController.hasClients) {
      _stop();
      return;
    }

    if (_velocity.abs() < 0.5) {
      _stop();
      return;
    }

    final double current = _scrollController.offset;
    final double target = (current + _velocity).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );

    if (target == current) {
      _stop();
      return;
    }

    _scrollController.jumpTo(target);

    // Decelerate.
    _velocity *= widget.friction;

    // Hard-stop at boundaries.
    if (target == _scrollController.position.minScrollExtent || target == _scrollController.position.maxScrollExtent) {
      _stop();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _clampVelocity() {
    const double maxVelocity = 600.0; // px per frame ceiling
    _velocity = _velocity.clamp(-maxVelocity, maxVelocity);
  }

  void _ensureTickerRunning() {
    if (!(_ticker?.isTicking ?? false)) {
      _ticker?.start();
    }
  }

  void _stop() {
    _velocity = 0.0;
    _ticker?.stop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // We wrap with a Listener so we capture pointer signals BEFORE Flutter's
    // default scroll machinery can interfere.
    return Listener(
      onPointerSignal: _handlePointerSignal,
      // Absorb wheel events so they don't bubble to parent scrollables.
      child: ScrollConfiguration(
        // Disable all built-in scroll physics / behaviour for this subtree.
        behavior: const MaterialScrollBehavior().copyWith(
          dragDevices: <PointerDeviceKind>{
            /*Add this*/
            PointerDeviceKind.mouse,
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.unknown,
          },
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: widget.scrollDirection,
          reverse: widget.reverse,
          padding: widget.padding,
          clipBehavior: widget.clipBehavior,
          // NeverScrollableScrollPhysics prevents any touch/drag scrolling;
          // remove this line if you also need touch support.
          physics: const NeverScrollableScrollPhysics(),
          child: widget.child,
        ),
      ),
    );
  }
}
