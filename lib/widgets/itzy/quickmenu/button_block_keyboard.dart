import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class BlockKeyboardButton extends StatelessWidget {
  const BlockKeyboardButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Block Keyboard",
        icon: const Icon(Icons.keyboard_hide_rounded),
        child: () => const BlockKeyboardPanel());
  }
}

class BlockKeyboardPanel extends StatefulWidget {
  const BlockKeyboardPanel({super.key});

  @override
  State<BlockKeyboardPanel> createState() => _BlockKeyboardPanelState();
}

class _BlockKeyboardPanelState extends State<BlockKeyboardPanel> with QuickMenuTriggers {
  final TextEditingController _minutesController = TextEditingController(text: "01");
  final TextEditingController _secondsController = TextEditingController(text: "00");
  final FocusNode _minutesFocus = FocusNode();

  Timer? _ticker;
  Duration _selectedDuration = const Duration(minutes: 5);
  Duration _remaining = Duration.zero;
  DateTime? _endsAt;
  bool _active = false;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _minutesFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    QuickMenuFunctions.removeListener(this);
    if (_active) unawaited(stopKeyboardBlocker());
    _minutesController.dispose();
    _secondsController.dispose();
    _minutesFocus.dispose();
    super.dispose();
  }

  @override
  void onQuickActionExecute(String actionName) async {
    if (actionName == "StartBlockingKeyboard") {
      print("EXECUTING");
      QuickMenuFunctions.keepOpen = true;
      await Future<void>.delayed(const Duration(milliseconds: 100), () {});
      _minutesController.text = "9999";
      _secondsController.text = "00";
      _start();
      // if (mounted) setState(() {});
    }
  }

  Future<void> _start() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 200), () {});
    final Duration duration = _durationFromInputs();
    if (duration <= Duration.zero) return;

    final bool started = await startKeyboardBlocker();
    if (!started) return;
    if (!mounted) {
      await stopKeyboardBlocker();
      return;
    }

    setState(() {
      _selectedDuration = duration;
      _remaining = duration;
      _endsAt = DateTime.now().add(duration);
      _active = true;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _syncRemaining());
  }

  Future<void> _stop() async {
    QuickMenuFunctions.keepOpen = false;
    await Future<void>.delayed(const Duration(milliseconds: 200), () {});
    _ticker?.cancel();
    _ticker = null;
    await stopKeyboardBlocker();
    releaseAllKeys();
    if (!mounted) return;
    setState(() {
      _active = false;
      _remaining = Duration.zero;
      _endsAt = null;
    });
  }

  void _syncRemaining() {
    final DateTime? endsAt = _endsAt;
    if (endsAt == null) return;

    final Duration next = endsAt.difference(DateTime.now());
    if (next <= Duration.zero) {
      unawaited(_stop());
      return;
    }

    if (mounted) setState(() => _remaining = next);
  }

  Duration _durationFromInputs() {
    final int minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final int seconds = int.tryParse(_secondsController.text.trim()) ?? 0;
    return Duration(minutes: minutes.clamp(0, 999), seconds: seconds.clamp(0, 59));
  }

  void _applyPreset(Duration duration) {
    if (_active) return;
    setState(() {
      _minutesController.text = duration.inMinutes.toString().padLeft(2, '0');
      _secondsController.text = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      _selectedDuration = duration;
    });
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes;
    final int seconds = duration.inSeconds.remainder(60);
    return "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  double get _progress {
    if (!_active || _selectedDuration <= Duration.zero) return 0;
    final double elapsed = 1 - (_remaining.inMilliseconds / _selectedDuration.inMilliseconds);
    return elapsed.clamp(0, 1);
  }

  void releaseAllKeys() {
    final List<int> keys = <int>[
      for (int vk = 1; vk <= 254; vk++) vk,
    ];

    final Pointer<INPUT> inputs = calloc<INPUT>(keys.length);

    for (int i = 0; i < keys.length; i++) {
      inputs[i].type = INPUT_KEYBOARD;
      inputs[i].ki.wVk = keys[i];
      inputs[i].ki.wScan = 0;
      inputs[i].ki.dwFlags = KEYEVENTF_KEYUP;
      inputs[i].ki.time = 0;
      inputs[i].ki.dwExtraInfo = 0;
    }

    SendInput(keys.length, inputs, sizeOf<INPUT>());
    free(inputs);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(
          title: "Block Keyboard",
          icon: Icons.keyboard_hide_rounded,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _StatusCard(
                    active: _active,
                    remainingLabel: _formatDuration(_active ? _remaining : _durationFromInputs()),
                    progress: _progress,
                    accent: accent,
                    onSurface: onSurface,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _TimeField(
                        controller: _minutesController,
                        focusNode: _minutesFocus,
                        label: "MIN",
                        enabled: !_active,
                        accent: accent,
                        onSurface: onSurface,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          ":",
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w300, color: onSurface.withAlpha(120)),
                        ),
                      ),
                      _TimeField(
                        controller: _secondsController,
                        label: "SEC",
                        enabled: !_active,
                        accent: accent,
                        onSurface: onSurface,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      _PresetChip(
                          label: "30s", active: !_active, onTap: () => _applyPreset(const Duration(seconds: 30))),
                      _PresetChip(label: "1m", active: !_active, onTap: () => _applyPreset(const Duration(minutes: 1))),
                      _PresetChip(label: "5m", active: !_active, onTap: () => _applyPreset(const Duration(minutes: 5))),
                      _PresetChip(
                          label: "15m", active: !_active, onTap: () => _applyPreset(const Duration(minutes: 15))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _active ? null : () => unawaited(_start()),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text("Start"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: onSurface.withAlpha(16),
                            disabledForegroundColor: onSurface.withAlpha(90),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _active ? () => unawaited(_stop()) : null,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text("Stop"),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.redAccent.withAlpha(220),
                            disabledForegroundColor: onSurface.withAlpha(80),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoStrip(accent: accent, onSurface: onSurface),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.active,
    required this.remainingLabel,
    required this.progress,
    required this.accent,
    required this.onSurface,
  });

  final bool active;
  final String remainingLabel;
  final double progress;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: active ? accent.withAlpha(20) : onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? accent.withAlpha(90) : onSurface.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: accent.withAlpha(22), borderRadius: BorderRadius.circular(9)),
                child: Icon(active ? Icons.lock_clock_rounded : Icons.keyboard_alt_outlined, size: 18, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      active ? "Keyboard clear is active" : "Keyboard clear is ready",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active ? "Keyboard input is being blocked." : "Set a timer, then start the keyboard blocker.",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(130)),
                    ),
                  ],
                ),
              ),
              Text(
                remainingLabel,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: active ? accent : onSurface),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: active ? progress : 0,
              minHeight: 4,
              color: accent,
              backgroundColor: onSurface.withAlpha(18),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.accent,
    required this.onSurface,
    this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool enabled;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: 78,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: enabled ? onSurface : onSurface.withAlpha(110)),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: onSurface.withAlpha(8),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: onSurface.withAlpha(18)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent.withAlpha(100)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(label,
            style:
                TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w800, color: onSurface.withAlpha(115))),
      ],
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: active ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accent.withAlpha(16) : onSurface.withAlpha(6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? accent.withAlpha(55) : onSurface.withAlpha(12)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w800,
            color: active ? accent : onSurface.withAlpha(90),
          ),
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.accent, required this.onSurface});

  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.code_rounded, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Useful if you want to clear your keyboard, or to stop your cat from writing poetry while you are away.",
              style: TextStyle(fontSize: Design.baseFontSize + 1, height: 1.25, color: onSurface.withAlpha(135)),
            ),
          ),
        ],
      ),
    );
  }
}
