import 'package:flutter/material.dart';

import '../../widgets/custom_tooltip.dart';
import 'trktivity_models.dart';

class TrktivityTimeline extends StatelessWidget {
  final List<MapEntry<String, List<TTrack>>> wTimeTrackList;
  final List<MapEntry<String, List<TTrack>>> tTimeTrackList;

  const TrktivityTimeline({
    super.key,
    required this.wTimeTrackList,
    required this.tTimeTrackList,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 20),
            _buildTimelineSection(
              context,
              title: "Timeline by App",
              icon: Icons.app_settings_alt_rounded,
              trackList: wTimeTrackList,
              totalWidth: constraints.maxWidth,
            ),
            if (tTimeTrackList.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              _buildTimelineSection(
                context,
                title: "Timeline by Title",
                icon: Icons.title_rounded,
                trackList: tTimeTrackList,
                totalWidth: constraints.maxWidth,
              ),
            ],
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildTimelineSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<MapEntry<String, List<TTrack>>> trackList,
    required double totalWidth,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        // Time Scale Header
        _buildTimeScale(context, totalWidth),
        // Timeline Content
        SizedBox(
          height: 300,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: List<Widget>.generate(
                trackList.length,
                (int index) => _buildTimelineRow(context, trackList[index], totalWidth),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeScale(BuildContext context, double totalWidth) {
    return Container(
      height: 24,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: List<Widget>.generate(9, (int index) {
          final int hour = index * 3; // 0, 3, 6, 9, 12, 15, 18, 21, 24
          final double left = (hour / 24) * totalWidth;
          final String label = hour == 0
              ? "12 AM"
              : hour == 12
                  ? "12 PM"
                  : hour > 12
                      ? "${hour - 12} PM"
                      : "$hour AM";

          return Positioned(
            left: left - (index == 0 ? 0 : 20),
            top: 4,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTimelineRow(BuildContext context, MapEntry<String, List<TTrack>> entry, double totalWidth) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color rowColor = _getColorFromHash(entry.key, colorScheme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            entry.key,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(
          height: 14,
          width: totalWidth,
          child: Stack(
            children: <Widget>[
              // Subtle background grid lines
              ...List<Widget>.generate(9, (int i) {
                final double left = (i * 3 / 24) * totalWidth;
                return Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.2)),
                );
              }),
              // Timeline pulses
              ...List<Widget>.generate(entry.value.length, (int i) {
                final TTrack track = entry.value[i];
                final DateTime startDate = DateTime.fromMillisecondsSinceEpoch(track.from);
                final DateTime endDate = DateTime.fromMillisecondsSinceEpoch(track.to);

                final int startSeconds = startDate.hour * 3600 + startDate.minute * 60 + startDate.second;
                final int endSeconds = endDate.hour * 3600 + endDate.minute * 60 + endDate.second;
                const int secondsInDay = 86400;

                final double startP = startSeconds / secondsInDay;
                final double widthP = (endSeconds - startSeconds) / secondsInDay;

                return Positioned(
                  left: startP * totalWidth,
                  width: (widthP * totalWidth).clamp(2.0, totalWidth),
                  child: CustomTooltip(
                    message: "${entry.key}\n${_formatTime(startDate)} - ${_formatTime(endDate)}",
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: rowColor.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final String h = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString();
    final String m = dt.minute.toString().padLeft(2, '0');
    final String p = dt.hour >= 12 ? 'PM' : 'AM';
    return "$h:$m $p";
  }

  Color _getColorFromHash(String text, ColorScheme colorScheme) {
    if (text.toLowerCase() == "idle") return Colors.grey;
    final int hash = text.hashCode;
    final List<Color> colors = <Color>[
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      Colors.blue,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.indigo,
      Colors.cyan,
      Colors.deepOrange,
    ];
    return colors[hash.abs() % colors.length];
  }
}
