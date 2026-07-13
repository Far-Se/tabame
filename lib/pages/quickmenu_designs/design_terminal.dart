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

/// "Terminal" QuickMenu design — a real terminal emulator session.
///
/// The menu renders as a focused terminal window: a title bar with traffic
/// lights and a `user@tabame: ~` title, a flat console body where every
/// section is introduced by a shell prompt line (`$ tabame ls --windows`
/// above the switcher, `$ tabame ls --pinned` above the pinned strip), an
/// idle prompt with a blinking block cursor awaiting input, and a tmux-style
/// status bar with an accent session segment holding the info bar.
///
/// Colors follow the user's theme (`Design.background` / `Design.accent`);
/// fonts fall back through common monospace faces if the theme's family is
/// missing. The cursor blink pauses while the QuickMenu is hidden.
const List<String> _monoFallback = <String>['JetBrains Mono', 'Cascadia Mono', 'Consolas', 'Courier New'];

String _shellUser() {
  final String name = Platform.environment['USERNAME'] ?? 'user';
  final String clean = name.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  return clean.isEmpty ? 'user' : clean;
}

/// Raised chrome (title bar / status bar), derived from the theme background
/// so it reads correctly in both light and dark themes.
Color _terminalChrome() {
  final Color bg = Design.background;
  final bool isDark = bg.computeLuminance() < 0.5;
  return Color.alphaBlend(
    (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 16 : 14),
    bg,
  );
}

class MainMenuTerminalWidget extends StatelessWidget {
  const MainMenuTerminalWidget({super.key});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // register as theme-dependent so Design.* values update live
    final Color accent = Design.accent;
    final Color chrome = _terminalChrome();
    final double radius = Design.borderRadius;
    final bool hasBackdrop = user.activeBackdropPath.isNotEmpty;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // Console surface — flat, semi-transparent when a backdrop is active.
              Positioned.fill(
                child: RepaintBoundary(
                  child: ShaderMask(
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
                        color: Design.background.withValues(alpha: hasBackdrop ? 0.82 : 1.0),
                        border: Border.all(color: accent.withAlpha(80)),
                        borderRadius: BorderRadius.circular(radius),
                      ),
                      child: Design.hasBackdrop ? const Stack(children: <Widget>[StableBackdrop()]) : null,
                    ),
                  ),
                ),
              ),

              // ---- Session content ----
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _TermTitleBar(chrome: chrome),
                    if (!user.quickActionsAtBottom)
                      const TopBar()
                    else if (user.bottomBarOnTop)
                      const PinnedAndTrayList(),
                    // const _PromptLine(command: "tabame ls", flags: "--windows"),
                    const TaskBar(),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
                    if (user.libreStats) const LibreStats(withTopDivider: false),
                    // const _IdlePrompt(),
                    _TmuxBar(chrome: chrome, accent: accent),
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

// ---------------------------------------------------------------------------
// Title bar — traffic lights + session title
// ---------------------------------------------------------------------------

class _TermTitleBar extends StatelessWidget {
  const _TermTitleBar({required this.chrome});

  final Color chrome;

  @override
  Widget build(BuildContext context) {
    final Color text = Design.text;
    return Container(
      decoration: BoxDecoration(
        color: chrome,
        border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.35))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: <Widget>[
          const _TrafficLight(color: Color(0xffFF5F57)),
          const SizedBox(width: 5),
          const _TrafficLight(color: Color(0xffFEBC2E)),
          const SizedBox(width: 5),
          const _TrafficLight(color: Color(0xff28C840)),
          Expanded(
            child: Text(
              "${_shellUser()}@tabame: ~",
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize - 0.5,
                fontFamily: Design.uiFontFamily,
                fontFamilyFallback: _monoFallback,
                fontWeight: FontWeight.w600,
                color: text.withValues(alpha: 0.55),
              ),
            ),
          ),
          // Balance the traffic lights so the title stays centered.
          const SizedBox(width: 34),
        ],
      ),
    );
  }
}

class _TrafficLight extends StatelessWidget {
  const _TrafficLight({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.9),
        border: Border.all(color: Colors.black.withValues(alpha: 0.2), width: 0.5),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shell prompts
// ---------------------------------------------------------------------------

TextStyle _promptStyle(Color color, {FontWeight weight = FontWeight.w500}) {
  return TextStyle(
    fontSize: Design.baseFontSize - 0.5,
    fontFamily: Design.uiFontFamily,
    fontFamilyFallback: _monoFallback,
    fontWeight: weight,
    color: color,
  );
}

// class _PromptText extends StatelessWidget {
//   const _PromptText({required this.command, this.flags});

//   final String command;
//   final String? flags;

//   @override
//   Widget build(BuildContext context) {
//     final Color accent = Design.accent;
//     final Color text = Design.text;
//     return Text.rich(
//       TextSpan(
//         children: <InlineSpan>[
//           TextSpan(text: r"$ ", style: _promptStyle(accent, weight: FontWeight.w700)),
//           // TextSpan(text: command, style: _promptStyle(text.withValues(alpha: 0.78))),
//           // if (flags != null) TextSpan(text: " $flags", style: _promptStyle(text.withValues(alpha: 0.40))),
//         ],
//       ),
//       maxLines: 1,
//       overflow: TextOverflow.clip,
//     );
//   }
// }

/// A command on its own line — the section's "output" follows below it.
// class _PromptLine extends StatelessWidget {
//   const _PromptLine({required this.command, this.flags});

//   final String command;
//   final String? flags;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
//       child: Align(
//         alignment: Alignment.centerLeft,
//         child: _PromptText(command: command, flags: flags),
//       ),
//     );
//   }
// }

/// A command whose "output" renders inline to the right of the prompt.
// class _PromptRow extends StatelessWidget {
//   const _PromptRow({required this.command, required this.child, this.flags});

//   final String command;
//   final String? flags;
//   final Widget child;

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(8, 3, 4, 0),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.center,
//         children: <Widget>[
//           // _PromptText(command: command, flags: flags),
//           const SizedBox(width: 5),
//           Expanded(child: child),
//         ],
//       ),
//     );
//   }
// }

// ---------------------------------------------------------------------------
// Idle prompt with blinking block cursor
// ---------------------------------------------------------------------------

class _IdlePrompt extends StatefulWidget {
  const _IdlePrompt();

  @override
  State<_IdlePrompt> createState() => _IdlePromptState();
}

class _IdlePromptState extends State<_IdlePrompt> with QuickMenuTriggers {
  Timer? _timer;
  bool _on = true;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    _start();
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (mounted) setState(() => _on = !_on);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    // The QuickMenu stays mounted while hidden — stop ticking off-screen.
    if (visible) {
      _start();
    } else {
      _stop();
    }
  }

  @override
  void dispose() {
    _stop();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: <Widget>[
          Text(r"$", style: _promptStyle(accent, weight: FontWeight.w700)),
          const SizedBox(width: 5),
          Container(
            width: 6.5,
            height: Design.baseFontSize + 3,
            color: _on ? accent.withValues(alpha: 0.85) : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// tmux status bar
// ---------------------------------------------------------------------------

class _TmuxBar extends StatelessWidget {
  const _TmuxBar({required this.chrome, required this.accent});

  final Color chrome;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // final Color bg = Design.background;
    return Container(
      decoration: BoxDecoration(
        color: chrome,
        border: Border(top: BorderSide(color: accent.withAlpha(50))),
      ),
      padding: const EdgeInsets.fromLTRB(0, 0, 6, 1),
      child: const BottomBar(),
      // Row(
      //   children: <Widget>[
      //     // Container(
      //     //   color: accent,
      //     //   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      //     //   margin: const EdgeInsets.only(right: 7),
      //     //   child: Text(
      //     //     "[0] 0:tabame*",
      //     //     style: TextStyle(
      //     //       fontSize: Design.baseFontSize - 1,
      //     //       fontFamily: Design.uiFontFamily,
      //     //       fontFamilyFallback: _monoFallback,
      //     //       fontWeight: FontWeight.w700,
      //     //       color: bg,
      //     //     ),
      //     //   ),
      //     // ),
      //     const Expanded(child: BottomBar()),
      //   ],
      // ),
    );
  }
}
