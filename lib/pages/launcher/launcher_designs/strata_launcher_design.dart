part of '../launcher_design_builder.dart';

class StrataSearchBar extends StatelessWidget {
  const StrataSearchBar({super.key, required this.dragHandle, required this.textField, required this.trailingBadge, required this.isSearching});
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 16, 16, 16),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: <Color>[Color(0xFF19242C), Color(0xFF141E25)]),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: StrataTokens.accent.withAlpha(180), width: 2),
    ),
    child: Row(children: <Widget>[
      dragHandle, const SizedBox(width: 20), Expanded(child: textField),
      if (trailingBadge != null) trailingBadge!,
      if (isSearching) const Padding(padding: EdgeInsets.only(left: 12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: StrataTokens.accent))),
    ]),
  );
}

class StrataLauncherFrame extends StatelessWidget {
  const StrataLauncherFrame({super.key, required this.surface, required this.accent, required this.onSurface, required this.resultCount, required this.child});
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;

  Widget _control(String tooltip, IconData icon, VoidCallback action) => IconButton(
    tooltip: tooltip, onPressed: action, icon: Icon(icon, size: 17, color: StrataTokens.dim),
  );

  @override
  Widget build(BuildContext context) => LauncherTheme(
    data: const LauncherThemeData(design: LauncherDesign.strata),
    child: Container(
      decoration: LauncherDesign.strata.outerDecoration(surface: surface, accent: accent),
      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
        Container(height: 48, decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: StrataTokens.border))),
          child: Row(children: <Widget>[
            Expanded(child: DragToMoveArea(child: Padding(padding: const EdgeInsets.only(left: 22), child: Row(children: <Widget>[
              const CustomPaint(size: Size(28, 24), painter: _StrataLogoPainter()),
              const SizedBox(width: 22), Text('Strata', style: StrataTokens.font(size: 16).copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 16), Container(width: 1, height: 20, color: StrataTokens.border),
              const SizedBox(width: 16), Flexible(child: Text('Find. Open. Do more.', maxLines: 1, overflow: TextOverflow.ellipsis, style: StrataTokens.font(size: 12, color: StrataTokens.dim))),
            ])))),
            _control('Minimize', Icons.remove, () { windowManager.minimize(); }),
            _control('Maximize / Restore', Icons.crop_square_rounded, () async { if (await windowManager.isMaximized()) { await windowManager.unmaximize(); } else { await windowManager.maximize(); } }),
            _control('Hide launcher', Icons.close, () { windowManager.hide(); }),
            const SizedBox(width: 8),
          ])),
        Flexible(fit: FlexFit.loose, child: child),
        Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: StrataTokens.border))),
          child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) => Row(children: <Widget>[
            _hint('? ?', 'Navigate'), const SizedBox(width: 18), _hint('?', 'Open'),
            if (constraints.maxWidth > 520) ...<Widget>[const SizedBox(width: 18), _hint('Ctrl K', 'Actions')],
            const Spacer(), const Icon(Icons.circle, size: 8, color: Color(0xFF80F454)), const SizedBox(width: 8),
            Text('$resultCount results', style: StrataTokens.font(size: 11, color: StrataTokens.dim)),
          ]))),
      ])),
    ),
  );

  Widget _hint(String key, String label) => Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
    Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF202D37), border: Border.all(color: const Color(0xFF354653)), borderRadius: BorderRadius.circular(4)), child: Text(key, style: StrataTokens.font(size: 11, color: StrataTokens.dim))),
    const SizedBox(width: 9), Text(label, style: StrataTokens.font(size: 11, color: StrataTokens.dim)),
  ]);
}

class _StrataLogoPainter extends CustomPainter {
  const _StrataLogoPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = StrataTokens.accent;
    for (final double offset in <double>[0, 12]) {
      canvas.drawPath(Path()..moveTo(offset, 20)..lineTo(offset + 10, 2)..lineTo(offset + 18, 2)..lineTo(offset + 8, 20)..close(), paint);
    }
  }
  @override
  bool shouldRepaint(_StrataLogoPainter oldDelegate) => false;
}
