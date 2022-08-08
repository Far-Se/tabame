// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'package:tabamewin32/tabamewin32.dart';

import 'classes/boxes.dart';
import 'globals.dart';
import 'settings.dart';
import 'win32/imports.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';
import 'win32/window.dart';

class WindowWatcher {
  static List<Window> list = <Window>[];
  static Map<int, Uint8List?> icons = <int, Uint8List?>{};
  static Map<int, int> iconsHandles = <int, int>{};
  static Map<String, Window> specialList = <String, Window>{};
  static Map<String, String> taskBarRewrites = Boxes().taskBarRewrites;
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
      if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd).isNotEmpty && !<String>["Tabame", "PopupHost"].contains(Win32.getTitle(hWnd))) {
        allHWNDs.add(hWnd);
      }
    }

    final List<Window> newList = <Window>[];

    for (int element in allHWNDs) {
      newList.add(Window(element));

      if (newList.last.process.exe == "Spotify.exe") {
        specialList["Spotify"] = newList.last;
        if (Boxes.pref.getString("SpotifyLocation") == null) {
          Boxes.pref.setString("SpotifyLocation", newList.last.process.exePath);
        }
      }
    }

    for (Window window in newList) {
      if (window.process.path == "" && (window.process.exe == "AccessBlocked.exe" || window.process.exe == "")) {
        window.process.exe = await getHwndName(window.hWnd);
      }
      for (MapEntry<String, String> rewrite in taskBarRewrites.entries) {
        final RegExp re = RegExp(rewrite.key, caseSensitive: false);
        if (re.hasMatch(window.title)) {
          window.title = window.title.replaceAllMapped(re, (Match match) {
            String replaced = rewrite.value;
            for (int x = 0; x < match.groupCount; x++) {
              replaced = replaced.replaceAll("\$${x + 1}", match.group(x + 1)!);
            }
            return replaced;
          });
        }
        if (window.title.contains(rewrite.key)) {
          window.title = window.title.replaceAll(rewrite.key, rewrite.value);
        }
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
    if (list.length != icons.length) {
      icons.removeWhere((int key, Uint8List? value) => !list.any((Window w) => w.hWnd == key));
      iconsHandles.removeWhere((int key, int value) => !list.any((Window w) => w.hWnd == key));
    }

    for (Window win in list) {
      //?APPX
      if (icons.containsKey(win.hWnd) && win.isAppx) continue;
      if (win.isAppx) {
        if (win.appxIcon != "" && File(win.appxIcon).existsSync()) icons[win.hWnd] = File(win.appxIcon).readAsBytesSync();
        continue;
      }
      //?EXE
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
    }
    fetching = false;
    return true;
  }

  static List<int> getSpotify() {
    int spotifyHwnd = 0;
    int spotifyPID = 0;
    if (specialList.containsKey("Spotify")) {
      spotifyHwnd = specialList["Spotify"]!.hWnd;
      spotifyPID = specialList["Spotify"]!.process.pId;
    } else if (Globals.spotifyTrayHwnd[0] != 0) {
      spotifyHwnd = Globals.spotifyTrayHwnd[0];
      spotifyPID = Globals.spotifyTrayHwnd[1];
    }
    return <int>[spotifyHwnd, spotifyPID];
  }

  static bool mediaControl(int index, {int button = AppCommand.mediaPlayPause}) {
    int spotifyHwnd = 0;
    int spotifyPID = 0;
    if (specialList.containsKey("Spotify")) {
      spotifyHwnd = specialList["Spotify"]!.hWnd;
      spotifyPID = specialList["Spotify"]!.process.pId;
    } else if (Globals.spotifyTrayHwnd[0] != 0) {
      spotifyHwnd = Globals.spotifyTrayHwnd[0];
      spotifyPID = Globals.spotifyTrayHwnd[1];
    }

    if (list[index].process.exe == "Spotify.exe") {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    } else if (spotifyHwnd == 0) {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
    } else {
      Audio.enumAudioMixer().then((List<ProcessVolume>? e) async {
        List<ProcessVolume> elements = e as List<ProcessVolume>;
        final ProcessVolume spotifyMixer = elements.firstWhere((ProcessVolume element) => element.processId == spotifyPID, orElse: () => ProcessVolume()..maxVolume = -1);

        final double volume = spotifyMixer.maxVolume;
        if (spotifyMixer.maxVolume != -1) {
          await Audio.setAudioMixerVolume(spotifyPID, 0.1);
        }
        SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
        Future<void>.delayed(const Duration(milliseconds: 200), () async {
          if (button == AppCommand.mediaPlayPause) {
            SendMessage(spotifyHwnd, AppCommand.appCommand, 0, AppCommand.mediaStop);
          } else {
            SendMessage(spotifyHwnd, AppCommand.appCommand, 0, AppCommand.mediaPrevioustrack);
            SendMessage(spotifyHwnd, AppCommand.appCommand, 0, AppCommand.mediaStop);
          }

          if (spotifyMixer.maxVolume != -1) {
            Future<void>.delayed(const Duration(milliseconds: 500), () => Audio.setAudioMixerVolume(spotifyPID, volume));
          }
          return;
        });
      });
    }
    return true;
  }

  static List<int> hierarchy = <int>[];
  static void hierarchyAdd(int hWnd) {
    if (hierarchy.contains(hWnd)) hierarchy.remove(hWnd);
    hierarchy.insert(0, hWnd);
    if (hierarchy.length != list.length) {
      final List<int> listHwnds = list.map((Window e) => e.hWnd).toList();
      hierarchy.removeWhere((int element) => !listHwnds.contains(element));
      hierarchy.addAll(listHwnds.where((int element) => !hierarchy.contains(element)).toList());
    }
  }

  static void focusSecondWindow() {
    if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);
    if (Monitor.list.contains(monitor)) {
      final List<int> hWnds = list.where((Window element) => element.monitor == monitor).map((Window e) => e.hWnd).toList();
      if (hWnds.length > 1) {
        bool skippedFirst = false;
        for (int h in hierarchy) {
          if (hWnds.contains(h)) {
            if (!skippedFirst) {
              skippedFirst = true;
              continue;
            }
            Win32.activateWindow(h);
            Future<void>.delayed(const Duration(milliseconds: 200), () {
              if (GetForegroundWindow() != h) {
                Win32.activateWindow(h);
              }
            });
            return;
          }
        }
      }
    }
  }

  static playPauseSpotify() {
    if (specialList.containsKey("Spotify")) {
      SendMessage(specialList["Spotify"]!.hWnd, AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
    } else if (Globals.spotifyTrayHwnd[0] != 0) {
      SendMessage(Globals.spotifyTrayHwnd[0], AppCommand.appCommand, 0, AppCommand.mediaPlayPause);
    }
  }
}
