part of '../launcher_design_builder.dart';

BoxDecoration _lodestoneOuterDecoration(Color surface) => BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: LodestoneTokens.border),
    );

class _LodestoneSearchBar extends StatelessWidget {
  const _LodestoneSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 11),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: LodestoneTokens.border))),
        child: Row(children: <Widget>[
          content.dragHandle,
          const SizedBox(width: 10),
          Expanded(child: _LauncherSearchField(content)),
          const SizedBox(width: 8),
          // Reserved so the query does not reflow when a search starts.
          SizedBox.square(dimension: 18, child: content.isSearching ? const _LodestoneSeeker() : null),
        ]),
      );
}

/// A needle that hunts back and forth while a search is running.
class _LodestoneSeeker extends StatefulWidget {
  const _LodestoneSeeker();

  @override
  State<_LodestoneSeeker> createState() => _LodestoneSeekerState();
}

class _LodestoneSeekerState extends State<_LodestoneSeeker> with SingleTickerProviderStateMixin {
  late final AnimationController _hunt = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncRepeatingAnimation(_hunt, context);
  }

  @override
  void dispose() {
    _hunt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          painter: _LodestoneSeekerPainter(
            hunt: _hunt,
            head: LodestoneTokens.accent,
            tail: LodestoneTokens.dim,
          ),
        ),
      );
}

class _LodestoneSeekerPainter extends CustomPainter {
  _LodestoneSeekerPainter({required this.hunt, required this.head, required this.tail}) : super(repaint: hunt);

  final Animation<double> hunt;
  final Color head;
  final Color tail;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    // Stopped, the needle rests pointing north-east.
    final double angle = -math.pi / 4 + math.sin(hunt.value * math.pi * 2) * 1.15;
    final Offset arm = Offset(math.cos(angle), math.sin(angle)) * (size.shortestSide * 0.44);
    final Paint stroke = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, center - arm, stroke..color = tail);
    canvas.drawLine(center, center + arm, stroke..color = head);
  }

  @override
  bool shouldRepaint(_LodestoneSeekerPainter oldDelegate) =>
      hunt != oldDelegate.hunt || head != oldDelegate.head || tail != oldDelegate.tail;
}

class LodestoneLauncherFrame extends StatelessWidget {
  const LodestoneLauncherFrame({
    super.key,
    required this.searchChild,
    required this.resultCount,
    required this.child,
  });

  final Widget searchChild;
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherSurface(
        decoration: _lodestoneOuterDecoration(LodestoneTokens.background),
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          searchChild,
          // The field covers the results only. The query stays on a plain plate.
          Flexible(fit: FlexFit.loose, child: LodestoneSurface(child: child)),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
            color: LodestoneTokens.plate,
            child: Row(children: <Widget>[
              Text(
                Globals.isLauncherPluginActive ? 'PLUGIN' : '$resultCount ${resultCount == 1 ? 'RESULT' : 'RESULTS'}',
                style: LodestoneTokens.label(),
              ),
              const SizedBox(width: 16),
              // Hints are listed by priority. Ones that do not fit wrap to a
              // second line, which the fixed height clips away.
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 14,
                    runSpacing: 18,
                    clipBehavior: Clip.hardEdge,
                    children: <Widget>[
                      _hint('↵', 'Open'),
                      _hint('Tab', 'Actions'),
                      _hint('↑↓', 'Navigate'),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ]),
      );

  Widget _hint(String key, String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Text(key, style: LodestoneTokens.font(size: 11, weight: FontWeight.w600)),
        const SizedBox(width: 5),
        Text(label, style: LodestoneTokens.font(size: 11, color: LodestoneTokens.dim)),
      ]);
}
