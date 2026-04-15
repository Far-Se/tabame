import 'dart:io';
import 'package:flutter/foundation.dart';

import '../models/win32/win32.dart';

void handleErrors(FlutterErrorDetails details) async {
  final String error = "(${details.library ?? "unknownLib"}) ${details.exceptionAsString()}";
  String stack = details.stack.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack = "$stack\n${details.context?.toDescription()}\n${details.summary.toString()}\n${details.context.toString()}\n===============\n${DateTime.now().toString()}\n";
  File("${WinUtils.getTabameAppDataFolder()}\\errors.log").writeAsStringSync("$error\n$stack", mode: FileMode.append);
}

bool handlePlatformErrors(Object error, StackTrace stack2) {
  String stack = stack2.toString();
  final List<String> stackArr = stack.split("\n");
  if (stackArr.length > 10) {
    stack = stackArr.take(10).join("\n");
  }
  stack = "$stack\n===============\n";
  File("${WinUtils.getTabameAppDataFolder()}\\errors.log").writeAsStringSync("${DateTime.now().toString()}\n${error.toString()}\n$stack", mode: FileMode.append);
  return true;
}
