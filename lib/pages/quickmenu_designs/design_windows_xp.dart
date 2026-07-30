import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

/// Windows XP "Luna" Quick Menu.
///
/// This deliberately ignores modern translucency and dark-mode conventions:
/// XP used opaque ivory work areas, saturated blue chrome, hard one-pixel
/// bevels and a green Start affordance.
abstract final class _XpColors {
  static bool get _isDark => Design.background.computeLuminance() < 0.5;
  static const Color blueDark = Color(0xFF003399);
  static const Color blue = Color(0xFF245EDC);
  static const Color blueLight = Color(0xFF5A8CF0);
  static const Color blueHighlight = Color(0xFF7AA5F7);
  static Color get cream => _isDark ? Design.background : const Color(0xFFECE9D8);
  static Color get creamLight =>
      _isDark ? Color.alphaBlend(Design.text.withAlpha(10), Design.background) : const Color(0xFFFFFEF5);
  static const Color orange = Color(0xFFFF8C00);
  // static const Color greenDark = Color(0xFF2C811A);
  // static const Color green = Color(0xFF4BAE31);
  // static const Color greenLight = Color(0xFF75C85C);
}

class MainMenuWindowsXpWidget extends StatelessWidget {
  const MainMenuWindowsXpWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: _XpColors.cream,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: _XpColors.blueDark, width: 2),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(4, 7)),
              BoxShadow(color: _XpColors.blueHighlight, offset: Offset(-1, -1)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const DragToMoveArea(child: _XpMenuHeader()),
                if (!user.quickActionsAtBottom)
                  const _XpInsetBand(
                    padding: EdgeInsets.fromLTRB(4, 3, 5, 3),
                    child: TopBar(),
                  )
                else if (user.bottomBarOnTop)
                  const _XpPinnedBand()
                else
                  const SizedBox(height: 3),
                ColoredBox(
                  color: _XpColors.creamLight,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: TaskBar(),
                  ),
                ),
                const _XpOrangeDivider(),
                if (!user.bottomBarOnTop) const _XpPinnedBand(),
                if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                if (user.libreStats) const LibreStats(withTopDivider: false),
                const _XpFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _XpMenuHeader extends StatelessWidget {
  const _XpMenuHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      padding: const EdgeInsets.fromLTRB(8, 5, 9, 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _XpColors.blueLight,
            _XpColors.blue,
            Color(0xFF0B48C9),
          ],
          stops: <double>[0, 0.48, 1],
        ),
        border: Border(
          top: BorderSide(color: _XpColors.blueHighlight),
          bottom: BorderSide(color: _XpColors.blueDark),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: _XpColors.creamLight,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFB8C7E8)),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x66000000), offset: Offset(1, 1)),
              ],
            ),
            child: const _WindowsFlag(),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Tabame',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Tahoma',
                fontSize: Design.baseFontSize + 5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFF8FBFF),
                shadows: const <Shadow>[
                  Shadow(color: Color(0x99002A8E), offset: Offset(1, 1)),
                ],
              ),
            ),
          ),
          const Text(
            'Windows XP',
            style: TextStyle(
              fontFamily: 'Tahoma',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xFFDDE9FF),
            ),
          ),
        ],
      ),
    );
  }
}

class _XpInsetBand extends StatelessWidget {
  const _XpInsetBand({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _XpColors.cream,
        border: Border(
          top: BorderSide(color: _XpColors.creamLight),
          bottom: BorderSide(color: Color(0xFFACA899)),
        ),
      ),
      child: child,
    );
  }
}

class _XpPinnedBand extends StatelessWidget {
  const _XpPinnedBand();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            Color(0xFFD3E5FA),
            Color(0xFFEAF3FD),
          ],
        ),
        border: Border(
          top: BorderSide(color: _XpColors.creamLight),
          bottom: BorderSide(color: Color(0xFFB8C7DA)),
        ),
      ),
      child: PinnedAndTrayList(),
    );
  }
}

class _XpOrangeDivider extends StatelessWidget {
  const _XpOrangeDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Colors.transparent,
            _XpColors.orange,
            Color(0xFFFFC66D),
            Colors.transparent,
          ],
          stops: <double>[0, 0.18, 0.82, 1],
        ),
      ),
    );
  }
}

class _XpFooter extends StatelessWidget {
  const _XpFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            _XpColors.blueLight,
            _XpColors.blue,
            _XpColors.blueDark,
          ],
        ),
        border: Border(top: BorderSide(color: _XpColors.blueHighlight)),
      ),
      child: const Row(
        children: <Widget>[
          // Container(
          //   height: 31,
          //   decoration: const BoxDecoration(
          //     gradient: LinearGradient(
          //       begin: Alignment.topCenter,
          //       end: Alignment.bottomCenter,
          //       colors: <Color>[
          //         _XpColors.greenLight,
          //         _XpColors.green,
          //         _XpColors.greenDark,
          //       ],
          //     ),
          //     borderRadius: BorderRadius.only(topRight: Radius.circular(15), bottomRight: Radius.circular(15)),
          //   ),
          //   child: const ClipRRect(
          //     borderRadius: BorderRadius.only(
          //       topRight: Radius.circular(15),
          //       bottomRight: Radius.circular(15),
          //     ),
          //     child: Stack(
          //       children: <Widget>[
          //         Positioned(
          //           top: 0,
          //           left: 0,
          //           right: 0,
          //           height: 1,
          //           child: ColoredBox(color: Color(0xFFA3E38E)),
          //         ),
          //         Positioned(
          //           top: 0,
          //           right: 0,
          //           bottom: 0,
          //           width: 1,
          //           child: ColoredBox(color: Color(0xFF1D6410)),
          //         ),
          //         Padding(
          //           padding: EdgeInsets.fromLTRB(9, 0, 12, 0),
          //           child: Row(
          //             mainAxisSize: MainAxisSize.min,
          //             crossAxisAlignment: CrossAxisAlignment.center,
          //             mainAxisAlignment: MainAxisAlignment.center,
          //             children: <Widget>[
          //               _WindowsFlag(size: 16),
          //               // SizedBox(width: 5),
          //               // Text(
          //               //   'start',
          //               //   style: TextStyle(
          //               //     fontFamily: 'Tahoma',
          //               //     fontSize: 12,
          //               //     fontStyle: FontStyle.italic,
          //               //     fontWeight: FontWeight.w700,
          //               //     color: Color(0xFFF7FFF3),
          //               //     shadows: <Shadow>[Shadow(color: Color(0x990F5A09), offset: Offset(1, 1))],
          //               //   ),
          //               // ),
          //             ],
          //           ),
          //         ),
          //       ],
          //     ),
          //   ),
          // ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(4, 2, 4, 3),
              child: BottomBar(),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsFlag extends StatelessWidget {
  const _WindowsFlag() : size = 22;

  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.08,
      child: SizedBox(
        width: size,
        height: size,
        child: GridView.count(
          crossAxisCount: 2,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 1.5,
          crossAxisSpacing: 1.5,
          children: const <Widget>[
            ColoredBox(color: Color(0xFFF25022)),
            ColoredBox(color: Color(0xFF7FBA00)),
            ColoredBox(color: Color(0xFF00A4EF)),
            ColoredBox(color: Color(0xFFFFB900)),
          ],
        ),
      ),
    );
  }
}
