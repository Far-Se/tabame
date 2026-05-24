import 'dart:async';
import 'dart:io';

import 'models/win32/win32.dart' show Win32;

Future<void> startRun(List<String> arguments) async {
  final ArgParser parser = ArgParser();
  parser.parseArgs(arguments);
  String runType = parser.getArg('run') ?? 'Default';
  // Win32.invokeShellMenuItem(path, Win32.hWnd, verb: action.verb, id: action.id);
  // runTabameWithParams(<String, dynamic>{"run":"shellMenuItem", "path": path, "hwnd": hWnd, "verb": verb, "id": id});
  if (runType == "shellMenuItem") {
    final String path = parser.getArg('path') ?? "";
    final String verb = parser.getArg('verb') ?? "";
    final int id = int.tryParse(parser.getArg('id') ?? "-1") ?? -1;
    final int hWnd = int.tryParse(parser.getArg('hwnd') ?? "-1") ?? -1;
    Win32.invokeShellMenuItem(path, hWnd, verb: verb, id: id);
    exit(0);
  }

  exit(0);
}

class ArgParser {
  final Map<String, String> _parsedArgs = <String, String>{};

  String? getArg(String key) {
    final String normalizedKey = key.startsWith('-') ? key.toLowerCase() : '-${key.toLowerCase()}';
    return _parsedArgs[normalizedKey];
  }

  void parseArgs(List<String> args) {
    _parsedArgs.clear();

    for (int i = 0; i < args.length; i++) {
      String arg = args[i];

      if (arg.startsWith('-')) {
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          _parsedArgs[arg.toLowerCase()] = args[i + 1];
          i++;
        } else {
          _parsedArgs[arg.toLowerCase()] = 'true';
        }
      }
    }
  }
}
