import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

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

  void _finish() {
    _timer?.cancel();
    _isRunning = false;
    _isPaused = false;
    _totalSecondsRemaining = 0;
    notifyListeners();

    // Audible notification
    for (int i = 0; i < 3; i++) {
      Beep(100 + (i * 50), 200);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
