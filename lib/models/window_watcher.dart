// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'package:tabamewin32/tabamewin32.dart';

import 'globals.dart';
import 'utils.dart';
import 'win32/imports.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';
import 'win32/window.dart';

class WindowWatcher {
  static List<Window> list = <Window>[];
  static Map<int, Uint8List?> icons = <int, Uint8List?>{};
  static Map<int, int> iconsHandles = <int, int>{};
  static Map<String, Window> specialList = <String, Window>{};
  static int _activeWinHandle = 0;
  static get active {
    if (list.length > _activeWinHandle) {
      return list[_activeWinHandle];
    } else {
      return 0;
    }
  }

  static bool fetching = false;

  static Future<bool> fetchWindows() async {
    if (fetching) return false;
    fetching = true;
    final List<int> winHWNDS = enumWindows();
    final List<int> allHWNDs = <int>[];
    if (winHWNDS.isEmpty) print("ENUM WINDS IS EMPTY");
    for (int hWnd in winHWNDS) {
      if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd) != "" && Win32.getTitle(hWnd) != "Tabame") {
        allHWNDs.add(hWnd);
      }
    }

    final List<Window> newList = <Window>[];
    specialList.clear();

    for (int element in allHWNDs) {
      newList.add(Window(element));

      if (newList.last.process.exe == "Spotify.exe") specialList["Spotify"] = newList.last;
    }

    for (Window element in newList) {
      if (element.process.path == "" && (element.process.exe == "AccessBlocked.exe" || element.process.exe == "")) {
        element.process.exe = await getHwndName(element.hWnd);
      }
    }

    final int activeWindow = GetForegroundWindow();
    _activeWinHandle = newList.indexWhere((Window element) => element.hWnd == activeWindow);
    list = <Window>[...newList];
    if (_activeWinHandle > -1) {
      Globals.lastFocusedWinHWND = list[_activeWinHandle].hWnd;
    }
    await handleIcons();
    orderBy(globalSettings.taskBarAppsStyle);
    return true;
  }

  static Future<bool> handleIcons() async {
    //Delete closed windows
    if (list.length != icons.length) {
      icons.removeWhere((int key, Uint8List? value) => !list.any((Window w) => w.hWnd == key));
      iconsHandles.removeWhere((int key, int value) => !list.any((Window w) => w.hWnd == key));
    }

    for (Window win in list) {
      //APPX
      if (icons.containsKey(win.hWnd) && win.isAppx) continue;
      if (win.isAppx) {
        if (win.appxIcon != "" && File(win.appxIcon).existsSync()) icons[win.hWnd] = File(win.appxIcon).readAsBytesSync();
        continue;
      }
      //EXE
      bool fetchingIcon = false;
      if (!iconsHandles.containsKey(win.hWnd)) {
        fetchingIcon = true;
      } else if (iconsHandles[win.hWnd] != win.process.iconHandle) {
        fetchingIcon = true;
      }

      if (fetchingIcon) {
        icons[win.hWnd] = await getWindowIcon(win.hWnd);
        if (icons[win.hWnd]!.length == 3) icons[win.hWnd] = await getExecutableIcon(win.process.path + win.process.exe);
        iconsHandles[win.hWnd] = win.process.iconHandle;
      }
    }
    return true;
  }

  static bool orderBy(TaskBarAppsStyle type) {
    if (<TaskBarAppsStyle>[TaskBarAppsStyle.activeMonitorFirst, TaskBarAppsStyle.onlyActiveMonitor].contains(type)) {
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        if (type == TaskBarAppsStyle.activeMonitorFirst) {
          List<Window> firstItems = <Window>[];
          firstItems = list.where((Window element) => element.monitor == monitor ? true : false).toList();
          list.removeWhere((Window element) => firstItems.contains(element));
          list = firstItems + list;
        } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {
          list.removeWhere((Window element) => element.monitor != monitor);
        }
      }
    } else if (type == TaskBarAppsStyle.onlyActiveMonitor) {}
    fetching = false;
    return true;
  }

  static bool mediaControl(int index, {int button = AppCommand.mediaPlayPause}) {
    if (list[index].process.exe == "Spotify.exe") {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    } else if (/* list[index].process.exe == "chrome.exe" && */ specialList.containsKey("Spotify") == true) {
      Audio.enumAudioMixer().then((List<ProcessVolume>? e) async {
        final Window spotify = specialList["Spotify"]!;

        List<ProcessVolume> elements = e as List<ProcessVolume>;
        final double volume = elements.firstWhere((ProcessVolume element) => element.processId == spotify.process.pId).maxVolume;

        await Audio.setAudioMixerVolume(spotify.process.pId, 0.1);

        Future<void>.delayed(const Duration(milliseconds: 100), () async {
          SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);

          if (AppCommand.mediaPlayPause == button) {
            SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
          } else {
            SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack);
            SendMessage(spotify.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPause);
          }

          Future<void>.delayed(const Duration(milliseconds: 500), () => Audio.setAudioMixerVolume(spotify.process.pId, volume));

          return;
        });
      });
    } else {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    }
    return true;
  }
}
