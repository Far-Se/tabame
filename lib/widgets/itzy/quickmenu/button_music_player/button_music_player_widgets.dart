part of '../button_music_player.dart';

class _TabSpec {
  const _TabSpec(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _TabButton extends StatefulWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;

  final VoidCallback onTap;

  @override
  State<_TabButton> createState() => _TabButtonState();
}

class _TabButtonState extends State<_TabButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

    final double targetScale = _pressed ? 0.94 : (_hovered ? 1.05 : 1.0);

    return CustomTooltip(
      message: widget.label,
      verticalOffset: 36,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: (_) => setState(() => _pressed = true),
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: reduceMotion ? 1.0 : targetScale,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              height: 32,
              decoration: BoxDecoration(
                gradient: widget.active
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Design.accent.withAlpha(45),
                          Design.accent.withAlpha(15),
                        ],
                      )
                    : null,
                color: widget.active ? null : (Theme.of(context).colorScheme.onSurface.withAlpha(_hovered ? 14 : 0)),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: widget.active
                      ? Design.accent.withAlpha(120)
                      : Theme.of(context).colorScheme.onSurface.withAlpha(_hovered ? 28 : 12),
                  width: 1,
                ),
                boxShadow: widget.active
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Design.accent.withAlpha(15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  widget.icon,
                  size: 17,
                  color: widget.active
                      ? Design.accent
                      : Theme.of(context).colorScheme.onSurface.withAlpha(_hovered ? 180 : 110),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimelineTimeLabel extends StatelessWidget {
  const _TimelineTimeLabel({
    required this.label,
  });

  final String label;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 32, maxWidth: 54),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: GoogleFonts.getFont(
            Design.entryFontFamily,
            fontSize: Design.baseFontSize + 0.5,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
            letterSpacing: 0.4,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _QueueEntry {
  const _QueueEntry({
    required this.index,
    required this.item,
  });

  final int index;
  final MusicItem item;

  bool matches(String query) {
    return item.title.toLowerCase().contains(query) ||
        (item.artist ?? "").toLowerCase().contains(query) ||
        (item.album ?? "").toLowerCase().contains(query);
  }
}

enum _SmartPlaylistType { topRated, mostPlayed, recentlyPlayed }

class _SmartPlaylistCategory {
  const _SmartPlaylistCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.type,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final _SmartPlaylistType type;
}

class _RowAction {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
}

class _CoverArt extends StatelessWidget {
  const _CoverArt({required this.item, required this.size});

  final MusicItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: Design.accent.withAlpha(20), borderRadius: BorderRadius.circular(12)),
      child:
          Icon(item.isFolder ? Icons.album_rounded : Icons.music_note_rounded, size: size * 0.38, color: Design.accent),
    );

    final String? localArtworkPath = size >= 96 ? item.localArtworkLargePath : item.localArtworkSmallPath;
    if (localArtworkPath != null && localArtworkPath.isNotEmpty && File(localArtworkPath).existsSync()) {
      return Image.file(
        File(localArtworkPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: size >= 96 ? 256 : 96,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (item.coverUrl == null || item.coverUrl!.isEmpty) return fallback;
    return Image.network(
      item.coverUrl!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: size >= 96 ? 256 : 96,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _MusicRow extends StatefulWidget {
  const _MusicRow({
    required this.item,
    required this.onTap,
    this.trailingActions = const <_RowAction>[],
  });

  final MusicItem item;

  final VoidCallback onTap;
  final List<_RowAction> trailingActions;

  @override
  State<_MusicRow> createState() => _MusicRowState();
}

class _MusicRowState extends State<_MusicRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !reduceMotion ? 1.006 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _hovered ? Design.accent.withAlpha(14) : Theme.of(context).colorScheme.onSurface.withAlpha(7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color:
                      _hovered ? Design.accent.withAlpha(52) : Theme.of(context).colorScheme.onSurface.withAlpha(14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _CoverArt(item: widget.item, size: widget.item.isFolder ? 36 : 46),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(widget.item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurface)),
                          ),
                          if (widget.item.duration != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(_durationLabel(widget.item.duration!),
                                  style: TextStyle(
                                      fontSize: Design.baseFontSize,
                                      color: Theme.of(context).colorScheme.onSurface.withAlpha(110))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _primaryMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
                      ),
                      if (_secondaryMeta != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          _secondaryMeta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 0.5,
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(102)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: widget.trailingActions
                      .map(
                        (_RowAction action) => Tooltip(
                          message: action.tooltip,
                          child: InkWell(
                            onTap: action.onTap,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(action.icon, size: 15, color: Design.accent),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _primaryMeta {
    if (!widget.item.isFolder) {
      return widget.item.artist?.trim().isNotEmpty == true ? widget.item.artist!.trim() : "Track";
    }
    return switch (widget.item.type) {
      MusicItemType.album => "Album",
      MusicItemType.artist => "Artist",
      MusicItemType.folder => "Folder",
      _ => "Library",
    };
  }

  String? get _secondaryMeta {
    if (!widget.item.isFolder) {
      final String album = widget.item.album?.trim() ?? '';
      return album.isEmpty ? null : album;
    }
    if (widget.item.type == MusicItemType.album && widget.item.artist?.trim().isNotEmpty == true) {
      return widget.item.artist!.trim();
    }
    return null;
  }

  static String _durationLabel(Duration duration) {
    return "${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}";
  }
}

class _PlaylistRow extends StatefulWidget {
  const _PlaylistRow({
    required this.playlist,
    required this.onTap,
    this.trailingActions = const <_RowAction>[],
  });

  final MusicPlaylist playlist;

  final VoidCallback onTap;
  final List<_RowAction> trailingActions;

  @override
  State<_PlaylistRow> createState() => _PlaylistRowState();
}

class _PlaylistRowState extends State<_PlaylistRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !reduceMotion ? 1.006 : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: duration,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _hovered ? Design.accent.withAlpha(14) : Theme.of(context).colorScheme.onSurface.withAlpha(8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color:
                      _hovered ? Design.accent.withAlpha(52) : Theme.of(context).colorScheme.onSurface.withAlpha(18)),
            ),
            child: Row(
              children: <Widget>[
                const _IconPill(icon: Icons.playlist_play_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(widget.playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Theme.of(context).colorScheme.onSurface)),
                      const SizedBox(height: 2),
                      Text("${widget.playlist.songCount} songs",
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 1,
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(130))),
                      const SizedBox(height: 2),
                      Text("${widget.playlist.duration.inMinutes} min total",
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 0.5,
                              color: Theme.of(context).colorScheme.onSurface.withAlpha(102))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: widget.trailingActions
                      .map(
                        (_RowAction action) => Tooltip(
                          message: action.tooltip,
                          child: InkWell(
                            onTap: action.onTap,
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: Icon(action.icon, size: 15, color: Design.accent),
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmartPlaylistRow extends StatelessWidget {
  const _SmartPlaylistRow({
    required this.category,
    required this.onTap,
  });

  final _SmartPlaylistCategory category;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Design.accent.withAlpha(36)),
        ),
        child: Row(
          children: <Widget>[
            _IconPill(icon: category.icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    category.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    category.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: Design.accent),
          ],
        ),
      ),
    );
  }
}

class _PlaylistPickerRow extends StatelessWidget {
  const _PlaylistPickerRow({
    required this.playlist,
    required this.onTap,
  });

  final MusicPlaylist playlist;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(14)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.playlist_add_check_rounded, size: 17, color: Design.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            Text(
              "${playlist.songCount}",
              style: TextStyle(
                  fontSize: Design.baseFontSize + 0.5,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(120)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QueueEditRow extends StatelessWidget {
  const _QueueEditRow({
    super.key,
    required this.item,
    required this.active,
    required this.onTap,
    required this.onRemove,
    required this.reorderable,
    this.index,
  });

  final MusicItem item;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool reorderable;
  final int? index;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return SizedBox(
      height: 40,
      child: Row(
        children: <Widget>[
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: <Widget>[
                    _CoverArt(item: item, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_queueLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: Design.baseFontSize + 1.5,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                              color: active ? onSurface : onSurface.withAlpha(155))),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Tooltip(
            message: "Remove from queue",
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 15, color: onSurface.withAlpha(130)),
              ),
            ),
          ),
          if (reorderable && index != null)
            ReorderableDragStartListener(
              index: index!,
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.drag_handle_rounded, size: 16, color: onSurface.withAlpha(110)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String get _queueLabel {
    final String? artist = item.artist?.trim();
    if (artist == null || artist.isEmpty) return item.title;
    return "$artist - ${item.title}";
  }
}

class _PlayerTrackMenuButton extends StatelessWidget {
  const _PlayerTrackMenuButton({
    required this.onSelected,
  });

  final ValueChanged<_PlayerTrackMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: "Track options",
      child: PopupMenuButton<_PlayerTrackMenuAction>(
        position: PopupMenuPosition.under,
        tooltip: "",
        color: Color.alphaBlend(Design.accent.withAlpha(16), Theme.of(context).colorScheme.surface),
        surfaceTintColor: Design.accent.withAlpha(30),
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        onSelected: onSelected,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<_PlayerTrackMenuAction>>[
          _trackMenuItem(Icons.person_search_rounded, "Go to Artist", _PlayerTrackMenuAction.artist),
          _trackMenuItem(Icons.album_rounded, "Go to Album", _PlayerTrackMenuAction.album),
          _trackMenuItem(Icons.folder_open_rounded, "Go to Folder", _PlayerTrackMenuAction.folder),
          _trackMenuItem(Icons.file_open_rounded, "Open File", _PlayerTrackMenuAction.file),
        ],
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withAlpha(8),
            shape: BoxShape.circle,
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(20)),
          ),
          child: Icon(Icons.more_vert_rounded, size: 18, color: Theme.of(context).colorScheme.onSurface.withAlpha(170)),
        ),
      ),
    );
  }

  PopupMenuItem<_PlayerTrackMenuAction> _trackMenuItem(
    IconData icon,
    String label,
    _PlayerTrackMenuAction action,
  ) {
    return PopupMenuItem<_PlayerTrackMenuAction>(
      value: action,
      height: 34,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: Design.accent),
          const SizedBox(width: 9),
          Text(label, style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TransportButton extends StatefulWidget {
  const _TransportButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.enabled = true,
    this.isPrimary = false,
    this.size = 38,
  });

  final IconData icon;

  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final bool enabled;
  final bool isPrimary;
  final double size;

  @override
  State<_TransportButton> createState() => _TransportButtonState();
}

class _TransportButtonState extends State<_TransportButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 140);

    final double targetScale = _pressed ? 0.92 : (_hovered ? 1.05 : 1.0);

    return CustomTooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: widget.enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: reduceMotion ? 1.0 : targetScale,
            duration: duration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                gradient: widget.isPrimary
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          Design.accent.withAlpha(220),
                          Design.accent.withAlpha(140),
                        ],
                      )
                    : null,
                color: widget.isPrimary
                    ? null
                    : (widget.active
                        ? Design.accent.withAlpha(30)
                        : Theme.of(context).colorScheme.onSurface.withAlpha(8)),
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.isPrimary
                      ? Design.accent.withAlpha(180)
                      : (widget.active
                          ? Design.accent.withAlpha(100)
                          : Theme.of(context).colorScheme.onSurface.withAlpha(20)),
                ),
                boxShadow: widget.isPrimary
                    ? <BoxShadow>[
                        BoxShadow(
                          color: Design.accent.withAlpha(_hovered ? 80 : 50),
                          blurRadius: _hovered ? 18 : 14,
                          offset: Offset(0, _hovered ? 6 : 5),
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInBack,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return ScaleTransition(scale: animation, child: FadeTransition(opacity: animation, child: child));
                },
                child: Icon(
                  widget.icon,
                  key: ValueKey<IconData>(widget.icon),
                  size: (widget.size * 0.52).clamp(16.0, 28.0),
                  color: widget.isPrimary
                      ? Theme.of(context).colorScheme.surface
                      : (widget.enabled
                          ? (widget.active ? Design.accent : Theme.of(context).colorScheme.onSurface.withAlpha(170))
                          : Theme.of(context).colorScheme.onSurface.withAlpha(55)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.count,
    this.hideCount = false,
  });

  final IconData icon;
  final String label;
  final int count;

  final bool hideCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.45,
                color: Theme.of(context).colorScheme.onSurface)),
        if (!hideCount) ...<Widget>[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Design.accent.withAlpha(24), borderRadius: BorderRadius.circular(999)),
            child: Text("$count",
                style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w800, color: Design.accent)),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withAlpha(20))),
      ],
    );
  }
}

class _IconPill extends StatelessWidget {
  const _IconPill({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: Design.accent.withAlpha(20), borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 17, color: Design.accent),
    );
  }
}

class _QuickLaunchTile extends StatefulWidget {
  const _QuickLaunchTile({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.onSurface,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;

  final Color onSurface;
  final List<_RowAction> actions;

  @override
  State<_QuickLaunchTile> createState() => _QuickLaunchTileState();
}

class _QuickLaunchTileState extends State<_QuickLaunchTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 150);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: duration,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? Design.accent.withAlpha(14) : widget.onSurface.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _hovered ? Design.accent.withAlpha(48) : widget.onSurface.withAlpha(14)),
        ),
        child: Row(
          children: <Widget>[
            _IconPill(icon: widget.icon),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: widget.onSurface)),
                  const SizedBox(height: 1),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: widget.onSurface.withAlpha(126)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.meta,
              style: TextStyle(fontSize: 9.5, color: widget.onSurface.withAlpha(98), fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 6),
            Wrap(
              spacing: 2,
              children: widget.actions
                  .map(
                    (_RowAction action) => Tooltip(
                      message: action.tooltip,
                      child: InkWell(
                        onTap: action.onTap,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(action.icon, size: 14, color: Design.accent),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({required this.icon, required this.onTap, this.accent});

  final IconData icon;
  final Color? accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 16, color: accent != null ? accent!.withAlpha(220) : Design.accent.withAlpha(220)),
      ),
    );
  }
}

class _InlinePanel extends StatelessWidget {
  const _InlinePanel({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withAlpha(8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(18))),
      child: Row(
        children: <Widget>[
          _IconPill(icon: icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(135))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 42, color: Design.accent.withAlpha(170)),
            const SizedBox(height: 12),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 5),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(140),
                    height: 1.25)),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 12),
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Design.background,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Design.accent.withAlpha(18),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 8),
            Expanded(
                child: Text(message,
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w700, color: Design.accent))),
            InkWell(
              onTap: onClose,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 14, color: Design.accent),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
