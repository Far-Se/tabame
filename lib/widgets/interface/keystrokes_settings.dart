import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/windows_scroll.dart';

/// Interface subpage that configures the Keystroke & Click Visualizer overlay
/// (the standalone `-keystrokes` window). Every option here is read live by the
/// overlay from `user.keystrokes*`; changes take effect the next time the
/// overlay repaints, so there is no need to relaunch it.
class KeystrokesSettingsPage extends StatefulWidget {
  const KeystrokesSettingsPage({super.key});

  @override
  State<KeystrokesSettingsPage> createState() => _KeystrokesSettingsPageState();
}

class _KeystrokesSettingsPageState extends State<KeystrokesSettingsPage> {
  static const List<String> _positions = <String>[
    "Top Left",
    "Top Center",
    "Bottom Center",
    "Bottom Right",
    "Bottom Left",
  ];

  bool get _running => Win32.findWindow("Tabame Keystrokes") != 0;

  void _toggleOverlay() {
    final int hwnd = Win32.findWindow("Tabame Keystrokes");
    if (hwnd != 0) {
      Win32.closeWindow(hwnd);
    } else {
      WinUtils.startTabame(closeCurrent: false, arguments: "-keystrokes");
    }
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return WindowsScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.keyboard_alt_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              const Text("Keystroke & Click Visualizer", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton.icon(
                onPressed: _toggleOverlay,
                icon: Icon(_running ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                label: Text(_running ? "Stop" : "Start"),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Shows the keys you press and where you click, on top of everything — "
            "for screencasts, tutorials and live demos. Pairs with the Screen Recorder / Rewindly.",
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          CheckBoxWidget(
            value: user.keystrokesShowClicks,
            text: "Show mouse click ripples",
            onChanged: (bool v) {
              setState(() => user.keystrokesShowClicks = v);
              Boxes.updateSettings("keystrokesShowClicks", v);
            },
          ),
          const SizedBox(height: 6),
          CheckBoxWidget(
            value: user.keystrokesModifiersOnly,
            text: "Only show shortcuts (hide plain typing)",
            onChanged: (bool v) {
              setState(() => user.keystrokesModifiersOnly = v);
              Boxes.updateSettings("keystrokesModifiersOnly", v);
            },
          ),
          const SizedBox(height: 20),
          const Text("Position", style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: List<Widget>.generate(_positions.length, (int i) {
              final bool selected = user.keystrokesPosition == i;
              return ChoiceChip(
                label: Text(_positions[i]),
                selected: selected,
                onSelected: (_) {
                  setState(() => user.keystrokesPosition = i);
                  Boxes.updateSettings("keystrokesPosition", i);
                },
              );
            }),
          ),
          const SizedBox(height: 20),
          _slider(
            label: "Badge size",
            value: user.keystrokesScale.toDouble(),
            min: 60,
            max: 200,
            divisions: 14,
            suffix: "%",
            onChanged: (double v) {
              setState(() => user.keystrokesScale = v.round());
              Boxes.updateSettings("keystrokesScale", v.round());
            },
          ),
          _slider(
            label: "Hold duration",
            value: user.keystrokesFadeMs.toDouble(),
            min: 800,
            max: 6000,
            divisions: 26,
            suffix: " ms",
            onChanged: (double v) {
              setState(() => user.keystrokesFadeMs = v.round());
              Boxes.updateSettings("keystrokesFadeMs", v.round());
            },
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text("${value.round()}$suffix", style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
