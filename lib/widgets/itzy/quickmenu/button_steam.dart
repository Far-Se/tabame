import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/registry.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// A single installed Steam game, distilled from its `appmanifest_*.acf`.
class SteamGame {
  final String appId;
  final String name;
  final String installDir;

  /// Absolute path to a cover/header image inside Steam's library cache, if any.
  final String? coverPath;
  final DateTime? lastPlayed;
  final int sizeOnDisk;

  const SteamGame({
    required this.appId,
    required this.name,
    required this.installDir,
    this.coverPath,
    this.lastPlayed,
    this.sizeOnDisk = 0,
  });

  /// The protocol URI Steam uses to launch a game directly.
  String get launchUri => 'steam://rungameid/$appId';
  String get storeUri => 'steam://nav/games/details/$appId';

  String get sizeLabel {
    if (sizeOnDisk <= 0) return '';
    const double gb = 1024 * 1024 * 1024;
    const double mb = 1024 * 1024;
    if (sizeOnDisk >= gb) return '${(sizeOnDisk / gb).toStringAsFixed(1)} GB';
    return '${(sizeOnDisk / mb).toStringAsFixed(0)} MB';
  }
}

/// Locates the Steam installation and parses its installed library.
///
/// Mirrors the C# `SteamDockExtension` reference: it reads the registry to find
/// Steam, walks `libraryfolders.vdf` for extra library roots, then parses every
/// `appmanifest_*.acf` for the game id/name/install dir. ACF/VDF files are valid
/// key/value text, so light regex extraction is enough for the few fields used.
class SteamLibraryService {
  static const String steamPathKey = "steamLibraryPath";

  /// Steamworks Common Redistributables – never a real game.
  static const String _redistAppId = "228980";

  static List<SteamGame>? _cachedGames;
  static String? _cachedForSteamPath;

  /// The configured override path, empty when Steam should be auto-detected.
  static String get configuredPath => (Boxes.pref.getString(steamPathKey) ?? "").trim();

  static void invalidateCache() {
    _cachedGames = null;
    _cachedForSteamPath = null;
  }

  static bool _isSteamDirectory(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    return File(p.join(path, 'steam.exe')).existsSync() && Directory(p.join(path, 'steamapps')).existsSync();
  }

  static String? _readRegistry(RegistryHive hive, String path, String value) {
    try {
      final RegistryKey key = Registry.openPath(hive, path: path);
      final String? result = key.getValueAsString(value);
      key.close();
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Resolves the active Steam install dir: configured override → registry →
  /// the default `Program Files (x86)\Steam`. Returns null when none is valid.
  static String? findSteamPath() {
    if (_isSteamDirectory(configuredPath)) return p.normalize(configuredPath);

    final List<String?> candidates = <String?>[
      _readRegistry(RegistryHive.currentUser, r'Software\Valve\Steam', 'SteamPath'),
      _readRegistry(RegistryHive.localMachine, r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
      _readRegistry(RegistryHive.localMachine, r'SOFTWARE\Valve\Steam', 'InstallPath'),
    ];
    for (final String? candidate in candidates) {
      if (_isSteamDirectory(candidate)) return p.normalize(candidate!);
    }

    final String programFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final String defaultPath = p.join(programFilesX86, 'Steam');
    return _isSteamDirectory(defaultPath) ? defaultPath : null;
  }

  /// All Steam library roots: the install dir plus any folders declared in
  /// `steamapps/libraryfolders.vdf`.
  static Set<String> _findLibraryPaths(String steamPath) {
    final Set<String> paths = <String>{steamPath};
    final File libraryFile = File(p.join(steamPath, 'steamapps', 'libraryfolders.vdf'));
    if (!libraryFile.existsSync()) return paths;

    try {
      final String content = libraryFile.readAsStringSync();
      for (final RegExpMatch match in RegExp(r'"path"\s*"([^"]*)"').allMatches(content)) {
        final String raw = match.group(1) ?? '';
        // VDF escapes backslashes; collapse them back to a real Windows path.
        final String path = raw.replaceAll(r'\\', r'\');
        if (path.isNotEmpty && Directory(path).existsSync()) paths.add(p.normalize(path));
      }
    } catch (_) {
      // The install root alone is still usable if the file is malformed.
    }
    return paths;
  }

  static String? _acfString(String content, String key) {
    final RegExpMatch? match = RegExp('"$key"\\s*"([^"]*)"', caseSensitive: false).firstMatch(content);
    return match?.group(1);
  }

  static SteamGame? _tryReadGame(File manifest, String libraryPath, String steamPath) {
    try {
      final String content = manifest.readAsStringSync();
      final String? appId = _acfString(content, 'appid');
      final String? name = _acfString(content, 'name');
      final String? installDir = _acfString(content, 'installdir');
      if (appId == null || appId.isEmpty || name == null || name.isEmpty || installDir == null) {
        return null;
      }

      final int size = int.tryParse(_acfString(content, 'SizeOnDisk') ?? '') ?? 0;
      DateTime? lastPlayed;
      final int unix = int.tryParse(_acfString(content, 'LastPlayed') ?? '') ?? 0;
      if (unix > 0) lastPlayed = DateTime.fromMillisecondsSinceEpoch(unix * 1000);

      return SteamGame(
        appId: appId,
        name: name,
        installDir: p.join(libraryPath, 'steamapps', 'common', installDir),
        coverPath: _findCover(steamPath, appId),
        lastPlayed: lastPlayed,
        sizeOnDisk: size,
      );
    } catch (_) {
      return null;
    }
  }

  /// Finds the best available artwork for [appId] in Steam's library cache,
  /// handling both the per-app-folder and the newer flat file layouts.
  static String? _findCover(String steamPath, String appId) {
    final String cacheDir = p.join(steamPath, 'appcache', 'librarycache');
    final List<String> candidates = <String>[
      p.join(cacheDir, appId, 'library_600x900.jpg'),
      p.join(cacheDir, appId, 'library_capsule.jpg'),
      p.join(cacheDir, '${appId}_library_600x900.jpg'),
      p.join(cacheDir, '${appId}_library_600x900_2x.jpg'),
      p.join(cacheDir, appId, 'header.jpg'),
      p.join(cacheDir, '${appId}_header.jpg'),
      p.join(cacheDir, appId, 'logo.png'),
    ];
    for (final String candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }

    // Fallback: scan the per-app folder for any cover-ish image.
    final Directory appDir = Directory(p.join(cacheDir, appId));
    if (appDir.existsSync()) {
      try {
        final List<File> files = appDir.listSync().whereType<File>().toList();
        for (final File f in files) {
          if (f.path.contains('library_600x900')) return f.path;
        }
        for (final File f in files) {
          if (p.extension(f.path).toLowerCase() == '.jpg') return f.path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Scans every Steam library for installed games, ordered by name. Cached
  /// per Steam path; pass [forceRefresh] to rescan after an install/uninstall.
  static Future<List<SteamGame>> scan({bool forceRefresh = false}) async {
    final String? steamPath = findSteamPath();
    if (steamPath == null) return <SteamGame>[];

    if (!forceRefresh && _cachedGames != null && _cachedForSteamPath == steamPath) {
      return _cachedGames!;
    }

    final Map<String, SteamGame> games = <String, SteamGame>{};
    for (final String library in _findLibraryPaths(steamPath)) {
      final Directory steamApps = Directory(p.join(library, 'steamapps'));
      if (!steamApps.existsSync()) continue;
      try {
        for (final FileSystemEntity entity in steamApps.listSync(followLinks: false)) {
          if (entity is! File) continue;
          final String fileName = p.basename(entity.path);
          if (!fileName.startsWith('appmanifest_') || !fileName.endsWith('.acf')) continue;
          final SteamGame? game = _tryReadGame(entity, library, steamPath);
          if (game != null && game.appId != _redistAppId) games[game.appId] = game;
        }
      } catch (_) {
        // Skip libraries we cannot enumerate.
      }
    }

    final List<SteamGame> result = games.values.toList()
      ..sort((SteamGame a, SteamGame b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    _cachedGames = result;
    _cachedForSteamPath = steamPath;
    return result;
  }

  static List<SteamGame> filter(List<SteamGame> games, String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return games;
    return games.where((SteamGame g) => g.name.toLowerCase().contains(q)).toList();
  }
}

class SteamButton extends StatelessWidget {
  const SteamButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Steam Library",
      icon: const Icon(Icons.sports_esports_rounded),
      child: () => const SteamWidget(),
    );
  }
}

class SteamWidget extends StatefulWidget {
  const SteamWidget({super.key});

  @override
  State<SteamWidget> createState() => _SteamWidgetState();
}

class _SteamWidgetState extends State<SteamWidget> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchKeyboardFocusNode = FocusNode(canRequestFocus: false);
  final ScrollController _listScrollController = ScrollController();

  bool _isSetupMode = false;
  bool _isLoading = false;
  String? _errorMessage;

  String _currentQuery = "";
  List<SteamGame> _allGames = <SteamGame>[];
  List<SteamGame> _results = <SteamGame>[];
  int _selectedIndex = -1;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (SteamLibraryService.findSteamPath() == null) {
      _isSetupMode = true;
    } else {
      _loadGames();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isSetupMode) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchKeyboardFocusNode.dispose();
    _listScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadGames({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final List<SteamGame> games = await SteamLibraryService.scan(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _allGames = games;
        _results = SteamLibraryService.filter(games, _currentQuery);
        _selectedIndex = _results.isEmpty ? -1 : 0;
        _errorMessage = games.isEmpty ? "No installed games found." : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Error scanning Steam library: $e";
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      _currentQuery = value;
      if (!mounted) return;
      setState(() {
        _results = SteamLibraryService.filter(_allGames, _currentQuery);
        _selectedIndex = _results.isEmpty ? -1 : 0;
      });
    });
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_results.isEmpty) return;
      setState(() => _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1));
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_results.isEmpty) return;
      setState(() => _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1));
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _results.length) _launchGame(_results[_selectedIndex]);
    }
  }

  void _scrollToIndex() {
    if (_selectedIndex < 0 || !_listScrollController.hasClients) return;
    const double itemHeight = 56.0;
    const double viewportHeight = 320.0;
    final double offset = _selectedIndex * itemHeight;
    if (offset < _listScrollController.offset) {
      _listScrollController.jumpTo(offset.clamp(0.0, _listScrollController.position.maxScrollExtent));
    } else if (offset + itemHeight > _listScrollController.offset + viewportHeight) {
      _listScrollController
          .jumpTo((offset + itemHeight - viewportHeight).clamp(0.0, _listScrollController.position.maxScrollExtent));
    }
  }

  void _launchGame(SteamGame game) {
    WinUtils.open(game.launchUri);
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  void _openSteam() {
    WinUtils.open('steam://open/games');
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  Future<void> _pickSteamFolder() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select your Steam installation folder';
    final Directory? dir = dirPicker.getDirectory();

    Timer(const Duration(milliseconds: 1000), () => QuickMenuFunctions.keepOpen = false);
    if (dir == null || dir.path.isEmpty) return;

    if (!SteamLibraryService._isSteamDirectory(dir.path)) {
      setState(() => _errorMessage = "That folder doesn't contain steam.exe / steamapps.");
      return;
    }

    await Boxes.updateSettings(SteamLibraryService.steamPathKey, dir.path);
    SteamLibraryService.invalidateCache();
    setState(() {
      _isSetupMode = false;
      _errorMessage = null;
    });
    await _loadGames(forceRefresh: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _isSetupMode ? 'Steam Setup' : 'Steam Library',
          icon: _isSetupMode ? Icons.settings_rounded : Icons.sports_esports_rounded,
          buttonIcon: _isSetupMode ? Icons.close_rounded : Icons.settings_rounded,
          buttonTooltip: _isSetupMode ? 'Close' : 'Change Steam folder',
          buttonPressed: () {
            if (_isSetupMode) {
              if (SteamLibraryService.findSteamPath() != null) setState(() => _isSetupMode = false);
            } else {
              setState(() => _isSetupMode = true);
            }
          },
          extraActions: _isSetupMode
              ? null
              : <Widget>[
                  _HeaderIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Rescan library',
                    accent: accent,
                    onTap: () => _loadGames(forceRefresh: true),
                  ),
                  _HeaderIconButton(
                    icon: Icons.open_in_new_rounded,
                    tooltip: 'Open Steam',
                    accent: accent,
                    onTap: _openSteam,
                  ),
                ],
        ),
        _isLoading
            ? LinearProgressIndicator(
                minHeight: 1.5, color: accent.withValues(alpha: 0.2), backgroundColor: Colors.transparent)
            : const SizedBox(height: 1.8),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _isSetupMode ? _buildSetupMode() : _buildSearchMode(),
          ),
        ),
      ],
    );
  }

  Widget _buildSetupMode() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            "Steam wasn't found automatically. Select your Steam installation folder (the one containing steam.exe).",
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(150)),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Design.text.withAlpha(8),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Design.text.withAlpha(20)),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.folder_outlined, size: 14, color: Design.text.withAlpha(150)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SteamLibraryService.configuredPath.isEmpty ? 'Not set' : SteamLibraryService.configuredPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: Design.text.withAlpha(SteamLibraryService.configuredPath.isEmpty ? 110 : 220)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _pickSteamFolder,
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: const Text("Select Steam Folder"),
          ),
          if (_errorMessage != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_errorMessage!, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchMode() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: KeyboardListener(
            focusNode: _searchKeyboardFocusNode,
            onKeyEvent: _onKeyEvent,
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search_rounded, size: 16, color: Design.text.withAlpha(150)),
                hintText: "Search games...",
                isDense: true,
                filled: true,
                fillColor: Design.text.withAlpha(8),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(20)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(20)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.accent.withAlpha(100)),
                ),
              ),
            ),
          ),
        ),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: Colors.redAccent.withAlpha(30), borderRadius: BorderRadius.circular(6)),
            child: Text(_errorMessage!, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent)),
          ),
        Flexible(
          child: _results.isEmpty && !_isLoading
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      _currentQuery.isEmpty ? "No installed games found" : "No results for '$_currentQuery'",
                      style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(120)),
                    ),
                  ),
                )
              : WindowsScrollView(
                  child: ListView.builder(
                    controller: _listScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final SteamGame game = _results[index];
                      final bool isSelected = index == _selectedIndex;
                      return MouseRegion(
                        onHover: (PointerHoverEvent event) {
                          if (event.delta != Offset.zero) setState(() => _selectedIndex = index);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Design.accent.withAlpha(40) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _launchGame(game),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: Row(
                                  children: <Widget>[
                                    _GameThumbnail(game: game),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            game.name,
                                            style: TextStyle(
                                                fontSize: 13, fontWeight: FontWeight.w600, color: Design.text),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _metaLine(game),
                                            style: TextStyle(
                                              fontSize: Design.baseFontSize,
                                              color: Design.text.withAlpha(120),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.play_arrow_rounded, size: 16, color: Design.accent.withAlpha(180)),
                                    const SizedBox(width: 4),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  String _metaLine(SteamGame game) {
    final List<String> parts = <String>[];
    if (game.sizeLabel.isNotEmpty) parts.add(game.sizeLabel);
    if (game.lastPlayed != null) {
      final Duration ago = DateTime.now().difference(game.lastPlayed!);
      if (ago.inDays >= 1) {
        parts.add('Played ${ago.inDays}d ago');
      } else if (ago.inHours >= 1) {
        parts.add('Played ${ago.inHours}h ago');
      } else {
        parts.add('Played recently');
      }
    }
    return parts.isEmpty ? 'STEAM · #${game.appId}' : parts.join(' · ').toUpperCase();
  }
}

/// A compact game cover thumbnail with a graceful icon fallback.
class _GameThumbnail extends StatelessWidget {
  const _GameThumbnail({required this.game});
  final SteamGame game;

  @override
  Widget build(BuildContext context) {
    const double width = 30;
    const double height = 40;
    final Widget fallback = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Design.accent.withAlpha(20), borderRadius: BorderRadius.circular(6)),
      child: Icon(Icons.videogame_asset_rounded, size: 16, color: Design.accent.withAlpha(200)),
    );

    if (game.coverPath == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(game.coverPath!),
        width: width,
        height: height,
        fit: BoxFit.cover,
        cacheWidth: 90,
        gaplessPlayback: true,
        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => fallback,
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: accent),
        ),
      ),
    );
  }
}
