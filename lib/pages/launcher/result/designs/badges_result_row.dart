part of '../result_row.dart';

class LauncherKindBadge extends StatelessWidget {
  const LauncherKindBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (user.launcherDesign == LauncherDesign.phosphor)
      return Text('[$label]', style: PhosphorTokens.font(size: 11, color: PhosphorTokens.dim));
    if (user.launcherDesign == LauncherDesign.retro)
      return Text(label.toUpperCase(), style: RetroTokens.label(size: 7, color: RetroTokens.cyan));
    if (user.launcherDesign == LauncherDesign.tui) return Text('[$label]');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(60),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ).withLauncherCorners(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: accent.withAlpha(180)),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: accent.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }
}
