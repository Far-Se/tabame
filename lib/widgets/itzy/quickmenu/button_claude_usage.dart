import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../../services/claude_usage_service.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class ClaudeUsageButton extends StatelessWidget {
  const ClaudeUsageButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Claude Usage",
      icon: const Icon(Icons.bar_chart_rounded),
      child: () => const ClaudeUsagePanel(),
    );
  }
}

class ClaudeUsagePanel extends StatefulWidget {
  const ClaudeUsagePanel({super.key});

  @override
  State<ClaudeUsagePanel> createState() => _ClaudeUsagePanelState();
}

class _ClaudeUsagePanelState extends State<ClaudeUsagePanel> {
  ClaudeUsageRecord? _record;

  void _onUsage(ClaudeUsageRecord? record) {
    if (mounted) setState(() => _record = record);
  }

  @override
  void initState() {
    super.initState();
    ClaudeUsageService.instance.addListener(_onUsage);
  }

  @override
  void dispose() {
    ClaudeUsageService.instance.removeListener(_onUsage);
    super.dispose();
  }

  String _timeAgo(DateTime dt) {
    final Duration diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes == 1) return '1 min ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final ClaudeUsageRecord? r = _record;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        const PanelHeader(icon: Icons.bar_chart_rounded, title: "Claude Usage"),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: r == null
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Fetching…', style: TextStyle(fontSize: 12)),
                )
              : Column(
                  crossAxisAlignment: C.start,
                  children: <Widget>[
                    _UsageCard(label: '5-hour window', value: r.fiveHour, resetAt: r.fiveResetAt, onSurface: onSurface),
                    const SizedBox(height: 8),
                    _UsageCard(label: '7-day window', value: r.sevenDay, resetAt: r.sevenResetAt, onSurface: onSurface),
                    const SizedBox(height: 8),
                    Text(
                      'Updated ${_timeAgo(r.fetchedAt)}',
                      style: TextStyle(fontSize: Design.baseFontSize, color: onSurface.withAlpha(150)),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.label, required this.value, required this.onSurface, this.resetAt});

  final String label;
  final double value;
  final String? resetAt;
  final Color onSurface;

  Color _barColor() {
    if (value >= 80) return Colors.redAccent;
    if (value >= 50) return Colors.orange;
    return Colors.greenAccent.shade400;
  }

  String _formatTime(DateTime dt) {
    final String h = dt.hour.toString().padLeft(2, '0');
    final String m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _resetLabel(String iso) {
    try {
      final DateTime target = DateTime.parse(iso).toLocal();
      final Duration diff = target.difference(DateTime.now());

      final String timeStr = _formatTime(target);

      if (diff.isNegative) {
        return 'resetting soon at $timeStr';
      }
      if (diff.inHours > 0) {
        return 'resets in ${diff.inHours}h ${diff.inMinutes % 60}m at $timeStr';
      }
      return 'resets in ${diff.inMinutes}m at $timeStr';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color barColor = _barColor();

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w700, color: onSurface),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: barColor.withAlpha(30), borderRadius: BorderRadius.circular(999)),
                child: Text(
                  '${value.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: Design.baseFontSize + 0.5, fontWeight: FontWeight.w700, color: barColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: onSurface.withAlpha(16),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          if (resetAt != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _resetLabel(resetAt!),
              style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: onSurface.withAlpha(150)),
            ),
          ],
        ],
      ),
    );
  }
}
