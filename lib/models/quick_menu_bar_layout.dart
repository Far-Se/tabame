import 'dart:convert';

enum QuickMenuBarItem {
  quickActions('Quick actions'),
  pinnedApps('Pinned apps'),
  trayIcons('Tray icons');

  const QuickMenuBarItem(this.label);

  final String label;
}

enum QuickMenuBarPosition { top, bottom }

enum QuickMenuMergeMode {
  separate('Keep all separate'),
  pinnedAndTray('Pinned apps + tray icons'),
  quickActionsAndPinned('Quick actions + pinned apps'),
  quickActionsAndTray('Quick actions + tray icons'),
  all('Merge all three');

  const QuickMenuMergeMode(this.label);

  final String label;
}

class QuickMenuBarGroup {
  const QuickMenuBarGroup({required this.items, required this.position});

  final List<QuickMenuBarItem> items;
  final QuickMenuBarPosition position;

  String get id => items.first.name;

  String get label => items.map((QuickMenuBarItem item) => item.label).join(' + ');

  bool contains(QuickMenuBarItem item) => items.contains(item);
}

/// Saved composition and placement for the three QuickMenu utility sources.
/// Positions are stored per source, then normalized so merged sources always
/// use the same position.
class QuickMenuBarLayout {
  const QuickMenuBarLayout({
    this.mergeMode = QuickMenuMergeMode.separate,
    this.quickActionsPosition = QuickMenuBarPosition.top,
    this.pinnedAppsPosition = QuickMenuBarPosition.bottom,
    this.trayIconsPosition = QuickMenuBarPosition.bottom,
  });

  final QuickMenuMergeMode mergeMode;
  final QuickMenuBarPosition quickActionsPosition;
  final QuickMenuBarPosition pinnedAppsPosition;
  final QuickMenuBarPosition trayIconsPosition;

  static const QuickMenuBarLayout defaultLayout = QuickMenuBarLayout();

  factory QuickMenuBarLayout.fromJson(
    String? encoded, {
    bool legacyQuickActionsAtBottom = false,
    bool legacyBottomBarOnTop = false,
    bool legacyMergePinnedTray = false,
  }) {
    if (encoded == null || encoded.isEmpty) {
      return QuickMenuBarLayout._fromLegacy(
        quickActionsAtBottom: legacyQuickActionsAtBottom,
        bottomBarOnTop: legacyBottomBarOnTop,
        mergePinnedTray: legacyMergePinnedTray,
      );
    }

    try {
      final Map<String, dynamic> map = jsonDecode(encoded) as Map<String, dynamic>;
      final QuickMenuMergeMode mode = QuickMenuMergeMode.values.firstWhere(
        (QuickMenuMergeMode value) => value.name == map['mergeMode'],
        orElse: () => QuickMenuMergeMode.separate,
      );
      final Map<String, dynamic> positions =
          map['positions'] is Map<String, dynamic> ? map['positions'] as Map<String, dynamic> : <String, dynamic>{};

      return QuickMenuBarLayout(
        mergeMode: mode,
        quickActionsPosition: _parsePosition(positions['quickActions'], QuickMenuBarPosition.top),
        pinnedAppsPosition: _parsePosition(positions['pinnedApps'], QuickMenuBarPosition.bottom),
        trayIconsPosition: _parsePosition(positions['trayIcons'], QuickMenuBarPosition.bottom),
      )._normalized();
    } catch (_) {
      return QuickMenuBarLayout._fromLegacy(
        quickActionsAtBottom: legacyQuickActionsAtBottom,
        bottomBarOnTop: legacyBottomBarOnTop,
        mergePinnedTray: legacyMergePinnedTray,
      );
    }
  }

  static QuickMenuBarPosition _parsePosition(Object? value, QuickMenuBarPosition fallback) {
    return QuickMenuBarPosition.values.firstWhere(
      (QuickMenuBarPosition position) => position.name == value,
      orElse: () => fallback,
    );
  }

  factory QuickMenuBarLayout._fromLegacy({
    required bool quickActionsAtBottom,
    required bool bottomBarOnTop,
    required bool mergePinnedTray,
  }) {
    final QuickMenuMergeMode legacyMergeMode = bottomBarOnTop
        ? QuickMenuMergeMode.all
        : mergePinnedTray
            ? QuickMenuMergeMode.pinnedAndTray
            : QuickMenuMergeMode.separate;
    final QuickMenuBarPosition legacyPosition = bottomBarOnTop
        ? QuickMenuBarPosition.top
        : quickActionsAtBottom
            ? QuickMenuBarPosition.bottom
            : QuickMenuBarPosition.top;
    return QuickMenuBarLayout(
      mergeMode: legacyMergeMode,
      quickActionsPosition: legacyPosition,
      pinnedAppsPosition: bottomBarOnTop ? QuickMenuBarPosition.top : QuickMenuBarPosition.bottom,
      trayIconsPosition: bottomBarOnTop ? QuickMenuBarPosition.top : QuickMenuBarPosition.bottom,
    );
  }

  QuickMenuBarPosition positionOf(QuickMenuBarItem item) {
    for (final QuickMenuBarGroup group in groups) {
      if (group.contains(item)) return group.position;
    }
    return QuickMenuBarPosition.bottom;
  }

  List<QuickMenuBarGroup> get groups {
    final List<List<QuickMenuBarItem>> members = switch (mergeMode) {
      QuickMenuMergeMode.separate => <List<QuickMenuBarItem>>[
          <QuickMenuBarItem>[QuickMenuBarItem.quickActions],
          <QuickMenuBarItem>[QuickMenuBarItem.pinnedApps],
          <QuickMenuBarItem>[QuickMenuBarItem.trayIcons],
        ],
      QuickMenuMergeMode.pinnedAndTray => <List<QuickMenuBarItem>>[
          <QuickMenuBarItem>[QuickMenuBarItem.quickActions],
          <QuickMenuBarItem>[QuickMenuBarItem.pinnedApps, QuickMenuBarItem.trayIcons],
        ],
      QuickMenuMergeMode.quickActionsAndPinned => <List<QuickMenuBarItem>>[
          <QuickMenuBarItem>[QuickMenuBarItem.quickActions, QuickMenuBarItem.pinnedApps],
          <QuickMenuBarItem>[QuickMenuBarItem.trayIcons],
        ],
      QuickMenuMergeMode.quickActionsAndTray => <List<QuickMenuBarItem>>[
          <QuickMenuBarItem>[QuickMenuBarItem.quickActions, QuickMenuBarItem.trayIcons],
          <QuickMenuBarItem>[QuickMenuBarItem.pinnedApps],
        ],
      QuickMenuMergeMode.all => <List<QuickMenuBarItem>>[
          <QuickMenuBarItem>[
            QuickMenuBarItem.quickActions,
            QuickMenuBarItem.pinnedApps,
            QuickMenuBarItem.trayIcons,
          ],
        ],
    };

    return <QuickMenuBarGroup>[
      for (final List<QuickMenuBarItem> items in members)
        QuickMenuBarGroup(items: items, position: _groupPosition(items)),
    ];
  }

  List<QuickMenuBarGroup> groupsAt(QuickMenuBarPosition position) =>
      groups.where((QuickMenuBarGroup group) => group.position == position).toList();

  QuickMenuBarGroup? groupFor(QuickMenuBarItem item) {
    for (final QuickMenuBarGroup group in groups) {
      if (group.contains(item)) return group;
    }
    return null;
  }

  bool get quickActionsAtBottom => positionOf(QuickMenuBarItem.quickActions) == QuickMenuBarPosition.bottom;

  bool get quickActionsAtTop => !quickActionsAtBottom;

  bool get quickActionsMerged => (groupFor(QuickMenuBarItem.quickActions)?.items.length ?? 1) > 1;

  bool get pinnedTrayAtTop =>
      positionOf(QuickMenuBarItem.pinnedApps) == QuickMenuBarPosition.top ||
      positionOf(QuickMenuBarItem.trayIcons) == QuickMenuBarPosition.top;

  bool get hasContentAtTop => groups.any((QuickMenuBarGroup group) => group.position == QuickMenuBarPosition.top);

  bool get hasContentAtBottom => groups.any((QuickMenuBarGroup group) => group.position == QuickMenuBarPosition.bottom);

  bool get hasPinnedTrayAtTop => pinnedTrayAtTop;

  QuickMenuBarLayout withMergeMode(QuickMenuMergeMode value) {
    final QuickMenuBarLayout changed = QuickMenuBarLayout(
      mergeMode: value,
      quickActionsPosition: quickActionsPosition,
      pinnedAppsPosition: pinnedAppsPosition,
      trayIconsPosition: trayIconsPosition,
    );
    final Map<QuickMenuBarItem, QuickMenuBarPosition> nextPositions = <QuickMenuBarItem, QuickMenuBarPosition>{
      QuickMenuBarItem.quickActions: changed.quickActionsPosition,
      QuickMenuBarItem.pinnedApps: changed.pinnedAppsPosition,
      QuickMenuBarItem.trayIcons: changed.trayIconsPosition,
    };
    for (final List<QuickMenuBarItem> group in changed.groups.map((QuickMenuBarGroup group) => group.items)) {
      final QuickMenuBarItem leader = group.first;
      final QuickMenuBarPosition position = _positionForItem(leader);
      for (final QuickMenuBarItem item in group) {
        nextPositions[item] = position;
      }
    }
    return QuickMenuBarLayout(
      mergeMode: value,
      quickActionsPosition: nextPositions[QuickMenuBarItem.quickActions]!,
      pinnedAppsPosition: nextPositions[QuickMenuBarItem.pinnedApps]!,
      trayIconsPosition: nextPositions[QuickMenuBarItem.trayIcons]!,
    );
  }

  QuickMenuBarLayout withGroupPosition(QuickMenuBarGroup group, QuickMenuBarPosition position) {
    QuickMenuBarPosition nextQuickActionsPosition = quickActionsPosition;
    QuickMenuBarPosition nextPinnedAppsPosition = pinnedAppsPosition;
    QuickMenuBarPosition nextTrayIconsPosition = trayIconsPosition;
    for (final QuickMenuBarItem item in group.items) {
      switch (item) {
        case QuickMenuBarItem.quickActions:
          nextQuickActionsPosition = position;
        case QuickMenuBarItem.pinnedApps:
          nextPinnedAppsPosition = position;
        case QuickMenuBarItem.trayIcons:
          nextTrayIconsPosition = position;
      }
    }
    return QuickMenuBarLayout(
      mergeMode: mergeMode,
      quickActionsPosition: nextQuickActionsPosition,
      pinnedAppsPosition: nextPinnedAppsPosition,
      trayIconsPosition: nextTrayIconsPosition,
    );
  }

  String toJson() {
    final Map<String, String> positions = <String, String>{};
    for (final QuickMenuBarGroup group in groups) {
      for (final QuickMenuBarItem item in group.items) {
        positions[item.name] = group.position.name;
      }
    }
    return jsonEncode(<String, Object>{'mergeMode': mergeMode.name, 'positions': positions});
  }

  QuickMenuBarPosition _groupPosition(List<QuickMenuBarItem> items) => _positionForItem(items.first);

  QuickMenuBarPosition _positionForItem(QuickMenuBarItem item) {
    return switch (item) {
      QuickMenuBarItem.quickActions => quickActionsPosition,
      QuickMenuBarItem.pinnedApps => pinnedAppsPosition,
      QuickMenuBarItem.trayIcons => trayIconsPosition,
    };
  }

  QuickMenuBarLayout _normalized() {
    QuickMenuBarLayout result = this;
    for (final QuickMenuBarGroup group in groups) {
      result = result.withGroupPosition(group, group.position);
    }
    return result;
  }
}
