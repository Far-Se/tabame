import 'dart:async';
import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';
import 'package:window_manager/window_manager.dart';

import 'boxes.dart';
import 'utils.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

late Timer monitorChecker;
Future registerAll() async {
  await windowManager.ensureInitialized();
  final locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Main Handle
  Win32.fetchMainWindowHandle();
  Monitor.fetchMonitor();
  monitorChecker = Timer.periodic(const Duration(seconds: 5), (timer) => Monitor.fetchMonitor());
  // ? Boxes
  await Boxes.registerBoxes();

  globalSettings.volumeOSD = VolumeOSDStyle.media;
  if (globalSettings.volumeOSD != VolumeOSDStyle.normal) {
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSD, applyStyle: true);
  }
}

unregisterAll() {
  monitorChecker.cancel();
}
