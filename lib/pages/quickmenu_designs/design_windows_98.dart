import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

abstract final class _Win98Colors {
  static const Color face = Color(0xFFC0C0C0);
  static const Color light = Color(0xFFFFFFFF);
  static const Color highlight = Color(0xFFDFDFDF);
  static const Color shadow = Color(0xFF808080);
  static const Color dark = Color(0xFF000000);
  static const Color title = Color(0xFF000080);
  static const Color titleLight = Color(0xFF1084D0);
  static const Color field = Color(0xFFFFFFFF);
}

class MainMenuWindows98Widget extends StatelessWidget {
  const MainMenuWindows98Widget({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: _Win98Bevel(
          raised: true,
          child: ColoredBox(
            color: _Win98Colors.face,
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _Win98TitleBar(),
                  const SizedBox(height: 2),
                  if (!user.quickActionsAtBottom)
                    const _Win98RaisedBand(
                      padding: EdgeInsets.fromLTRB(3, 2, 3, 2),
                      child: TopBar(),
                    )
                  else if (user.bottomBarOnTop)
                    const _Win98RaisedBand(child: PinnedAndTrayList())
                  else
                    const SizedBox(height: 2),
                  const SizedBox(height: 2),
                  const _Win98InsetField(child: TaskBar()),
                  const SizedBox(height: 2),
                  if (!user.bottomBarOnTop) const _Win98RaisedBand(child: PinnedAndTrayList()),
                  if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                  if (user.libreStats) const LibreStats(withTopDivider: false),
                  const SizedBox(height: 2),
                  const _Win98Footer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Win98TitleBar extends StatelessWidget {
  const _Win98TitleBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 23,
      padding: const EdgeInsets.fromLTRB(3, 2, 2, 2),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_Win98Colors.title, _Win98Colors.titleLight],
        ),
      ),
      child: Row(
        children: <Widget>[
          const _Win98Flag(size: 16),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Tabame - Quick Menu',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'MS Sans Serif',
                fontFamilyFallback: const <String>['Tahoma', 'Segoe UI'],
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                color: _Win98Colors.light,
                height: 1,
              ),
            ),
          ),
          const _Win98CaptionButton(label: '_'),
          const SizedBox(width: 2),
          const _Win98CaptionButton(label: '□'),
          const SizedBox(width: 2),
          const _Win98CaptionButton(
            label: '×',
            onTap: QuickMenuFunctions.hideQuickMenu,
          ),
        ],
      ),
    );
  }
}

class _Win98CaptionButton extends StatelessWidget {
  const _Win98CaptionButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _Win98Bevel(
        raised: true,
        child: SizedBox(
          width: 17,
          height: 17,
          child: ColoredBox(
            color: _Win98Colors.face,
            child: Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: 'MS Sans Serif',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _Win98Colors.dark,
                  height: 0.9,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Win98RaisedBand extends StatelessWidget {
  const _Win98RaisedBand({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return _Win98Bevel(
      raised: true,
      child: ColoredBox(
        color: _Win98Colors.face,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _Win98InsetField extends StatelessWidget {
  const _Win98InsetField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _Win98Bevel(
      raised: false,
      child: ColoredBox(
        color: _Win98Colors.field,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: child,
        ),
      ),
    );
  }
}

class _Win98Footer extends StatelessWidget {
  const _Win98Footer();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: <Widget>[
        _Win98Bevel(
          raised: true,
          child: ColoredBox(
            color: _Win98Colors.face,
            child: Padding(
              padding: EdgeInsets.fromLTRB(5, 3, 7, 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _Win98Flag(size: 17),
                  SizedBox(width: 4),
                  Text(
                    'Start',
                    style: TextStyle(
                      fontFamily: 'MS Sans Serif',
                      fontFamilyFallback: <String>['Tahoma'],
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _Win98Colors.dark,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SizedBox(width: 3),
        Expanded(
          child: _Win98Bevel(
            raised: false,
            child: ColoredBox(
              color: _Win98Colors.face,
              child: Padding(
                padding: EdgeInsets.fromLTRB(2, 1, 2, 1),
                child: BottomBar(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Win98Bevel extends StatelessWidget {
  const _Win98Bevel({required this.raised, required this.child});

  final bool raised;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color topLeftOuter = raised ? _Win98Colors.light : _Win98Colors.dark;
    final Color bottomRightOuter = raised ? _Win98Colors.dark : _Win98Colors.light;
    final Color topLeftInner = raised ? _Win98Colors.highlight : _Win98Colors.shadow;
    final Color bottomRightInner = raised ? _Win98Colors.shadow : _Win98Colors.highlight;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: topLeftOuter),
          top: BorderSide(color: topLeftOuter),
          right: BorderSide(color: bottomRightOuter),
          bottom: BorderSide(color: bottomRightOuter),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: topLeftInner),
            top: BorderSide(color: topLeftInner),
            right: BorderSide(color: bottomRightInner),
            bottom: BorderSide(color: bottomRightInner),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _Win98Flag extends StatelessWidget {
  const _Win98Flag({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: GridView.count(
        crossAxisCount: 2,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        children: const <Widget>[
          ColoredBox(color: Color(0xFFFF0000)),
          ColoredBox(color: Color(0xFF00A000)),
          ColoredBox(color: Color(0xFF0000FF)),
          ColoredBox(color: Color(0xFFFFFF00)),
        ],
      ),
    );
  }
}
