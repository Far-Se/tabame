// ignore_for_file: invalid_use_of_protected_member

part of '../button_music_player.dart';

extension _MusicServerPanelStateViews on _MusicServerPanelState {
  String _clipPlayerLabel(String value, {int maxChars = 40}) {
    final String normalized = value.trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars).trimRight()}...';
  }

  Widget _buildPlayerTab(Color accent) {
    return StreamBuilder<SequenceState?>(
      stream: MusicServerManager.player.sequenceStateStream,
      builder: (BuildContext context, AsyncSnapshot<SequenceState?> sequenceSnapshot) {
        final SequenceState? sequenceState = sequenceSnapshot.data;
        final MusicItem? item =
            sequenceState?.currentSource?.tag is MusicItem ? sequenceState!.currentSource!.tag as MusicItem : null;
        final int queueLength = sequenceState?.sequence.length ?? 0;
        final int currentIndex = (sequenceState?.currentIndex ?? 0) + 1;

        if (item == null) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _EmptyState(
                  icon: Icons.album_outlined,
                  title: "Nothing playing",
                  subtitle: "Start with a playlist or indexed folder.",
                ),
                if (_savedQueueAvailable) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildSavedQueueCard(accent),
                ],
                const SizedBox(height: 12),
              ],
            ),
          );
        }

        return Stack(
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                final Color surface = Theme.of(context).colorScheme.surface;
                final Color onSurface = Theme.of(context).colorScheme.onSurface;

                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Container(
                      // Deep immersive top-to-bottom gradient
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color.alphaBlend(accent.withAlpha(38), surface),
                            Color.alphaBlend(accent.withAlpha(18), surface),
                            surface,
                          ],
                          stops: const <double>[0.0, 0.45, 1.0],
                        ),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                          child: Stack(
                            children: <Widget>[
                              // More-menu aligned right
                              Positioned(
                                top: 0,
                                right: 0,
                                child: _PlayerTrackMenuButton(
                                  onSelected: (_PlayerTrackMenuAction action) =>
                                      _handlePlayerTrackMenuAction(action, item),
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  const SizedBox(height: 6),
                                  // Large centered cover art with coloured shadow
                                  Center(
                                    child: AnimatedSwitcher(
                                      duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 300),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeOutCubic,
                                      transitionBuilder: (Widget child, Animation<double> anim) => FadeTransition(
                                        opacity: anim,
                                        child: ScaleTransition(
                                          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                                            CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                                          ),
                                          child: child,
                                        ),
                                      ),
                                      child: KeyedSubtree(
                                        key: ValueKey<String>(item.id),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            boxShadow: <BoxShadow>[
                                              BoxShadow(
                                                color: accent.withAlpha(90),
                                                blurRadius: 32,
                                                offset: const Offset(0, 14),
                                                spreadRadius: -4,
                                              ),
                                              BoxShadow(
                                                color: Colors.black.withAlpha(55),
                                                blurRadius: 20,
                                                offset: const Offset(0, 8),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(18),
                                            child: _CoverArt(
                                              item: item,
                                              size: (constraints.maxWidth * 0.58).clamp(130.0, 160.0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 15),

                                  // Song title + artist + album — centered
                                  AnimatedSwitcher(
                                    duration: disableAnimations ? Duration.zero : const Duration(milliseconds: 220),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeOutCubic,
                                    child: KeyedSubtree(
                                      key: ValueKey<String>('meta_${item.id}'),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: <Widget>[
                                          Text(
                                            _clipPlayerLabel(item.title, maxChars: 52),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: baseEntryStyle.copyWith(
                                              fontSize: 20,
                                              height: 1.15,
                                              fontWeight: FontWeight.w800,
                                              color: onSurface,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          const SizedBox(height: 5),
                                          Text(
                                            _clipPlayerLabel(item.artist ?? "Unknown artist"),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: baseEntryStyle.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: accent,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          if (item.album != null) ...<Widget>[
                                            const SizedBox(height: 3),
                                            Text(
                                              item.album!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: baseEntryStyle.copyWith(
                                                fontSize: Design.baseFontSize + 1,
                                                color: onSurface.withAlpha(120),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),

                                  _buildTimeline(accent, item),
                                  const SizedBox(height: 8),
                                  _buildTransport(accent, sequenceState, item),
                                  const SizedBox(height: 12),
                                  _buildVolumeBar(accent),
                                  const SizedBox(height: 10),
                                  _buildUtilityRow(accent),
                                  const SizedBox(height: 14),
                                  _buildQueueButton(accent, queueLength, currentIndex),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_queueVisible) _buildQueuePreview(accent, sequenceState),
            if (_playlistPickerVisible) _buildPlaylistPicker(accent, item),
          ],
        );
      },
    );
  }

  Future<void> _handlePlayerTrackMenuAction(_PlayerTrackMenuAction action, MusicItem item) async {
    switch (action) {
      case _PlayerTrackMenuAction.artist:
        await _goToCurrentArtist(item);
      case _PlayerTrackMenuAction.album:
        await _goToCurrentAlbum(item);
      case _PlayerTrackMenuAction.folder:
        await _goToCurrentFolder(item);
      case _PlayerTrackMenuAction.file:
        _openCurrentFile(item);
    }
  }

  Future<void> _goToCurrentArtist(MusicItem item) async {
    final String artist = item.artist?.trim() ?? '';
    if (artist.isEmpty) {
      _showInfo("Current track has no artist.");
      return;
    }

    setState(() => _loading = true);
    try {
      final List<MusicItem> artists = await MusicServerManager.getArtists();
      final MusicItem? match = _findExactMusicItem(artists, artist, MusicItemType.artist);
      if (match == null) {
        await _search(artist);
        if (mounted) setState(() => _tabIndex = 1);
        _showInfo("Showing search results for $artist.");
        return;
      }

      final List<MusicItem> albums = await MusicServerManager.getAlbums(match.id);
      _history.add(_items);
      _historyPlaylistIds.add(_activePlaylistId);
      _items = albums;
      _activePlaylistId = null;
      _titles.add(match.title);
      if (mounted) setState(() => _tabIndex = 2);
    } catch (_) {
      _showInfo("Could not open artist.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goToCurrentAlbum(MusicItem item) async {
    final String album = item.album?.trim() ?? '';
    if (album.isEmpty) {
      _showInfo("Current track has no album.");
      return;
    }

    setState(() => _loading = true);
    try {
      final List<MusicItem> results = await MusicServerManager.search(album);
      final MusicItem match = results.where((MusicItem result) => result.type == MusicItemType.album).firstWhere(
        (MusicItem result) {
          final bool sameAlbum = _sameMusicLabel(result.title, album);
          final String artist = item.artist?.trim() ?? '';
          return sameAlbum && (artist.isEmpty || _sameMusicLabel(result.artist ?? '', artist));
        },
        orElse: () =>
            _findExactMusicItem(results, album, MusicItemType.album) ??
            results.firstWhere(
              (MusicItem result) => result.type == MusicItemType.album,
              orElse: () => item,
            ),
      );

      if (match.type != MusicItemType.album) {
        await _search(album);
        if (mounted) setState(() => _tabIndex = 1);
        _showInfo("Showing search results for $album.");
        return;
      }

      final List<MusicItem> songs = await MusicServerManager.getSongs(match.id);
      _history.add(_items);
      _historyPlaylistIds.add(_activePlaylistId);
      _items = songs;
      _activePlaylistId = null;
      _titles.add(match.title);
      if (mounted) setState(() => _tabIndex = 2);
    } catch (_) {
      _showInfo("Could not open album.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goToCurrentFolder(MusicItem item) async {
    final String folderPath = item.parentPath?.trim() ?? File(item.localPath ?? '').parent.path.trim();
    if (folderPath.isEmpty || item.localPath == null) {
      _showInfo("Folder navigation is only available for local tracks.");
      return;
    }

    setState(() => _loading = true);
    try {
      _folderHistory.add(_folderItems);
      _folderPathHistory.add(_activeFolderPath);
      _folderItems = await MusicServerManager.getMusicDirectory(folderPath);
      _activeFolderPath = folderPath;
      _folderTitles.add(Directory(folderPath).uri.pathSegments.where((String segment) => segment.isNotEmpty).last);
      if (mounted) setState(() => _tabIndex = 3);
    } catch (_) {
      _showInfo("Could not open folder.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openCurrentFile(MusicItem item) {
    final String? path = item.localPath;
    if (path == null || path.trim().isEmpty || !File(path).existsSync()) {
      _showInfo("Local file is not available.");
      return;
    }

    WinUtils.open('explorer.exe', arguments: '/select,"$path"', parseParamaters: false);
    if (!kDebugMode) QuickMenuFunctions.hideQuickMenu();
  }

  MusicItem? _findExactMusicItem(List<MusicItem> items, String label, MusicItemType type) {
    for (final MusicItem item in items) {
      if (item.type == type && _sameMusicLabel(item.title, label)) return item;
    }
    return null;
  }

  bool _sameMusicLabel(String left, String right) => left.trim().toLowerCase() == right.trim().toLowerCase();

  Widget _buildSavedQueueCard(Color accent) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Row(
        children: <Widget>[
          const _IconPill(
            icon: Icons.queue_music_rounded,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Saved queue",
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 2),
                Text(
                  _restoringSavedQueue ? "Fetching tracks..." : "Ready to list in Player.",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: Design.baseFontSize + 1, color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MiniIconButton(
            icon: Icons.restore_rounded,
            onTap: _restoringSavedQueue ? () {} : () => _restoreSavedQueue(),
          ),
          _MiniIconButton(
            icon: Icons.delete_outline_rounded,
            onTap: _clearSavedQueue,
          ),
        ],
      ),
    );
  }

  Widget _buildVolumeBar(Color accent) {
    return ValueListenableBuilder<double>(
      valueListenable: MusicServerManager.volumeNotifier,
      builder: (BuildContext context, double volume, _) {
        final double clamped = volume.clamp(0.0, 1.0);
        final IconData icon = clamped <= 0
            ? Icons.volume_off_rounded
            : clamped < 0.5
                ? Icons.volume_down_rounded
                : Icons.volume_up_rounded;
        final Color onSurface = Theme.of(context).colorScheme.onSurface;
        return Row(
          children: <Widget>[
            Tooltip(
              message: clamped <= 0 ? "Unmute" : "Mute",
              child: _MiniIconButton(icon: icon, onTap: MusicServerManager.toggleMute),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: accent,
                  inactiveTrackColor: accent.withAlpha(35),
                  thumbColor: accent,
                  overlayColor: accent.withAlpha(28),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  min: 0,
                  max: 1,
                  value: clamped,
                  padding: EdgeInsets.zero,
                  onChanged: (double next) => MusicServerManager.setVolume(next),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              child: Text(
                "${(clamped * 100).round()}%",
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withAlpha(150),
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildUtilityRow(Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Expanded(child: _buildSpeedControl(accent)),
        const SizedBox(width: 8),
        Expanded(child: _buildSleepControl(accent)),
      ],
    );
  }

  Widget _buildSpeedControl(Color accent) {
    const List<double> presets = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    return ValueListenableBuilder<double>(
      valueListenable: MusicServerManager.speedNotifier,
      builder: (BuildContext context, double speed, _) {
        final bool active = (speed - 1.0).abs() > 0.001;
        return PopupMenuButton<double>(
          position: PopupMenuPosition.under,
          tooltip: "Playback speed",
          color: Color.alphaBlend(Design.accent.withAlpha(16), Theme.of(context).colorScheme.surface),
          surfaceTintColor: Design.accent.withAlpha(30),
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          onSelected: (double value) => MusicServerManager.setSpeed(value),
          itemBuilder: (BuildContext context) => presets
              .map(
                (double value) => _speedMenuItem(value, (value - speed).abs() < 0.001),
              )
              .toList(growable: false),
          child: _controlPill(
            icon: Icons.speed_rounded,
            label: "${_formatSpeed(speed)}×",
            active: active,
            accent: accent,
          ),
        );
      },
    );
  }

  PopupMenuItem<double> _speedMenuItem(double value, bool selected) {
    return PopupMenuItem<double>(
      value: value,
      height: 34,
      child: Row(
        children: <Widget>[
          Icon(selected ? Icons.check_rounded : Icons.speed_rounded,
              size: 16, color: selected ? Design.accent : Design.accent.withAlpha(150)),
          const SizedBox(width: 9),
          Text("${_formatSpeed(value)}×",
              style: TextStyle(
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildSleepControl(Color accent) {
    return ValueListenableBuilder<Duration?>(
      valueListenable: MusicServerManager.sleepRemainingNotifier,
      builder: (BuildContext context, Duration? remaining, _) {
        final bool active = MusicServerManager.sleepTimerActive;
        final String label = !active
            ? "Sleep"
            : remaining != null
                ? _formatDuration(remaining)
                : "End";
        return PopupMenuButton<int>(
          position: PopupMenuPosition.under,
          tooltip: "Sleep timer",
          color: Color.alphaBlend(Design.accent.withAlpha(16), Theme.of(context).colorScheme.surface),
          surfaceTintColor: Design.accent.withAlpha(30),
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          onSelected: _onSleepSelected,
          itemBuilder: (BuildContext context) => <PopupMenuEntry<int>>[
            _sleepMenuItem(Icons.timer_outlined, "15 minutes", 15),
            _sleepMenuItem(Icons.timer_outlined, "30 minutes", 30),
            _sleepMenuItem(Icons.timer_outlined, "45 minutes", 45),
            _sleepMenuItem(Icons.timer_outlined, "60 minutes", 60),
            _sleepMenuItem(Icons.music_note_rounded, "End of track", -1),
            if (active) ...<PopupMenuEntry<int>>[
              const PopupMenuDivider(),
              _sleepMenuItem(Icons.timer_off_rounded, "Turn off", 0),
            ],
          ],
          child: _controlPill(
            icon: active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
            label: label,
            active: active,
            accent: accent,
          ),
        );
      },
    );
  }

  void _onSleepSelected(int value) {
    if (value == 0) {
      MusicServerManager.cancelSleepTimer();
      _showInfo("Sleep timer off.");
    } else if (value == -1) {
      MusicServerManager.startSleepAtEndOfTrack();
      _showInfo("Will pause at end of track.");
    } else {
      MusicServerManager.startSleepTimer(Duration(minutes: value));
      _showInfo("Pausing in $value minutes.");
    }
  }

  PopupMenuItem<int> _sleepMenuItem(IconData icon, String label, int value) {
    return PopupMenuItem<int>(
      value: value,
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

  Widget _controlPill({
    required IconData icon,
    required String label,
    required bool active,
    required Color accent,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active ? accent.withAlpha(22) : onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: active ? accent.withAlpha(90) : onSurface.withAlpha(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 15, color: active ? accent : onSurface.withAlpha(150)),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                color: active ? accent : onSurface.withAlpha(170),
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSpeed(double speed) {
    if (speed == speed.roundToDouble()) return speed.toStringAsFixed(0);
    String text = speed.toStringAsFixed(2);
    if (text.endsWith('0')) text = text.substring(0, text.length - 1);
    return text;
  }

  Widget _buildTimeline(Color accent, MusicItem item) {
    return StreamBuilder<Duration>(
      stream: MusicServerManager.player.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> positionSnapshot) {
        final Duration position = positionSnapshot.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: MusicServerManager.player.durationStream,
          builder: (BuildContext context, AsyncSnapshot<Duration?> durationSnapshot) {
            final Duration? decoderDuration = durationSnapshot.data ?? MusicServerManager.player.duration;
            final Duration? trustedDuration = _bestTimelineDuration(decoderDuration, item.duration);
            final Duration duration = trustedDuration ?? Duration.zero;
            final double max = trustedDuration == null ? 1 : trustedDuration.inMilliseconds.toDouble();
            final double value = position.inMilliseconds.clamp(0, max.toInt()).toDouble();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0),
              child: Column(
                children: <Widget>[
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: accent,
                      inactiveTrackColor: accent.withAlpha(35),
                      thumbColor: accent,
                      overlayColor: accent.withAlpha(28),
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      min: 0,
                      max: max,
                      value: value,
                      padding: EdgeInsets.zero,
                      onChanged: trustedDuration == null
                          ? null
                          : (double next) {
                              final int nextMilliseconds = next.round().clamp(0, trustedDuration.inMilliseconds);
                              MusicServerManager.player.seek(Duration(milliseconds: nextMilliseconds));
                            },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _TimelineTimeLabel(label: _formatDuration(position)),
                        _TimelineTimeLabel(
                          label: trustedDuration == null ? "--:--" : _formatDuration(duration),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTransport(Color accent, SequenceState? sequenceState, MusicItem item) {
    final int queueLength = sequenceState?.sequence.length ?? 0;
    final int currentIndex = sequenceState?.currentIndex ?? 0;
    final bool canPrevious = currentIndex > 0;
    final bool atLastTrack = currentIndex >= queueLength - 1;
    // Next is enabled whenever there's more than one track; on the last track it
    // wraps around to the first track instead of being disabled.
    final bool canNext = queueLength > 1;
    final bool starred = _starredOverrides[item.id] ?? item.starred;

    return StreamBuilder<PlayerState>(
      stream: MusicServerManager.player.playerStateStream,
      builder: (BuildContext context, AsyncSnapshot<PlayerState> snapshot) {
        final PlayerState? state = snapshot.data;
        final bool buffering =
            state?.processingState == ProcessingState.loading || state?.processingState == ProcessingState.buffering;
        final bool playing = state?.playing ?? false;

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double gap = (constraints.maxWidth * 0.018).clamp(3.0, 8.0);
            final double secondarySize = ((constraints.maxWidth - (gap * 6) - 54) / 6).clamp(30.0, 38.0);
            final double primarySize = (secondarySize + 12).clamp(42.0, 54.0);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: <Widget>[
                    _TransportButton(
                      icon: starred ? Icons.star_rounded : Icons.star_border_rounded,
                      tooltip: "Save to Stared Playlist",
                      active: starred,
                      size: secondarySize,
                      onTap: () => _toggleStarred(item, !starred),
                    ),
                    SizedBox(width: gap),
                    ValueListenableBuilder<bool>(
                      valueListenable: MusicServerManager.shuffleEnabledNotifier,
                      builder: (BuildContext context, bool shuffleEnabled, _) => _TransportButton(
                        icon: shuffleEnabled ? Icons.shuffle_on_rounded : Icons.shuffle_rounded,
                        active: shuffleEnabled,
                        tooltip: "Shuffle",
                        size: secondarySize,
                        onTap: () => MusicServerManager.setShuffleEnabled(!shuffleEnabled),
                      ),
                    ),
                    SizedBox(width: gap),
                    _TransportButton(
                      icon: Icons.skip_previous_rounded,
                      tooltip: "Previous",
                      enabled: canPrevious,
                      size: secondarySize,
                      onTap: MusicServerManager.player.seekToPrevious,
                    ),
                    SizedBox(width: gap),
                    _TransportButton(
                      icon: buffering
                          ? Icons.hourglass_top_rounded
                          : playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                      tooltip: playing ? "Pause" : "Play",
                      active: true,
                      isPrimary: true,
                      size: primarySize,
                      onTap: buffering
                          ? null
                          : playing
                              ? MusicServerManager.player.pause
                              : MusicServerManager.player.play,
                    ),
                    SizedBox(width: gap),
                    _TransportButton(
                      icon: Icons.skip_next_rounded,
                      tooltip: "Next",
                      enabled: canNext,
                      size: secondarySize,
                      onTap: atLastTrack
                          ? () => MusicServerManager.player.seek(Duration.zero, index: 0)
                          : MusicServerManager.player.seekToNext,
                    ),
                    SizedBox(width: gap),
                    _TransportButton(
                      icon: sequenceState?.loopMode == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
                      active: sequenceState?.loopMode != LoopMode.off,
                      tooltip: "Repeat",
                      size: secondarySize,
                      onTap: () {
                        final LoopMode next = sequenceState?.loopMode == LoopMode.off
                            ? LoopMode.all
                            : sequenceState?.loopMode == LoopMode.all
                                ? LoopMode.one
                                : LoopMode.off;
                        MusicServerManager.player.setLoopMode(next);
                      },
                    ),
                    SizedBox(width: gap),
                    _TransportButton(
                      icon: Icons.playlist_add_rounded,
                      tooltip: "Add to Playlist",
                      size: secondarySize,
                      onTap: () => _openPlaylistPicker(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleStarred(MusicItem item, bool starred) async {
    setState(() => _loading = true);
    try {
      final bool success = await MusicServerManager.setSongStarred(songId: item.id, starred: starred);
      if (success) {
        _starredOverrides[item.id] = starred;
        _showInfo(starred ? "Rated ${item.title}." : "Removed rating from ${item.title}.");
      } else {
        _showInfo("Could not update rating.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openPlaylistPicker() async {
    if (_playlists.isEmpty) {
      setState(() => _loading = true);
      try {
        _playlists = await MusicServerManager.getPlaylists();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (mounted) setState(() => _playlistPickerVisible = true);
  }

  Widget _buildQueueButton(Color accent, int queueLength, int currentIndex) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: queueLength == 0 ? null : () => setState(() => _queueVisible = true),
      borderRadius: BorderRadius.circular(99),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: accent.withAlpha(14),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: accent.withAlpha(40)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.queue_music_rounded, size: 15, color: accent),
            const SizedBox(width: 7),
            Text(
              "Up next",
              style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w700, color: onSurface),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withAlpha(22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                "$currentIndex / $queueLength",
                style: TextStyle(fontSize: Design.baseFontSize, fontWeight: FontWeight.w800, color: accent),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: onSurface.withAlpha(110)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistPicker(Color accent, MusicItem item) {
    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(245),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(24)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _SectionLabel(
                        icon: Icons.playlist_add_rounded,
                        label: "Add To",
                        count: _playlists.length,
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => setState(() => _playlistPickerVisible = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(Icons.close_rounded,
                            size: 17, color: Theme.of(context).colorScheme.onSurface.withAlpha(150)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_playlists.isEmpty)
                  const Expanded(
                    child: _EmptyState(
                      icon: Icons.playlist_remove_rounded,
                      title: "No playlists",
                      subtitle: "Create a playlist first, then add this song.",
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: _playlists.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (BuildContext context, int index) {
                        final MusicPlaylist playlist = _playlists[index];
                        return _PlaylistPickerRow(
                          playlist: playlist,
                          onTap: () => _addCurrentSongToPlaylist(playlist, item),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQueueList(List<_QueueEntry> entries, int currentIndex, {required bool reorderable}) {
    if (!reorderable) {
      return ClipRRect(
        child: Material(
          type: MaterialType.transparency,
          child: ListView.builder(
            itemCount: entries.length,
            itemExtent: 40,
            scrollCacheExtent: const ScrollCacheExtent.pixels(160),
            itemBuilder: (BuildContext context, int index) {
              final _QueueEntry entry = entries[index];
              return _QueueEditRow(
                key: ValueKey<String>('q_${entry.index}_${entry.item.id}'),
                item: entry.item,
                active: entry.index == currentIndex,
                reorderable: false,
                onTap: () => MusicServerManager.player.seek(Duration.zero, index: entry.index),
                onRemove: () => _removeFromQueue(entry.index),
              );
            },
          ),
        ),
      );
    }

    return ClipRRect(
      child: Material(
        type: MaterialType.transparency,
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: entries.length,
          onReorderItem: (int oldIndex, int newIndex) {
            if (oldIndex == newIndex) return;
            unawaited(MusicServerManager.moveQueueItem(entries[oldIndex].index, entries[newIndex].index));
          },
          itemBuilder: (BuildContext context, int index) {
            final _QueueEntry entry = entries[index];
            return _QueueEditRow(
              key: ValueKey<String>('q_${entry.index}_${entry.item.id}'),
              index: index,
              item: entry.item,
              active: entry.index == currentIndex,
              reorderable: true,
              onTap: () => MusicServerManager.player.seek(Duration.zero, index: entry.index),
              onRemove: () => _removeFromQueue(entry.index),
            );
          },
        ),
      ),
    );
  }

  Future<void> _removeFromQueue(int index) async {
    // The sequenceStateStream drives the rebuild once the source is removed.
    await MusicServerManager.removeFromQueueAt(index);
  }

  Future<void> _queueTrack(MusicItem item, {required bool next}) async {
    if (item.isFolder) return;
    if (next) {
      await MusicServerManager.playNext(<MusicItem>[item]);
      _showInfo("Playing next: ${item.title}.");
    } else {
      await MusicServerManager.addToQueue(<MusicItem>[item]);
      _showInfo("Added to queue: ${item.title}.");
    }
  }

  List<_RowAction> _trackQueueActions(MusicItem item) {
    if (item.isFolder) return const <_RowAction>[];
    return <_RowAction>[
      _RowAction(
        icon: Icons.playlist_play_rounded,
        tooltip: "Play next",
        onTap: () => _queueTrack(item, next: true),
      ),
      _RowAction(
        icon: Icons.queue_music_rounded,
        tooltip: "Add to queue",
        onTap: () => _queueTrack(item, next: false),
      ),
    ];
  }

  Widget _buildQueuePreview(Color accent, SequenceState? sequenceState) {
    final List<IndexedAudioSource> sequence = sequenceState?.sequence ?? <IndexedAudioSource>[];
    if (sequence.isEmpty) return const SizedBox.shrink();
    final int currentIndex = sequenceState?.currentIndex ?? 0;
    final String query = _queueSearchController.text.trim().toLowerCase();
    final List<_QueueEntry> entries = <_QueueEntry>[
      for (int index = 0; index < sequence.length; index++)
        if (sequence[index].tag is MusicItem) _QueueEntry(index: index, item: sequence[index].tag as MusicItem),
    ];
    final List<_QueueEntry> visibleEntries =
        query.isEmpty ? entries : entries.where((_QueueEntry entry) => entry.matches(query)).toList(growable: false);

    return Positioned.fill(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withAlpha(245),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(24)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _queueSearchController,
                          onChanged: (_) => setState(() {}),
                          style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600),
                          decoration: _inputDecoration(
                            hint: "Search queue by artist, album, or title",
                            icon: Icons.queue_music_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => setState(() => _queueVisible = false),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Icon(Icons.close_rounded,
                              size: 17, color: Theme.of(context).colorScheme.onSurface.withAlpha(150)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visibleEntries.isEmpty
                        ? const _EmptyState(
                            icon: Icons.search_off_rounded,
                            title: "No queue matches",
                            subtitle: "Try another artist, album, or title.",
                          )
                        : _buildQueueList(visibleEntries, currentIndex, reorderable: query.isEmpty),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTab(Color accent) {
    final List<MusicItem> artistResults =
        _searchResults.where((MusicItem item) => item.type == MusicItemType.artist).toList(growable: false);
    final List<MusicItem> albumResults =
        _searchResults.where((MusicItem item) => item.type == MusicItemType.album).toList(growable: false);
    final List<MusicItem> songResults =
        _searchResults.where((MusicItem item) => !item.isFolder).toList(growable: false);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onSubmitted: (String e) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _searchFocusNode.requestFocus();
              });
              _search(e);
            },
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            decoration: _inputDecoration(
              hint: "Search artists, albums, or songs",
              icon: Icons.search_rounded,
              suffix: CancelTraversal(
                child: IconButton(
                  tooltip: "Search",
                  onPressed: () {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _searchFocusNode.requestFocus();
                    });
                    _search(_searchController.text);
                  },
                  icon: Icon(Icons.arrow_forward_rounded, size: 16, color: accent),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: _searchResults.isEmpty
              ? _EmptyState(
                  icon: _searchController.text.trim().isEmpty ? Icons.search_rounded : Icons.search_off_rounded,
                  title: _searchController.text.trim().isEmpty
                      ? (MusicServerManager.isLocalActive ? "Search local music" : "Search your server")
                      : "No matches",
                  subtitle: _searchController.text.trim().isEmpty
                      ? "Type a title, artist, or album."
                      : "Try a broader query.",
                )
              : ClipRRect(
                  child: Material(
                    type: MaterialType.transparency,
                    child: WindowsScrollView(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (artistResults.isNotEmpty) ...<Widget>[
                            _SectionLabel(
                              icon: Icons.person_search_rounded,
                              label: "Artists",
                              count: artistResults.length,
                            ),
                            const SizedBox(height: 8),
                            _buildItemSection(artistResults, accent),
                            const SizedBox(height: 12),
                          ],
                          if (albumResults.isNotEmpty) ...<Widget>[
                            _SectionLabel(
                              icon: Icons.album_rounded,
                              label: "Albums",
                              count: albumResults.length,
                            ),
                            const SizedBox(height: 8),
                            _buildItemSection(albumResults, accent),
                            const SizedBox(height: 12),
                          ],
                          if (songResults.isNotEmpty) ...<Widget>[
                            _SectionLabel(
                              icon: Icons.music_note_rounded,
                              label: "Songs",
                              count: songResults.length,
                            ),
                            const SizedBox(height: 8),
                            _buildItemSection(songResults, accent),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildLibraryTab(Color accent) {
    if (_items.isEmpty && !_loading) {
      return _EmptyState(
        icon: Icons.library_music_outlined,
        title: MusicServerManager.isConnected
            ? (MusicServerManager.isLocalActive ? "Local library is empty" : "Library is empty")
            : "No active music source",
        subtitle: MusicServerManager.isConnected
            ? (MusicServerManager.isLocalActive
                ? "Add a music folder or reindex Local."
                : "Refresh or check your Subsonic library.")
            : "Add or activate a source in settings.",
        actionLabel: "Refresh",
        onAction: _refresh,
      );
    }
    return _buildItemList(_items, accent, playlistId: _activePlaylistId);
  }

  Widget _buildItemList(List<MusicItem> items, Color accent, {String? playlistId}) {
    return ClipRRect(
      child: Material(
        type: MaterialType.transparency,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (BuildContext context, int index) {
            final MusicItem item = items[index];
            return _MusicRow(
              item: item,
              onTap: () => _onItemTap(item, items, index),
              trailingActions: <_RowAction>[
                if (item.isFolder)
                  _RowAction(
                    icon: Icons.play_arrow_rounded,
                    tooltip: "Play",
                    onTap: () => _playLibraryItem(item),
                  ),
                if (item.isFolder)
                  _RowAction(
                    icon: Icons.shuffle_rounded,
                    tooltip: "Shuffle",
                    onTap: () => _playLibraryItem(item, shuffle: true),
                  ),
                ..._trackQueueActions(item),
                if (!item.isFolder && playlistId != null)
                  _RowAction(
                    icon: Icons.delete_outline_rounded,
                    tooltip: "Remove from playlist",
                    onTap: () => _removeSongFromCurrentPlaylist(item, index),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildItemSection(List<MusicItem> items, Color accent) {
    return Column(
      children: List<Widget>.generate(items.length, (int index) {
        final MusicItem item = items[index];
        return Padding(
          padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 6),
          child: _MusicRow(
            item: item,
            onTap: () => _onItemTap(item, items, index),
            trailingActions: <_RowAction>[
              if (item.isFolder)
                _RowAction(
                  icon: Icons.play_arrow_rounded,
                  tooltip: "Play",
                  onTap: () => _playLibraryItem(item),
                ),
              if (item.isFolder)
                _RowAction(
                  icon: Icons.shuffle_rounded,
                  tooltip: "Shuffle",
                  onTap: () => _playLibraryItem(item, shuffle: true),
                ),
              ..._trackQueueActions(item),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildFoldersTab(Color accent) {
    if (_folderItems.isEmpty && !_loading) {
      return _EmptyState(
        icon: Icons.folder_outlined,
        title: MusicServerManager.isConnected ? "No indexed folders" : "No active music source",
        subtitle: MusicServerManager.isConnected
            ? (MusicServerManager.isLocalActive
                ? "Add a local root folder or reindex Local."
                : "Refresh or check whether your server exposes Subsonic indexes.")
            : "Add or activate a source in settings.",
        actionLabel: "Refresh",
        onAction: _refresh,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      itemCount: _folderItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (BuildContext context, int index) {
        final MusicItem item = _folderItems[index];
        return _MusicRow(
          item: item,
          onTap: () => _onFolderTap(item, _folderItems, index),
          trailingActions: <_RowAction>[
            _RowAction(
              icon: Icons.play_arrow_rounded,
              tooltip: item.isFolder ? "Play folder" : "Play track",
              onTap: () => _playFolder(item, source: _folderItems, index: index),
            ),
            if (item.isFolder)
              _RowAction(
                icon: Icons.shuffle_rounded,
                tooltip: "Shuffle folder",
                onTap: () => _playFolder(item, shuffle: true),
              ),
            ..._trackQueueActions(item),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistsTab(Color accent) {
    const List<_SmartPlaylistCategory> smartCategories = <_SmartPlaylistCategory>[
      _SmartPlaylistCategory(
        title: "Top Rated",
        subtitle: "Starred songs",
        icon: Icons.star_rounded,
        type: _SmartPlaylistType.topRated,
      ),
      _SmartPlaylistCategory(
        title: "Most Played",
        subtitle: "Songs with higher play counts",
        icon: Icons.local_fire_department_rounded,
        type: _SmartPlaylistType.mostPlayed,
      ),
      _SmartPlaylistCategory(
        title: "Recently Played",
        subtitle: "Recently played songs",
        icon: Icons.history_rounded,
        type: _SmartPlaylistType.recentlyPlayed,
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _cardDecoration(),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _playlistNameController,
                    onSubmitted: (_) => _createPlaylist(),
                    style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600),
                    decoration: _inputDecoration(
                      hint: "New playlist name",
                      icon: Icons.playlist_add_rounded,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _createPlaylist,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(24),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: accent.withAlpha(80)),
                    ),
                    child: Icon(Icons.add_rounded, size: 16, color: accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SectionLabel(
            icon: Icons.auto_awesome_rounded,
            label: MusicServerManager.isLocalActive ? "Local" : "Subsonic",
            count: smartCategories.length,
          ),
          const SizedBox(height: 8),
          ...smartCategories.map(
            (_SmartPlaylistCategory category) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SmartPlaylistRow(
                category: category,
                onTap: () => _openSmartPlaylist(category),
              ),
            ),
          ),
          const SizedBox(height: 4),
          _SectionLabel(
            icon: Icons.playlist_play_rounded,
            label: "Playlists",
            count: _playlists.length,
          ),
          const SizedBox(height: 8),
          if (_playlists.isEmpty && !_loading)
            const _InlinePanel(
              icon: Icons.playlist_remove_rounded,
              title: "No saved playlists",
              subtitle: "Create a playlist above or refresh after creating one on your server.",
            )
          else
            ..._playlists.map(
              (MusicPlaylist playlist) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PlaylistRow(
                  playlist: playlist,
                  onTap: () => _openPlaylist(playlist),
                  trailingActions: <_RowAction>[
                    _RowAction(
                        icon: Icons.play_arrow_rounded, tooltip: "Play playlist", onTap: () => _playPlaylist(playlist)),
                    _RowAction(
                        icon: Icons.shuffle_rounded,
                        tooltip: "Shuffle playlist",
                        onTap: () => _playPlaylist(playlist, shuffle: true)),
                    _RowAction(
                        icon: Icons.delete_outline_rounded,
                        tooltip: "Delete playlist",
                        onTap: () => _deletePlaylist(playlist)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocalSourceCard(Color accent) {
    final bool active = MusicServerManager.isLocalActive;
    final bool indexing = MusicLocalIndexer.instance.isIndexingNotifier.value;
    final int indexed = MusicLocalIndexer.instance.indexedCount.value;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? accent.withAlpha(20) : Theme.of(context).colorScheme.onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: active ? accent.withAlpha(80) : Theme.of(context).colorScheme.onSurface.withAlpha(18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              _IconPill(
                icon: active ? Icons.radio_button_checked_rounded : Icons.folder_special_rounded,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text("Local",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface)),
                    const SizedBox(height: 2),
                    Text(
                      indexing
                          ? "Indexing $indexed tracks..."
                          : "${_localRoots.length} folders - $_localSongCount tracks indexed",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
                    ),
                  ],
                ),
              ),
              if (!active)
                Tooltip(
                  message: "Activate Local",
                  child: _MiniIconButton(
                    icon: Icons.login_rounded,
                    onTap: _activateLocal,
                  ),
                ),
              Tooltip(
                message: "Edit folders",
                child: _MiniIconButton(
                  icon: Icons.edit_rounded,
                  onTap: () => setState(() => _localEditorVisible = !_localEditorVisible),
                ),
              ),
              Tooltip(
                message: "Reindex all",
                child: _MiniIconButton(
                  icon: Icons.sync_rounded,
                  onTap: _reindexLocalAll,
                ),
              ),
            ],
          ),
          if (_localEditorVisible) ...<Widget>[
            const SizedBox(height: 10),
            _buildLocalRootEditor(accent),
          ],
        ],
      ),
    );
  }

  Widget _buildLocalRootEditor(Color accent) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_localRoots.isEmpty)
            const _InlinePanel(
              icon: Icons.folder_off_rounded,
              title: "No local folders",
              subtitle: "Add a root folder to index local music.",
            )
          else
            ..._localRoots.map(
              (MusicRoot root) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Directory(root.path).existsSync() ? Icons.folder_rounded : Icons.folder_off_rounded,
                      size: 16,
                      color: accent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        root.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1.5,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    Tooltip(
                      message: "Reindex folder",
                      child: _MiniIconButton(
                        icon: Icons.sync_rounded,
                        onTap: () async {
                          setState(() => _loading = true);
                          try {
                            final MusicIndexResult result = await MusicServerManager.reindexLocalFolder(root.path);
                            await _refresh();
                            _showInfo("Indexed ${result.indexedCount} tracks.");
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        },
                      ),
                    ),
                    Tooltip(
                      message: "Remove folder",
                      child: _MiniIconButton(
                        icon: Icons.delete_outline_rounded,
                        accent: Colors.redAccent,
                        onTap: () => _removeLocalRoot(root),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _addLocalRoot,
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                color: accent.withAlpha(24),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: accent.withAlpha(80)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.create_new_folder_rounded, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Text("Add Music Folder",
                      style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w800, color: accent)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab(Color accent) {
    final List<MusicServerConfig> configs = MusicServerManager.configs;
    final String? activeId = MusicServerManager.activeConfigId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SectionLabel(
            icon: Icons.dns_rounded,
            label: "Servers",
            count: configs.length + 1,
          ),
          const SizedBox(height: 8),
          _buildLocalSourceCard(accent),
          if (configs.isEmpty)
            const _InlinePanel(
              icon: Icons.cloud_off_rounded,
              title: "No remote servers configured",
              subtitle: "Use Local above or add a Subsonic-compatible server below.",
            )
          else
            ...configs.map((MusicServerConfig config) {
              final bool active = config.id == activeId;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: active ? accent.withAlpha(20) : Theme.of(context).colorScheme.onSurface.withAlpha(8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: active ? accent.withAlpha(80) : Theme.of(context).colorScheme.onSurface.withAlpha(18)),
                ),
                child: Row(
                  children: <Widget>[
                    _IconPill(
                      icon: active ? Icons.radio_button_checked_rounded : Icons.dns_outlined,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(config.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).colorScheme.onSurface)),
                          const SizedBox(height: 2),
                          Text(config.url,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: Design.baseFontSize + 1,
                                  color: Theme.of(context).colorScheme.onSurface.withAlpha(130))),
                        ],
                      ),
                    ),
                    if (!active)
                      _MiniIconButton(
                        icon: Icons.login_rounded,
                        onTap: () => _activateServer(config),
                      ),
                    _MiniIconButton(
                      icon: Icons.sync_rounded,
                      onTap: () => _testServer(config),
                    ),
                    _MiniIconButton(
                      icon: Icons.delete_outline_rounded,
                      accent: Colors.redAccent,
                      onTap: () async {
                        await MusicServerManager.removeServer(config.id);
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 16),
          const _SectionLabel(
            icon: Icons.settings_suggest_rounded,
            label: "Preferences",
            count: 0,
            hideCount: true,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: _cardDecoration(),
            child: Row(
              children: <Widget>[
                const _IconPill(
                  icon: Icons.task_rounded,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "Show in Taskbar",
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Display playback controls in the quick menu taskbar.",
                        style: TextStyle(
                            fontSize: Design.baseFontSize + 1,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(130)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                MiniToggleSwitch(
                  value: user.musicPlayerInTaskbar,
                  activeThumbColor: accent,
                  onChanged: (bool val) async {
                    user.musicPlayerInTaskbar = val;
                    await Boxes.updateSettings("showMusicPlayerInTaskbar", val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionLabel(icon: Icons.add_link_rounded, label: "Add Music Server", count: 0, hideCount: true),
          const SizedBox(height: 8),
          const _InlinePanel(
            icon: Icons.info_outline_rounded,
            title: "Jellyfin / Navidrome compatibility",
            subtitle: "Tabame connects over the Subsonic API. For Navidrome or Subsonic, keep Subsonic mode. "
                "For Jellyfin, install its \"Subsonic API\" plugin and pick Jellyfin mode — Tabame auto-probes the "
                "/sb path and uses plaintext auth, since Jellyfin can't verify Subsonic token logins.",
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: _cardDecoration(),
            child: Column(
              children: <Widget>[
                _buildTextField(_nameController, "Server name", Icons.badge_outlined, accent),
                const SizedBox(height: 8),
                _buildTextField(_urlController, "Server URL", Icons.link_rounded, accent),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(child: _buildTextField(_userController, "Username", Icons.person_outline_rounded, accent)),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            _buildTextField(_passController, "Password", Icons.key_rounded, accent, isPassword: true)),
                  ],
                ),
                const SizedBox(height: 8),
                _buildAuthModeSelector(accent),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _addServer,
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(24),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: accent.withAlpha(80)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(Icons.add_rounded, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Text("Add ${_newServerType == MusicServerType.jellyfin ? 'Jellyfin' : 'Subsonic'} Server",
                            style: TextStyle(
                                fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w800, color: accent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _activateServer(MusicServerConfig config) async {
    setState(() => _loading = true);
    final bool success = await MusicServerManager.setActiveServer(config);
    _showInfo(
      success
          ? "Switched to ${config.name}."
          : (MusicServerManager.lastConnectionError ?? "Failed to connect to ${config.name}."),
      duration: success ? null : 10,
    );
    if (mounted) setState(() => _loading = false);
    if (success) unawaited(_refresh());
  }

  Future<void> _activateLocal() async {
    setState(() => _loading = true);
    final bool success = await MusicServerManager.setLocalActive();
    if (success) {
      _history.clear();
      _historyPlaylistIds.clear();
      _folderHistory.clear();
      _folderPathHistory.clear();
      _titles
        ..clear()
        ..add("Library");
      _folderTitles
        ..clear()
        ..add("Folders");
      _activePlaylistId = null;
      _activeFolderPath = null;
      _items = <MusicItem>[];
      _folderItems = <MusicItem>[];
      _rootFolders = <MusicItem>[];
      _playlists = <MusicPlaylist>[];
      _searchResults = <MusicItem>[];
      await _refresh();
    }
    _showInfo(success ? "Switched to Local." : "Could not activate Local.");
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addLocalRoot() async {
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select music folder';
    final Directory? directory = picker.getDirectory();
    if (directory == null) return;

    setState(() => _loading = true);
    try {
      await MusicServerManager.addLocalRoot(directory.path);
      await _refreshLocalSummary();
      _showInfo("Indexing ${directory.path}.");
      final MusicIndexResult result = await MusicServerManager.reindexLocalFolder(directory.path);
      await _refresh();
      _showInfo("Indexed ${result.indexedCount} tracks.");
    } catch (_) {
      _showInfo("Local folder indexing failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeLocalRoot(MusicRoot root) async {
    setState(() => _loading = true);
    try {
      await MusicServerManager.removeLocalRoot(root.path);
      await _refresh();
      _showInfo("Removed ${root.title}.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reindexLocalAll() async {
    if (_localRoots.isEmpty) {
      _showInfo("Add a local music folder first.");
      return;
    }

    setState(() => _loading = true);
    try {
      _showInfo("Reindexing local music.");
      final MusicIndexResult result = await MusicServerManager.reindexLocalAll();
      await _refresh();
      _showInfo("Indexed ${result.indexedCount} tracks.");
    } catch (_) {
      _showInfo("Local reindex failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reindexCurrentFolder() async {
    if (!MusicServerManager.isLocalActive) {
      await _refresh();
      return;
    }

    final String? folderPath = _activeFolderPath;
    if (folderPath == null) {
      await _reindexLocalAll();
      return;
    }

    setState(() => _loading = true);
    try {
      _showInfo("Reindexing ${_folderTitles.last}.");
      final MusicIndexResult result = await MusicServerManager.reindexLocalFolder(folderPath);
      _folderItems = await MusicServerManager.getMusicDirectory('${MusicLibraryDb.folderIdPrefix}$folderPath');
      await _refreshLocalSummary();
      _showInfo("Indexed ${result.indexedCount} tracks.");
    } catch (_) {
      _showInfo("Folder reindex failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _testServer(MusicServerConfig config) async {
    setState(() => _loading = true);
    final bool success = await MusicServerManager.setActiveServer(config);
    _showInfo(
      success ? "Connection OK." : (MusicServerManager.lastConnectionError ?? "Connection failed."),
      duration: success ? null : 10,
    );
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addServer() async {
    if (_urlController.text.trim().isEmpty || _userController.text.trim().isEmpty) {
      _showInfo("Server URL and username are required.");
      return;
    }

    final MusicServerConfig config = MusicServerConfig(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameController.text.trim().isEmpty ? "Music Server" : _nameController.text.trim(),
      url: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passController.text,
      type: _newServerType,
    );
    await MusicServerManager.addServer(config);
    _nameController.clear();
    _urlController.clear();
    _userController.clear();
    _passController.clear();
    _showInfo("Added ${config.name}.");
    if (mounted) setState(() {});
  }

  Widget _buildAuthModeSelector(Color accent) {
    final bool jellyfin = _newServerType == MusicServerType.jellyfin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
                child: _authModeChip(
                    label: "Subsonic", hint: "Token auth", type: MusicServerType.subsonic, accent: accent)),
            const SizedBox(width: 8),
            Expanded(
                child: _authModeChip(
                    label: "Jellyfin", hint: "Plaintext auth", type: MusicServerType.jellyfin, accent: accent)),
          ],
        ),
        if (jellyfin) ...<Widget>[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded, size: 13, color: Colors.orangeAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  "Jellyfin mode sends your password hex-encoded — effectively cleartext. Prefer an https:// server URL.",
                  style: TextStyle(
                      fontSize: Design.baseFontSize, height: 1.25, color: Colors.orangeAccent.withAlpha(220)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _authModeChip({
    required String label,
    required String hint,
    required MusicServerType type,
    required Color accent,
  }) {
    final bool selected = _newServerType == type;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: () => setState(() => _newServerType = type),
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(24) : onSurface.withAlpha(8),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? accent.withAlpha(110) : onSurface.withAlpha(18)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              size: 15,
              color: selected ? accent : onSurface.withAlpha(110),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w800,
                          color: selected ? accent : onSurface)),
                  Text(hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: Design.baseFontSize - 1, color: onSurface.withAlpha(120))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon,
    Color accent, {
    bool isPassword = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: TextStyle(fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.w600),
      decoration: _inputDecoration(
        hint: label,
        icon: icon,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle:
          TextStyle(fontSize: Design.baseFontSize + 2, color: Theme.of(context).colorScheme.onSurface.withAlpha(110)),
      prefixIcon: Icon(icon, size: 16, color: Design.accent),
      suffixIcon: suffix,
      filled: true,
      fillColor: Design.accent.withAlpha(10),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Design.accent.withAlpha(90)),
      ),
    );
  }

  Widget _buildTabBar(Color accent) {
    final List<_TabSpec> tabs = <_TabSpec>[
      const _TabSpec(Icons.graphic_eq_rounded, "Player"),
      const _TabSpec(Icons.search_rounded, "Search"),
      const _TabSpec(Icons.library_music_rounded, "Library"),
      const _TabSpec(Icons.folder_rounded, "Folders"),
      const _TabSpec(Icons.playlist_play_rounded, "Lists"),
      const _TabSpec(Icons.settings_rounded, "Servers"),
    ];

    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(onSurface.withAlpha(6), surface),
        border: Border(top: BorderSide(color: onSurface.withAlpha(14), width: 1)),
      ),
      child: Row(
        children: tabs.asMap().entries.map((MapEntry<int, _TabSpec> entry) {
          final bool active = entry.key == _tabIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => _setTab(entry.key),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: active ? accent.withAlpha(22) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active ? accent.withAlpha(80) : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: SizedBox(
                  height: 35,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        top: active ? 2 : 8,
                        child: Icon(
                          entry.value.icon,
                          size: 18,
                          color: active ? accent : onSurface.withAlpha(100),
                        ),
                      ),
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        bottom: active ? 4 : -10,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 150),
                          opacity: active ? 1 : 0,
                          child: Text(
                            entry.value.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: accent,
                              height: 1.0,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.onSurface.withAlpha(8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(18)),
    );
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    final int hours = duration.inHours;
    if (hours > 0) return "$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  Duration? _bestTimelineDuration(Duration? decoderDuration, Duration? metadataDuration) {
    if (_isSaneTimelineDuration(decoderDuration)) return decoderDuration;
    if (_isSaneTimelineDuration(metadataDuration)) return metadataDuration;
    return null;
  }

  bool _isSaneTimelineDuration(Duration? duration) {
    return duration != null && duration > Duration.zero && duration <= const Duration(hours: 24);
  }
}
