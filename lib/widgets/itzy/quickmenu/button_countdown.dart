// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/countdown_manager.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class CountdownButton extends StatelessWidget {
  const CountdownButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Countdown",
        icon: const Icon(Icons.hourglass_bottom_rounded),
        child: () => const CountDownWidget());
  }
}

class CountDownWidget extends StatefulWidget {
  const CountDownWidget({super.key});
  @override
  CountDownWidgetState createState() => CountDownWidgetState();
}

class CountDownWidgetState extends State<CountDownWidget> {
  List<CountDown> timers = Boxes.getSavedMap<CountDown>(CountDown.fromJson, "countdowns");

  final TextEditingController minutesController = TextEditingController(text: "00");
  final TextEditingController secondsController = TextEditingController(text: "00");

  @override
  void initState() {
    super.initState();
    Globals.countdownManager.addListener(_onManagerUpdate);
    _updateControllers();
  }

  @override
  void dispose() {
    Globals.countdownManager.removeListener(_onManagerUpdate);
    minutesController.dispose();
    secondsController.dispose();
    super.dispose();
  }

  void _onManagerUpdate() {
    if (mounted) {
      setState(() {
        _updateControllers();
      });
    }
  }

  void _startTimer() {
    final int min = int.tryParse(minutesController.text) ?? 0;
    final int sec = int.tryParse(secondsController.text) ?? 0;
    if (min == 0 && sec == 0) return;

    // Add to history if new
    final int index = timers.indexWhere((CountDown t) => t.minutes == min && t.seconds == sec);
    if (index > -1) timers.removeAt(index);
    timers.insert(0, CountDown(minutes: min, seconds: sec));
    if (timers.length > 5) timers.removeRange(5, timers.length);
    Boxes.updateSettings("countdowns", jsonEncode(timers.map((CountDown t) => t.toJson()).toList()));

    Globals.countdownManager.start(min * 60 + sec);
  }

  void _updateControllers() {
    if (Globals.countdownManager.isRunning || Globals.countdownManager.isPaused) {
      minutesController.text = (Globals.countdownManager.totalSecondsRemaining ~/ 60).toString().padLeft(2, '0');
      secondsController.text = (Globals.countdownManager.totalSecondsRemaining % 60).toString().padLeft(2, '0');
    }
  }

  void _pauseTimer() {
    Globals.countdownManager.pause();
  }

  void _resumeTimer() {
    Globals.countdownManager.resume();
  }

  void _stopTimer() {
    Globals.countdownManager.reset();
  }

  void _resetTimer() {
    final int initialSeconds = Globals.countdownManager.initialTotalSeconds;
    Globals.countdownManager.reset();
    setState(() {
      minutesController.text = (initialSeconds ~/ 60).toString().padLeft(2, '0');
      secondsController.text = (initialSeconds % 60).toString().padLeft(2, '0');
    });
  }

  void _deleteHistoryItem(int index) {
    setState(() {
      timers.removeAt(index);
    });
    Boxes.updateSettings("countdowns", jsonEncode(timers.map((CountDown t) => t.toJson()).toList()));
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = userSettings.themeColors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(
          title: "Countdown",
          icon: Icons.timer_outlined,
        ),

        // Time Picker / Display
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _buildTimeField(minutesController, "MIN", accent, onSurface),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(":",
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: onSurface.withAlpha(128))),
              ),
              _buildTimeField(secondsController, "SEC", accent, onSurface),
            ],
          ),
        ),

        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              if (!Globals.countdownManager.isRunning && !Globals.countdownManager.isPaused)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _startTimer,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text("Start"),
                    style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                          backgroundColor: WidgetStateProperty.all(accent),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                        ),
                  ),
                )
              else ...<Widget>[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: Globals.countdownManager.isPaused ? _resumeTimer : _pauseTimer,
                    icon: Icon(Globals.countdownManager.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                    label: Text(Globals.countdownManager.isPaused ? "Resume" : "Pause"),
                    style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                          backgroundColor: WidgetStateProperty.all(accent.withAlpha(200)),
                          foregroundColor: WidgetStateProperty.all(Colors.white),
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text("Reset"),
                    style: TextButton.styleFrom(
                      foregroundColor: onSurface.withAlpha(178),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (Globals.countdownManager.isRunning || Globals.countdownManager.isPaused)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextButton(
              onPressed: _stopTimer,
              child: Text("Cancel Countdown",
                  style: TextStyle(color: Colors.redAccent.withAlpha(200), fontSize: Design.baseFontSize + 2)),
            ),
          ),

        const Divider(height: 24),

        // History List
        if (timers.isNotEmpty && !Globals.countdownManager.isRunning && !Globals.countdownManager.isPaused) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text("Recent",
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Colors.grey)),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              itemCount: timers.length,
              itemBuilder: (BuildContext context, int index) {
                return _HistoryTimerTile(
                  timer: timers[index],
                  accent: accent,
                  onSurface: onSurface,
                  onTap: () {
                    minutesController.text = timers[index].minutes.toString().padLeft(2, '0');
                    secondsController.text = timers[index].seconds.toString().padLeft(2, '0');
                    // start the countdown
                    _startTimer();
                  },
                  onDelete: () => _deleteHistoryItem(index),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTimeField(TextEditingController controller, String label, Color accent, Color onSurface) {
    return Column(
      children: <Widget>[
        Container(
          width: 80,
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: TextField(
            controller: controller,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: -2),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
            readOnly: Globals.countdownManager.isRunning && !Globals.countdownManager.isPaused,
          ),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: Design.baseFontSize, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.4))),
      ],
    );
  }
}

class _HistoryTimerTile extends StatefulWidget {
  final CountDown timer;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _HistoryTimerTile({
    required this.timer,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_HistoryTimerTile> createState() => _HistoryTimerTileState();
}

class _HistoryTimerTileState extends State<_HistoryTimerTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: _isHovered
              ? userSettings.themeColors.accent.withValues(alpha: 0.25)
              : widget.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.history_rounded, size: 14, color: widget.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "${widget.timer.minutes.toString().padLeft(2, '0')}:${widget.timer.seconds.toString().padLeft(2, '0')}",
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (_isHovered)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 14),
                    onPressed: widget.onDelete,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                    color: Colors.redAccent.withValues(alpha: 0.7),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
