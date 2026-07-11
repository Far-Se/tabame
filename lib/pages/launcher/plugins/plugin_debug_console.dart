import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import 'plugin_debug.dart';

/// Live protocol console shown under the plugin view for `"dev": true`
/// plugins: stderr, malformed/dropped frames, accepted frames, commands, and
/// lifecycle events (start / crash / hot-reload), newest pinned at the bottom.
///
/// Collapsed it is a one-line strip previewing the latest entry; clicking the
/// header expands it into a scrollable log.
class PluginDebugConsole extends StatefulWidget {
  const PluginDebugConsole({super.key, required this.log, required this.pluginId});

  final PluginDebugLog log;
  final String pluginId;

  @override
  State<PluginDebugConsole> createState() => _PluginDebugConsoleState();
}

class _PluginDebugConsoleState extends State<PluginDebugConsole> {
  bool _expanded = false;

  Color _kindColor(PluginDebugKind kind) {
    switch (kind) {
      case PluginDebugKind.error:
      case PluginDebugKind.dropped:
        return const Color(0xFFE57373);
      case PluginDebugKind.stderr:
        return const Color(0xFFFFB74D);
      case PluginDebugKind.frame:
      case PluginDebugKind.command:
        return Design.accent;
      case PluginDebugKind.info:
      case PluginDebugKind.stdout:
        return Design.text.withAlpha(150);
    }
  }

  String _kindLabel(PluginDebugKind kind) {
    switch (kind) {
      case PluginDebugKind.info:
        return 'INFO';
      case PluginDebugKind.stderr:
        return 'ERR>';
      case PluginDebugKind.stdout:
        return 'OUT>';
      case PluginDebugKind.frame:
        return 'FRAME';
      case PluginDebugKind.dropped:
        return 'DROP';
      case PluginDebugKind.command:
        return 'CMD';
      case PluginDebugKind.error:
        return 'FAIL';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.log.revision,
      builder: (BuildContext context, int _, Widget? __) {
        final List<PluginDebugEntry> entries = widget.log.entries;
        final PluginDebugEntry? last = entries.isEmpty ? null : entries.last;
        return Container(
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(40),
            border: Border(top: BorderSide(color: Design.accent.withAlpha(40))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Design.accent.withAlpha(30),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: Design.accent.withAlpha(70)),
                        ),
                        child: Text(
                          'DEV',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Design.accent, letterSpacing: 0.6),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: last == null
                            ? Text('${widget.pluginId} — waiting for output',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 10.5, fontFamily: 'Consolas', color: Design.text.withAlpha(120)))
                            : Text.rich(
                                TextSpan(children: <InlineSpan>[
                                  TextSpan(
                                    text: '${_kindLabel(last.kind)} ',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: _kindColor(last.kind)),
                                  ),
                                  TextSpan(text: last.message, style: TextStyle(color: Design.text.withAlpha(180))),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5, fontFamily: 'Consolas'),
                              ),
                      ),
                      const SizedBox(width: 6),
                      Text('${entries.length}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Design.text.withAlpha(110))),
                      const SizedBox(width: 4),
                      if (_expanded)
                        GestureDetector(
                          onTap: widget.log.clear,
                          child: Icon(Icons.clear_all_rounded, size: 13, color: Design.text.withAlpha(120)),
                        ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                        size: 14,
                        color: Design.text.withAlpha(140),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 130),
                  child: ListView.builder(
                    // Newest at the visual bottom; reverse pins the scroll there
                    // so the log follows live output until the user scrolls up.
                    reverse: true,
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                    itemCount: entries.length,
                    itemBuilder: (BuildContext context, int index) {
                      final PluginDebugEntry entry = entries[entries.length - 1 - index];
                      return Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text.rich(
                          TextSpan(children: <InlineSpan>[
                            TextSpan(text: '${entry.timestamp} ', style: TextStyle(color: Design.text.withAlpha(90))),
                            TextSpan(
                              text: '${_kindLabel(entry.kind).padRight(6)} ',
                              style: TextStyle(fontWeight: FontWeight.w700, color: _kindColor(entry.kind)),
                            ),
                            TextSpan(text: entry.message, style: TextStyle(color: Design.text.withAlpha(190))),
                          ]),
                          style: const TextStyle(fontSize: 10.5, fontFamily: 'Consolas', height: 1.35),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
