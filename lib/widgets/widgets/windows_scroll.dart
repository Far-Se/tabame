import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WindowsScrollView extends StatefulWidget {
  const WindowsScrollView({
    super.key,
    required this.child,
    this.scrollSpeed = 12.0,
    this.friction = 0.76,
    this.scrollDirection = Axis.vertical,
    this.reverse = false,
    this.padding,
    this.controller,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final double scrollSpeed;
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

  double _velocity = 0.0;
  Ticker? _ticker;

  // Track whether a scrollbar drag is in progress.
  bool _isDraggingScrollbar = false;

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
    // Ignore wheel events while user is dragging the scrollbar thumb.
    if (_isDraggingScrollbar) return;

    final double delta = widget.scrollDirection == Axis.vertical ? event.scrollDelta.dy : event.scrollDelta.dx;

    if (delta == 0.0) return;

    const double lineHeight = 40.0;
    final double lines = delta / lineHeight;
    final double pixelDelta = lines * widget.scrollSpeed * (widget.reverse ? -1 : 1);

    _velocity += pixelDelta * 0.35;
    _clampVelocity();
    _ensureTickerRunning();
  }

  // ── Scroll notifications (detect scrollbar drag) ─────────────────────────

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      // DragScrollActivity means the user is dragging (scrollbar or content).
      if (notification.dragDetails != null) {
        _isDraggingScrollbar = true;
        // Kill any momentum so it doesn't fight the drag.
        _stop();
        setState(() {}); // rebuild to swap physics
      }
    } else if (notification is ScrollEndNotification) {
      if (_isDraggingScrollbar) {
        _isDraggingScrollbar = false;
        setState(() {}); // rebuild to restore NeverScrollable
      }
    }
    return false; // don't absorb the notification
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
    _velocity *= widget.friction;

    if (target == _scrollController.position.minScrollExtent || target == _scrollController.position.maxScrollExtent) {
      _stop();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _clampVelocity() {
    const double maxVelocity = 600.0;
    _velocity = _velocity.clamp(-maxVelocity, maxVelocity);
  }

  void _ensureTickerRunning() {
    if (!(_ticker?.isTicking ?? false)) _ticker?.start();
  }

  void _stop() {
    _velocity = 0.0;
    _ticker?.stop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // While the scrollbar is being dragged use normal clamping physics so the
    // thumb can actually move the scroll position. The rest of the time lock
    // it to NeverScrollable so only our ticker drives the position.
    final ScrollPhysics physics =
        _isDraggingScrollbar ? const ClampingScrollPhysics() : const NeverScrollableScrollPhysics();

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: Listener(
        onPointerSignal: _handlePointerSignal,
        child: ScrollConfiguration(
          behavior: const MaterialScrollBehavior().copyWith(
            dragDevices: <PointerDeviceKind>{
              PointerDeviceKind.mouse,
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.unknown,
            },
          ),
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: widget.scrollDirection,
              reverse: widget.reverse,
              padding: widget.padding,
              clipBehavior: widget.clipBehavior,
              physics: physics,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
