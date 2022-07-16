import 'dart:async';
import 'dart:io';

import 'package:win32/win32.dart';

class Heights {
  double taskbar = 0;
  double traybar = 0;
  double topbar = 0;
  double get allSummed => taskbar + traybar + topbar;
}

class Globals {
  static bool changingPages = false;
  static bool isWindowActive = false;
  static final Heights heights = Heights();
  static int lastFocusedWinHWND = 0;
  static bool alwaysAwake = false;
  static String iconCachePath = "${Directory.current.path}\\data\\cache";
  static bool audioBoxVisible = false;

  static bool justStarted = false;

  static alwaysAwakeRun(bool state) {
    if (state == false) {
      SetThreadExecutionState(ES_CONTINUOUS);
    } else {
      Timer.periodic(const Duration(seconds: 45), (Timer timer) {
        SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
        if (Globals.alwaysAwake == false) {
          SetThreadExecutionState(ES_CONTINUOUS);
          timer.cancel();
        }
      });
    }
  }
}
