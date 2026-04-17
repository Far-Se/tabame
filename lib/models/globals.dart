import 'package:flutter/material.dart';

void printWarning(String text) {
  print('\x1B[33m$text\x1B[0m');
}

void printError(String text) {
  print('\x1B[31m$text\x1B[0m');
}

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
  views,
}

enum QuickMenuPage {
  quickMenu,
  fileSearch,
  quickActions,
  audioBox,
}

class Globals {
  Globals._();
  static QuickMenuPage quickMenuPage = QuickMenuPage.quickMenu;
  static bool debugHooks = true;
  static bool debugHotkeys = true;
  static String version = "2.0";

  static int virtualDesktop = 0;

  static bool changingPages = false;
  static bool isWindowActive = false;
  static final Heights heights = Heights();

  static int lastFocusedWinHWND = 0;
  static bool alwaysAwake = false;
  static bool audioBoxVisible = false;

  static bool taskbarVisible = true;
  static GlobalKey quickMenu = GlobalKey();
  static ValueNotifier<bool> fullLoaded = ValueNotifier<bool>(false);
  static ValueNotifier<bool> themeChangeNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<int> quickMenuSearchInputVersion = ValueNotifier<int>(0);
  static PageController mainPageViewController = PageController();
  static String _pendingQuickMenuSearchInput = "";
  static String lastQuickSnapZoneId = "";

  static Pages lastPage = Pages.quickmenu;
  static Pages _currentPage = Pages.quickmenu;
  static Pages get currentPage => _currentPage;
  static set currentPage(Pages page) {
    lastPage = _currentPage;
    _currentPage = page;
  }

  static void queueQuickMenuSearchInput(String input) {
    if (input.isEmpty) return;
    _pendingQuickMenuSearchInput += input;
    quickMenuSearchInputVersion.value++;
  }

  static String takeQuickMenuSearchInput() {
    final String value = _pendingQuickMenuSearchInput;
    _pendingQuickMenuSearchInput = "";
    return value;
  }

  static void clearQuickMenuSearchInput() {
    _pendingQuickMenuSearchInput = "";
    quickMenuSearchInputVersion.value++;
  }
}
