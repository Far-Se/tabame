import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../services/claude_usage_service.dart';
import '../../../services/codex_usage_service.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class AiUsageButton extends StatelessWidget {
  const AiUsageButton({super.key});

  @override
  Widget build(BuildContext context) {
    // The QuickMenu tree is built at startup, so wiring the reset-alarm hook
    // here guarantees a restored (post-restart) type-3 timer can beep.
    ClaudeUsageAlarm.ensureRegistered();
    return ModalButton(
      actionName: 'AI Usage Stats',
      icon: const Icon(Icons.bar_chart_rounded),
      child: () => const ClaudeUsagePanel(),
    );
  }
}

/// Owns the "alert when the 5-hour window resets" alarm. The alarm is a
/// persistent quick timer (type 3) so it survives app restarts; when it fires,
/// [Boxes] opens the usage panel and calls back into [_playBeep] here.
class ClaudeUsageAlarm {
  /// QuickTimer type dedicated to the Claude 5-hour reset alarm.
  static const int timerType = 3;

  static const String _timerName = 'Claude 5-hour window reset';
  static bool _registered = false;

  /// Whether a reset alarm is currently armed.
  static bool get isArmed => Boxes.quickTimers.any((QuickTimer timer) => timer.type == timerType);

  ClaudeUsageAlarm._();

  /// Arm an alarm that fires at [resetIso] (an ISO-8601 timestamp). Returns
  /// false if the time is unparseable or already in the past.
  static bool arm(String resetIso) {
    final DateTime target;
    try {
      target = DateTime.parse(resetIso).toLocal();
    } catch (_) {
      return false;
    }
    if (!target.isAfter(DateTime.now())) return false;
    cancel();
    Boxes().addQuickTimerAt(_timerName, target, timerType);
    return true;
  }

  /// Disarm any pending reset alarm.
  static void cancel() {
    Boxes.quickTimers.removeWhere((QuickTimer timer) {
      if (timer.type == timerType) {
        timer.timer?.cancel();
        return true;
      }
      return false;
    });
    Boxes.saveQuickTimers();
  }

  /// Point the type-3 quick-timer fire hook at the beep. Idempotent.
  static void ensureRegistered() {
    if (_registered) return;
    _registered = true;
    Boxes.onClaudeResetTimer = _playBeep;
  }

  static Future<void> _playBeep() async {
    final AudioPlayer player = AudioPlayer();
    await player.setAsset('resources/beep.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await player.seek(Duration.zero);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.dispose();
  }
}

class ClaudeUsagePanel extends StatefulWidget {
  const ClaudeUsagePanel({super.key});

  @override
  State<ClaudeUsagePanel> createState() => _ClaudeUsagePanelState();
}

class _ClaudeUsagePanelState extends State<ClaudeUsagePanel> {
  static const Duration _claudeStaleAfter = Duration(days: 2);

  ClaudeUsageRecord? _claudeRecord;
  CodexUsageRecord? _codexRecord;
  bool _claudeLoading = true;
  bool _codexLoading = true;
  bool _refreshing = false;

  DateTime? get _lastUpdatedAt {
    // Claude can restore its disk cache before Codex finishes loading on a
    // cold start. Do not present that older timestamp as the combined status
    // while the other provider is still expected to report.
    if ((_claudeRecord == null && _claudeLoading) || (_codexRecord == null && _codexLoading)) return null;

    final List<DateTime> dates = <DateTime>[
      if (_claudeRecord != null) _claudeRecord!.fetchedAt,
      if (_codexRecord != null) _codexRecord!.fetchedAt,
    ];
    if (dates.isEmpty) return null;
    return dates.reduce((DateTime first, DateTime second) => first.isAfter(second) ? first : second);
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? lastUpdatedAt = _lastUpdatedAt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        PanelHeader(
          icon: Icons.bar_chart_rounded,
          title: 'AI Usage Stats',
          buttonPressed: _refreshUsage,
          buttonIcon: _refreshing ? Icons.sync_rounded : Icons.refresh_rounded,
          buttonTooltip: 'Refresh usage',
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: C.start,
                  children: <Widget>[
                    _buildClaudeSection(),
                    const SizedBox(height: 10),
                    _buildCodexSection(),
                    if (lastUpdatedAt != null) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        'Updated ${_timeAgo(lastUpdatedAt)}',
                        style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150)),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      'Claude Code API · Codex CLI/cache',
                      style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(125)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    ClaudeUsageService.instance.removeListener(_onClaudeUsage);
    CodexUsageService.instance.removeListener(_onCodexUsage);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ClaudeUsageAlarm.ensureRegistered();

    _claudeRecord = ClaudeUsageService.instance.latest;
    _codexRecord = CodexUsageService.instance.latest;
    _claudeLoading = _claudeRecord == null;
    _codexLoading = _codexRecord == null;

    ClaudeUsageService.instance.addListener(_onClaudeUsage);
    CodexUsageService.instance.addListener(_onCodexUsage);
  }

  Widget _buildClaudeSection() {
    final ClaudeUsageRecord? record = _claudeRecord;
    if (record != null) {
      final Duration age = DateTime.now().difference(record.fetchedAt);
      if (age > _claudeStaleAfter) return _buildClaudeStaleMessage(age.inDays);
    }

    return Column(
      crossAxisAlignment: C.start,
      children: <Widget>[
        _buildSectionLabel(title: 'Claude Code', icon: Icons.auto_awesome_rounded, badges: const <String>['USED']),
        const SizedBox(height: 6),
        if (record == null)
          _buildUnavailableCard(
            loading: _claudeLoading,
            icon: Icons.auto_awesome_rounded,
            title: _claudeLoading ? 'Fetching Claude Code usage' : 'Claude Code data unavailable',
            message: _claudeLoading
                ? 'Checking the local Claude Code sign-in.'
                : 'Sign in to Claude Code, then refresh this panel.',
          )
        else ...<Widget>[
          _UsageCard(
            label: '5h',
            value: record.fiveHour,
            resetAt: record.fiveResetAt,
            direction: _UsageDirection.used,
          ),
          if (record.fiveResetAt != null) ...<Widget>[
            const SizedBox(height: 6),
            _ResetAlarmButton(
              armed: ClaudeUsageAlarm.isArmed,
              onTap: () => _toggleAlarm(record.fiveResetAt!),
            ),
          ],
          const SizedBox(height: 8),
          _UsageCard(
            label: 'Weekly',
            value: record.sevenDay,
            resetAt: record.sevenResetAt,
            direction: _UsageDirection.used,
          ),
        ],
      ],
    );
  }

  Widget _buildClaudeStaleMessage(int daysAgo) {
    return Text(
      'Claude: Stale data from $daysAgo days ago',
      style: TextStyle(
        fontSize: Design.baseFontSize + 1,
        fontWeight: FontWeight.w600,
        color: Design.text.withAlpha(175),
      ),
    );
  }

  Widget _buildCodexSection() {
    final CodexUsageRecord? record = _codexRecord;
    final List<String> badges = <String>['REMAINING'];
    if (record != null && record.plan.isNotEmpty) badges.insert(0, record.plan);

    return Column(
      crossAxisAlignment: C.start,
      children: <Widget>[
        _buildSectionLabel(title: 'Codex', icon: Icons.code_rounded, badges: badges),
        const SizedBox(height: 6),
        if (record == null)
          _buildUnavailableCard(
            loading: _codexLoading,
            icon: Icons.code_rounded,
            title: _codexLoading ? 'Fetching Codex usage' : 'Codex data unavailable',
            message: _codexLoading
                ? 'Reading codex-cli-usage or the local cache.'
                : 'Install codex-cli-usage or run it once, then refresh.',
          )
        else ...<Widget>[
          if (record.fiveHourRemaining != null ||
              record.fiveHourResetAt != null ||
              record.fiveHourResetDateTime != null) ...<Widget>[
            _UsageCard(
              label: '5h',
              value: record.fiveHourRemaining,
              resetAt: record.fiveHourResetAt,
              resetDateTime: record.fiveHourResetDateTime,
              direction: _UsageDirection.remaining,
            ),
            if (record.weeklyRemaining != null || record.weeklyResetAt != null || record.weeklyResetDateTime != null)
              const SizedBox(height: 8),
          ],
          if (record.weeklyRemaining != null || record.weeklyResetAt != null || record.weeklyResetDateTime != null)
            _UsageCard(
              label: 'Weekly',
              value: record.weeklyRemaining,
              resetAt: record.weeklyResetAt,
              resetDateTime: record.weeklyResetDateTime,
              direction: _UsageDirection.remaining,
            ),
        ],
      ],
    );
  }

  Widget _buildMetaChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Design.baseFontSize - 0.5,
          fontWeight: FontWeight.w700,
          color: Design.accent,
        ),
      ),
    );
  }

  Widget _buildSectionLabel({required String title, required IconData icon, required List<String> badges}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        ...badges.map(_buildMetaChip),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildUnavailableCard({
    required bool loading,
    required IconData icon,
    required String title,
    required String message,
  }) {
    final Color tint = loading ? Design.accent : Design.text;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(loading ? Icons.sync_rounded : icon, size: 16, color: tint),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(150)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onClaudeUsage(ClaudeUsageRecord? record) {
    if (!mounted) return;
    setState(() {
      _claudeRecord = record;
      _claudeLoading = false;
    });
  }

  void _onCodexUsage(CodexUsageRecord? record) {
    if (!mounted) return;
    setState(() {
      _codexRecord = record;
      _codexLoading = false;
    });
  }

  Future<void> _refreshUsage() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (_claudeRecord == null) _claudeLoading = true;
      if (_codexRecord == null) _codexLoading = true;
    });

    try {
      await Future.wait<void>(<Future<void>>[
        ClaudeUsageService.instance.refresh(),
        CodexUsageService.instance.refresh(force: true),
      ]);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  String _timeAgo(DateTime dateTime) {
    final Duration diff = DateTime.now().difference(dateTime);
    if (diff.isNegative || diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inDays > 2) return 'days ago';
    return '${diff.inHours}h ago';
  }

  void _toggleAlarm(String resetAt) {
    if (ClaudeUsageAlarm.isArmed) {
      ClaudeUsageAlarm.cancel();
    } else {
      ClaudeUsageAlarm.arm(resetAt);
    }
    if (mounted) setState(() {});
  }
}

class _ResetAlarmButton extends StatelessWidget {
  final bool armed;

  final VoidCallback onTap;
  const _ResetAlarmButton({required this.armed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final Color tint = armed ? Design.accent : Design.text;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: tint.withAlpha(armed ? 22 : 8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tint.withAlpha(armed ? 90 : 30)),
          ),
          child: Row(
            children: <Widget>[
              Icon(armed ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                  size: 14, color: tint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  armed ? 'Reset alert armed — tap to cancel' : 'Alert when 5h usage resets',
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w600,
                    color: armed ? tint : Design.text.withAlpha(200),
                  ),
                ),
              ),
              if (armed) Icon(Icons.close_rounded, size: 13, color: tint.withAlpha(180)),
            ],
          ),
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  final String label;

  final double? value;
  final String? resetAt;
  final DateTime? resetDateTime;
  final _UsageDirection direction;
  const _UsageCard({
    required this.label,
    required this.value,
    required this.resetAt,
    this.resetDateTime,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final double percent = (value ?? 0).clamp(0.0, 100.0).toDouble();
    final Color barColor = _barColor(percent);
    final String valueLabel = value == null ? '--' : '${_formatPercent(percent)}%';
    final String modeLabel = direction == _UsageDirection.used ? 'used' : 'remaining';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2.5,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: barColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w700,
                    color: barColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                modeLabel,
                style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(145)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value == null ? null : percent / 100,
              minHeight: 5,
              backgroundColor: Design.text.withAlpha(16),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          if (_resetLabel(resetAt, resetDateTime) case final String resetLabel) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              resetLabel,
              style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(150)),
            ),
          ],
        ],
      ),
    );
  }

  Color _barColor(double percent) {
    final double pressure = direction == _UsageDirection.used ? percent : 100 - percent;
    if (pressure >= 80) return Colors.redAccent;
    if (pressure >= 50) return Colors.orange;
    return Colors.greenAccent.shade400;
  }

  String _formatPercent(double percent) {
    return percent == percent.roundToDouble() ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1);
  }

  String? _resetLabel(String? value, DateTime? resetDateTime) {
    if ((value == null || value.isEmpty || value == '--') && resetDateTime == null) return null;

    if (resetDateTime != null) {
      final Duration diff = resetDateTime.difference(DateTime.now());
      if (diff.isNegative) return 'resetting soon';
      final String label = value == null || value.isEmpty || value == '--' ? _formatResetDate(resetDateTime) : value;
      return 'resets $label (in ${_formatTimeUntil(diff)})';
    }

    final String resetValue = value!;
    try {
      final DateTime target = DateTime.parse(resetValue).toLocal();
      final Duration diff = target.difference(DateTime.now());
      final int hour = target.hour % 12 == 0 ? 12 : target.hour % 12;
      final String minute = target.minute.toString().padLeft(2, '0');
      final String time = '$hour:$minute ${target.hour >= 12 ? 'PM' : 'AM'}';

      if (diff.isNegative) return 'resetting soon at $time';
      if (diff.inHours > 0) return 'resets in ${diff.inHours}h ${diff.inMinutes % 60}m at $time';
      return 'resets in ${diff.inMinutes}m at $time';
    } on FormatException {
      final String lower = resetValue.toLowerCase();
      if (lower.startsWith('resets ') || lower.startsWith('reset ') || lower.startsWith('resetting '))
        return resetValue;
      return 'resets $resetValue';
    }
  }

  String _formatResetDate(DateTime dateTime) {
    final DateTime now = DateTime.now();
    if (dateTime.year == now.year && dateTime.month == now.month && dateTime.day == now.day) {
      final int hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
      final String minute = dateTime.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${dateTime.hour >= 12 ? 'PM' : 'AM'}';
    }
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}';
  }

  String _formatTimeUntil(Duration duration) {
    final int totalMinutes = duration.inMinutes;
    if (totalMinutes < 1) return 'less than a minute';

    final int days = totalMinutes ~/ Duration.minutesPerDay;
    final int hours = (totalMinutes % Duration.minutesPerDay) ~/ Duration.minutesPerHour;
    final int minutes = totalMinutes % Duration.minutesPerHour;
    final List<String> parts = <String>[];
    if (days > 0) parts.add('$days ${days == 1 ? 'day' : 'days'}');
    if (hours > 0 && (days > 0 || parts.isEmpty)) parts.add('$hours ${hours == 1 ? 'hour' : 'hours'}');
    if (parts.isEmpty || (days == 0 && hours == 0)) {
      parts.add('$minutes ${minutes == 1 ? 'minute' : 'minutes'}');
    }
    return parts.length == 2 ? '${parts[0]} and ${parts[1]}' : parts.first;
  }
}

enum _UsageDirection { used, remaining }
