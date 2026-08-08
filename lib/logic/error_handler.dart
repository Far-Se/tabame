import 'dart:io';
import 'package:flutter/foundation.dart';

import '../platform/app_paths.dart';
import 'package:stack_trace/stack_trace.dart';

class ErrorLogger {
  static File get errorLog {
    return File(AppPaths.resolvePath('errors.log'));
  }

  static Future<void> log(
    String source,
    String error,
    StackTrace? stack,
  ) async {
    try {
      // Demangle the stack trace — critical for release mode
      final String chain = stack != null ? Chain.forTrace(stack).terse.toString() : 'no stack trace';

      final String entry = '''
==============================
[$source] ${DateTime.now().toIso8601String()}
ERROR: $error
STACK:
$chain
''';
      if (kReleaseMode) {
        await errorLog.parent.create(recursive: true);
        await errorLog.writeAsString(entry, mode: FileMode.append, flush: true);
      }

      // Also print in debug
      assert(() {
        print(entry);
        return true;
      }());
    } catch (e) {
      // Don't let the logger itself crash the app
      print('ErrorLogger failed: $e');
    }
  }

  /// Call this from a debug screen / shake gesture to retrieve logs
  static Future<String> readLogs() async {
    try {
      final File file = errorLog;
      return file.existsSync() ? await file.readAsString() : 'No logs found.';
    } catch (e) {
      return 'Failed to read logs: $e';
    }
  }

  static Future<void> clearLogs() async {
    final File file = errorLog;
    if (file.existsSync()) await file.delete();
  }
}

void handleErrors(FlutterErrorDetails details) async {
  final String error = "(${details.library ?? "unknownLib"}) ${details.exceptionAsString()}";
  String stack = details.stack.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack =
      "$stack\n${details.context?.toDescription()}\n${details.summary.toString()}\n${details.context.toString()}\n===============\n${DateTime.now().toString()}\n";
  final File errorFile = File(AppPaths.currentPath('errors.log'));
  errorFile.parent.createSync(recursive: true);
  errorFile.writeAsStringSync("$error\n$stack", mode: FileMode.append);
}

bool handlePlatformErrors(Object error, StackTrace stack2) {
  String stack = stack2.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack = "$stack\n===============\n";
  final File errorFile = File(AppPaths.currentPath('errors.log'));
  errorFile.parent.createSync(recursive: true);
  errorFile.writeAsStringSync(
    "${DateTime.now().toString()}\n${error.toString()}\n$stack",
    mode: FileMode.append,
  );
  return true;
}
