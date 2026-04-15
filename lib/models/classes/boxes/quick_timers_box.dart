import 'dart:async';

// --------------------------------------------------------------------------
// QuickTimer / SavedQuickTimers
// --------------------------------------------------------------------------

class QuickTimer {
  String name = "";
  Timer? timer;
  DateTime endTime = DateTime.now();
  int type = 0;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'endTime': endTime.millisecondsSinceEpoch,
      'type': type,
    };
  }

  static QuickTimer fromMap(Map<String, dynamic> map) {
    return QuickTimer()
      ..name = map['name'] ?? ''
      ..endTime = DateTime.fromMillisecondsSinceEpoch(map['endTime'] ?? 0)
      ..type = map['type'] ?? 0;
  }
}

class SavedQuickTimers {
  String name = "";
  int minutes = 0;
  int type = 0;
}
