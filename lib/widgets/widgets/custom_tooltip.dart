import 'package:flutter/material.dart';

/// Project wrapper around [Tooltip] that defaults to not intercepting pointer
/// input while the overlay is visible.
class CustomTooltip extends StatelessWidget {
  const CustomTooltip({
    super.key,
    this.message,
    this.richMessage,
    @Deprecated(
      'Use CustomTooltip.constraints instead. '
      'This feature was deprecated after v3.30.0-0.1.pre.',
    )
    this.height,
    this.constraints,
    this.padding,
    this.margin,
    this.verticalOffset,
    this.preferBelow,
    this.excludeFromSemantics,
    this.decoration,
    this.textStyle,
    this.textAlign,
    this.waitDuration,
    this.showDuration,
    this.exitDuration,
    this.enableTapToDismiss = true,
    this.triggerMode,
    this.enableFeedback,
    this.onTriggered,
    this.mouseCursor,
    this.ignorePointer = true,
    this.positionDelegate,
    this.child,
  })  : assert(
          (message == null) != (richMessage == null),
          'Either `message` or `richMessage` must be specified',
        ),
        assert(
          height == null || constraints == null,
          'Only one of `height` and `constraints` may be specified.',
        );

  final String? message;
  final InlineSpan? richMessage;

  @Deprecated(
    'Use CustomTooltip.constraints instead. '
    'This feature was deprecated after v3.30.0-0.1.pre.',
  )
  final double? height;

  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? verticalOffset;
  final bool? preferBelow;
  final bool? excludeFromSemantics;
  final Decoration? decoration;
  final TextStyle? textStyle;
  final TextAlign? textAlign;
  final Duration? waitDuration;
  final Duration? showDuration;
  final Duration? exitDuration;
  final bool enableTapToDismiss;
  final TooltipTriggerMode? triggerMode;
  final bool? enableFeedback;
  final TooltipTriggeredCallback? onTriggered;
  final MouseCursor? mouseCursor;
  final bool ignorePointer;
  final TooltipPositionDelegate? positionDelegate;
  final Widget? child;

  static bool dismissAllToolTips() {
    return Tooltip.dismissAllToolTips();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      richMessage: richMessage,
      // Preserve the native API surface so existing call sites can switch over
      // without losing access to the deprecated `height` escape hatch.
      // ignore: deprecated_member_use
      height: height,
      constraints: constraints,
      padding: padding,
      margin: margin,
      verticalOffset: verticalOffset,
      preferBelow: preferBelow,
      excludeFromSemantics: excludeFromSemantics,
      decoration: decoration,
      textStyle: textStyle,
      textAlign: textAlign,
      waitDuration: waitDuration,
      showDuration: showDuration,
      exitDuration: exitDuration,
      enableTapToDismiss: enableTapToDismiss,
      triggerMode: triggerMode,
      enableFeedback: enableFeedback,
      onTriggered: onTriggered,
      mouseCursor: mouseCursor,
      ignorePointer: ignorePointer,
      positionDelegate: positionDelegate,
      child: child,
    );
  }
}
