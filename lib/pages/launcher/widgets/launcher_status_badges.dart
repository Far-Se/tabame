part of '../../launcher.dart';

class _LauncherStatusBadges extends StatefulWidget {
  const _LauncherStatusBadges({
    required this.accent,
    required this.onSurface,
    required this.onOpenTimers,
    required this.onOpenReminders,
  });

  final Color accent;
  final Color onSurface;
  final VoidCallback onOpenTimers;
  final VoidCallback onOpenReminders;

  @override
  State<_LauncherStatusBadges> createState() => _LauncherStatusBadgesState();
}

class _LauncherStatusBadgesState extends State<_LauncherStatusBadges> {
  Timer? _ticker;
  String _timerLabel = '';

  @override
  void initState() {
    super.initState();
    Boxes().loadLatestQuickTimers();
    _updateTimerLabel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateTimerLabel();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _updateTimerLabel() {
    if (Boxes.quickTimers.isEmpty) {
      if (_timerLabel.isNotEmpty) setState(() => _timerLabel = '');
      return;
    }
    Duration diff = Boxes.quickTimers[0].endTime.difference(DateTime.now());
    for (final QuickTimer t in Boxes.quickTimers) {
      final Duration d = t.endTime.difference(DateTime.now());
      if (d < diff) diff = d;
    }
    // A timer that has just elapsed yields a negative remaining duration until
    // it is cleared; clamp so the badge never shows "-5s" / negative minutes.
    if (diff.isNegative) diff = Duration.zero;
    final String label = diff.inMinutes != 0
        ? "${diff.inSeconds % 60 < 30 ? diff.inMinutes % 60 : (diff.inMinutes % 60) + 1}m"
        : "${diff.inSeconds % 60}s";
    if (label != _timerLabel) setState(() => _timerLabel = label);
  }

  @override
  Widget build(BuildContext context) {
    final bool hasTimers = Boxes.quickTimers.isNotEmpty;
    final bool hasReminders = user.persistentReminders.isNotEmpty;
    if (!hasTimers && !hasReminders) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasTimers)
            _StatusChip(
              accent: Design.accent,
              icon: Icons.timer_outlined,
              label: _timerLabel,
              tooltip: 'Timers (Alt+T)',
              onTap: widget.onOpenTimers,
            ),
          if (hasTimers && hasReminders) const SizedBox(width: 6),
          if (hasReminders)
            _StatusChip(
              accent: Design.accent,
              icon: Icons.warning_rounded,
              label: '${user.persistentReminders.length}',
              tooltip: 'Reminders (Alt+R)',
              onTap: widget.onOpenReminders,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatefulWidget {
  const _StatusChip({
    required this.accent,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final Color accent;
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_StatusChip> createState() => _StatusChipState();
}

class _StatusChipState extends State<_StatusChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _hovered ? widget.accent.withAlpha(45) : widget.accent.withAlpha(22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: widget.accent.withAlpha(_hovered ? 100 : 50),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(widget.icon, size: 10, color: widget.accent.withAlpha(210)),
                if (widget.label.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 3),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: widget.accent.withAlpha(210),
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsHintBadge extends StatefulWidget {
  const _ActionsHintBadge({
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  State<_ActionsHintBadge> createState() => _ActionsHintBadgeState();
}

class _ActionsHintBadgeState extends State<_ActionsHintBadge> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered ? widget.accent.withAlpha(40) : widget.accent.withAlpha(18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.accent.withAlpha(_hovered ? 80 : 40),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.bolt_rounded,
                size: 10,
                color: widget.accent.withAlpha(200),
              ),
              const SizedBox(width: 3),
              Text(
                'Ctrl+K',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: widget.accent.withAlpha(200),
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
