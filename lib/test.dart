import 'dart:async';
import 'dart:io';

import 'models/win32/win_utils.dart';

class TimestampLogger {
  static Timer? _timer;

  static String get filePath {
    // final localAppData = Platform.environment['LOCALAPPDATA'];

    // if (localAppData == null) {
    //   throw StateError('LOCALAPPDATA not found.');
    // }

    return '${WinUtils.getTabameAppDataFolder()}\\timestamp.log';
  }

  static Future<void> init() async {
    final file = File(filePath);

    // Ensure the Tabame directory exists.
    await file.parent.create(recursive: true);

    // Clear the log file.
    await file.writeAsString('');

    // Prevent duplicate timers.
    _timer?.cancel();

    // Start logging every minute.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _writeTimestamp(),
    );
  }

  static Future<void> _writeTimestamp() async {
    try {
      final file = File(filePath);

      await file.writeAsString(
        '${DateTime.now().toIso8601String()}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      print('TimestampLogger error: $e');
    }
  }

  static void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
