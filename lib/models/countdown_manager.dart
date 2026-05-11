import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class CountDown {
  int minutes;
  int seconds;
  CountDown({required this.minutes, required this.seconds});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'minutes': minutes, 'seconds': seconds};
  }

  factory CountDown.fromMap(Map<String, dynamic> map) {
    return CountDown(
      minutes: (map['minutes'] ?? 0) as int,
      seconds: (map['seconds'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());
  factory CountDown.fromJson(String source) => CountDown.fromMap(json.decode(source) as Map<String, dynamic>);
}

class CountdownManager extends ChangeNotifier {
  Timer? _timer;
  int _totalSecondsRemaining = 0;
  int _initialTotalSeconds = 0;
  bool _isRunning = false;
  bool _isPaused = false;

  int get totalSecondsRemaining => _totalSecondsRemaining;
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  int get initialTotalSeconds => _initialTotalSeconds;

  void start(int seconds) {
    _initialTotalSeconds = seconds;
    _totalSecondsRemaining = seconds;
    _isPaused = false;
    _isRunning = true;
    _startTimer();
    notifyListeners();
  }

  void resume() {
    if (_isPaused) {
      _isPaused = false;
      _isRunning = true;
      _startTimer();
      notifyListeners();
    }
  }

  void pause() {
    if (_isRunning) {
      _timer?.cancel();
      _isRunning = false;
      _isPaused = true;
      notifyListeners();
    }
  }

  void reset() {
    _timer?.cancel();
    _totalSecondsRemaining = 0;
    _isRunning = false;
    _isPaused = false;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_totalSecondsRemaining > 0) {
        _totalSecondsRemaining--;
        notifyListeners();
      } else {
        _finish();
      }
    });
  }

  void _finish() async {
    _timer?.cancel();
    _isRunning = false;
    _isPaused = false;
    _totalSecondsRemaining = 0;
    notifyListeners();

    final AudioPlayer player = AudioPlayer();
    await player.setAsset('resources/beep.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.seek(Duration.zero);
    await player.play();

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.dispose();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
