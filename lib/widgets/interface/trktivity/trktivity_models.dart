import '../../../models/settings.dart';

String timeFormat(int time) {
  final Duration dur = Duration(seconds: time);
  return "${dur.inHours.toString().numberFormat()}:${dur.inMinutes.remainder(60).toString().numberFormat()}:${dur.inSeconds.remainder(60).toString().numberFormat()}";
}

class MTrack {
  int mouse;
  int keyboard;
  int time;
  String get timeFormat {
    final Duration dur = Duration(seconds: time);
    return "${dur.inHours.toString().numberFormat()}:${dur.inMinutes.remainder(60).toString().numberFormat()}:${dur.inSeconds.remainder(60).toString().numberFormat()}";
  }

  MTrack({required this.mouse, required this.keyboard, this.time = 0});

  @override
  String toString() => '\nMTrack(mouse: $mouse, keyboard: $keyboard, time: ${time.formatTime()})';
}

class DMTRack extends MTrack {
  int idleTime;
  DMTRack({
    required super.mouse,
    required super.keyboard,
    required super.time,
    required this.idleTime,
  });
}

class TTrack {
  int from;
  int to;
  int get diff => to - from;
  TTrack({
    required this.from,
    required this.to,
  });

  @override
  String toString() => '\nTTrack(from: $from, to: $to)';
}
