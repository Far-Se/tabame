import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import 'windows_scroll.dart';

class BarWithButtons extends StatefulWidget {
  final List<Widget> children;
  final bool withScroll;
  final bool shrinkWrap;
  final double height;
  const BarWithButtons({
    super.key,
    required this.children,
    this.withScroll = true,
    this.shrinkWrap = false,
    this.height = 30,
  });

  @override
  State<BarWithButtons> createState() => _BarWithButtonsState();
}

class _BarWithButtonsState extends State<BarWithButtons> with QuickMenuTriggers {
  final ScrollController _buttonBarScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _buttonBarScrollController.dispose();
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (mounted) {
      _buttonBarScrollController.animateTo(0, duration: const Duration(milliseconds: 50), curve: Curves.ease);
    }
  }

  @override
  Widget build(BuildContext context) {
    const double middleOffset = 0.93;
    final Widget content = _ButtonList(children: widget.children);

    if (!widget.withScroll) {
      return SizedBox(height: widget.height, child: content);
    }

    Widget buildScroll(double minWidth) {
      return ShaderMask(
        shaderCallback: (Rect rect) => const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
          stops: <double>[0.0, middleOffset, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstOut,
        child: ScrollConfiguration(
          behavior: const WindowsScrollBehavior(),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _buttonBarScrollController,
            physics: const ClampingScrollPhysics(),
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: minWidth),
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.height,
      width: widget.shrinkWrap ? null : double.infinity,
      // A LayoutBuilder fills the available width. Bypass it when the viewport
      // should shrink to its contents, up to the category's width cap.
      child: widget.shrinkWrap
          ? buildScroll(0)
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) => buildScroll(constraints.maxWidth),
            ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent pointerSignal) {
    if (pointerSignal is! PointerScrollEvent) return;

    final double targetOffset = pointerSignal.scrollDelta.dy < 0
        ? _buttonBarScrollController.offset - 70
        : _buttonBarScrollController.offset + 70;

    _buttonBarScrollController.animateTo(
      targetOffset.clamp(0, _buttonBarScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.ease,
    );
  }
}

class _ButtonList extends StatelessWidget {
  const _ButtonList({
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        verticalDirection: VerticalDirection.down,
        spacing: 0,
        children: <Widget>[
          ...List<Widget>.generate(
            children.length,
            (int index) {
              return Flexible(
                flex: 1,
                fit: FlexFit.loose,
                child: children[index],
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}
