import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import 'countdown_manager.dart';

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
  double pinnedAndTray = 0;
  double infoBar = 0;
  double get allSummed => taskbar + traybar + topbar + pinnedAndTray + infoBar;
  Heights();

  @override
  String toString() =>
      'Heights(taskbar: $taskbar, traybar: $traybar, topbar: $topbar, pinnedAndTray: $pinnedAndTray, infoBar: $infoBar)';
}

enum Pages {
  quickmenu,
  interface,
  views,
}

enum QuickMenuPage {
  quickMenu,
  launcher,
  quickSnap,
  fancyShotLive,
  fancyShotFreeze,
  colorPicker,
  emojiPicker,
  quickClick,
}

class Globals {
  Globals._();
  static final GlobalKey quickMenuKey = GlobalKey();
  static double quickMenuCurrentHeight = 0;
  static Size launcherCurrentSize = Size.zero;

  static ({double width, double height}) quickMenuSize = (width: 355, height: 555);
  static ({double width, double height}) launcherSize = (width: 715, height: 555);
  static QuickMenuPage quickMenuPage = QuickMenuPage.quickMenu;
  static bool debugHooks = true;
  static bool debugHotkeys = true;
  static String version = "v2.0";
  static WinRect? focusedRect;
  static int virtualDesktop = 0;

  static const int totalGradients = 12;
  static bool changingPages = false;
  static bool isWindowActive = false;
  static final Heights heights = Heights();
  static final CountdownManager countdownManager = CountdownManager();
  static Map<int, List<int>> snappedWindowOriginalSizes = <int, List<int>>{};

  static int lastFocusedWinHWND = 0;
  static bool alwaysAwake = false;
  static bool mouseJiggler = false;
  static bool audioBoxVisible = false;

  static bool taskbarVisible = true;
  static GlobalKey quickMenu = GlobalKey();
  static ValueNotifier<bool> fullLoaded = ValueNotifier<bool>(false);
  static ValueNotifier<bool> themeChangeNotifier = ValueNotifier<bool>(false);
  static ValueNotifier<int> quickMenuSearchInputVersion = ValueNotifier<int>(0);
  static PageController mainPageViewController = PageController();
  static String _pendingQuickMenuSearchInput = "";
  static String _pendingLauncherQuickAction = "";
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

  static void setQuickMenuSearchInput(String input) {
    if (input.isEmpty) return;
    _pendingQuickMenuSearchInput = input;
    quickMenuSearchInputVersion.value++;
  }

  static void setLauncherQuickAction(String actionName) {
    final String normalized = actionName.trim();
    if (normalized.isEmpty) return;
    _pendingLauncherQuickAction = normalized;
    _pendingQuickMenuSearchInput = "/$normalized";
    quickMenuSearchInputVersion.value++;
  }

  static void setLauncherPretext(String actionName) {
    final String normalized = actionName.trim();
    if (normalized.isEmpty) return;
    _pendingLauncherQuickAction = normalized;
    _pendingQuickMenuSearchInput = "$normalized";
    quickMenuSearchInputVersion.value++;
  }

  static String takeQuickMenuSearchInput() {
    final String value = _pendingQuickMenuSearchInput;
    _pendingQuickMenuSearchInput = "";
    return value;
  }

  static String takeLauncherQuickAction() {
    final String value = _pendingLauncherQuickAction;
    _pendingLauncherQuickAction = "";
    return value;
  }

  static void clearQuickMenuSearchInput() {
    _pendingQuickMenuSearchInput = "";
    _pendingLauncherQuickAction = "";
    quickMenuSearchInputVersion.value++;
  }
}
