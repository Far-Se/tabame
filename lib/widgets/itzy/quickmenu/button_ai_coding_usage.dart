import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/settings.dart';
import '../../../services/ai_coding_usage_service.dart';
import '../../../services/claude_usage_service.dart';
import '../../../services/codex_usage_service.dart';
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

class _UsageButton extends StatelessWidget {
  const _UsageButton({required this.codex});

  final bool codex;

  @override
  Widget build(BuildContext context) {
    final GlobalKey<TooltipState> tooltipKey = GlobalKey<TooltipState>();
    return ListenableBuilder(
      listenable: AiCodingUsageService.instance,
      builder: (BuildContext context, Widget? child) {
        final _UsageSnapshot usage = _UsageSnapshot(codex);
        return Tooltip(
          key: tooltipKey,
          preferBelow: !user.quickActionsAtBottom,
          verticalOffset: 14,
          waitDuration: const Duration(milliseconds: 110),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Design.text.withAlpha(24)),
          ),
          richMessage: WidgetSpan(
            child: ListenableBuilder(
              listenable: AiCodingUsageService.instance,
              builder: (BuildContext context, Widget? child) => _UsageDetails(codex: codex),
            ),
          ),
          child: Semantics(
            label: '${usage.name}: ${_percent(usage.five)} remaining in 5 hours',
            button: true,
            child: QuickActionItem(
              message: '',
              onTap: () => tooltipKey.currentState?.ensureTooltipVisible(),
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
                        codex ? 'C' : 'Cl',
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
    return SizedBox(
      width: 250,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: Design.baseFontSize + 1, height: 1.4, color: Design.text),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${usage.name} usage', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (usage.fetchedAt != null) ...<Widget>[
              _limit('5-hour limit', usage.five, usage.fiveReset, usage.fiveFallback),
              const SizedBox(height: 8),
              _limit('Weekly limit', usage.week, usage.weekReset, usage.weekFallback),
              const SizedBox(height: 8),
              Text('Fetched ${_date(usage.fetchedAt!)}',
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
        Text(reset != null ? 'Resets ${_date(reset)}' : 'Resets ${fallback ?? 'unavailable'}',
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(175))),
      ],
    );
  }
}

String _percent(double? value) => value == null ? '—' : '${value.clamp(0, 100).round()}%';

String _date(DateTime date) => DateFormat('MMM d, yyyy · HH:mm:ss').format(date.toLocal());

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
