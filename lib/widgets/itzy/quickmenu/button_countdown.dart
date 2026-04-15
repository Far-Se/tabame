// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/quick_actions_item.dart';

class CountdownButton extends StatefulWidget {
  const CountdownButton({super.key});
  @override
  CountdownButtonState createState() => CountdownButtonState();
}

class CountdownButtonState extends State<CountdownButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Countdown",
      icon: const Icon(Icons.hourglass_bottom_rounded),
      onTap: () async {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 280),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: TimersWidget(),
                  ),
                ),
              ),
            );
          },
        );
        return;
      },
    );
  }
}

class CountDown {
  int minutes;
  int seconds;
  CountDown({required this.minutes, required this.seconds});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'minute': minutes, 'second': seconds};
  }

  factory CountDown.fromMap(Map<String, dynamic> map) {
    return CountDown(
      minutes: (map['minute'] ?? 0) as int,
      seconds: (map['second'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());
  factory CountDown.fromJson(String source) => CountDown.fromMap(json.decode(source) as Map<String, dynamic>);
}

class TimersWidget extends StatefulWidget {
  const TimersWidget({super.key});
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  List<CountDown> timers = Boxes.getSavedMap<CountDown>(CountDown.fromJson, "countdowns");

  final TextEditingController minutesController = TextEditingController(text: "00");
  final TextEditingController secondsController = TextEditingController(text: "00");

  Timer? _countDownTimer;
  int _totalSecondsRemaining = 0;
  int _initialTotalSeconds = 0;
  bool _isPaused = false;
  bool _isRunning = false;

  @override
  void dispose() {
    _countDownTimer?.cancel();
    minutesController.dispose();
    secondsController.dispose();
    super.dispose();
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

    _initialTotalSeconds = min * 60 + sec;
    _totalSecondsRemaining = _initialTotalSeconds;
    _isRunning = true;
    _isPaused = false;
    _createTicker();
    setState(() {});
  }

  void _createTicker() {
    _countDownTimer?.cancel();
    _countDownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_totalSecondsRemaining > 0) {
        setState(() {
          _totalSecondsRemaining--;
          _updateControllers();
        });
      } else {
        _stopTimer();
        _onFinished();
      }
    });
  }

  void _updateControllers() {
    minutesController.text = (_totalSecondsRemaining ~/ 60).toString().padLeft(2, '0');
    secondsController.text = (_totalSecondsRemaining % 60).toString().padLeft(2, '0');
  }

  void _pauseTimer() {
    _countDownTimer?.cancel();
    setState(() {
      _isPaused = true;
    });
  }

  void _resumeTimer() {
    setState(() {
      _isPaused = false;
    });
    _createTicker();
  }

  void _stopTimer() {
    _countDownTimer?.cancel();
    _countDownTimer = null;
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _totalSecondsRemaining = 0;
    });
  }

  void _resetTimer() {
    _stopTimer();
    setState(() {
      minutesController.text = (_initialTotalSeconds ~/ 60).toString().padLeft(2, '0');
      secondsController.text = (_initialTotalSeconds % 60).toString().padLeft(2, '0');
    });
  }

  void _onFinished() {
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      Beep(100, 200);
      Beep(500, 200);
      Beep(1000, 200);
      Beep(500, 200);
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
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Color(globalSettings.themeColors.accentColor);

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 280,
          constraints: const BoxConstraints(maxHeight: 500),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: surface.withAlpha(216),
            border: Border.all(color: onSurface.withAlpha(25), width: 1),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Header
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.timer_outlined, size: 20),
                    SizedBox(width: 10),
                    Text("Countdown", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Time Picker / Display
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    _buildTimeField(minutesController, "MIN", accent, onSurface),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(":", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: onSurface.withAlpha(128))),
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
                    if (!_isRunning)
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
                          onPressed: _isPaused ? _resumeTimer : _pauseTimer,
                          icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          label: Text(_isPaused ? "Resume" : "Pause"),
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

              if (_isRunning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton(
                    onPressed: _stopTimer,
                    child: Text("Cancel Countdown", style: TextStyle(color: Colors.redAccent.withAlpha(200), fontSize: 12)),
                  ),
                ),

              const Divider(height: 24),

              // History List
              if (timers.isNotEmpty && !_isRunning) ...<Widget>[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text("Recent", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.grey)),
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
          ),
        ),
      ),
    );
  }

  Widget _buildTimeField(TextEditingController controller, String label, Color accent, Color onSurface) {
    return Column(
      children: <Widget>[
        Container(
          width: 80,
          decoration: BoxDecoration(
            color: onSurface.withAlpha(10),
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
            readOnly: _isRunning && !_isPaused,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: onSurface.withAlpha(100))),
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
          color: _isHovered ? widget.accent.withAlpha(60) : widget.onSurface.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.history_rounded, size: 14, color: widget.onSurface.withAlpha(128)),
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
                    color: Colors.redAccent.withAlpha(178),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
