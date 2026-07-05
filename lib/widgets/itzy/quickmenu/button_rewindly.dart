import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../services/rewindly_service.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class RewindlyButton extends StatelessWidget {
  const RewindlyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: RewindlyService.instance.runningNotifier,
      builder: (BuildContext context, bool running, _) {
        return ModalButton(
          actionName: "Rewindly",
          heightFactor: 0.9,
          icon: Icon(
            Icons.history_rounded,
            color: running ? Colors.red : null,
          ),
          child: () => const RewindlyPanel(),
        );
      },
    );
  }
}

class RewindlyPanel extends StatefulWidget {
  const RewindlyPanel({super.key});

  @override
  State<RewindlyPanel> createState() => _RewindlyPanelState();
}

class _RewindlyPanelState extends State<RewindlyPanel> {
  final RewindlyService _service = RewindlyService.instance;
  bool _exporting = false;
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _toggle(bool enable) async {
    setState(() {
      user.rewindlyEnabled = enable;
      _statusMessage = null;
    });
    await Boxes.updateSettings("rewindlyEnabled", enable);
    if (enable) {
      await _service.start();
    } else {
      await _service.stop();
    }
    if (mounted) setState(() {});
  }

  Future<void> _setFps(int value) async {
    setState(() => user.rewindlyFps = value);
    await Boxes.updateSettings("rewindlyFps", value);
    // FPS only takes effect on the next segment; restart to apply immediately.
    if (_service.isRunning) await _service.restart();
  }

  Future<void> _setClipMinutes(int value) async {
    setState(() => user.rewindlyClipMinutes = value);
    await Boxes.updateSettings("rewindlyClipMinutes", value);
  }

  Future<void> _setRetention(int value) async {
    setState(() => user.rewindlyRetentionMinutes = value);
    await Boxes.updateSettings("rewindlyRetentionMinutes", value);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _statusMessage = null;
    });
    final List<String> files = await _service.exportLastClip();
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _statusIsError = files.isEmpty;
      _statusMessage = files.isEmpty
          ? "Nothing to export yet — let it record for a bit."
          : "Saved ${files.length} clip${files.length == 1 ? '' : 's'} to FancyShot.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _service.runningNotifier,
      builder: (BuildContext context, bool running, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: C.start,
          children: <Widget>[
            PanelHeader(
              title: "Rewindly",
              icon: Icons.history_rounded,
              buttonPressed: () => WinUtils.open(WinUtils.getFancyshotFolder()),
              buttonIcon: Icons.folder_open_rounded,
              buttonTooltip: "Open FancyShot folder",
            ),
            Flexible(
              child: Material(
                type: MaterialType.transparency,
                child: WindowsScrollView(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                  child: Column(
                    crossAxisAlignment: C.start,
                    children: <Widget>[
                      _buildEnableCard(running),
                      const SizedBox(height: 8),
                      _buildStatusCard(running),
                      const SizedBox(height: 10),
                      _buildSliderCard(
                        title: "Capture rate",
                        description: "Frames captured per second.",
                        value: user.rewindlyFps,
                        min: 1,
                        max: 10,
                        unit: "fps",
                        onChanged: _setFps,
                      ),
                      const SizedBox(height: 8),
                      _buildSliderCard(
                        title: "Clip length",
                        description: "How much of the past to export.",
                        value: user.rewindlyClipMinutes,
                        min: 1,
                        max: 10,
                        unit: "min",
                        onChanged: _setClipMinutes,
                      ),
                      const SizedBox(height: 8),
                      _buildSliderCard(
                        title: "History kept",
                        description: "Rolling buffer retained on disk.",
                        value: user.rewindlyRetentionMinutes,
                        min: 15,
                        max: 240,
                        step: 15,
                        unit: "min",
                        onChanged: _setRetention,
                      ),
                      const SizedBox(height: 12),
                      _buildExportButton(running),
                      if (_statusMessage != null) ...<Widget>[
                        const SizedBox(height: 10),
                        _buildStatusStrip(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEnableCard(bool running) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: running ? Design.accent.withAlpha(14) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: running ? Design.accent.withAlpha(60) : Design.text.withAlpha(16),
        ),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            running ? Icons.fiber_manual_record_rounded : Icons.videocam_off_rounded,
            size: 16,
            color: running ? Colors.red : Design.text.withAlpha(120),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  running ? "Recording" : "Rewindly is off",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                    color: Design.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  running
                      ? "Buffering the last ${user.rewindlyRetentionMinutes} min across all monitors."
                      : "Enable to keep an instant-replay buffer.",
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 0.5,
                    color: Design.text.withAlpha(140),
                  ),
                ),
              ],
            ),
          ),
          MiniToggleSwitch(
            value: user.rewindlyEnabled,
            activeThumbColor: Design.accent,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(bool running) {
    final double mb = _service.bufferSizeBytes() / (1024 * 1024);
    final String sizeLabel = mb >= 1024 ? "${(mb / 1024).toStringAsFixed(2)} GB" : "${mb.toStringAsFixed(0)} MB";
    return Row(
      children: <Widget>[
        Expanded(
          child: _buildMetric(
            icon: Icons.desktop_windows_rounded,
            label: "MONITORS",
            value: running ? "${_service.monitorCount}" : "—",
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetric(
            icon: Icons.sd_storage_rounded,
            label: "BUFFER",
            value: running ? sizeLabel : "—",
          ),
        ),
      ],
    );
  }

  Widget _buildMetric({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 14, color: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Design.text.withAlpha(130),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1,
                    fontWeight: FontWeight.w700,
                    color: Design.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderCard({
    required String title,
    required String description,
    required int value,
    required int min,
    required int max,
    required String unit,
    required Future<void> Function(int) onChanged,
    int step = 1,
  }) {
    final int divisions = ((max - min) / step).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
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
                      description,
                      style: TextStyle(
                        fontSize: Design.baseFontSize - 1,
                        color: Design.text.withAlpha(130),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(24),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  "$value $unit",
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w700,
                    color: Design.accent,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              activeTrackColor: Design.accent,
              inactiveTrackColor: Design.text.withAlpha(24),
              thumbColor: Design.accent,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
              onChanged: (double v) {
                final int snapped = (min + (v - min) / step * step).round();
                onChanged(snapped);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportButton(bool running) {
    final bool enabled = running && !_exporting;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: InkWell(
        onTap: enabled ? _export : null,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: Design.accent.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Design.accent.withAlpha(80)),
          ),
          child: Center(
            child: _exporting
                ? SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Design.accent),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.save_alt_rounded, size: 15, color: Design.accent),
                      const SizedBox(width: 8),
                      Text(
                        "Save last ${user.rewindlyClipMinutes} min",
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: Design.accent,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStrip() {
    final Color color = _statusIsError ? Colors.orangeAccent : Design.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            _statusIsError ? Icons.info_outline_rounded : Icons.check_circle_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text),
            ),
          ),
          if (!_statusIsError)
            InkWell(
              onTap: () => WinUtils.open(WinUtils.getFancyshotFolder()),
              child: Text(
                "Open",
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
