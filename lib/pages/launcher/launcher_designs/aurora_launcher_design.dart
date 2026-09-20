part of '../launcher_design_builder.dart';

BoxDecoration _auroraOuterDecoration() {
  return BoxDecoration(
      color: AuroraTokens.background,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AuroraTokens.border));
}

class _AuroraSearchBar extends StatelessWidget {
  const _AuroraSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
      final bool wide = constraints.maxWidth >= 760;
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 22, 18, 14),
        child: Row(children: <Widget>[
          if (wide) ...<Widget>[
            DragToMoveArea(
                child: Row(children: <Widget>[
              const CustomPaint(size: Size(34, 38), painter: _AuroraLogoPainter()),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('AURORA', style: AuroraTokens.font(size: 12, color: AuroraTokens.accent, spacing: 4)),
                const SizedBox(height: 4),
                Text('Launch Everything', style: AuroraTokens.font(size: 10, color: AuroraTokens.dim)),
              ]),
            ])),
            const SizedBox(width: 24),
          ],
          Expanded(
              child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AuroraTokens.background.withAlpha(220),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AuroraTokens.accent),
              boxShadow: <BoxShadow>[
                BoxShadow(color: AuroraTokens.accent.withAlpha(42), blurRadius: 14, spreadRadius: 1)
              ],
            ),
            child: Row(children: <Widget>[
              content.dragHandle,
              const SizedBox(width: 15),
              Expanded(child: content.textField),
              if (content.trailingBadge != null) content.trailingBadge!,
              if (content.isSearching)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AuroraTokens.accent)),
            ]),
          )),
        ]),
      );
    });
  }
}

class AuroraLauncherFrame extends StatelessWidget {
  const AuroraLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _auroraOuterDecoration(),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(children: <Widget>[
            if (Design.hasBackdrop)
              const StableBackdrop()
            else
              Positioned.fill(
                  child: Image.asset('resources/images/aurora_launcher.png',
                      fit: BoxFit.cover,
                      alignment: Alignment.bottomCenter,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
                          const ColoredBox(color: AuroraTokens.background))),
            const Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xF2031722), Color(0x99031722), Color(0x77031722)],
              stops: <double>[0, .45, 1],
            )))),
            Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Flexible(fit: FlexFit.loose, child: child),
              Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: const BoxDecoration(
                      color: Color(0xDF031722), border: Border(top: BorderSide(color: AuroraTokens.border))),
                  child: Row(children: <Widget>[
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF00EF96),
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[BoxShadow(color: Color(0x6600EF96), blurRadius: 8)])),
                    const SizedBox(width: 10),
                    Text('Ready', style: AuroraTokens.font(size: 11, color: AuroraTokens.dim)),
                    const SizedBox(width: 22),
                    Text('$resultCount results', style: AuroraTokens.font(size: 11, color: AuroraTokens.dim)),
                    const Spacer(),
                    Text('Ctrl K  Actions     Esc  Close', style: AuroraTokens.font(size: 11, color: AuroraTokens.dim)),
                  ])),
            ]),
          ])),
    );
  }
}

class _AuroraLogoPainter extends CustomPainter {
  const _AuroraLogoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final Path left = Path()
      ..moveTo(4, size.height - 5)
      ..lineTo(size.width / 2, 5);
    final Path right = Path()
      ..moveTo(size.width / 2, 5)
      ..lineTo(size.width - 4, size.height - 5);
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    paint.color = AuroraTokens.accent.withAlpha(100);
    paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(left, paint);
    canvas.drawPath(right, paint);
    paint.maskFilter = null;
    paint.color = const Color(0xFF8DF7FF);
    canvas.drawPath(left, paint);
    paint.color = AuroraTokens.accent;
    canvas.drawPath(right, paint);
  }

  @override
  bool shouldRepaint(_AuroraLogoPainter oldDelegate) => false;
}
