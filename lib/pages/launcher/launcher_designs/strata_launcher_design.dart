part of '../launcher_design_builder.dart';

BoxDecoration _strataOuterDecoration() {
  return BoxDecoration(
      color: StrataTokens.background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: StrataTokens.border));
}

class _StrataSearchBar extends StatelessWidget {
  const _StrataSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: StrataTokens.border)),
      ),
      child: Row(children: <Widget>[
        MouseRegion(
          cursor: SystemMouseCursors.move,
          child: DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: CustomPaint(size: const Size(30, 24), painter: _StrataLogoPainter(StrataTokens.accent)),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: content.textField),
        if (content.trailingBadge != null) content.trailingBadge!,
        const SizedBox(width: 10),
        Tooltip(
            message: 'Toggle file preview',
            child: Text('Ctrl + P', style: StrataTokens.font(size: 12, color: StrataTokens.dim))),
        if (content.isSearching)
          Padding(
              padding: const EdgeInsets.only(left: 12),
              child: SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: StrataTokens.accent))),
      ]),
    );
  }
}

class StrataLauncherFrame extends StatelessWidget {
  const StrataLauncherFrame({super.key, required this.resultCount, required this.child});
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LauncherSurface(
      decoration: _strataOuterDecoration(),
      child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Flexible(fit: FlexFit.loose, child: child),
        Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: StrataTokens.border))),
            child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) => Row(children: <Widget>[
                      _hint('↑↓ ', 'Navigate'),
                      const SizedBox(width: 18),
                      _hint('↵ ', 'Open'),
                      if (constraints.maxWidth > 650) ...<Widget>[
                        const SizedBox(width: 18),
                        _hint('Ctrl C', 'Copy'),
                        const SizedBox(width: 18),
                      ],
                      const Spacer(),
                      const Icon(Icons.circle, size: 8, color: Color(0xFF80F454)),
                      const SizedBox(width: 8),
                      Text('$resultCount results', style: StrataTokens.font(size: 11, color: StrataTokens.dim)),
                    ]))),
      ]),
    );
  }

  Widget _hint(String key, String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
                    color: StrataTokens.foreground,
                    border: Border.all(color: StrataTokens.border),
                    borderRadius: BorderRadius.circular(4))
                .withLauncherCorners(),
            child: Text(key, style: StrataTokens.font(size: 11, color: StrataTokens.dim))),
        const SizedBox(width: 9),
        Text(label, style: StrataTokens.font(size: 11, color: StrataTokens.dim)),
      ]);
}

class _StrataLogoPainter extends CustomPainter {
  const _StrataLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (final double offset in <double>[0, 12]) {
      canvas.drawPath(
          Path()
            ..moveTo(offset, 20)
            ..lineTo(offset + 10, 2)
            ..lineTo(offset + 18, 2)
            ..lineTo(offset + 8, 20)
            ..close(),
          paint);
    }
  }

  @override
  bool shouldRepaint(_StrataLogoPainter oldDelegate) => color != oldDelegate.color;
}

class StrataResultsPanel extends StatelessWidget {
  const StrataResultsPanel({super.key, required this.enabled, required this.resultCount, required this.child});
  final bool enabled;
  final int resultCount;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Container(
      decoration: BoxDecoration(
              color: StrataTokens.panel,
              border: Border.all(color: StrataTokens.border),
              borderRadius: BorderRadius.circular(8))
          .withLauncherCorners(),
      child: Column(children: <Widget>[
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(children: <Widget>[
              Text('Results  ($resultCount)', style: StrataTokens.font(color: StrataTokens.dim)),
              const Spacer(),
              Text('Best match', style: StrataTokens.font(size: 12, color: StrataTokens.dim)),
            ])),
        Expanded(child: child),
      ]),
    );
  }
}
