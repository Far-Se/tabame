import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../../../models/classes/boxes/boxes_base.dart';
import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/classes/music_server.dart';
import '../../../models/classes/music_server_manager.dart';
import '../../../models/db/music_library_db.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../services/music_local_indexer.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/mix_widgets.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/quick_menu_panel.dart';
import '../../widgets/windows_scroll.dart';

part 'button_music_player/button_music_player_views.dart';
part 'button_music_player/button_music_player_widgets.dart';

class MusicServerButton extends StatefulWidget {
  const MusicServerButton({super.key});

  @override
  State<MusicServerButton> createState() => _MusicServerButtonState();
}

class _MusicServerButtonState extends State<MusicServerButton> {
  Timer? _monitorTimer;
  Timer? _feedbackTimer;
  IconData? _feedbackIcon;
  double _lastDragPosition = 0;
  static const double _kDragThreshold = 15.0;
  static const Duration _kFeedbackDuration = Duration(milliseconds: 1500);
  static const Duration _kMonitorInterval = Duration(milliseconds: 200);
  @override
  void initState() {
    super.initState();
    _monitorTimer = Timer.periodic(_kMonitorInterval, _checkForAppPlaying);
  }

  @override
  void dispose() {
    _monitorTimer?.cancel();
    _feedbackTimer?.cancel();
    super.dispose();
  }

  bool _lastState = MusicServerManager.player.playing;

  /// Checks the actual background process state.
  void _checkForAppPlaying(Timer timer) {
    if (!mounted) return;
    if (_lastState != MusicServerManager.player.playing) {
      setState(() {
        _lastState = MusicServerManager.player.playing;
      });
    }
  }

  /// Sets a temporary icon. It cancels any previous pending clear actions.
  void _setFeedbackIcon(IconData icon) {
    _feedbackTimer?.cancel(); // Cancel any pending reset

    setState(() {
      _feedbackIcon = icon;
    });

    _feedbackTimer = Timer(_kFeedbackDuration, () {
      if (mounted) {
        setState(() => _feedbackIcon = null);
      }
    });
  }

  void _handleVolumeDrag(DragUpdateDetails details) {
    if (details.delta.direction == 0) return;

    if (_lastDragPosition == 0) {
      _lastDragPosition = details.localPosition.distance;
      return;
    }

    if ((details.localPosition.distance - _lastDragPosition).abs() < _kDragThreshold) {
      return;
    }

    _lastDragPosition = details.localPosition.distance;
    final bool isUp = (details.primaryDelta ?? 0) < 0;
    //seek 3 seconds
    unawaited(
      MusicServerManager.player.seek(MusicServerManager.player.position + Duration(seconds: isUp ? -3 : 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    if (_feedbackIcon != null) {
      content = Icon(_feedbackIcon, color: Colors.amber[700]);
    } else if (MusicServerManager.player.playing) {
      content = Icon(Icons.multitrack_audio_sharp, color: Colors.amber[700]);
    } else {
      content = const Icon(Icons.library_music_outlined);
    }
    return ModalButton(
      actionName: "Music Player",
      onDoubleTap: () =>
          MusicServerManager.player.playing ? MusicServerManager.player.pause() : MusicServerManager.player.play(),
      onSecondaryTap: () {
        MusicServerManager.player.seekToNext();
        _setFeedbackIcon(Icons.fast_forward);
      },
      onTertiaryTapUp: (_) {
        MusicServerManager.player.seekToPrevious();
        _setFeedbackIcon(Icons.fast_rewind);
      },
      onVerticalDragStart: (_) => _lastDragPosition = 0,
      onVerticalDragEnd: (_) => _lastDragPosition = 0,
      onVerticalDragUpdate: _handleVolumeDrag,
      icon: content,
      child: () => MusicServerPanel(key: UniqueKey()),
    );
  }
}

class MusicServerPanel extends StatefulWidget {
  const MusicServerPanel({super.key});

  @override
  State<MusicServerPanel> createState() => _MusicServerPanelState();
}

enum _PlayerTrackMenuAction { artist, album, folder, file }

class _MusicServerPanelState extends State<MusicServerPanel> {
  static const Duration _kBufferingWarningDelay = Duration(seconds: 5);

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _queueSearchController = TextEditingController();
  final TextEditingController _playlistNameController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _backFocusNode = FocusNode();

  final List<List<MusicItem>> _history = <List<MusicItem>>[];
  final List<String> _titles = <String>["Library"];
  final List<String?> _historyPlaylistIds = <String?>[];
  final List<List<MusicItem>> _folderHistory = <List<MusicItem>>[];
  final List<String> _folderTitles = <String>["Folders"];
  final List<String?> _folderPathHistory = <String?>[];

  int _tabIndex = 0;
  bool _loading = false;
  bool _queueVisible = false;
  bool _playlistPickerVisible = false;
  bool _localEditorVisible = false;
  bool _savedQueueAvailable = false;
  bool _restoringSavedQueue = false;
  String? _infoMessage;
  Timer? _infoTimer;
  Timer? _bufferingWarningTimer;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  String? _bufferingTimerItemId;
  String? _bufferingWarnedItemId;
  List<MusicItem> _items = <MusicItem>[];
  List<MusicItem> _folderItems = <MusicItem>[];
  List<MusicItem> _rootFolders = <MusicItem>[];
  List<MusicPlaylist> _playlists = <MusicPlaylist>[];
  List<MusicItem> _searchResults = <MusicItem>[];
  List<MusicRoot> _localRoots = <MusicRoot>[];
  final Map<String, bool> _starredOverrides = <String, bool>{};
  String? _activePlaylistId;
  String? _activeFolderPath;
  int _localSongCount = 0;

  @override
  void initState() {
    super.initState();
    MusicLocalIndexer.instance.indexedCount.addListener(_handleIndexProgress);
    MusicLocalIndexer.instance.isIndexingNotifier.addListener(_handleIndexProgress);
    _playerStateSubscription = MusicServerManager.player.playerStateStream.listen(_handlePlayerStateChanged);
    unawaited(_initManager());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _backFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _infoTimer?.cancel();
    _bufferingWarningTimer?.cancel();
    _playerStateSubscription?.cancel();
    MusicLocalIndexer.instance.indexedCount.removeListener(_handleIndexProgress);
    MusicLocalIndexer.instance.isIndexingNotifier.removeListener(_handleIndexProgress);
    _searchController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    _nameController.dispose();
    _queueSearchController.dispose();
    _playlistNameController.dispose();
    _searchFocusNode.dispose();
    _backFocusNode.dispose();
    super.dispose();
  }

  void _handleIndexProgress() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePlayerStateChanged(PlayerState state) {
    final bool buffering =
        state.processingState == ProcessingState.loading || state.processingState == ProcessingState.buffering;
    final MusicItem? currentItem = _currentQueuedItem();
    print(currentItem);

    if (!buffering || currentItem == null) {
      _cancelBufferingWarning(resetWarnedItem: !buffering);
      return;
    }

    if (_bufferingWarnedItemId == currentItem.id) return;
    if (_bufferingTimerItemId == currentItem.id && _bufferingWarningTimer?.isActive == true) return;

    _bufferingWarningTimer?.cancel();
    _bufferingTimerItemId = currentItem.id;
    _bufferingWarningTimer = Timer(_kBufferingWarningDelay, () {
      if (!mounted) return;
      final PlayerState currentState = MusicServerManager.player.playerState;
      final bool stillBuffering = currentState.processingState == ProcessingState.loading ||
          currentState.processingState == ProcessingState.buffering;
      final MusicItem? bufferedItem = _currentQueuedItem();
      if (!stillBuffering || bufferedItem == null || bufferedItem.id != currentItem.id) return;

      _bufferingWarnedItemId = bufferedItem.id;
      _showInfo(_buildBufferingFailureMessage(bufferedItem), duration: 10);
    });
  }

  MusicItem? _currentQueuedItem() {
    final int? currentIndex = MusicServerManager.player.currentIndex;
    final List<IndexedAudioSource> sequence = MusicServerManager.player.sequence;
    if (currentIndex == null || currentIndex < 0 || currentIndex >= sequence.length) return null;
    final Object? tag = sequence[currentIndex].tag;
    return tag is MusicItem ? tag : null;
  }

  String _buildBufferingFailureMessage(MusicItem item) {
    final String? path = item.localPath?.trim();
    if (path == null || path.isEmpty) {
      return "Playback is stuck. The file may be missing or use an unsupported filename.";
    }

    if (!File(path).existsSync()) {
      return "Playback is stuck. The file is missing: ${item.title}.";
    }

    return "Playback is stuck. The file may use an unsupported filename or format: ${item.localPath}.";
  }

  void _cancelBufferingWarning({bool resetWarnedItem = false}) {
    _bufferingWarningTimer?.cancel();
    _bufferingWarningTimer = null;
    _bufferingTimerItemId = null;
    if (resetWarnedItem) _bufferingWarnedItemId = null;
  }

  Future<void> _initManager() async {
    await MusicServerManager.init();
    final bool restored = await MusicServerManager.restoreSavedQueue();
    final bool hasSavedQueue = await MusicServerManager.hasSavedQueue;
    if (mounted) {
      setState(() {
        _savedQueueAvailable = hasSavedQueue;
      });
    }
    if (restored) _showInfo("Restored previous queue.");
    await _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      await _refreshLocalSummary();
      if (_playlists.isEmpty || _tabIndex == 4 || _tabIndex == 0) {
        _playlists = await MusicServerManager.getPlaylists();
      }
      if (_rootFolders.isEmpty || (_tabIndex == 3 && _folderHistory.isEmpty) || _tabIndex == 0) {
        _rootFolders = await MusicServerManager.getIndexedFolders();
      }
      if (_tabIndex == 2 && _history.isEmpty) {
        _items = await MusicServerManager.getArtists();
      } else if (_tabIndex == 3) {
        if (_folderHistory.isEmpty) {
          await _showRootFoldersOrSingleRootContents();
        }
      }
    } catch (_) {
      _showInfo("Music request failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRootFoldersOrSingleRootContents() async {
    _folderHistory.clear();
    _folderPathHistory.clear();

    if (_rootFolders.length == 1 && _rootFolders.single.isFolder) {
      final MusicItem root = _rootFolders.single;
      _folderItems = await MusicServerManager.getMusicDirectory(root.id);
      _activeFolderPath = root.localPath;
      _folderTitles
        ..clear()
        ..add(root.title);
      return;
    }

    _folderItems = List<MusicItem>.from(_rootFolders);
    _activeFolderPath = null;
    _folderTitles
      ..clear()
      ..add("Folders");
  }

  Future<void> _refreshLocalSummary() async {
    _localRoots = await MusicServerManager.getLocalRoots();
    _localSongCount = await MusicServerManager.getLocalSongCount();
  }

  Future<void> _search(String query) async {
    final String value = query.trim();
    if (value.isEmpty) {
      setState(() => _searchResults = <MusicItem>[]);
      return;
    }

    setState(() => _loading = true);
    try {
      _searchResults = await MusicServerManager.search(value);
    } catch (_) {
      _showInfo("Search failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onItemTap(MusicItem item, List<MusicItem> source, int index) async {
    if (item.isFolder) {
      setState(() => _loading = true);
      try {
        final List<MusicItem> nextItems = item.type == MusicItemType.album
            ? await MusicServerManager.getSongs(item.id)
            : await MusicServerManager.getAlbums(item.id);
        _history.add(_items);
        _historyPlaylistIds.add(_activePlaylistId);
        _items = nextItems;
        _activePlaylistId = null;
        _titles.add(item.title);
        _tabIndex = 2;
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    await MusicServerManager.playQueue(source, initialIndex: index);
    if (mounted) setState(() => _tabIndex = 0);
  }

  Future<void> _openPlaylist(MusicPlaylist playlist) async {
    setState(() => _loading = true);
    try {
      final List<MusicItem> songs = await MusicServerManager.getPlaylistSongs(playlist.id);
      _history.add(_items);
      _historyPlaylistIds.add(_activePlaylistId);
      _items = songs;
      _activePlaylistId = playlist.id;
      _titles.add(playlist.name);
      setState(() => _tabIndex = 2);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playPlaylist(MusicPlaylist playlist, {bool shuffle = false}) async {
    setState(() => _loading = true);
    try {
      final List<MusicItem> songs = await MusicServerManager.getPlaylistSongs(playlist.id);
      if (songs.isEmpty) {
        _showInfo("${playlist.name} is empty.");
        return;
      }
      if (shuffle) songs.shuffle();
      await MusicServerManager.playQueue(songs);
      if (mounted) setState(() => _tabIndex = 0);
      _showInfo("${shuffle ? 'Shuffling' : 'Playing'} ${playlist.name}.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePlaylist(MusicPlaylist playlist) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        shadowColor: Colors.red,
        elevation: 5,
        surfaceTintColor: userSettings.themeColors.accent,
        title: const Text("Delete Playlist?"),
        content:
            Text("Delete '${playlist.name}' from ${MusicServerManager.isLocalActive ? 'Local' : 'the music server'}?"),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final bool success = await MusicServerManager.deletePlaylist(playlist.id);
      if (success) {
        _playlists = await MusicServerManager.getPlaylists();
        if (_activePlaylistId == playlist.id) {
          _activePlaylistId = null;
        }
        _showInfo("Deleted ${playlist.name}.");
      } else {
        _showInfo("Could not delete ${playlist.name}.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openSmartPlaylist(_SmartPlaylistCategory category) async {
    setState(() => _loading = true);
    try {
      final List<MusicItem> songs = switch (category.type) {
        _SmartPlaylistType.topRated => await MusicServerManager.getStarredSongs(),
        _SmartPlaylistType.mostPlayed => await MusicServerManager.getAlbumListSongs('frequent'),
        _SmartPlaylistType.recentlyPlayed => await MusicServerManager.getAlbumListSongs('recent'),
      };
      _history.add(_items);
      _historyPlaylistIds.add(_activePlaylistId);
      _items = songs;
      _activePlaylistId = null;
      _titles.add(category.title);
      setState(() => _tabIndex = 2);
    } catch (_) {
      _showInfo("Could not load ${category.title}.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playLibraryItem(MusicItem item, {bool shuffle = false}) async {
    setState(() => _loading = true);
    try {
      List<MusicItem> songs = <MusicItem>[];
      if (!item.isFolder) {
        songs = <MusicItem>[item];
      } else if (item.type == MusicItemType.album) {
        songs = await MusicServerManager.getSongs(item.id);
      } else {
        final List<MusicItem> albums = await MusicServerManager.getAlbums(item.id);
        for (final MusicItem album in albums) {
          songs.addAll(await MusicServerManager.getSongs(album.id));
        }
      }

      if (songs.isEmpty) {
        _showInfo("No playable tracks found in ${item.title}.");
        return;
      }
      if (shuffle) songs.shuffle();
      await MusicServerManager.playQueue(songs);
      if (mounted) setState(() => _tabIndex = 0);
      _showInfo("${shuffle ? 'Shuffling' : 'Playing'} ${item.title}.");
    } catch (_) {
      _showInfo("Could not load ${item.title}.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPlaylist() async {
    final String name = _playlistNameController.text.trim();
    if (name.isEmpty) {
      _showInfo("Playlist name is required.");
      return;
    }

    setState(() => _loading = true);
    try {
      final bool success = await MusicServerManager.createPlaylist(name);
      if (success) {
        _playlistNameController.clear();
        _playlists = await MusicServerManager.getPlaylists();
        _showInfo("Created $name.");
      } else {
        _showInfo("Could not create playlist.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addCurrentSongToPlaylist(MusicPlaylist playlist, MusicItem item) async {
    setState(() => _loading = true);
    try {
      final bool success = await MusicServerManager.addSongToPlaylist(
        playlistId: playlist.id,
        songId: item.id,
      );
      if (success) {
        _playlists = await MusicServerManager.getPlaylists();
        _playlistPickerVisible = false;
        _showInfo("Added to ${playlist.name}.");
      } else {
        _showInfo("Could not add song to ${playlist.name}.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeSongFromCurrentPlaylist(MusicItem item, int index) async {
    final String? playlistId = _activePlaylistId;
    if (playlistId == null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Remove Track?"),
        shadowColor: Colors.red,
        elevation: 5,
        surfaceTintColor: userSettings.themeColors.accent,
        content: Text("Remove '${item.title}' from this playlist?"),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Remove"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final bool success = await MusicServerManager.removeSongFromPlaylist(
        playlistId: playlistId,
        songIndex: index,
      );
      if (success) {
        _items = await MusicServerManager.getPlaylistSongs(playlistId);
        _playlists = await MusicServerManager.getPlaylists();
        _showInfo("Removed ${item.title} from playlist.");
      } else {
        _showInfo("Could not remove ${item.title} from playlist.");
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _onFolderTap(MusicItem item, List<MusicItem> source, int index) async {
    if (!item.isFolder) {
      await MusicServerManager.playQueue(source, initialIndex: index);
      if (mounted) setState(() => _tabIndex = 0);
      return;
    }

    setState(() => _loading = true);
    try {
      final List<MusicItem> nextItems = await MusicServerManager.getMusicDirectory(item.id);
      _folderHistory.add(_folderItems);
      _folderPathHistory.add(_activeFolderPath);
      _folderItems = nextItems;
      _activeFolderPath = item.localPath;
      _folderTitles.add(item.title);
    } catch (_) {
      _showInfo("Folder browse failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _playFolder(MusicItem item, {bool shuffle = false}) async {
    if (!item.isFolder) {
      await MusicServerManager.playQueue(<MusicItem>[item]);
      if (mounted) setState(() => _tabIndex = 0);
      return;
    }

    setState(() => _loading = true);
    try {
      final List<MusicItem> songs = await MusicServerManager.getMusicDirectorySongsRecursive(item.id);
      if (songs.isEmpty) {
        _showInfo("No playable songs found in ${item.title}.");
        return;
      }
      if (shuffle) songs.shuffle();
      await MusicServerManager.playQueue(songs);
      _showInfo("${shuffle ? 'Shuffling' : 'Playing'} ${item.title}.");
      if (mounted) setState(() => _tabIndex = 0);
    } catch (_) {
      _showInfo("Folder playback failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /* Future<void> _shuffleFolder(MusicItem folder) async {
    setState(() => _loading = true);
    try {
      final List<MusicItem> songs = await MusicServerManager.getMusicDirectorySongsRecursive(folder.id);
      if (songs.isEmpty) {
        _showInfo("No playable songs found in ${folder.title}.");
        return;
      }

      songs.shuffle();
      await MusicServerManager.playQueue(songs);
      _showInfo("Shuffling ${songs.length} songs from ${folder.title}.");
      if (mounted) setState(() => _tabIndex = 0);
    } catch (_) {
      _showInfo("Folder shuffle failed.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  } */

  void _goBack() {
    if (_tabIndex == 3) {
      if (_folderHistory.isEmpty) return;
      setState(() {
        _folderItems = _folderHistory.removeLast();
        _activeFolderPath = _folderPathHistory.isEmpty ? null : _folderPathHistory.removeLast();
        _folderTitles.removeLast();
      });
      return;
    }

    if (_history.isEmpty) return;
    setState(() {
      _items = _history.removeLast();
      _activePlaylistId = _historyPlaylistIds.removeLast();
      _titles.removeLast();
    });
  }

  bool get _hasBackHistory => (_tabIndex == 3 && _folderHistory.isNotEmpty) || (_tabIndex == 2 && _history.isNotEmpty);

  KeyEventResult _handlePanelKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape && event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_queueVisible) {
      setState(() => _queueVisible = false);
      return KeyEventResult.handled;
    }

    if (_playlistPickerVisible) {
      setState(() => _playlistPickerVisible = false);
      return KeyEventResult.handled;
    }

    if (_hasBackHistory) {
      _goBack();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _setTab(int index) {
    setState(() {
      _tabIndex = index;
      if (index != 0) {
        _queueVisible = false;
        _playlistPickerVisible = false;
      }
    });
    if (index == 1) _searchFocusNode.requestFocus();
    if (index == 2 || index == 3 || index == 4) unawaited(_refresh());
  }

  void _showInfo(String message, {int? duration}) {
    _infoTimer?.cancel();
    setState(() => _infoMessage = message);
    _infoTimer = Timer(Duration(seconds: duration ?? 3), () {
      if (mounted) setState(() => _infoMessage = null);
    });
  }

  Future<void> _restoreSavedQueue({bool play = false}) async {
    setState(() {
      _loading = true;
      _restoringSavedQueue = true;
    });
    try {
      final bool restored = await MusicServerManager.restoreSavedQueue(play: play, replaceExisting: true);
      final bool hasSavedQueue = await MusicServerManager.hasSavedQueue;
      _savedQueueAvailable = hasSavedQueue;
      _showInfo(restored ? "Restored previous queue." : "No previous queue found.");
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _restoringSavedQueue = false;
        });
      }
    }
  }

  Future<void> _clearSavedQueue() async {
    await MusicServerManager.clearSavedQueue();
    if (mounted) {
      setState(() => _savedQueueAvailable = false);
      _showInfo("Previous queue cleared.");
    }
  }

  Future<void> _disconnectServer() async {
    setState(() => _loading = true);
    await MusicServerManager.disconnect();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _queueVisible = false;
      _playlistPickerVisible = false;
      _items = <MusicItem>[];
      _folderItems = <MusicItem>[];
      _rootFolders = <MusicItem>[];
      _playlists = <MusicPlaylist>[];
      _searchResults = <MusicItem>[];
      _activePlaylistId = null;
      _activeFolderPath = null;
      _localEditorVisible = false;
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
    });
    _showInfo("Disconnected from music source.");
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final Duration transitionDuration = reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final bool localFolderTab = MusicServerManager.isLocalActive && _tabIndex == 3;

    return KeyboardListener(
      autofocus: true,
      focusNode: _backFocusNode,
      onKeyEvent: _handlePanelKey,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTap: _hasBackHistory ? _goBack : null,
        child: QuickMenuPanel(
          accent: userSettings.themeColors.accent,
          title: _tabIndex == 2
              ? _titles.last
              : _tabIndex == 3
                  ? _folderTitles.last
                  : _tabTitle,
          icon: _tabIcon,
          buttonIcon: localFolderTab ? Icons.sync_rounded : Icons.refresh_rounded,
          buttonTooltip: localFolderTab ? "Reindex current folder" : "Refresh",
          buttonPressed: localFolderTab ? _reindexCurrentFolder : _refresh,
          extraActions: <Widget>[
            if (MusicServerManager.isConnected)
              IconButton(
                tooltip: "Disconnect",
                onPressed: _disconnectServer,
                icon: const Icon(Icons.link_off_rounded, size: 14),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 14,
              ),
            if (_hasBackHistory)
              IconButton(
                tooltip: "Back",
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 14),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 14,
              ),
          ],
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_loading) LinearProgressIndicator(minHeight: 1.5, color: accent),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ClipRRect(
                        child: Material(
                          type: MaterialType.transparency,
                          child: AnimatedSwitcher(
                            duration: transitionDuration,
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeOutCubic,
                            transitionBuilder: (Widget child, Animation<double> animation) {
                              if (reduceMotion) return child;
                              final Animation<Offset> offsetAnimation = Tween<Offset>(
                                begin: const Offset(0.03, 0),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                              final Animation<double> scaleAnimation = Tween<double>(
                                begin: 0.98,
                                end: 1.0,
                              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: scaleAnimation,
                                  child: SlideTransition(position: offsetAnimation, child: child),
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<int>(_tabIndex),
                              child: IndexedStack(
                                index: _tabIndex,
                                children: <Widget>[
                                  _buildPlayerTab(accent),
                                  _buildSearchTab(accent),
                                  _buildLibraryTab(accent),
                                  _buildFoldersTab(accent),
                                  _buildPlaylistsTab(accent),
                                  _buildSettingsTab(accent),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_infoMessage != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: TweenAnimationBuilder<double>(
                          duration: transitionDuration,
                          tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
                          curve: Curves.easeOutCubic,
                          builder: (BuildContext context, double value, Widget? child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.translate(
                                offset: Offset(0, reduceMotion ? 0 : (10 * (1 - value))),
                                child: child,
                              ),
                            );
                          },
                          child: _StatusStrip(
                            message: _infoMessage!,
                            onClose: () => setState(() => _infoMessage = null),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _buildTabBar(accent),
            ],
          ),
        ),
      ),
    );
  }

  String get _tabTitle {
    return switch (_tabIndex) {
      1 => "Search",
      2 => "Library",
      3 => "Folders",
      4 => "Playlists",
      5 => "Servers",
      _ => "Player",
    };
  }

  IconData get _tabIcon {
    return switch (_tabIndex) {
      1 => Icons.search_rounded,
      2 => Icons.library_music_rounded,
      3 => Icons.folder_rounded,
      4 => Icons.playlist_play_rounded,
      5 => Icons.settings_rounded,
      _ => Icons.graphic_eq_rounded,
    };
  }
}
