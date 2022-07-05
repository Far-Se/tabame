// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'utils.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'win32/imports.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';
import 'win32/window.dart';

class WindowWatcher {
  List<Window> list = <Window>[];
  Map<int, Window> cacheList = <int, Window>{};
  Map<String, Window> specialList = <String, Window>{};
  int _activeWinHandle = 0;
  get active {
    if (list.length > _activeWinHandle) {
      return list[_activeWinHandle];
    } else {
      return 0;
    }
  }

  WindowWatcher() {
    //fetchWindows();
    return;
  }

  bool fetchWindows({bool debug = false}) {
    final winHWNDS = enumWindows();
    final allHWNDs = <int>[];

    for (var hWnd in winHWNDS) {
      if (debug) {}
      if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "" && Win32.getTitle(hWnd) != "Tabame") {
        allHWNDs.add(hWnd);
      }
    }

    //cacheList.keys.where((hWnd) => !allHWNDs.contains(hWnd)).toList().forEach((hWnd) => cacheList.remove(hWnd));

    list.clear();
    specialList.clear();

    for (int element in allHWNDs) {
      // if (cacheList.containsKey(element)) {
      //   cacheList[element]!.getWorkspace();
      //   cacheList[element]!.getTitle();
      //   cacheList[element]!.getTitle();
      //   list.add(cacheList[element]!);
      // } else {
      list.add(Window(element));
      // cacheList[element] = list.last;
      // }

      if (list.last.process.exe == "Spotify.exe") specialList["Spotify"] = list.last;
    }

    for (var element in list) {
      if (element.process.path == "" && (element.process.exe == "AccessBlocked.exe" || element.process.exe == "")) {
        getHwndName(element.hWnd).then((value) => element.process.exe = value);
      }
    }

    final activeWindow = GetForegroundWindow();
    _activeWinHandle = list.indexWhere((element) => element.hWnd == activeWindow);
    if (_activeWinHandle < 0) _activeWinHandle = 0;

    orderBy(globalSettings.taskBarStyle);
    return true;
  }

  bool orderBy(TaskBarAppsStyle type) {
    if ([TaskBarAppsStyle.activeMonitorFirst, TaskBarAppsStyle.onlyActiveMonitor].contains(type)) {
      final lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final monitor = MonitorFromPoint(lpPoint.ref, 0);
      if (Monitor.monitors.contains(monitor)) {
        if (type == TaskBarAppsStyle.activeMonitorFirst) {
          List<Window> firstItems = [];
          firstItems = list.where((element) => element.appearance.monitor == monitor ? true : false).toList();
          list.removeWhere((element) => firstItems.contains(element));
          list = firstItems + list;
          // list.sort((a, b) => monitor == a.appearance.monitor ? -1 : 1);
        } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {
          list.removeWhere((element) => element.appearance.monitor != monitor);
        }
      }
      free(lpPoint);
    } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {}
    return true;
  }

  bool mediaControl(index, {button = AppCommand.mediaPlayPause}) {
    if (list[index].process.exe == "Spotify.exe") {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    } else if (/* list[index].process.exe == "chrome.exe" && */ specialList.containsKey("Spotify") == true) {
      Audio.enumAudioMixer().then((e) async {
        final Window spotify = specialList["Spotify"]!;

        List<ProcessVolume> elements = e as List<ProcessVolume>;
        final volume = elements.firstWhere((element) => element.processId == spotify.process.pId).maxVolume;

        await Audio.setAudioMixerVolume(spotify.process.pId, 0.1);

        Future.delayed(const Duration(milliseconds: 100), () async {
          SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);

          (AppCommand.mediaPlayPause == button && SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPlayPause) == 1) ||
              (SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack) == 1 &&
                  SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPause) == 1);

          Future.delayed(const Duration(milliseconds: 500), () => Audio.setAudioMixerVolume(spotify.process.pId, volume));

          return;
        });
      });
    } else {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    }
    return true;
  }
}
