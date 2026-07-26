part of '../launcher_design_builder.dart';

class _TerminalSearchBar extends StatelessWidget {
  const _TerminalSearchBar({
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
      child: Row(
        children: <Widget>[
          // Prompt chevron (also the window drag handle).
          dragHandle,
          const SizedBox(width: 6),
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
          // Blinking-style block cursor that runs while a query resolves.
          if (isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: accent.withAlpha(170)),
              ),
            )
          else
            _TerminalBlinkCursor(color: accent),
        ],
      ),
    );
  }
}

/// A small blinking block — the idle terminal cursor.
class _TerminalBlinkCursor extends StatefulWidget {
  const _TerminalBlinkCursor({required this.color});

  final Color color;

  @override
  State<_TerminalBlinkCursor> createState() => _TerminalBlinkCursorState();
}

class _TerminalBlinkCursorState extends State<_TerminalBlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1060),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          // On half the cycle the block is lit, off the other half.
          final bool lit = _controller.value < 0.5;
          return Container(
            width: 8,
            height: 15,
            decoration: BoxDecoration(
              color: lit ? widget.color.withAlpha(90) : widget.color.withAlpha(0),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        },
      ),
    );
  }
}

/// The console window — a forced-dark screen with a faux title bar, a
/// keyboard status line, and a subtle CRT scanline overlay.
class TerminalLauncherFrame extends StatelessWidget {
  const TerminalLauncherFrame({
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
      data: const LauncherThemeData(design: LauncherDesign.terminal),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.terminal.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _TerminalTitleBar(accent: accent, isDark: isDark),
                  child,
                  _TerminalStatusBar(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
              // CRT scanlines.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ScanlinePainter(isDark: isDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalTitleBar extends StatelessWidget {
  const _TerminalTitleBar({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (DragStartDetails _) {
        windowManager.startDragging();
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: TerminalTokens.chrome(isDark),
          border: Border(bottom: BorderSide(color: accent.withAlpha(40))),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent.withAlpha(220), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'QuickLaunch',
              style: TerminalTokens.mono(
                fontSize: Design.baseFontSize - 1,
                color: TerminalTokens.dim(isDark),
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                QuickMenuFunctions.hideQuickMenu();
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  '─  ✕',
                  style: TerminalTokens.mono(
                    fontSize: Design.baseFontSize - 1,
                    color: TerminalTokens.dim(isDark),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalStatusBar extends StatelessWidget {
  const _TerminalStatusBar({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final TextStyle key = TerminalTokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: accent.withAlpha(210),
      fontWeight: FontWeight.w700,
    );
    final TextStyle label = TerminalTokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: TerminalTokens.dim(isDark),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: TerminalTokens.chrome(isDark),
        border: Border(top: BorderSide(color: accent.withAlpha(40))),
      ),
      child: Row(
        children: <Widget>[
          Text('↵', style: key),
          Text(' run   ', style: label),
          Text('→', style: key),
          Text(' Ctrl+K   ', style: label),
          Text('esc', style: key),
          Text(' quit', style: label),
          const Spacer(),
          Text(
            '[ ${resultCount.toString().padLeft(2, '0')} ]',
            style: TerminalTokens.mono(
              fontSize: Design.baseFontSize - 1.5,
              color: accent.withAlpha(180),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Very subtle horizontal scanlines for a CRT feel. Light phosphor lines on the
/// dark screen; faint ink lines on the light "paper console".
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(5)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => oldDelegate.isDark != isDark;
}

// ---------------------------------------------------------------------------
// Zen (nature) — a calm, airy search field, frame, and rolling-hills footer.
// ---------------------------------------------------------------------------
