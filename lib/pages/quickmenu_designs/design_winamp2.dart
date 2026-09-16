import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// "Winamp2" QuickMenu design.
///
/// This variant follows the proportions and visual language of the classic
/// Winamp skin in the reference: a narrow title strip, twin LCD readouts, a
/// transport rail, a full equalizer bay, and a framed playlist. The playlist
/// itself is still Tabame's live window switcher, so the skin remains useful
/// when it is more than a visual homage.
class MainMenuWinamp2Widget extends StatelessWidget {
  const MainMenuWinamp2Widget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the selected QuickMenu theme changes.
    final _Winamp2Palette palette = _Winamp2Palette.fromTheme();
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 550,
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 30,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: RepaintBoundary(
                  child: _Winamp2Chassis(palette: palette, hasBackdrop: hasBackdrop),
                ),
              ),
              RepaintBoundary(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    DragToMoveArea(child: _Winamp2TitleBar(palette: palette)),
                    if (!user.quickActionsAtBottom)
                      _Winamp2ActionRail(palette: palette)
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),
                    _Winamp2PlayerDeck(palette: palette),
                    _Winamp2Equalizer(palette: palette),
                    _Winamp2Playlist(palette: palette),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    _Winamp2Footer(palette: palette),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Winamp2Palette {
  const _Winamp2Palette({
    required this.isDark,
    required this.accent,
    required this.text,
    required this.dimText,
    required this.chassisTop,
    required this.chassisBottom,
    required this.face,
    required this.screen,
    required this.slot,
    required this.edgeHi,
    required this.edgeLo,
    required this.line,
    required this.ledOff,
  });

  factory _Winamp2Palette.fromTheme() {
    final Color background = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool isDark = background.computeLuminance() < 0.5;
    final double intensity = (Design.gradientAlpha.clamp(0, 255)) / 255.0;

    Color lift(Color color, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), color);
    Color sink(Color color, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), color);

    return _Winamp2Palette(
      isDark: isDark,
      accent: accent,
      text: text.withValues(alpha: 0.94),
      dimText: text.withValues(alpha: isDark ? 0.52 : 0.62),
      chassisTop: lift(background, isDark ? 0.06 : 0.30),
      chassisBottom: sink(background, isDark ? 0.18 : 0.10),
      face: sink(background, isDark ? 0.08 : 0.04),
      screen: Color.alphaBlend(
        accent.withValues(alpha: 0.025 + intensity * 0.045),
        sink(background, isDark ? 0.38 : 0.22),
      ),
      slot: sink(background, isDark ? 0.52 : 0.30),
      edgeHi: Colors.white.withValues(alpha: isDark ? 0.20 : 0.68),
      edgeLo: Colors.black.withValues(alpha: isDark ? 0.68 : 0.38),
      line: text.withValues(alpha: isDark ? 0.34 : 0.42),
      ledOff: text.withValues(alpha: isDark ? 0.16 : 0.24),
    );
  }

  final bool isDark;
  final Color accent;
  final Color text;
  final Color dimText;
  final Color chassisTop;
  final Color chassisBottom;
  final Color face;
  final Color screen;
  final Color slot;
  final Color edgeHi;
  final Color edgeLo;
  final Color line;
  final Color ledOff;
}

class _Winamp2Chassis extends StatelessWidget {
  const _Winamp2Chassis({required this.palette, required this.hasBackdrop});

  final _Winamp2Palette palette;
  final bool hasBackdrop;

  @override
  Widget build(BuildContext context) {
    final double bodyAlpha = hasBackdrop ? 0.86 : 1.0;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) {
        final List<double> points = Design.panelOpacityPoints;
        final List<double> stops = <double>[];
        final List<Color> colors = <Color>[];
        for (int i = 0; i < points.length; i += 2) {
          stops.add(points[i]);
          colors.add(Colors.white.withValues(alpha: points[i + 1]));
        }
        return LinearGradient(
          begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
          end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
          colors: colors,
          stops: stops,
        ).createShader(bounds);
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              palette.chassisTop.withValues(alpha: bodyAlpha),
              palette.face.withValues(alpha: bodyAlpha),
              palette.chassisBottom.withValues(alpha: bodyAlpha),
            ],
            stops: const <double>[0.0, 0.55, 1.0],
          ),
          borderRadius: BorderRadius.circular(Design.borderRadius),
          border: Border.all(color: palette.edgeHi.withValues(alpha: 0.45)),
        ),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(painter: _Winamp2TexturePainter(palette: palette)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Winamp2TexturePainter extends CustomPainter {
  const _Winamp2TexturePainter({required this.palette});

  final _Winamp2Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dark = Paint()..color = Colors.black.withValues(alpha: palette.isDark ? 0.035 : 0.025);
    final Paint light = Paint()..color = Colors.white.withValues(alpha: palette.isDark ? 0.018 : 0.055);
    for (double y = 1; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
      canvas.drawRect(Rect.fromLTWH(0, y + 1, size.width, 1), light);
    }
  }

  @override
  bool shouldRepaint(covariant _Winamp2TexturePainter oldDelegate) => oldDelegate.palette != palette;
}

class _Winamp2Frame extends StatelessWidget {
  const _Winamp2Frame({
    required this.palette,
    required this.child,
    this.inset = false,
    this.margin,
  });

  final _Winamp2Palette palette;
  final Widget child;
  final bool inset;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inset ? <Color>[palette.edgeLo, palette.edgeHi] : <Color>[palette.edgeHi, palette.edgeLo],
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: inset ? palette.screen : palette.face,
          border: Border.all(color: palette.line.withValues(alpha: 0.46)),
        ),
        child: child,
      ),
    );
  }
}

class _Winamp2TitleBar extends StatelessWidget {
  const _Winamp2TitleBar({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 31,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(
          children: <Widget>[
            CustomPaint(
              size: const Size(18, 18),
              painter: _Winamp2LogoPainter(palette.accent),
            ),
            const SizedBox(width: 8),
            Expanded(child: _Winamp2Hairline(color: palette.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'SPOTIFAST',
                style: TextStyle(
                  color: palette.dimText,
                  fontFamily: Design.uiFontFamily,
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                  height: 1,
                ),
              ),
            ),
            Expanded(child: _Winamp2Hairline(color: palette.line)),
            const SizedBox(width: 7),
            _Winamp2CaptionButton(label: '−', palette: palette),
            _Winamp2CaptionButton(label: '×', palette: palette, onTap: QuickMenuFunctions.hideQuickMenu),
          ],
        ),
      ),
    );
  }
}

class _Winamp2LogoPainter extends CustomPainter {
  const _Winamp2LogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint cut = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final Path body = Path()
      ..moveTo(3, 1)
      ..lineTo(13, 1)
      ..lineTo(17, 5)
      ..lineTo(17, 13)
      ..lineTo(13, 17)
      ..lineTo(3, 17)
      ..lineTo(3, 14)
      ..lineTo(0, 14)
      ..lineTo(0, 4)
      ..lineTo(3, 4)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawRect(const Rect.fromLTWH(4, 5, 8, 8), cut);
    final Path play = Path()
      ..moveTo(8, 6)
      ..lineTo(13, 9)
      ..lineTo(8, 12)
      ..close();
    canvas.drawPath(play, fill);
  }

  @override
  bool shouldRepaint(covariant _Winamp2LogoPainter oldDelegate) => oldDelegate.color != color;
}

class _Winamp2Hairline extends StatelessWidget {
  const _Winamp2Hairline({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}

class _Winamp2CaptionButton extends StatelessWidget {
  const _Winamp2CaptionButton({required this.label, required this.palette, this.onTap});

  final String label;
  final _Winamp2Palette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 17,
      height: 22,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: palette.accent.withValues(alpha: 0.18),
          splashColor: palette.accent.withValues(alpha: 0.25),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: label == '×' ? palette.text : palette.dimText,
                fontFamily: Design.uiFontFamily,
                fontSize: label == '×' ? Design.baseFontSize + 3 : Design.baseFontSize + 1,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Winamp2ActionRail extends StatelessWidget {
  const _Winamp2ActionRail({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return _Winamp2Frame(
      palette: palette,
      margin: const EdgeInsets.fromLTRB(7, 2, 7, 3),
      child: SizedBox(
        height: 25,
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: IconThemeData(size: 15, color: palette.text),
            hoverColor: palette.accent.withValues(alpha: 0.18),
            splashColor: palette.accent.withValues(alpha: 0.20),
          ),
          child: const TopBar(),
        ),
      ),
    );
  }
}

class _Winamp2PlayerDeck extends StatelessWidget {
  const _Winamp2PlayerDeck({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return _Winamp2Frame(
      palette: palette,
      inset: true,
      margin: const EdgeInsets.fromLTRB(7, 2, 7, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 7, 7, 5),
            child: SizedBox(
              height: 89,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(flex: 36, child: _Winamp2CounterScreen(palette: palette)),
                  const SizedBox(width: 5),
                  Expanded(flex: 64, child: _Winamp2TrackScreen(palette: palette)),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: SizedBox(
              height: 17,
              child: CustomPaint(painter: _Winamp2SeekPainter(palette: palette)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
            child: Row(
              children: <Widget>[
                _Winamp2TransportButton(
                  icon: Icons.skip_previous_rounded,
                  tooltip: 'Previous window',
                  palette: palette,
                  onTap: () => QuickMenuFunctions.onVerticalArrow(true),
                ),
                _Winamp2TransportButton(
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'Activate selected window',
                  palette: palette,
                  selected: true,
                  onTap: QuickMenuFunctions.onEnter,
                ),
                _Winamp2TransportButton(
                  icon: Icons.pause_rounded,
                  tooltip: 'Clear window selection',
                  palette: palette,
                  onTap: QuickMenuFunctions.resetKeyboardSelection,
                ),
                _Winamp2TransportButton(
                  icon: Icons.stop_rounded,
                  tooltip: 'Hide QuickMenu',
                  palette: palette,
                  onTap: QuickMenuFunctions.hideQuickMenu,
                ),
                _Winamp2TransportButton(
                  icon: Icons.skip_next_rounded,
                  tooltip: 'Next window',
                  palette: palette,
                  onTap: () => QuickMenuFunctions.onVerticalArrow(false),
                ),
                const Spacer(),
                _Winamp2TransportButton(icon: Icons.eject_rounded, tooltip: 'Eject', palette: palette),
                const SizedBox(width: 5),
                _Winamp2LabelButton(label: 'SHUFFLE', palette: palette),
                _Winamp2LabelButton(label: 'REP', palette: palette),
                const SizedBox(width: 6),
                _Winamp2TransportButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'QuickMenu controls',
                  palette: palette,
                  selected: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Winamp2CounterScreen extends StatelessWidget {
  const _Winamp2CounterScreen({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return _Winamp2Screen(
      palette: palette,
      child: Stack(
        children: <Widget>[
          Positioned(
            left: 7,
            top: 8,
            child: Text(
              'O\nA\nR\nI\nV',
              style: TextStyle(
                color: palette.dimText,
                fontFamily: Design.entryFontFamily,
                fontSize: Design.baseFontSize - 1,
                height: 0.84,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Positioned(
            left: 32,
            top: 28,
            child: Icon(Icons.play_arrow_rounded, size: 17, color: palette.accent),
          ),
          Positioned(
            top: 7,
            right: 7,
            child: Text(
              '01:24',
              style: TextStyle(
                color: palette.accent,
                fontFamily: Design.entryFontFamily,
                fontSize: Design.baseFontSize + 19,
                fontWeight: FontWeight.w500,
                letterSpacing: 1.2,
                height: 1,
                shadows: <Shadow>[
                  Shadow(color: palette.accent.withValues(alpha: 0.55), blurRadius: 5),
                ],
              ),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 7,
            child: Text(
              'PLAY 01',
              style: TextStyle(
                color: palette.dimText,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 2,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Winamp2TrackScreen extends StatelessWidget {
  const _Winamp2TrackScreen({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return _Winamp2Screen(
      palette: palette,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'BOMBOO - ROSEWOOD (3:00)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.text,
                fontFamily: Design.entryFontFamily,
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Text(
                  'KBPS: 44KHZ',
                  style: TextStyle(
                    color: palette.dimText,
                    fontFamily: Design.entryFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  'MONO',
                  style: TextStyle(
                    color: palette.dimText,
                    fontFamily: Design.entryFontFamily,
                    fontSize: Design.baseFontSize - 1,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'STEREO',
                  style: TextStyle(
                    color: palette.accent,
                    fontFamily: Design.entryFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    shadows: <Shadow>[Shadow(color: palette.accent.withValues(alpha: 0.45), blurRadius: 4)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: <Widget>[
                Expanded(child: _Winamp2ProgressStrip(palette: palette, value: 0.38)),
                const SizedBox(width: 7),
                SizedBox(width: 37, child: _Winamp2ProgressStrip(palette: palette, value: 0.68)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Winamp2Screen extends StatelessWidget {
  const _Winamp2Screen({required this.palette, required this.child});

  final _Winamp2Palette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.screen,
        border: Border.all(color: palette.line),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: palette.isDark ? 0.24 : 0.12), offset: const Offset(1, 1)),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Winamp2ScreenGlassPainter(palette: palette)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Winamp2ProgressStrip extends StatelessWidget {
  const _Winamp2ProgressStrip({required this.palette, required this.value});

  final _Winamp2Palette palette;
  final double value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.slot,
          border: Border.all(color: palette.line.withValues(alpha: 0.75)),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(color: palette.accent),
          ),
        ),
      ),
    );
  }
}

class _Winamp2SeekPainter extends CustomPainter {
  const _Winamp2SeekPainter({required this.palette});

  final _Winamp2Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Rect track = Rect.fromLTWH(0, y - 3, size.width, 6);
    final Paint trackPaint = Paint()..color = palette.slot;
    final Paint borderPaint = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final Paint progressPaint = Paint()..color = palette.accent;
    canvas.drawRect(track, trackPaint);
    canvas.drawRect(track, borderPaint);
    canvas.drawRect(Rect.fromLTWH(1, y - 2, size.width * 0.44, 4), progressPaint);
    final double knobX = size.width * 0.44;
    canvas.drawRect(Rect.fromLTWH(knobX - 3, y - 7, 6, 14), Paint()..color = palette.edgeHi);
    canvas.drawRect(Rect.fromLTWH(knobX - 2, y - 6, 4, 12), Paint()..color = palette.edgeLo);
  }

  @override
  bool shouldRepaint(covariant _Winamp2SeekPainter oldDelegate) => oldDelegate.palette != palette;
}

class _Winamp2ScreenGlassPainter extends CustomPainter {
  const _Winamp2ScreenGlassPainter({required this.palette});

  final _Winamp2Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint topShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[Colors.black.withValues(alpha: 0.26), Colors.transparent],
        stops: const <double>[0.0, 0.18],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, topShadow);
    final Paint corner = Paint()..color = palette.accent.withValues(alpha: 0.34);
    const double inset = 3;
    const double length = 6;
    canvas.drawRect(const Rect.fromLTWH(inset, inset, length, 1), corner);
    canvas.drawRect(const Rect.fromLTWH(inset, inset, 1, length), corner);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - length, inset, length, 1), corner);
    canvas.drawRect(Rect.fromLTWH(size.width - inset - 1, inset, 1, length), corner);
  }

  @override
  bool shouldRepaint(covariant _Winamp2ScreenGlassPainter oldDelegate) => oldDelegate.palette != palette;
}

class _Winamp2TransportButton extends StatelessWidget {
  const _Winamp2TransportButton({
    required this.icon,
    required this.tooltip,
    required this.palette,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final _Winamp2Palette palette;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 39,
        height: 34,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? palette.accent.withValues(alpha: 0.12) : palette.face,
              border: Border.all(
                color: selected ? palette.accent.withValues(alpha: 0.56) : palette.line.withValues(alpha: 0.62),
              ),
            ),
            child: InkWell(
              onTap: onTap,
              hoverColor: palette.accent.withValues(alpha: 0.18),
              splashColor: palette.accent.withValues(alpha: 0.24),
              child: Icon(icon, size: 17, color: selected ? palette.accent : palette.text),
            ),
          ),
        ),
      ),
    );
  }
}

class _Winamp2LabelButton extends StatelessWidget {
  const _Winamp2LabelButton({required this.label, required this.palette});

  final String label;
  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: palette.face,
            border: Border.all(color: palette.line.withValues(alpha: 0.62)),
          ),
          child: InkWell(
            hoverColor: palette.accent.withValues(alpha: 0.18),
            splashColor: palette.accent.withValues(alpha: 0.24),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.dimText,
                    fontFamily: Design.uiFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
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

class _Winamp2Equalizer extends StatelessWidget {
  const _Winamp2Equalizer({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Winamp2SectionHeader(label: 'EQUALIZER', palette: palette),
        Padding(
          padding: const EdgeInsets.fromLTRB(27, 1, 27, 3),
          child: Row(
            children: <Widget>[
              _Winamp2ToggleButton(label: 'ON', palette: palette, selected: true),
              const SizedBox(width: 5),
              _Winamp2ToggleButton(label: 'AUTO', palette: palette),
              const Spacer(),
              _Winamp2LabelButton(label: 'PRESETS', palette: palette),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(25, 1, 25, 1),
          child: SizedBox(
            height: 51,
            child: Row(
              children: <Widget>[
                const SizedBox(width: 118),
                Expanded(child: CustomPaint(painter: _Winamp2EqGraphPainter(palette: palette))),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 1, 18, 5),
          child: SizedBox(
            height: 143,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 92,
                  child: _Winamp2EqFader(label: 'PREAMP', value: 0.50, palette: palette),
                ),
                ...List<Widget>.generate(
                  _kWinamp2EqLabels.length - 1,
                  (int index) => Expanded(
                    child: _Winamp2EqFader(
                      label: _kWinamp2EqLabels[index + 1],
                      value: _kWinamp2EqValues[index + 1],
                      palette: palette,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

const List<String> _kWinamp2EqLabels = <String>[
  'PREAMP',
  '60',
  '70',
  '310',
  '600',
  '1K',
  '3K',
  '6K',
  '12K',
  '14K',
  '16K'
];

const List<double> _kWinamp2EqValues = <double>[0.50, 0.62, 0.44, 0.26, 0.18, 0.36, 0.48, 0.61, 0.74, 0.72, 0.68];

class _Winamp2SectionHeader extends StatelessWidget {
  const _Winamp2SectionHeader({required this.label, required this.palette});

  final String label;
  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 1, 7, 2),
      child: Row(
        children: <Widget>[
          Expanded(child: _Winamp2Hairline(color: palette.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              label,
              style: TextStyle(
                color: palette.dimText,
                fontFamily: Design.uiFontFamily,
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.4,
                height: 1,
              ),
            ),
          ),
          Expanded(child: _Winamp2Hairline(color: palette.line)),
          const SizedBox(width: 8),
          Text(
            '×',
            style: TextStyle(
              color: palette.dimText,
              fontFamily: Design.uiFontFamily,
              fontSize: Design.baseFontSize + 2,
              height: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _Winamp2ToggleButton extends StatelessWidget {
  const _Winamp2ToggleButton({required this.label, required this.palette, this.selected = false});

  final String label;
  final _Winamp2Palette palette;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? palette.accent.withValues(alpha: 0.12) : palette.face,
            border: Border.all(color: selected ? palette.accent.withValues(alpha: 0.60) : palette.line),
          ),
          child: InkWell(
            hoverColor: palette.accent.withValues(alpha: 0.18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? palette.accent : palette.dimText,
                    fontFamily: Design.uiFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
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

class _Winamp2EqFader extends StatelessWidget {
  const _Winamp2EqFader({required this.label, required this.value, required this.palette});

  final String label;
  final double value;
  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: CustomPaint(
            painter: _Winamp2FaderPainter(palette: palette, value: value),
            child: const SizedBox.expand(),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: palette.dimText,
            fontFamily: Design.entryFontFamily,
            fontSize: Design.baseFontSize - 1,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

class _Winamp2FaderPainter extends CustomPainter {
  const _Winamp2FaderPainter({required this.palette, required this.value});

  final _Winamp2Palette palette;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final double center = size.width / 2;
    const double top = 1;
    final double bottom = size.height - 1;
    final Rect track = Rect.fromLTWH(center - 13, top, 26, bottom - top);
    final Paint trackPaint = Paint()..color = palette.slot;
    final Paint trackBorder = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(track, trackPaint);
    canvas.drawRect(track, trackBorder);

    for (double y = top + 12; y < bottom; y += 16) {
      canvas.drawLine(
        Offset(center - 9, y),
        Offset(center + 9, y),
        Paint()..color = palette.line.withValues(alpha: 0.40),
      );
    }

    final double normalized = value.clamp(0.0, 1.0);
    final double knobY = bottom - normalized * (bottom - top - 12) - 6;
    final double fillTop = knobY + 7;
    if (fillTop < bottom) {
      canvas.drawRect(
        Rect.fromLTRB(center - 4, fillTop, center + 4, bottom - 1),
        Paint()..color = palette.accent,
      );
    }

    final Rect knob = Rect.fromCenter(center: Offset(center, knobY), width: 20, height: 15);
    canvas.drawRect(knob, Paint()..color = palette.edgeHi);
    canvas.drawRect(knob.deflate(2), Paint()..color = palette.edgeLo);
    canvas.drawLine(Offset(knob.left + 3, knob.center.dy), Offset(knob.right - 3, knob.center.dy),
        Paint()..color = palette.edgeHi.withValues(alpha: 0.65));
  }

  @override
  bool shouldRepaint(covariant _Winamp2FaderPainter oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.value != value;
}

class _Winamp2EqGraphPainter extends CustomPainter {
  const _Winamp2EqGraphPainter({required this.palette});

  final _Winamp2Palette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint background = Paint()..color = palette.slot;
    final Paint border = Paint()
      ..color = palette.line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, background);
    canvas.drawRect(Offset.zero & size, border);

    final Paint grid = Paint()
      ..color = palette.line.withValues(alpha: 0.26)
      ..strokeWidth = 1;
    for (double x = 8; x < size.width; x += 18) {
      canvas.drawLine(Offset(x, 1), Offset(x, size.height - 1), grid);
    }
    for (double y = 8; y < size.height; y += 12) {
      canvas.drawLine(Offset(1, y), Offset(size.width - 1, y), grid);
    }

    final Path curve = Path();
    final int points = math.max(20, size.width.toInt());
    for (int index = 0; index <= points; index++) {
      final double x = size.width * index / points;
      final double normalized = points == 0 ? 0 : index / points;
      final double dip = math.exp(-math.pow((normalized - 0.38) / 0.19, 2).toDouble());
      final double y = size.height * (0.16 + dip * 0.66);
      if (index == 0) {
        curve.moveTo(x, y);
      } else {
        curve.lineTo(x, y);
      }
    }
    final Paint glow = Paint()
      ..color = palette.accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final Paint core = Paint()
      ..color = palette.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    canvas.drawPath(curve, glow);
    canvas.drawPath(curve, core);
  }

  @override
  bool shouldRepaint(covariant _Winamp2EqGraphPainter oldDelegate) => oldDelegate.palette != palette;
}

class _Winamp2Playlist extends StatelessWidget {
  const _Winamp2Playlist({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _Winamp2SectionHeader(label: 'PLAYLIST', palette: palette),
        _Winamp2Frame(
          palette: palette,
          inset: true,
          margin: const EdgeInsets.fromLTRB(7, 1, 7, 4),
          child: SizedBox(
            height: 254,
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(9, 4, 9, 3),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'WINDOWS',
                        style: TextStyle(
                          color: palette.dimText,
                          fontFamily: Design.uiFontFamily,
                          fontSize: Design.baseFontSize - 2,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'ACTIVE DESKTOP',
                        style: TextStyle(
                          color: palette.dimText,
                          fontFamily: Design.uiFontFamily,
                          fontSize: Design.baseFontSize - 2,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const Expanded(child: TaskBar()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Winamp2Footer extends StatelessWidget {
  const _Winamp2Footer({required this.palette});

  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return _Winamp2Frame(
      palette: palette,
      inset: true,
      margin: const EdgeInsets.fromLTRB(7, 1, 7, 7),
      child: SizedBox(
        height: 36,
        child: Row(
          children: <Widget>[
            _Winamp2FooterButton(label: 'ADD', palette: palette),
            _Winamp2FooterButton(label: 'REM', palette: palette),
            _Winamp2FooterButton(label: 'SEL', palette: palette),
            _Winamp2FooterButton(label: 'MISC', palette: palette),
            const SizedBox(width: 7),
            Expanded(
              child: Theme(
                data: Theme.of(context).copyWith(
                  iconTheme: IconThemeData(size: 14, color: palette.text),
                  hoverColor: palette.accent.withValues(alpha: 0.18),
                ),
                child: const BottomBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Winamp2FooterButton extends StatelessWidget {
  const _Winamp2FooterButton({required this.label, required this.palette});

  final String label;
  final _Winamp2Palette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: label == 'MISC' ? 47 : 43,
      height: 27,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: palette.face,
              border: Border.all(color: palette.line.withValues(alpha: 0.62)),
            ),
            child: InkWell(
              hoverColor: palette.accent.withValues(alpha: 0.18),
              splashColor: palette.accent.withValues(alpha: 0.24),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: palette.dimText,
                    fontFamily: Design.uiFontFamily,
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
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
