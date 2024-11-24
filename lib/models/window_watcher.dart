// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'package:tabamewin32/tabamewin32.dart';

import 'classes/boxes.dart';
import 'globals.dart';
import 'settings.dart';
import 'win32/imports.dart';
import 'win32/mixed.dart';
import 'win32/win32.dart';
import 'win32/window.dart';

class WindowWatcher {
  static bool firstEverRun = true;
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
    if (firstEverRun) Debug.add("QuickMenu: enumWindows");
    final List<int> winHWNDS = enumWindows();
    final List<int> allHWNDs = <int>[];
    if (winHWNDS.isEmpty) print("ENUM WINDS IS EMPTY");

    for (int hWnd in winHWNDS) {
      if (Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd).isNotEmpty && hWnd != Win32.getMainHandle() && !<String>["PopupHost"].contains(Win32.getTitle(hWnd))) {
        allHWNDs.add(hWnd);
      }
    }
    if (firstEverRun) Debug.add("QuickMenu: Wins ${allHWNDs.length}");
    final List<Window> newList = <Window>[];

    if (firstEverRun) Debug.add("QuickMenu: adding Win");
    for (int element in allHWNDs) {
      newList.add(Window(element));

      if (newList.last.process.exe == "Spotify.exe") {
        specialList["Spotify"] = newList.last;
        if (Boxes.pref.getString("SpotifyLocation") == null) {
          Boxes.pref.setString("SpotifyLocation", newList.last.process.exePath);
          if (firstEverRun) Debug.add("QuickMenu: Spotify");
        }
      }
      if (newList.last.process.exe == "foobar2000.exe") {
        specialList["Foobar"] = newList.last;
        if (Boxes.pref.getString("FoobarLocation") == null) {
          Boxes.pref.setString("FoobarLocation", newList.last.process.exePath);
          if (firstEverRun) Debug.add("QuickMenu: Foobar");
        }
      }
      if (newList.last.process.exe == "MusicBee.exe") {
        specialList["MusicBee"] = newList.last;
        if (Boxes.pref.getString("MusicBeeLocation") == null) {
          Boxes.pref.setString("MusicBeeLocation", newList.last.process.exePath);
          if (firstEverRun) Debug.add("QuickMenu: MusicBee");
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
    await orderBy(globalSettings.taskBarAppsStyle);
    firstEverRun = false;
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
        icons[win.hWnd] = WinUtils.windowIcon(win.hWnd);
        if (<Object>[icons[win.hWnd] ?? 0].length == 3) {
          icons[win.hWnd] = WinUtils.extractIcon(win.process.path + win.process.exe);
          printError(win.title);
        } else {
          printWarning(win.title);
        }
        iconsHandles[win.hWnd] = win.process.iconHandle;
      }
    }
    return true;
  }

  static Future<bool> orderBy(TaskBarAppsStyle type) async {
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

  static List<int> getFoobar() {
    int foobarHwnd = 0;
    int foobarPID = 0;
    if (specialList.containsKey("Foobar")) {
      foobarHwnd = specialList["Foobar"]!.hWnd;
      foobarPID = specialList["Foobar"]!.process.pId;
    } else if (Globals.foobarTrayHwnd[0] != 0) {
      foobarHwnd = Globals.foobarTrayHwnd[0];
      foobarPID = Globals.foobarTrayHwnd[1];
    }
    return <int>[foobarHwnd, foobarPID];
  }

  static List<int> getMusicBee() {
    int musicBeeHwnd = 0;
    int musicBeePID = 0;
    if (specialList.containsKey("MusicBee")) {
      musicBeeHwnd = specialList["MusicBee"]!.hWnd;
      musicBeePID = specialList["MusicBee"]!.process.pId;
    } else if (Globals.musicBeeTrayHwnd[0] != 0) {
      musicBeeHwnd = Globals.musicBeeTrayHwnd[0];
      musicBeePID = Globals.musicBeeTrayHwnd[1];
    }
    return <int>[musicBeeHwnd, musicBeePID];
  }

  static bool mediaControl(int index, {int button = AppCommand.mediaPlayPause}) {
    if (!globalSettings.pauseSpotifyWhenPlaying) {
      SendMessage(list[index].hWnd, AppCommand.appCommand, 0, button);
      return true;
    }
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
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        final List<int> hWnds = list.where((Window element) => element.monitor == monitor && !element.isPinned).map((Window e) => e.hWnd).toList();
        if (hWnds.length > 1) {
          final int h = hWnds[1];
          Win32.activateWindow(h);
          Future<void>.delayed(const Duration(milliseconds: 200), () {
            if (GetForegroundWindow() != h) {
              Win32.activateWindow(h);
            }
          });
          return;
        }
      }
    });
  }

  /// Shows the second window under the cursor.
  ///
  /// This function delays the execution for 100 milliseconds and then retrieves
  /// the current cursor position. It then checks if the cursor is within the
  /// boundaries of any windows and activates the second window found. If the
  /// second window cannot be activated, it waits for an additional 200
  /// milliseconds and tries again.
  static void showSecondWindowUnderCursor() {
    Win32.activeWindowUnderCursor();
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      if (hierarchy.isEmpty) hierarchy = list.map((Window e) => e.hWnd).toList();
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      final PointXY mousePos = PointXY(X: lpPoint.ref.x, Y: lpPoint.ref.y);

      final int monitor = MonitorFromPoint(lpPoint.ref, 0);
      free(lpPoint);
      if (Monitor.list.contains(monitor)) {
        final List<int> hWnds = list.where((Window element) => element.monitor == monitor && !element.isPinned).map((Window e) => e.hWnd).toList();
        if (hWnds.length > 1) {
          final int activeHandle = Win32.getActiveWindowHandle();
          //loop through hWnds and find the second one
          for (int i = 1; i < hWnds.length; i++) {
            final int h = hWnds[i];
            if (h == activeHandle) {
              continue;
            }
            final Square rect = Win32.getWindowRect(hwnd: h);
            if (mousePos.X.isBetween(rect.x, rect.x + rect.width) && mousePos.Y.isBetween(rect.y, rect.y + rect.height)) {
              Win32.activateWindow(h);
              Future<void>.delayed(const Duration(milliseconds: 200), () => GetForegroundWindow() != h ? Win32.activateWindow(h) : null);
              return;
            }
          }
          focusSecondWindow();
          return;
        }
        focusSecondWindow();
      }
    });
  }

  static triggerSpotify({int button = AppCommand.mediaPlayPause}) {
    final List<int> sp = getSpotify();
    if (sp[0] != 0) {
      SendMessage(sp[0], AppCommand.appCommand, 0, button);
    }
  }
}
