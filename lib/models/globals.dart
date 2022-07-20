class Heights {
  double taskbar = 0;
  double traybar = 0;
  double topbar = 0;
  double get allSummed => taskbar + traybar + topbar;
  Heights();
}

enum Pages {
  quickmenu,
  interface,
  run,
  views,
}

class Globals {
  Globals();
  static bool changingPages = false;
  static bool isWindowActive = false;
  static final Heights heights = Heights();
  static int lastFocusedWinHWND = 0;
  static bool alwaysAwake = false;
  static bool audioBoxVisible = false;
  static Pages lastPage = Pages.quickmenu;
  static Pages _currentPage = Pages.quickmenu;

  static bool taskbarVisible = true;
  static Pages get currentPage => _currentPage;
  static set currentPage(Pages page) {
    lastPage = _currentPage;
    _currentPage = page;
  }

  static bool quickMenuFullyInitiated = false;
}
