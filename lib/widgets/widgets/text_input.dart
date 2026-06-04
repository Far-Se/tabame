// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/settings.dart';

class CustomTextInput extends StatefulWidget {
  final String labelText;
  final String? hintText;
  final String? value;
  final InputDecoration? decoration;
  final void Function(String val) onChanged;
  final void Function(String val)? onSubmitted;
  final void Function(String val)? onUpdated;
  final bool multiline;
  final TextInputType keyboardType;
  final bool showLabelSeparated;
  const CustomTextInput({
    super.key,
    required this.labelText,
    this.hintText,
    this.value,
    required this.onChanged(String val),
    this.onSubmitted,
    this.onUpdated,
    this.multiline = false,
    this.keyboardType = TextInputType.text,
    this.decoration,
    this.showLabelSeparated = false,
  });

  @override
  CustomTextInputState createState() => CustomTextInputState();
}

class CustomTextInputState extends State<CustomTextInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value ?? "";
    _focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    }
  }

  @override
  void didUpdateWidget(CustomTextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value ?? "";
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool sent = false;
  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Semantics(
      label: widget.labelText,
      textField: true,
      container: true,
      child: MouseRegion(
        onEnter: (PointerEnterEvent event) => setState(() => _isHovered = true),
        onExit: (PointerExitEvent event) => setState(() => _isHovered = false),
        child: Focus(
          onFocusChange: (bool value) async {
            if (value == false) {
              if (sent == false) {
                widget.onChanged(_controller.text);
                sent = true;
              }
            } else {
              sent = false;
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.labelText.isNotEmpty && widget.showLabelSeparated)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    widget.labelText.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                      color: theme.hintColor.withValues(alpha: _isFocused ? 1.0 : 0.8),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutQuart,
                decoration: BoxDecoration(
                  color: theme.cardColor.withValues(
                    alpha: _isFocused
                        ? 0.5
                        : _isHovered
                            ? 0.42
                            : 0.35,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isFocused
                        ? scheme.primary.withValues(alpha: 0.4)
                        : _isHovered
                            ? theme.dividerColor.withValues(alpha: 0.2)
                            : theme.dividerColor.withValues(alpha: 0.12),
                    width: _isFocused ? 1.0 : 1.0,
                  ),
                  boxShadow: _isFocused
                      ? <BoxShadow>[
                          BoxShadow(
                            color: scheme.primary.withValues(alpha: 0.05),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ]
                      : null,
                ),
                child: Listener(
                  onPointerSignal: _handlePointerSignal,
                  child: ScrollConfiguration(
                    behavior: const _DesktopTextScrollBehavior(),
                    child: TextField(
                      scrollController: _scrollController,
                      dragStartBehavior: DragStartBehavior.start,
                      focusNode: _focusNode,
                      keyboardType: widget.keyboardType,
                      inputFormatters: widget.keyboardType == TextInputType.number
                          ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
                          : null,
                      maxLines: widget.multiline ? null : 1,
                      decoration: widget.decoration ??
                          InputDecoration(
                            labelText: widget.labelText.toUpperCase(),
                            floatingLabelBehavior:
                                widget.showLabelSeparated ? FloatingLabelBehavior.never : FloatingLabelBehavior.auto,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: scheme.onSurface.withValues(alpha: 0.15), width: 1),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.6), width: 1),
                            ),
                            hoverColor: Colors.transparent,
                            filled: true,
                            fillColor: scheme.onSurface.withValues(alpha: 0.04),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            labelStyle: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                      /*
                          InputDecoration(
                            hintText: widget.hintText ?? (widget.labelText.isEmpty ? null : widget.labelText),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: theme.hintColor.withValues(alpha: 0.5),
                            ),
                          ), */
                      controller: _controller,
                      style: entryStyle(true, fontSize: 14, letterSpacing: 0.5),
                      cursorWidth: 1.5,
                      cursorRadius: const Radius.circular(2),
                      cursorColor: scheme.primary,
                      enableInteractiveSelection: true,
                      onSubmitted: (String e) {
                        widget.onChanged(e);
                        widget.onSubmitted == null ? null : widget.onSubmitted!(e);
                        sent = true;
                      },
                      onChanged: (String e) => widget.onUpdated == null ? null : widget.onUpdated!(e),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      _scrollController.animateTo(
        (_scrollController.offset + (event.scrollDelta.dy * 0.8)).clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }
}

class _DesktopTextScrollBehavior extends MaterialScrollBehavior {
  const _DesktopTextScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        // Intentionally empty — disables drag-to-scroll entirely.
        // Mouse wheel still works via the 'scrollAnimator' path.
      };
}
