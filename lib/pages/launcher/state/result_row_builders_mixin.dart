part of '../../launcher.dart';

// ignore_for_file: annotate_overrides

// ---------------------------------------------------------------------------
// Result row builders
// ---------------------------------------------------------------------------

mixin _ResultRowBuildersMixin on _LauncherStateMembersMixin {
  // ---------------------------------------------------------------------------
  // Item builders (delegate to split widget files)
  // ---------------------------------------------------------------------------
  Widget _buildShortcutResult(BuildContext context, ThemeData theme, LauncherShortcut shortcut, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (_design == LauncherDesign.newCast) {
      return LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: onSurface,
        onTap: () => _onShortcutPressed(shortcut),
        onHover: () => _selectResultFromMouse(index),
        icon: Icon(shortcut.icon, size: 15, color: accent),
        title: shortcut.caption,
        subtitle: shortcut.label,
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _onShortcutPressed(shortcut),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(shortcut.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      shortcut.caption,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      shortcut.opensPluginManager
                          ? 'Install, enable, or disable launcher plugins'
                          : 'Press ${!shortcut.label.startsWith('>') && shortcut.label.length > 1 ? "'${shortcut.label}'" : shortcut.label} to open',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.keyboard_return_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkResult(BuildContext context, ThemeData theme, BookmarkSearchResult result, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return BookmarkSearchListItem(
      result: result,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openBookmarkResult(result),
      onHover: () => _selectResultFromMouse(index),
    );
  }

  Widget _buildFileResult(BuildContext context, ThemeData theme, FileSystemEntity entity, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final VoidCallback onTap = (_searchMode == LauncherSearchMode.desktopOnly && entity is Directory)
        ? () => _browseFolder(entity.path)
        : () => _openFile(entity.path, nodeId: nodeId);

    // Read the active design from the nearest LauncherTheme instead of _design.
    return LauncherListItem(
      entity: entity,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      isInHistory: false,
      onTap: onTap,
      onHover: () => _selectResultFromMouse(index),
      onRemoveFromHistory: () {},
    );
  }

  Widget _buildAppResult(BuildContext context, ThemeData theme, LauncherAppResult app, int? nodeId, int index,
      bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return LauncherAppListItem(
      app: app,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openAppResult(app, nodeId: nodeId),
      onHover: () => _selectResultFromMouse(index),
    );
  }

  Widget _buildNotionResult(
      BuildContext context, ThemeData theme, NotionResult result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (_design == LauncherDesign.newCast) {
      return LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: onSurface,
        onTap: () => _openNotionResult(result),
        onHover: () => _selectResultFromMouse(index),
        icon: result.emojiIcon != null
            ? Text(result.emojiIcon!, style: const TextStyle(fontSize: 14))
            : Icon(Icons.description_outlined, size: 15, color: accent),
        title: result.title,
        subtitle: 'Notion · ${result.objectType}',
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openNotionResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: result.emojiIcon != null
                    ? Text(result.emojiIcon!, style: const TextStyle(fontSize: 16))
                    : Icon(Icons.description_outlined, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'NOTION ${result.objectType.toUpperCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildObsidianResult(
      BuildContext context, ThemeData theme, ObsidianNote result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (_design == LauncherDesign.newCast) {
      return LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: onSurface,
        onTap: () => _openObsidianResult(result),
        onHover: () => _selectResultFromMouse(index),
        icon: Icon(Icons.menu_book_rounded, size: 15, color: accent),
        title: result.name,
        subtitle: result.folder.isEmpty ? 'Obsidian · Vault root' : 'Obsidian · ${result.folder}',
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openObsidianResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 40 : 20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.menu_book_rounded, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'OBSIDIAN · ${result.folder.isEmpty ? "VAULT ROOT" : result.folder.toUpperCase()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.open_in_new_rounded, size: 14, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSteamResult(
      BuildContext context, ThemeData theme, SteamGame result, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (_design == LauncherDesign.newCast) {
      final Widget icon = result.coverPath != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.file(
                File(result.coverPath!),
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                cacheWidth: 54,
                errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                    Icon(Icons.sports_esports_rounded, size: 15, color: accent),
              ),
            )
          : Icon(Icons.sports_esports_rounded, size: 15, color: accent);
      return LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: onSurface,
        onTap: () => _openSteamResult(result),
        onHover: () => _selectResultFromMouse(index),
        icon: icon,
        title: result.name,
        subtitle: result.sizeLabel.isEmpty ? 'Steam' : 'Steam · ${result.sizeLabel}',
      );
    }

    Widget leading;
    if (result.coverPath != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(result.coverPath!),
          width: 26,
          height: 34,
          fit: BoxFit.cover,
          cacheWidth: 78,
          gaplessPlayback: true,
          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
              Icon(Icons.sports_esports_rounded, size: 18, color: accent),
        ),
      );
    } else {
      leading = Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withAlpha(isSelected ? 40 : 20),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.sports_esports_rounded, size: 18, color: accent),
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: GestureDetector(
        onTap: () => _openSteamResult(result),
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
          curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? theme.highlightColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      result.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      result.sizeLabel.isEmpty ? 'STEAM' : 'STEAM · ${result.sizeLabel}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: onSurface.withAlpha(140),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, size: 16, color: accent.withAlpha(180)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoResult(BuildContext context, ThemeData theme, LauncherInfoResult result, int index, bool isSelected,
      bool isRepeatingKey) {
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    if (_design == LauncherDesign.newCast) {
      return LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: onSurface,
        onTap: () {},
        onHover: () => _selectResultFromMouse(index),
        icon: Icon(result.icon, size: 15, color: accent),
        title: result.title,
        subtitle: result.subtitle,
      );
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
        curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.highlightColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withAlpha(isSelected ? 40 : 20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(result.icon, size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    result.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    result.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: onSurface.withAlpha(140),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionResult(BuildContext context, ThemeData theme, QuickActionMenuEntry quickAction, int index,
      bool isSelected, bool isRepeatingKey) {
    // final GlobalKey actionKey = _quickActionKeys.putIfAbsent(quickAction.id, () => GlobalKey());
    final GlobalKey? actionKey = _quickActionKeys[quickAction.id];
    final Color accent = Design.accent;
    final bool showSplash = _quickActionSplashId == quickAction.id;

    if (_design == LauncherDesign.newCast) {
      final Widget resultRow = LauncherResultRow(
        isSelected: isSelected,
        isRepeating: isRepeatingKey,
        accent: accent,
        onSurface: theme.colorScheme.onSurface,
        onTap: () => _runQuickAction(quickAction),
        onHover: () => _selectResultFromMouse(index),
        icon: Icon(Icons.bolt_rounded, size: 15, color: accent),
        title: quickAction.title,
      );

      // Some legacy quick actions expose their behavior only through the
      // tappable widget returned by [builder]. Keep that widget mounted offstage
      // so both the row tap and keyboard submission can use the shared fallback
      // executor without changing the NewCast row visuals.
      if (quickAction.onExecute == null && quickAction.allowRenderedFallbackExecute && actionKey != null) {
        return Stack(
          children: <Widget>[
            resultRow,
            Offstage(
              child: KeyedSubtree(
                key: actionKey,
                child: quickAction.builder(context),
              ),
            ),
          ],
        );
      }

      return resultRow;
    }

    return MouseRegion(
      onHover: (PointerHoverEvent event) => _selectResultFromPointerHover(event, index),
      child: AnimatedContainer(
        duration: Duration(milliseconds: isRepeatingKey ? 50 : 200),
        curve: isRepeatingKey ? Curves.linear : Curves.easeOutCubic,
        key: ValueKey<String>(quickAction.id),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(0),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: showSplash
              ? accent.withAlpha(90)
              : isSelected
                  ? theme.highlightColor
                  : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: KeyedSubtree(
          key: actionKey,
          child: quickAction.builder(context),
        ),
      ),
    );
  }

  Widget _buildWindowResult(
      BuildContext context, ThemeData theme, PlatformWindow window, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return WindowSearchListItem(
      window: window,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openWindow(window),
      onHover: () => _selectWindowResultFromMouse(index, window),
    );
  }

  Widget _buildBrowserTabResult(
      BuildContext context, ThemeData theme, BrowserTab browserTab, int index, bool isSelected, bool isRepeatingKey) {
    final Color accent = Design.accent;
    return BrowserTabSearchListItem(
      browserTab: browserTab,
      isSelected: isSelected,
      isRepeating: isRepeatingKey,
      accent: accent,
      onSurface: theme.colorScheme.onSurface,
      onTap: () => _openBrowserTab(browserTab),
      onHover: () => _selectResultFromMouse(index),
    );
  }
}
