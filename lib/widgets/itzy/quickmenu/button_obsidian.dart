import 'dart:async';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class ObsidianNote {
  final String absolutePath;
  final String vaultPath;

  const ObsidianNote({
    required this.absolutePath,
    required this.vaultPath,
  });

  String get name => p.basenameWithoutExtension(absolutePath);

  /// Relative directory inside the vault, '' if the note is at the vault root.
  String get folder {
    final String relativeDir = p.dirname(p.relative(absolutePath, from: vaultPath));
    return relativeDir == '.' ? '' : relativeDir.replaceAll('\\', '/');
  }

  String get relativePath => p.relative(absolutePath, from: vaultPath).replaceAll('\\', '/');

  DateTime get lastModified {
    try {
      return File(absolutePath).lastModifiedSync();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  String get vaultName => p.basename(vaultPath);

  String get obsidianProtocolUri =>
      'obsidian://open?vault=${Uri.encodeComponent(vaultName)}&file=${Uri.encodeComponent(relativePath)}';

  static String newNoteUri(String vaultName) => 'obsidian://new?vault=${Uri.encodeComponent(vaultName)}';

  static String dailyNoteUri(String vaultName) => 'obsidian://daily?vault=${Uri.encodeComponent(vaultName)}';
}

class ObsidianVaultService {
  /// Legacy single-vault key (pre multi-vault). Migrated into [vaultPathsKey].
  static const String vaultPathKey = "obsidianVaultPath";

  /// Stores the list of configured vault folder paths.
  static const String vaultPathsKey = "obsidianVaultPaths";

  static List<ObsidianNote>? _cachedNotes;
  static String? _cachedForVaultsKey;

  /// All configured vault paths, migrating the legacy single-vault setting.
  static List<String> get vaultPaths {
    final List<String> stored = (Boxes.pref.getStringList(vaultPathsKey) ?? <String>[])
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    if (stored.isNotEmpty) return stored;

    final String legacy = (Boxes.pref.getString(vaultPathKey) ?? "").trim();
    return legacy.isEmpty ? <String>[] : <String>[legacy];
  }

  /// First configured vault, used as the default target for new/daily notes.
  static String get vaultPath => vaultPaths.isEmpty ? "" : vaultPaths.first;
  static String get vaultName => vaultNameOf(vaultPath);

  static String vaultNameOf(String path) => path.isEmpty ? "" : p.basename(path);

  static Future<void> setVaultPaths(List<String> paths) async {
    final List<String> cleaned = <String>[];
    for (final String path in paths) {
      final String trimmed = path.trim();
      if (trimmed.isNotEmpty && !cleaned.contains(trimmed)) cleaned.add(trimmed);
    }
    await Boxes.updateSettings(vaultPathsKey, cleaned);
    invalidateCache();
  }

  static Future<void> addVault(String path) async {
    final List<String> paths = vaultPaths;
    final String trimmed = path.trim();
    if (trimmed.isEmpty || paths.contains(trimmed)) return;
    await setVaultPaths(<String>[...paths, trimmed]);
  }

  static Future<void> removeVault(String path) async {
    await setVaultPaths(vaultPaths.where((String e) => e != path).toList());
  }

  static void invalidateCache() {
    _cachedNotes = null;
    _cachedForVaultsKey = null;
  }

  /// Recursively scans every configured vault for markdown notes,
  /// skipping `.git`/`.obsidian`.
  static Future<List<ObsidianNote>> scan({bool forceRefresh = false}) async {
    final List<String> paths = vaultPaths;
    if (paths.isEmpty) return <ObsidianNote>[];

    final String cacheKey = paths.join('|');
    if (!forceRefresh && _cachedNotes != null && _cachedForVaultsKey == cacheKey) {
      return _cachedNotes!;
    }

    final List<ObsidianNote> notes = <ObsidianNote>[];
    for (final String currentVaultPath in paths) {
      final Directory vaultDir = Directory(currentVaultPath);
      if (!await vaultDir.exists()) continue;

      try {
        final Stream<FileSystemEntity> entries = vaultDir.list(recursive: true, followLinks: false);
        await for (final FileSystemEntity entity in entries) {
          if (entity is! File) continue;
          if (p.extension(entity.path).toLowerCase() != '.md') continue;

          final String relative = p.relative(entity.path, from: currentVaultPath).replaceAll('\\', '/');
          if (relative.split('/').any((String segment) => segment == '.git' || segment == '.obsidian')) continue;

          notes.add(ObsidianNote(absolutePath: entity.path, vaultPath: currentVaultPath));
        }
      } catch (e) {
        Debug.add("Obsidian: Error scanning vault '$currentVaultPath': $e");
      }
    }

    notes.sort((ObsidianNote a, ObsidianNote b) => b.lastModified.compareTo(a.lastModified));

    _cachedNotes = notes;
    _cachedForVaultsKey = cacheKey;
    return notes;
  }

  static List<ObsidianNote> filter(List<ObsidianNote> notes, String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return notes;
    return notes
        .where((ObsidianNote n) => n.name.toLowerCase().contains(q) || n.folder.toLowerCase().contains(q))
        .toList();
  }

  static Future<void> appendToNote(ObsidianNote note, String text) async {
    final File file = File(note.absolutePath);
    await file.writeAsString('\r\r$text', mode: FileMode.append);
  }
}

class ObsidianButton extends StatelessWidget {
  const ObsidianButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Obsidian",
      icon: const Icon(Icons.menu_book_rounded),
      child: () => const ObsidianWidget(),
    );
  }
}

class ObsidianWidget extends StatefulWidget {
  const ObsidianWidget({super.key});

  @override
  State<ObsidianWidget> createState() => _ObsidianWidgetState();
}

class _ObsidianWidgetState extends State<ObsidianWidget> {
  final TextEditingController _searchController = TextEditingController();

  List<String> _vaultPaths = <String>[];

  /// `null` means "all vaults"; otherwise restricts search to this vault path.
  String? _selectedVaultPath;
  bool _isSetupMode = false;

  bool _isLoading = false;
  String _currentQuery = "";
  List<ObsidianNote> _allNotes = <ObsidianNote>[];
  List<ObsidianNote> _results = <ObsidianNote>[];
  String? _errorMessage;

  Timer? _debounceTimer;

  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _searchKeyboardFocusNode = FocusNode(canRequestFocus: false);
  final ScrollController _listScrollController = ScrollController();
  int _selectedIndex = -1;

  @override
  void initState() {
    super.initState();
    _vaultPaths = ObsidianVaultService.vaultPaths;
    if (_vaultPaths.isEmpty) {
      _isSetupMode = true;
    } else {
      _loadNotes();
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

  Future<void> _loadNotes({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final List<ObsidianNote> notes = await ObsidianVaultService.scan(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _allNotes = notes;
        _results = _applyFilters();
        _selectedIndex = _results.isEmpty ? -1 : 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = "Error scanning vault: $e";
        _isLoading = false;
      });
    }
  }

  /// Applies the active vault filter then the text query to [_allNotes].
  List<ObsidianNote> _applyFilters() {
    Iterable<ObsidianNote> notes = _allNotes;
    if (_selectedVaultPath != null) {
      notes = notes.where((ObsidianNote n) => n.vaultPath == _selectedVaultPath);
    }
    return ObsidianVaultService.filter(notes.toList(), _currentQuery);
  }

  /// Vault name targeted by the New/Daily note actions — the selected vault if
  /// one is active, otherwise the first configured vault.
  String get _targetVaultName => _selectedVaultPath != null
      ? ObsidianVaultService.vaultNameOf(_selectedVaultPath!)
      : ObsidianVaultService.vaultName;

  Future<void> _addVaultFolder() async {
    QuickMenuFunctions.keepOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final DirectoryPicker dirPicker = DirectoryPicker()..title = 'Select an Obsidian vault folder';
    final Directory? dir = dirPicker.getDirectory();

    Timer(const Duration(milliseconds: 1000), () {
      QuickMenuFunctions.keepOpen = false;
    });
    if (dir == null || dir.path.isEmpty) return;

    await ObsidianVaultService.addVault(dir.path);
    if (!mounted) return;
    setState(() => _vaultPaths = ObsidianVaultService.vaultPaths);
    await _loadNotes(forceRefresh: true);
  }

  Future<void> _removeVault(String path) async {
    await ObsidianVaultService.removeVault(path);
    if (!mounted) return;
    setState(() {
      _vaultPaths = ObsidianVaultService.vaultPaths;
      if (_selectedVaultPath == path) _selectedVaultPath = null;
      if (_vaultPaths.isEmpty) _isSetupMode = true;
    });
    await _loadNotes(forceRefresh: true);
  }

  void _selectVault(String? path) {
    setState(() {
      _selectedVaultPath = path;
      _results = _applyFilters();
      _selectedIndex = _results.isEmpty ? -1 : 0;
    });
  }

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _currentQuery = value;
      if (!mounted) return;
      setState(() {
        _results = _applyFilters();
        _selectedIndex = _results.isEmpty ? -1 : 0;
      });
    });
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_results.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex + 1).clamp(0, _results.length - 1);
      });
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_results.isEmpty) return;
      setState(() {
        _selectedIndex = (_selectedIndex - 1).clamp(0, _results.length - 1);
      });
      _scrollToIndex();
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_selectedIndex >= 0 && _selectedIndex < _results.length) {
        _openNote(_results[_selectedIndex]);
      }
    }
  }

  void _scrollToIndex() {
    if (_selectedIndex < 0) return;
    const double itemHeight = 44.0;
    final double offset = _selectedIndex * itemHeight;
    const double viewportHeight = 300.0;
    if (!_listScrollController.hasClients) return;

    if (offset < _listScrollController.offset) {
      _listScrollController.jumpTo(offset.clamp(0.0, _listScrollController.position.maxScrollExtent));
    } else if (offset + itemHeight > _listScrollController.offset + viewportHeight) {
      _listScrollController
          .jumpTo((offset + itemHeight - viewportHeight).clamp(0.0, _listScrollController.position.maxScrollExtent));
    }
  }

  void _openNote(ObsidianNote note) {
    WinUtils.open(note.obsidianProtocolUri);
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  void _openNewNote() {
    final String vaultName = _targetVaultName;
    if (vaultName.isEmpty) return;
    WinUtils.open(ObsidianNote.newNoteUri(vaultName));
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  void _openDailyNote() {
    final String vaultName = _targetVaultName;
    if (vaultName.isEmpty) return;
    WinUtils.open(ObsidianNote.dailyNoteUri(vaultName));
    if (kReleaseMode) QuickMenuFunctions.hideQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _isSetupMode ? 'Vault Setup' : 'Obsidian',
          icon: _isSetupMode ? Icons.vpn_key_rounded : Icons.menu_book_rounded,
          buttonIcon: _isSetupMode ? Icons.close_rounded : Icons.settings_rounded,
          buttonTooltip: _isSetupMode ? 'Close' : 'Settings',
          buttonPressed: () {
            if (_isSetupMode) {
              if (_vaultPaths.isNotEmpty) setState(() => _isSetupMode = false);
            } else {
              setState(() => _isSetupMode = true);
            }
          },
          extraActions: _isSetupMode
              ? null
              : <Widget>[
                  _HeaderIconButton(
                    icon: Icons.note_add_rounded,
                    tooltip: 'New note',
                    accent: accent,
                    onTap: _openNewNote,
                  ),
                  _HeaderIconButton(
                    icon: Icons.today_rounded,
                    tooltip: 'Daily note',
                    accent: accent,
                    onTap: _openDailyNote,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            "Add one or more Obsidian vault folders. Notes from every vault are searched together.",
            style: TextStyle(fontSize: Design.baseFontSize + 2, color: Design.text.withAlpha(150)),
          ),
        ),
        Flexible(
          child: WindowsScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _vaultPaths.isEmpty
                    ? <Widget>[
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
                              Text('No vaults added yet',
                                  style: TextStyle(fontSize: 13, color: Design.text.withAlpha(110))),
                            ],
                          ),
                        ),
                      ]
                    : _vaultPaths.map(_buildVaultRow).toList(),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: _addVaultFolder,
                icon: const Icon(Icons.create_new_folder_rounded, size: 16),
                label: const Text("Add Vault Folder"),
              ),
              if (_errorMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(_errorMessage!, style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVaultRow(String path) {
    final bool exists = Directory(path).existsSync();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Design.text.withAlpha(20)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            exists ? Icons.folder_rounded : Icons.folder_off_rounded,
            size: 14,
            color: exists ? Design.text.withAlpha(150) : Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ObsidianVaultService.vaultNameOf(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Design.text),
                ),
                Text(
                  exists ? path : '$path (missing)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(exists ? 120 : 160)),
                ),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: 'Remove vault',
            accent: Colors.redAccent,
            onTap: () => _removeVault(path),
          ),
        ],
      ),
    );
  }

  /// Result subtitle: folder path, prefixed with the vault name when more than
  /// one vault is configured and the list isn't already filtered to one vault.
  String _subtitleFor(ObsidianNote note) {
    final String folder = note.folder.isEmpty ? 'VAULT ROOT' : note.folder.toUpperCase();
    if (_vaultPaths.length > 1 && _selectedVaultPath == null) {
      return '${note.vaultName.toUpperCase()} · $folder';
    }
    return folder;
  }

  Widget _buildVaultFilterBar() {
    return SizedBox(
      height: 34,
      child: WindowsScrollView(
        scrollDirection: Axis.horizontal,
        showScrollbar: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Row(
            children: <Widget>[
              _buildVaultChip(label: 'All', path: null),
              ..._vaultPaths.map((String path) => _buildVaultChip(
                    label: ObsidianVaultService.vaultNameOf(path),
                    path: path,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVaultChip({required String label, required String? path}) {
    final bool isSelected = _selectedVaultPath == path;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: () => _selectVault(path),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected ? Design.accent.withAlpha(40) : Design.text.withAlpha(8),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: isSelected ? Design.accent.withAlpha(120) : Design.text.withAlpha(20),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w600,
                color: isSelected ? Design.accent.withAlpha(230) : Design.text.withAlpha(160),
              ),
            ),
          ),
        ),
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
                hintText: "Search notes...",
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
        if (_vaultPaths.length > 1) _buildVaultFilterBar(),
        if (_errorMessage != null)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.redAccent.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Colors.redAccent),
            ),
          ),
        Flexible(
          child: _results.isEmpty && !_isLoading
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      _currentQuery.isEmpty ? "No notes found in vault" : "No results found for '$_currentQuery'",
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
                      final ObsidianNote note = _results[index];
                      final bool isSelected = index == _selectedIndex;
                      return MouseRegion(
                        onHover: (PointerHoverEvent event) {
                          if (event.delta != Offset.zero) {
                            setState(() => _selectedIndex = index);
                          }
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
                              onTap: () => _openNote(note),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: Design.accent.withAlpha(20),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child:
                                          Icon(Icons.menu_book_rounded, size: 14, color: Design.accent.withAlpha(200)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            note.name,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Design.text,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _subtitleFor(note),
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
                                    Icon(Icons.open_in_new_rounded, size: 14, color: Design.text.withAlpha(80)),
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
}

// ---------------------------------------------------------------------------
// Small header icon button helper
// ---------------------------------------------------------------------------

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
