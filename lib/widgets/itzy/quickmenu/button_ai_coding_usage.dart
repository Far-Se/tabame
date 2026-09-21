import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../services/ai_coding_usage_service.dart';
import '../../../services/claude_usage_service.dart';
import '../../../services/codex_usage_service.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/quick_actions_item.dart';

class ClaudeUsageButton extends StatelessWidget {
  const ClaudeUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(codex: false);
}

class CodexUsageButton extends StatelessWidget {
  const CodexUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(codex: true);
}

class _UsageButton extends StatefulWidget {
  const _UsageButton({required this.codex});

  final bool codex;

  @override
  State<_UsageButton> createState() => _UsageButtonState();
}

class _UsageButtonState extends State<_UsageButton> with QuickMenuTriggers {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  void checkTimer() {
    if (!mounted) return;
    final _UsageSnapshot usage = _UsageSnapshot(widget.codex);
    if (usage.five != null && usage.five! <= 0 && usage.fiveReset != null) setState(() {});
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (visible) {
      checkTimer();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => checkTimer());
    } else {
      _countdownTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiCodingUsageService.instance,
      builder: (BuildContext context, Widget? child) {
        final _UsageSnapshot usage = _UsageSnapshot(widget.codex);
        return Tooltip(
          key: _tooltipKey,
          ignorePointer: false,
          enableTapToDismiss: false,
          preferBelow: !user.quickActionsAtBottom,
          verticalOffset: 14,
          waitDuration: const Duration(milliseconds: 110),
          exitDuration: const Duration(milliseconds: 500),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Design.text.withAlpha(24)),
          ),
          richMessage: WidgetSpan(
            child: ListenableBuilder(
              listenable: AiCodingUsageService.instance,
              builder: (BuildContext context, Widget? child) => _UsageDetails(codex: widget.codex),
            ),
          ),
          child: Semantics(
            label: '${usage.name}: ${_percent(usage.five)} remaining in 5 hours',
            button: true,
            child: QuickActionItem(
              message: '',
              onTap: () => _tooltipKey.currentState?.ensureTooltipVisible(),
              icon: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Positioned.fill(
                        child: CircularProgressIndicator(
                          value:
                              usage.loading && usage.fetchedAt == null ? null : (usage.five ?? 0).clamp(0, 100) / 100,
                          strokeWidth: 2,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Design.text.withAlpha(30),
                          color: Design.accent,
                        ),
                      ),
                      Text(
                        usage.five != null && usage.five! <= 0 && usage.fiveReset != null
                            ? _resetCountdown(usage.fiveReset!)
                            : widget.codex
                                ? 'C'
                                : 'Cl',
                        style: TextStyle(fontSize: Design.baseFontSize - 3, color: Design.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UsageDetails extends StatelessWidget {
  const _UsageDetails({required this.codex});

  final bool codex;

  @override
  Widget build(BuildContext context) {
    final _UsageSnapshot usage = _UsageSnapshot(codex);
    final bool alertEnabled = AiCodingUsageService.instance.resetAlertEnabled(codex);
    return SizedBox(
      width: 250,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: Design.baseFontSize + 1, height: 1.4, color: Design.text),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('${usage.name} usage', style: const TextStyle(fontWeight: FontWeight.w600))),
                Material(
                  type: MaterialType.transparency,
                  child: Semantics(
                    toggled: alertEnabled,
                    label:
                        alertEnabled ? 'Disable recurring 5-hour reset alerts' : 'Enable recurring 5-hour reset alerts',
                    child: CustomTooltip(
                      message: alertEnabled
                          ? 'Disable recurring 5-hour reset alerts'
                          : 'Enable recurring 5-hour reset alerts',
                      child: IconButton(
                        // A nested Tooltip would dismiss the enclosing usage overlay on hover.
                        onPressed: () => AiCodingUsageService.instance.toggleResetAlert(codex),
                        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                        padding: EdgeInsets.zero,
                        iconSize: 16,
                        color: alertEnabled ? Design.accent : Design.text.withAlpha(175),
                        icon:
                            Icon(alertEnabled ? Icons.notifications_active_outlined : Icons.notifications_none_rounded),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (usage.fetchedAt != null) ...<Widget>[
              _limit('5-hour limit', usage.five, usage.fiveReset, usage.fiveFallback),
              const SizedBox(height: 8),
              _limit('Weekly limit', usage.week, usage.weekReset, usage.weekFallback),
              const SizedBox(height: 8),
              Text('Fetched ${_timeAgo(usage.fetchedAt!)}',
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(160))),
            ] else
              Text(usage.loading
                  ? 'Fetching usage…'
                  : codex
                      ? 'Install or run codex-cli-usage to make usage available.'
                      : 'Sign in to Claude Code to make usage available.'),
            if (usage.error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('${usage.fetchedAt == null ? '' : 'Showing cached usage. '}${usage.error}',
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _limit(String label, double? remaining, DateTime? reset, String? fallback) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(label)),
            Text('${_percent(remaining)} left', style: TextStyle(color: Design.accent)),
          ],
        ),
        const SizedBox(height: 3),
        LinearProgressIndicator(
          value: (remaining ?? 0).clamp(0, 100) / 100,
          minHeight: 3,
          color: Design.accent,
          backgroundColor: Design.text.withAlpha(20),
        ),
        const SizedBox(height: 3),
        Text(
            reset != null
                ? 'Resets in ${_timeUntil(reset)} at ${reset.hour}:${reset.minute}'
                : 'Resets ${fallback ?? 'unavailable'}',
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
      ],
    );
  }
}

String _percent(double? value) => value == null ? '—' : '${value.clamp(0, 100).round()}%';

String _timeAgo(DateTime date) {
  final Duration elapsed = DateTime.now().difference(date);
  if (elapsed.inMinutes < 1) return 'now';
  if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
  if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
  return '${elapsed.inMinutes}m ago';
}

String _timeUntil(DateTime reset) {
  final Duration remaining = reset.difference(DateTime.now());

  if (remaining.isNegative || remaining == Duration.zero) return '0m';

  if (remaining.inDays > 0) return '${remaining.inDays}d';

  if (remaining.inHours > 0) {
    final int hours = remaining.inHours;
    final int minutes = remaining.inMinutes % 60;

    return minutes > 0 ? '${hours}h${minutes}m' : '${hours}h';
  }

  return '${remaining.inMinutes.clamp(1, 59)}m';
}

String _resetCountdown(DateTime reset) {
  final Duration remaining = reset.difference(DateTime.now());
  if (remaining.isNegative || remaining == Duration.zero) return '0s';

  final int totalSeconds = (remaining.inMilliseconds / Duration.millisecondsPerSecond).ceil();
  if (totalSeconds >= Duration.secondsPerHour) return '${totalSeconds ~/ Duration.secondsPerHour}h';
  if (totalSeconds >= Duration.secondsPerMinute) return '${totalSeconds ~/ Duration.secondsPerMinute}m';
  return '${totalSeconds}s';
}

class _UsageSnapshot {
  _UsageSnapshot(this.codex);

  final bool codex;
  final CodexUsageRecord? _codex = CodexUsageService.instance.latest;
  final ClaudeUsageRecord? _claude = ClaudeUsageService.instance.latest;

  String get name => codex ? 'Codex' : 'Claude';
  DateTime? get fetchedAt => codex ? _codex?.fetchedAt : _claude?.fetchedAt;
  double? get five => codex ? _codex?.fiveHourRemaining : (_claude == null ? null : 100 - _claude.fiveHour);
  double? get week => codex ? _codex?.weeklyRemaining : (_claude == null ? null : 100 - _claude.sevenDay);
  DateTime? get fiveReset => codex ? _codex?.fiveHourResetDateTime : DateTime.tryParse(_claude?.fiveResetAt ?? '');
  DateTime? get weekReset => codex ? _codex?.weeklyResetDateTime : DateTime.tryParse(_claude?.sevenResetAt ?? '');
  String? get fiveFallback => codex ? _codex?.fiveHourResetAt : null;
  String? get weekFallback => codex ? _codex?.weeklyResetAt : null;
  bool get loading => codex ? AiCodingUsageService.instance.codexLoading : AiCodingUsageService.instance.claudeLoading;
  String? get error => codex ? CodexUsageService.instance.lastError : ClaudeUsageService.instance.lastError;
}
