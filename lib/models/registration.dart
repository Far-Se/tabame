import 'dart:async';
import 'dart:io';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:intl/intl_standalone.dart';

import 'boxes.dart';
import 'globals.dart';
import 'utils.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';

late Timer monitorChecker;
Future<void> registerAll() async {
  final String locale = Platform.localeName.substring(0, 2);
  Intl.systemLocale = await findSystemLocale();
  await initializeDateFormatting(locale);

  // ? Main Handle
  Monitor.fetchMonitor();
  monitorChecker = Timer.periodic(const Duration(seconds: 5), (Timer timer) => Monitor.fetchMonitor());
  await Boxes.registerBoxes();

  globalSettings.volumeOSD = VolumeOSDStyle.media;
  if (globalSettings.volumeOSD != VolumeOSDStyle.normal) {
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSD, applyStyle: true);
  }
  if (!Directory(Globals.iconCachePath).existsSync()) Directory(Globals.iconCachePath).createSync(recursive: true);
}

unregisterAll() {
  monitorChecker.cancel();
}
