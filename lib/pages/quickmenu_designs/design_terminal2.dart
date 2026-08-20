import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import 'design_backdrop_stable.dart';

/// A faithful terminal/TUI interpretation of the QuickMenu.
///
/// This preset deliberately avoids desktop-window chrome and decorative cards.
/// The interface is expressed as a shell session: command lines introduce real
/// QuickMenu controls, hairline frames establish the TUI hierarchy, and the
/// footer behaves like a tmux status line. All colors remain theme-driven.
const List<String> _monoFallback = <String>[
  'Cascadia Mono',
  'JetBrains Mono',
  'Consolas',
  'Courier New',
];

String _shellUser() {
  final String name = Platform.environment['USERNAME'] ?? 'user';
  final String clean = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  return clean.isEmpty ? 'user' : clean;
}

TextStyle _terminalText(
  Color color, {
  double? size,
  FontWeight weight = FontWeight.w500,
  double letterSpacing = 0,
}) {
  return TextStyle(
    color: color,
    fontFamily: 'Cascadia Mono',
    fontFamilyFallback: _monoFallback,
    fontSize: size ?? Design.baseFontSize,
    fontWeight: weight,
    height: 1.15,
    letterSpacing: letterSpacing,
  );
}

class _TerminalPalette {
  const _TerminalPalette({
    required this.background,
    required this.surface,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.accentInk,
    required this.rule,
  });

  factory _TerminalPalette.fromTheme() {
    final Color background = Design.background;
    final Color text = Design.text;
    final Color accent = Design.accent;
    final bool dark = background.computeLuminance() < 0.5;

    return _TerminalPalette(
      background: Color.alphaBlend(accent.withValues(alpha: dark ? 0.025 : 0.018), background),
      surface: Color.alphaBlend(text.withValues(alpha: dark ? 0.025 : 0.018), background),
      text: text.withValues(alpha: 0.92),
      muted: text.withValues(alpha: 0.58),
      faint: text.withValues(alpha: 0.28),
      accent: accent,
      accentInk: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark
          ? const Color(0xffF1F4E8)
          : const Color(0xff11140F),
      rule: accent.withValues(alpha: dark ? 0.46 : 0.54),
    );
  }

  final Color background;
  final Color surface;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color accentInk;
  final Color rule;
}

class MainMenuTerminal2Widget extends StatelessWidget {
  const MainMenuTerminal2Widget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final _TerminalPalette palette = _TerminalPalette.fromTheme();
    final double radius = Design.borderRadius.clamp(0, 3);

    final ThemeData terminalTheme = Theme.of(context).copyWith(
      splashFactory: NoSplash.splashFactory,
      hoverColor: palette.accent.withAlpha(28),
      highlightColor: palette.accent.withAlpha(22),
      focusColor: palette.accent.withAlpha(42),
      iconTheme: IconThemeData(color: palette.text, size: 15),
      textTheme: Theme.of(context).textTheme.apply(
            fontFamily: 'Cascadia Mono',
            bodyColor: palette.text,
            displayColor: palette.text,
          ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Theme(
            data: terminalTheme,
            child: Stack(
              children: <Widget>[
                Positioned.fill(child: _TerminalGround(palette: palette)),
                RepaintBoundary(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _TerminalHeader(palette: palette),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(5, 5, 5, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (!user.quickActionsAtBottom)
                              _TerminalSection(
                                palette: palette,
                                label: 'COMMANDS',
                                command: 'tabame actions --quick',
                                child: const TopBar(),
                              )
                            else if (user.bottomBarOnTop)
                              _TerminalSection(
                                palette: palette,
                                label: 'COMMANDS + LINKS',
                                command: 'tabame bar --combined',
                                child: const PinnedAndTrayList(),
                              ),
                            _TerminalSection(
                              palette: palette,
                              label: 'PROCESS TABLE',
                              command: 'tabame ps --interactive',
                              columnHeader: true,
                              child: const TaskBar(),
                            ),
                            if (!user.bottomBarOnTop)
                              _TerminalSection(
                                palette: palette,
                                label: user.quickActionsAtBottom ? 'COMMANDS + LINKS' : 'LINKS',
                                command: user.quickActionsAtBottom
                                    ? 'tabame bar --combined'
                                    : 'tabame links --pinned --tray',
                                child: const PinnedAndTrayList(),
                              ),
                            if (user.taskManagerStats)
                              _TerminalSection(
                                palette: palette,
                                label: 'SYSTEM LOAD',
                                command: 'tabame top --summary',
                                child: const TaskbarStats(withTopDivider: false),
                              ),
                            if (user.libreStats)
                              _TerminalSection(
                                palette: palette,
                                label: 'SENSORS',
                                command: 'tabame sensors --live',
                                child: const LibreStats(withTopDivider: false),
                              ),
                            _IdlePrompt(palette: palette),
                          ],
                        ),
                      ),
                      _TerminalStatusBar(palette: palette),
                    ],
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _ScanlinePainter(color: palette.text)),
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

class _TerminalGround extends StatelessWidget {
  const _TerminalGround({required this.palette});

  final _TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final List<double> points = Design.panelOpacityPoints;
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) => LinearGradient(
        begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
        end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
        stops: <double>[for (int index = 0; index < points.length; index += 2) points[index]],
        colors: <Color>[
          for (int index = 1; index < points.length; index += 2) Colors.white.withValues(alpha: points[index]),
        ],
      ).createShader(bounds),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: hasBackdrop ? 0.90 : 1),
          border: Border.all(color: palette.accent.withValues(alpha: 0.72)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            ColoredBox(color: palette.background.withValues(alpha: hasBackdrop ? 0.36 : 0)),
          ],
        ),
      ),
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({required this.palette});

  final _TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 31,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.rule)),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 6, height: 12, color: palette.accent),
          const SizedBox(width: 7),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '${_shellUser()}@tabame',
                    style: _terminalText(palette.accent, weight: FontWeight.w700),
                  ),
                  TextSpan(text: ':~', style: _terminalText(palette.text)),
                  TextSpan(text: r'$ ', style: _terminalText(palette.muted)),
                  TextSpan(
                    text: 'quickmenu --attach',
                    style: _terminalText(palette.text, weight: FontWeight.w600),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '[tty0]',
            style: _terminalText(
              palette.muted,
              size: Design.baseFontSize - 1,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TerminalSection extends StatelessWidget {
  const _TerminalSection({
    required this.palette,
    required this.label,
    required this.command,
    required this.child,
    this.columnHeader = false,
  });

  final _TerminalPalette palette;
  final String label;
  final String command;
  final Widget child;
  final bool columnHeader;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 3),
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: r'$ ', style: _terminalText(palette.accent, weight: FontWeight.w700)),
                  TextSpan(text: command, style: _terminalText(palette.text)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.surface,
              border: Border.all(color: palette.rule),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _SectionRule(palette: palette, label: label),
                if (columnHeader) _ProcessColumns(palette: palette),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRule extends StatelessWidget {
  const _SectionRule({required this.palette, required this.label});

  final _TerminalPalette palette;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 6),
          Text(
            '[ $label ]',
            style: _terminalText(
              palette.accent,
              size: Design.baseFontSize - 1,
              weight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(child: Container(height: 1, color: palette.rule)),
          const SizedBox(width: 5),
        ],
      ),
    );
  }
}

class _ProcessColumns extends StatelessWidget {
  const _ProcessColumns({required this.palette});

  final _TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = _terminalText(
      palette.muted,
      size: Design.baseFontSize - 1,
      weight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Container(
      height: 19,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.faint),
          bottom: BorderSide(color: palette.faint),
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 34, child: Text('PID', style: style)),
          const SizedBox(width: 4),
          Expanded(child: Text('PROCESS / WINDOW', style: style)),
          Text('ACTION', style: style),
        ],
      ),
    );
  }
}

class _IdlePrompt extends StatefulWidget {
  const _IdlePrompt({required this.palette});

  final _TerminalPalette palette;

  @override
  State<_IdlePrompt> createState() => _IdlePromptState();
}

class _IdlePromptState extends State<_IdlePrompt> with QuickMenuTriggers {
  Timer? _timer;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    _startCursor();
  }

  void _startCursor() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  void _stopCursor() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible) {
      _startCursor();
    } else {
      _stopCursor();
    }
  }

  @override
  void dispose() {
    _stopCursor();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final _TerminalPalette palette = widget.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 1, 2, 0),
      child: Row(
        children: <Widget>[
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: '${_shellUser()}@tabame',
                  style: _terminalText(palette.accent, weight: FontWeight.w700),
                ),
                TextSpan(text: ':~', style: _terminalText(palette.text)),
                TextSpan(text: r'$ ', style: _terminalText(palette.muted)),
              ],
            ),
          ),
          Container(
            width: 7,
            height: Design.baseFontSize + 3,
            color: _cursorVisible ? palette.accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

class _TerminalStatusBar extends StatelessWidget {
  const _TerminalStatusBar({required this.palette});

  final _TerminalPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.rule)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: double.infinity,
            color: palette.accent,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            child: Text(
              '[0] qmenu*',
              style: _terminalText(
                palette.accentInk,
                size: Design.baseFontSize - 1,
                weight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              'NORMAL',
              style: _terminalText(
                palette.accent,
                size: Design.baseFontSize - 1,
                weight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ),
          Expanded(child: DefaultTextStyle.merge(style: _terminalText(palette.text), child: const BottomBar())),
          Padding(
            padding: const EdgeInsets.only(left: 6, right: 7),
            child: Text(
              'TTY0',
              style: _terminalText(
                palette.muted,
                size: Design.baseFontSize - 1,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.018)
      ..strokeWidth = 1;
    for (double y = 2.5; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => oldDelegate.color != color;
}
