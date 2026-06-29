enum LauncherSearchMode {
  mixed,
  actionsOnly,
  filesOnly,
  windowsOnly,
  browserTabsOnly,
  bookmarksOnly,
  bookmarkOnly,
  cliOnly,
  appsOnly,
  desktopOnly,
  notionOnly,
  obsidianOnly,
  steamOnly,
  terminalOnly,
  timerCommand,
  functionCommand,
}

class LauncherQuery {
  const LauncherQuery({
    required this.raw,
    required this.normalized,
    required this.mode,
  });

  final String raw;
  final String normalized;
  final LauncherSearchMode mode;

  String get lower => normalized.toLowerCase();
  bool get isEmpty => raw.isEmpty || (normalized.isEmpty && mode == LauncherSearchMode.mixed);

  static LauncherQuery parse(String query) {
    final LauncherSearchMode mode = _modeFor(query);
    return LauncherQuery(
      raw: query,
      normalized: _normalizedFor(query),
      mode: mode,
    );
  }

  static LauncherSearchMode _modeFor(String query) {
    if (query.startsWith('/')) return LauncherSearchMode.actionsOnly;
    if (query.startsWith(r'$')) return LauncherSearchMode.functionCommand;
    if (query.startsWith('.')) return LauncherSearchMode.windowsOnly;
    if (query.startsWith(',')) return LauncherSearchMode.browserTabsOnly;
    if (query.startsWith(';')) return LauncherSearchMode.desktopOnly;
    if (query.startsWith('timer ')) return LauncherSearchMode.timerCommand;
    if (query.startsWith('n ')) return LauncherSearchMode.notionOnly;
    if (query.startsWith('o ')) return LauncherSearchMode.obsidianOnly;
    if (query.startsWith('s ')) return LauncherSearchMode.steamOnly;
    if (query.startsWith('cli ')) return LauncherSearchMode.cliOnly;
    if (query.startsWith('app ')) return LauncherSearchMode.appsOnly;
    if (query.startsWith('b ')) return LauncherSearchMode.bookmarkOnly;
    if (query.startsWith('>') || query.startsWith('?') || query.startsWith(' ')) {
      return LauncherSearchMode.filesOnly;
    }
    if (query.startsWith("'")) return LauncherSearchMode.bookmarksOnly;
    return LauncherSearchMode.mixed;
  }

  static String _normalizedFor(String query) {
    if (query.startsWith('timer ')) return query.substring(6).trimLeft();
    if (query.startsWith('cli ')) return query.substring(4).trimLeft();
    if (query.startsWith('app ')) return query.substring(4).trimLeft();
    if (query.startsWith('n ')) return query.substring(2).trimLeft();
    if (query.startsWith('o ')) return query.substring(2).trimLeft();
    if (query.startsWith('s ')) return query.substring(2).trimLeft();
    if (query.startsWith('b ')) return query.substring(2).trimLeft();
    if (query.startsWith('/') ||
        query.startsWith('.') ||
        query.startsWith(',') ||
        query.startsWith(r'$') ||
        query.startsWith('>') ||
        query.startsWith('?') ||
        query.startsWith(';') ||
        query.startsWith(' ') ||
        query.startsWith("'")) {
      return query.substring(1).trimLeft();
    }
    return query;
  }
}
