import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../services/ai_coding_usage_service.dart';
import '../../../services/claude_usage_service.dart';
import '../../../services/codex_usage_service.dart';
import '../../../services/provider_usage_service.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/quick_actions_item.dart';

class ClaudeUsageButton extends StatelessWidget {
  const ClaudeUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'claude');
}

class CodexUsageButton extends StatelessWidget {
  const CodexUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'codex');
}

class AntigravityUsageButton extends StatelessWidget {
  const AntigravityUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'antigravity');
}

class CursorUsageButton extends StatelessWidget {
  const CursorUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'cursor');
}

class GrokUsageButton extends StatelessWidget {
  const GrokUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'grok');
}

class OpenCodeUsageButton extends StatelessWidget {
  const OpenCodeUsageButton({super.key});

  @override
  Widget build(BuildContext context) => const _UsageButton(agent: 'opencode');
}

class _UsageButton extends StatefulWidget {
  const _UsageButton({required this.agent});

  final String agent;

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
    if (_UsageSnapshot(widget.agent).depleted) setState(() {});
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    _countdownTimer?.cancel();
    if (visible) {
      checkTimer();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) => checkTimer());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiCodingUsageService.instance,
      builder: (BuildContext context, Widget? child) {
        final _UsageSnapshot usage = _UsageSnapshot(widget.agent);
        final _Window? primary = usage.primary;
        return Tooltip(
          key: _tooltipKey,
          ignorePointer: false,
          enableTapToDismiss: false,
          preferBelow: !user.quickMenuBarLayout.quickActionsAtBottom,
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
              builder: (BuildContext context, Widget? child) => _UsageDetails(agent: widget.agent),
            ),
          ),
          child: Semantics(
            label: '${usage.name}: ${_percent(primary?.remaining)} remaining'
                '${primary == null ? '' : ' (${primary.label})'}',
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
                          value: usage.loading && usage.fetchedAt == null
                              ? null
                              : (primary?.remaining ?? 0).clamp(0, 100) / 100,
                          strokeWidth: 2,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Design.text.withAlpha(30),
                          color: Design.accent,
                        ),
                      ),
                      Text(
                        usage.depleted ? _resetCountdown(primary!.reset!) : usage.badge,
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
  const _UsageDetails({required this.agent});

  final String agent;

  @override
  Widget build(BuildContext context) {
    final _UsageSnapshot usage = _UsageSnapshot(agent);
    final bool alertEnabled = AiCodingUsageService.instance.resetAlertEnabled(agent);
    final String alertLabel = alertEnabled ? 'Disable recurring reset alerts' : 'Enable recurring reset alerts';
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
                    label: alertLabel,
                    child: CustomTooltip(
                      message: alertLabel,
                      child: IconButton(
                        // A nested Tooltip would dismiss the enclosing usage overlay on hover.
                        onPressed: () => AiCodingUsageService.instance.toggleResetAlert(agent),
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
              if (usage.plan != null && usage.plan!.isNotEmpty) ...<Widget>[
                Text('Plan: ${usage.plan}',
                    style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
                const SizedBox(height: 6),
              ],
              for (final _Window window in usage.windows) ...<Widget>[
                _limit(window),
                const SizedBox(height: 8),
              ],
              Text('Fetched ${_timeAgo(usage.fetchedAt!)}',
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(160))),
            ] else
              Text(usage.loading ? 'Fetching usage…' : usage.emptyHint),
            if (usage.error != null && usage.fetchedAt != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('Showing cached usage. ${usage.error}',
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _limit(_Window window) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(window.label, overflow: TextOverflow.ellipsis)),
            Text('${_percent(window.remaining)} left', style: TextStyle(color: Design.accent)),
          ],
        ),
        const SizedBox(height: 3),
        LinearProgressIndicator(
          value: (window.remaining ?? 0).clamp(0, 100) / 100,
          minHeight: 3,
          color: Design.accent,
          backgroundColor: Design.text.withAlpha(20),
        ),
        if (window.reset != null || window.fallback != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
              window.reset != null
                  ? 'Resets in ${_timeUntil(window.reset!)} at ${_clock(window.reset!)}'
                  : 'Resets ${window.fallback}',
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
        ],
      ],
    );
  }
}

String _percent(double? value) => value == null ? '–' : '${value.clamp(0, 100).round()}%';

String _clock(DateTime date) {
  final DateTime local = date.toLocal();
  final String time = '${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  final DateTime now = DateTime.now();
  if (local.year == now.year && local.month == now.month && local.day == now.day) return time;
  return '$time, ${local.day}/${local.month}';
}

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

  if (remaining.inDays > 0) {
    final int hours = remaining.inHours % 24;
    return hours > 0 ? '${remaining.inDays}d ${hours}h' : '${remaining.inDays}d';
  }

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

class _Window {
  const _Window(this.label, this.remaining, this.reset, [this.fallback]);

  final String label;
  final double? remaining;
  final DateTime? reset;
  final String? fallback;
}

/// Uniform read-only view over the Claude, Codex and generic provider services.
class _UsageSnapshot {
  _UsageSnapshot(this.agent) {
    switch (agent) {
      case 'codex':
        final CodexUsageRecord? codex = CodexUsageService.instance.latest;
        fetchedAt = codex?.fetchedAt;
        plan = codex?.plan;
        error = CodexUsageService.instance.lastError;
        if (codex != null) {
          windows = <_Window>[
            _Window('5-hour limit', codex.fiveHourRemaining, codex.fiveHourResetDateTime, codex.fiveHourResetAt),
            _Window('Weekly limit', codex.weeklyRemaining, codex.weeklyResetDateTime, codex.weeklyResetAt),
          ];
        }
      case 'claude':
        final ClaudeUsageRecord? claude = ClaudeUsageService.instance.latest;
        fetchedAt = claude?.fetchedAt;
        error = ClaudeUsageService.instance.lastError;
        if (claude != null) {
          windows = <_Window>[
            _Window('5-hour limit', 100 - claude.fiveHour, DateTime.tryParse(claude.fiveResetAt ?? '')),
            _Window('Weekly limit', 100 - claude.sevenDay, DateTime.tryParse(claude.sevenResetAt ?? '')),
          ];
        }
      default:
        final ProviderUsageService? service = ProviderUsageService.all[agent];
        final ProviderUsageRecord? record = service?.latest;
        fetchedAt = record?.fetchedAt;
        plan = record?.plan;
        error = service?.lastError;
        windows = <_Window>[
          for (final ProviderUsageWindow window in record?.windows ?? const <ProviderUsageWindow>[])
            _Window(window.label, window.remainingPercent, window.resetAt),
        ];
    }
  }

  final String agent;
  DateTime? fetchedAt;
  String? plan;
  String? error;
  List<_Window> windows = const <_Window>[];

  String get name => AiCodingUsageService.agentName(agent);
  _Window? get primary => windows.isEmpty ? null : windows.first;
  bool get loading => AiCodingUsageService.instance.isLoading(agent);
  bool get depleted => primary?.remaining != null && primary!.remaining! <= 0 && primary!.reset != null;

  String get badge => switch (agent) {
        'codex' => 'C',
        'claude' => 'Cl',
        'antigravity' => 'AG',
        'cursor' => 'Cu',
        'grok' => 'G',
        'opencode' => 'OC',
        _ => agent.substring(0, 1).toUpperCase(),
      };

  String get emptyHint =>
      error ??
      switch (agent) {
        'codex' => 'Sign in to Codex CLI to make usage available.',
        'claude' => 'Sign in to Claude Code to make usage available.',
        _ => 'Sign in to $name to make usage available.',
      };
}
