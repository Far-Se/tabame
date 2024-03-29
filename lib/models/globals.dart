// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'package:flutter/material.dart';

class Heights {
  double taskbar = 0;
  double traybar = 0;
  double topbar = 0;
  double get allSummed => taskbar + traybar + topbar;
  Heights();

  @override
  String toString() => 'Heights(taskbar: $taskbar, traybar: $traybar, topbar: $topbar)';
}

enum Pages {
  quickmenu,
  interface,
  run,
  views,
  quickActions,
}

enum QuickMenuPage {
  quickMenu,
  quickRun,
  quickActions,
}

class Globals {
  static QuickMenuPage quickMenuPage = QuickMenuPage.quickMenu;
  static bool debugHooks = false;
  static bool debugHotkeys = false;
  static String version = "1.3";

  static int virtualDesktop = 0;

  Globals();
  static bool changingPages = false;
  static bool isWindowActive = false;
  static final Heights heights = Heights();

  static int lastFocusedWinHWND = 0;
  static List<int> spotifyTrayHwnd = <int>[0, 0];
  static bool alwaysAwake = false;
  static bool audioBoxVisible = false;

  static bool taskbarVisible = true;
  static GlobalKey quickMenu = GlobalKey();

  static Pages lastPage = Pages.quickmenu;
  static Pages _currentPage = Pages.quickmenu;
  static Pages get currentPage => _currentPage;
  static set currentPage(Pages page) {
    lastPage = _currentPage;
    _currentPage = page;
  }
}
