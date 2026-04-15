import 'package:flutter/material.dart';
import '../../../models/settings.dart';
import '../../widgets/mouse_scroll_widget.dart';
import 'trktivity_models.dart';

class TrktivityFocusTables extends StatelessWidget {
  final Map<String, MTrack> wTrack;
  final List<MapEntry<String, MTrack>> wTrackList;
  final Map<String, MTrack> tTrack;
  final List<MapEntry<String, MTrack>> tTrackList;

  const TrktivityFocusTables({
    super.key,
    required this.wTrack,
    required this.wTrackList,
    required this.tTrack,
    required this.tTrackList,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Applications Card
          Expanded(
            child: _buildFocusCard(
              context,
              title: "Applications",
              icon: Icons.apps_rounded,
              trackList: wTrackList,
              totalTime: wTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "idle.exe" ? e.value.time : 0)),
              totalKeys: wTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "idle.exe" ? e.value.keyboard : 0)),
              totalMouse: wTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "idle.exe" ? e.value.mouse : 0)),
              idleKey: "idle.exe",
            ),
          ),
          const SizedBox(width: 16),
          // Window Titles Card
          if (tTrackList.length > 1)
            Expanded(
              child: _buildFocusCard(
                context,
                title: "Window Titles",
                icon: Icons.subtitles_rounded,
                trackList: tTrackList,
                totalTime: tTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "Idle" ? e.value.time : 0)),
                totalKeys: tTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "Idle" ? e.value.keyboard : 0)),
                totalMouse: tTrackList.fold(0, (int p, MapEntry<String, MTrack> e) => p + (e.key != "Idle" ? e.value.mouse : 0)),
                idleKey: "Idle",
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFocusCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<MapEntry<String, MTrack>> trackList,
    required int totalTime,
    required int totalKeys,
    required int totalMouse,
    required String idleKey,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: <Widget>[
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold))),
              _buildColumnHeader(context, "Time", 70),
              _buildColumnHeader(context, "Keys", 55),
              _buildColumnHeader(context, "Mouse", 55),
            ],
          ),
        ),
        // Total Summary Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text("Total", style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600)),
              ),
              _buildValueCell(context, timeFormat(totalTime), 70, isBold: true, color: colorScheme.primary),
              _buildValueCell(context, totalKeys.formatInt(), 55, isBold: true, color: colorScheme.primary),
              _buildValueCell(context, totalMouse.formatInt(), 55, isBold: true, color: colorScheme.primary),
            ],
          ),
        ),
        const Divider(height: 1, thickness: 0.5, indent: 8, endIndent: 8),
        // Data List
        SizedBox(
          height: 250,
          child: MouseScrollWidget(
            scrollDirection: Axis.vertical,
            child: Column(
              children: List<Widget>.generate(
                trackList.length,
                (int index) {
                  final MapEntry<String, MTrack> track = trackList.elementAt(index);
                  return InkWell(
                    onTap: () {},
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              track.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: track.key == idleKey ? colorScheme.onSurface.withValues(alpha: 0.5) : null,
                              ),
                            ),
                          ),
                          _buildValueCell(context, track.value.timeFormat, 70,
                              color: track.key == idleKey ? colorScheme.onSurface.withValues(alpha: 0.5) : colorScheme.primary.withValues(alpha: 0.8)),
                          _buildValueCell(context, track.value.keyboard.formatInt(), 55,
                              color: track.key == idleKey ? colorScheme.onSurface.withValues(alpha: 0.5) : null),
                          _buildValueCell(context, track.value.mouse.formatInt(), 55, color: track.key == idleKey ? colorScheme.onSurface.withValues(alpha: 0.5) : null),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnHeader(BuildContext context, String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildValueCell(BuildContext context, String text, double width, {bool isBold = false, Color? color}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.end,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color,
        ),
      ),
    );
  }
}
