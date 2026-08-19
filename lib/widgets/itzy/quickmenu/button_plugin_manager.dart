import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../pages/launcher/plugins/plugin_auto_updater.dart';
import '../../../pages/launcher/plugins/plugin_gallery.dart';
import '../../../pages/launcher/plugins/plugin_icons.dart';
import '../../../pages/launcher/plugins/plugin_manifest.dart';
import '../../../pages/launcher/plugins/plugin_registry.dart';
import '../../../platform/app_paths.dart';
import '../../../platform/file_picker_service.dart';
import '../../../services/browser_bridge_service.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/modern_dropdown.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// Top-bar entry point for the Launcher Plugins manager.
class PluginManagerButton extends StatelessWidget {
  const PluginManagerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Launcher Plugins",
      icon: const Icon(Icons.extension_outlined),
      child: () => const PluginManagerPanel(),
    );
  }
}

/// Where users submit their own plugins for review — opens the pre-filled
/// "Plugin submission" GitHub issue template. Curated submissions land in
/// `resources/plugins.json` and show up in everyone's gallery.
const String _submitPluginUrl = 'https://github.com/Far-Se/tabame/issues/new?template=plugin_submission.md';
const String _chromeConnectorUrl =
    'https://chromewebstore.google.com/detail/tabame-connector/affgkglfpdpkdfolkogkaplllgmmkhdd?authuser=0&hl=en';
const String _firefoxConnectorUrl = 'https://addons.mozilla.org/en-US/firefox/addon/tabame-connector-for-firefox/';

enum _PanelMode { installed, gallery, makeYourOwn }

PluginManifest? _findInstalledPlugin(String id) {
  final String lowerId = id.toLowerCase();
  for (final PluginManifest manifest in PluginRegistry.manifests) {
    if (manifest.id.toLowerCase() == lowerId) return manifest;
  }
  return null;
}

/// Three-mode panel for installed plugins, the community gallery, and authoring
/// guidance for local plugins.
class PluginManagerPanel extends StatefulWidget {
  const PluginManagerPanel({super.key});

  @override
  State<PluginManagerPanel> createState() => _PluginManagerPanelState();
}

class _PluginManagerPanelState extends State<PluginManagerPanel> {
  _PanelMode _mode = _PanelMode.installed;
  bool _reloading = false;
  String? _busyId;
  String _keywordError = '';

  List<PluginGalleryEntry>? _galleryEntries;
  bool _galleryLoading = false;
  String _galleryError = '';
  String? _installingId;
  bool _installingRecommended = false;
  String _installStatus = '';
  final TextEditingController _installedSearchController = TextEditingController();
  final TextEditingController _gallerySearchController = TextEditingController();
  String _galleryCategory = '';
  bool _pluginDirectoryBusy = false;
  String _pluginDirectoryStatus = '';
  bool _pluginDirectoryStatusError = false;
  bool _autoUpdateBusy = false;
  String _autoUpdateError = '';

  @override
  void dispose() {
    _installedSearchController.dispose();
    _gallerySearchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Rescan on open so freshly-dropped plugins show up without a restart.
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _reloading = true);
    await PluginRegistry.load();
    if (!mounted) return;
    setState(() => _reloading = false);
  }

  Future<void> _changePluginDirectory() async {
    if (_pluginDirectoryBusy) return;

    final Directory currentDirectory = Directory(AppPaths.pluginsDirectory);
    final DirectoryPicker picker = DirectoryPicker()
      ..title = 'Select Launcher Plugins Folder'
      ..initialDirectory = currentDirectory.existsSync() ? currentDirectory.path : null
      ..alwaysShowInitialDirectory = currentDirectory.existsSync();
    final Directory? selectedDirectory = await picker.getDirectoryAsync();
    if (!mounted || selectedDirectory == null || selectedDirectory.path.trim().isEmpty) return;

    setState(() {
      _pluginDirectoryBusy = true;
      _pluginDirectoryStatus = '';
      _pluginDirectoryStatusError = false;
    });
    final String? error = await AppPaths.setPluginsDirectory(selectedDirectory.path);
    if (error == null) await PluginRegistry.load();
    if (!mounted) return;
    setState(() {
      _pluginDirectoryBusy = false;
      _pluginDirectoryStatusError = error != null;
      _pluginDirectoryStatus = error ?? 'Plugin folder moved successfully.';
    });
  }

  Future<void> _toggle(PluginManifest manifest, bool enabled) async {
    setState(() => _busyId = manifest.id);
    await PluginRegistry.setEnabled(manifest, enabled);
    if (!mounted) return;
    setState(() => _busyId = null);
  }

  Future<void> _setAutoUpdate(bool enabled) async {
    if (_autoUpdateBusy) return;
    setState(() {
      _autoUpdateBusy = true;
      _autoUpdateError = '';
    });
    try {
      await Boxes.updateSettings(PluginAutoUpdater.settingKey, enabled);
      user.pluginAutoUpdate = enabled;
    } catch (_) {
      _autoUpdateError = 'Could not save the automatic update setting.';
    }
    if (!mounted) return;
    setState(() => _autoUpdateBusy = false);
  }

  Future<void> _editKeyword(PluginManifest manifest) async {
    final Set<String> occupiedKeywords = PluginRegistry.manifests
        .where((PluginManifest other) => other.directory != manifest.directory)
        .map((PluginManifest other) => other.keywordLower)
        .toSet();
    final String? keyword = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _PluginKeywordDialog(
        initialKeyword: manifest.keyword,
        occupiedKeywords: occupiedKeywords,
      ),
    );
    if (!mounted || keyword == null) return;

    setState(() {
      _busyId = manifest.id;
      _keywordError = '';
    });
    final String? error = await PluginRegistry.setKeyword(manifest, keyword);
    if (!mounted) return;
    setState(() {
      _busyId = null;
      _keywordError = error ?? '';
    });
  }

  Future<void> _loadGallery({bool force = false}) async {
    if (_galleryLoading) return;
    setState(() {
      _galleryLoading = true;
      _galleryError = '';
    });
    try {
      final List<PluginGalleryEntry> entries = await PluginGallery.fetchIndex(force: force);
      if (!mounted) return;
      setState(() {
        entries.sort((PluginGalleryEntry a, PluginGalleryEntry b) => a.name.compareTo(b.name));
        _galleryEntries = entries;
        _galleryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _galleryLoading = false;
        _galleryError = 'Could not load the gallery — check your connection.';
      });
    }
  }

  Future<void> _install(PluginGalleryEntry entry) async {
    if (_installingId != null) return;
    setState(() {
      _installingId = entry.id;
      _installStatus = '';
    });
    final String? error = await PluginGallery.install(entry);
    if (!mounted) return;
    setState(() {
      _installingId = null;
      _installStatus = error == null
          ? 'Installed "${entry.name}" — type "${entry.keyword}" in the launcher'
          : 'Install failed: $error';
    });
  }

  Future<void> _installAllRecommended() async {
    if (_installingId != null || _installingRecommended) return;
    final List<PluginGalleryEntry> pending = (_galleryEntries ?? <PluginGalleryEntry>[])
        .where(
          (PluginGalleryEntry entry) =>
              entry.recommended && entry.installable && _findInstalledPlugin(entry.id) == null,
        )
        .toList(growable: false);
    if (pending.isEmpty) {
      setState(() => _installStatus = 'All recommended plugins are already installed.');
      return;
    }

    setState(() {
      _installingRecommended = true;
      _installStatus = '';
    });
    int installed = 0;
    final List<String> failures = <String>[];
    for (final PluginGalleryEntry entry in pending) {
      if (!mounted) return;
      setState(() => _installingId = entry.id);
      final String? error = await PluginGallery.install(entry);
      if (error == null) {
        installed++;
      } else {
        failures.add(entry.name);
      }
    }
    if (!mounted) return;
    setState(() {
      _installingId = null;
      _installingRecommended = false;
      _installStatus = failures.isEmpty
          ? 'Installed all $installed recommended plugins.'
          : 'Installed $installed of ${pending.length} recommended plugins. Failed: ${failures.join(', ')}';
    });
  }

  void _switchMode(_PanelMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == _PanelMode.gallery && _galleryEntries == null) _loadGallery();
  }

  bool _matchesSearch(String query, Iterable<String> fields) {
    return query.isEmpty || fields.any((String field) => field.toLowerCase().contains(query));
  }

  Widget _buildSearchField({required TextEditingController controller, required String hintText}) {
    return TextField(
      controller: controller,
      onChanged: (_) => setState(() {}),
      style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(110)),
        prefixIcon: Icon(Icons.search_rounded, size: 16, color: Design.accent),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  setState(() {});
                },
                icon: Icon(Icons.close_rounded, size: 16, color: Design.text.withAlpha(130)),
              ),
        filled: true,
        fillColor: Design.accent.withAlpha(12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Design.accent.withAlpha(90), width: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool gallery = _mode == _PanelMode.gallery;
    final bool makeYourOwn = _mode == _PanelMode.makeYourOwn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        PanelHeader(
          title: makeYourOwn ? "Make Your Own Plugin" : (gallery ? "Plugin Gallery" : "Launcher Plugins"),
          icon:
              makeYourOwn ? Icons.construction_rounded : (gallery ? Icons.storefront_rounded : Icons.extension_rounded),
          buttonIcon: makeYourOwn
              ? null
              : ((gallery ? _galleryLoading : _reloading) ? Icons.hourglass_bottom_rounded : Icons.refresh_rounded),
          buttonTooltip: makeYourOwn ? null : (gallery ? "Refresh gallery" : "Reload plugins"),
          buttonPressed: makeYourOwn
              ? null
              : (gallery ? (_galleryLoading ? null : () => _loadGallery(force: true)) : (_reloading ? null : _reload)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: _buildModeRail(),
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: makeYourOwn ? _buildMakeYourOwn() : (gallery ? _buildGallery() : _buildInstalled()),
          ),
        ),
      ],
    );
  }

  Widget _buildModeRail() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          _modeChip(
            label: 'Installed',
            icon: Icons.extension_rounded,
            count: PluginRegistry.manifests.length,
            mode: _PanelMode.installed,
          ),
          const SizedBox(width: 6),
          _modeChip(
            label: 'Gallery',
            icon: Icons.storefront_rounded,
            count: _galleryEntries?.length,
            mode: _PanelMode.gallery,
          ),
          const SizedBox(width: 6),
          _modeChip(
            label: 'Make Your Own',
            icon: Icons.construction_rounded,
            mode: _PanelMode.makeYourOwn,
          ),
        ],
      ),
    );
  }

  Widget _modeChip({required String label, required IconData icon, required _PanelMode mode, int? count}) {
    final bool selected = _mode == mode;
    return InkWell(
      onTap: () => _switchMode(mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Design.accent.withAlpha(18) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: selected ? Design.accent : Design.text.withAlpha(130)),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: Design.baseFontSize + 0.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: selected ? Design.accent : Design.text.withAlpha(150),
              ),
            ),
            if (count != null) ...<Widget>[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  color: (selected ? Design.accent : Design.text).withAlpha(140),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Make your own mode
  // ---------------------------------------------------------------------------

  Widget _buildMakeYourOwn() {
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        child: MarkdownBody(
          data: '''
Build a plugin with your favorite AI coding assistant:

1. Copy [TABAME_PLUGIN_SKILL.md](https://github.com/Far-Se/tabame/blob/main/skills/TABAME_PLUGIN_SKILL.md) or [TABAME_PLUGIN_SKILL.min.md](https://github.com/Far-Se/tabame/blob/main/skills/TABAME_PLUGIN_SKILL.min.md) (the 'skills' folder has multiple separate skills).
2. Open your favorite AI coding site or app and paste the file.
3. Tell the AI what plugin you need, with detailed instructions for how it should work.
4. Create a new folder inside the plugin installation folder shown on the Installed tab.
5. Paste in your `plugin.json` and script files.
6. Open the launcher and type the shortcut.
7. If you want to share it with the community, make an issue [HERE](https://github.com/Far-Se/tabame/issues/new?template=plugin_submission.md) with the code, either paste it or zip/gist/rep.
''',
          selectable: true,
          onTapLink: (String text, String? href, String title) {
            if (href != null) WinUtils.open(href);
          },
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(fontSize: Design.baseFontSize + 0.5, height: 1.45, color: Design.text.withAlpha(190)),
            a: TextStyle(
              fontSize: Design.baseFontSize + 0.5,
              fontWeight: FontWeight.w600,
              color: Design.accent,
            ),
            listBullet: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.accent),
            code: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(220)),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Installed mode
  // ---------------------------------------------------------------------------

  Widget _buildInstalled() {
    final List<PluginManifest> plugins = PluginRegistry.manifests;
    final String query = _installedSearchController.text.trim().toLowerCase();
    final List<PluginManifest> filteredPlugins = plugins
        .where(
          (PluginManifest manifest) => _matchesSearch(query, <String>[
            manifest.name,
            manifest.id,
            manifest.keyword,
            manifest.description,
            manifest.runtime,
          ]),
        )
        .toList(growable: false);
    final int enabledCount = plugins.where((PluginManifest m) => m.enabled).length;

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: C.start,
          children: <Widget>[
            _buildSectionLabel(
              label: "Plugin folder",
              countText: "CONFIG",
              icon: Icons.folder_rounded,
            ),
            const SizedBox(height: 8),
            _buildPluginDirectoryCard(),
            const SizedBox(height: 16),
            _buildSectionLabel(
              label: "Updates",
              countText: user.pluginAutoUpdate ? "ON" : "OFF",
              icon: Icons.system_update_alt_rounded,
            ),
            const SizedBox(height: 8),
            _buildAutoUpdateCard(),
            const SizedBox(height: 16),
            _buildSectionLabel(
              label: "Browser integration",
              countText: "Optional",
              icon: Icons.language_rounded,
            ),
            const SizedBox(height: 8),
            const _BrowserBridgeCard(),
            const SizedBox(height: 16),
            _buildSectionLabel(
              label: "Installed",
              countText: "$enabledCount/${plugins.length}",
              icon: Icons.extension_rounded,
            ),
            const SizedBox(height: 8),
            _buildSearchField(
              controller: _installedSearchController,
              hintText: "Search installed plugins...",
            ),
            const SizedBox(height: 8),
            if (_keywordError.isNotEmpty) ...<Widget>[
              _buildStatusStrip(_keywordError, error: true),
              const SizedBox(height: 8),
            ],
            if (plugins.isEmpty)
              _buildInstalledEmpty()
            else if (filteredPlugins.isEmpty)
              _buildNoSearchResults("No installed plugins match your search.")
            else
              for (final PluginManifest m in filteredPlugins) ...<Widget>[
                _PluginCard(
                  manifest: m,
                  busy: _busyId == m.id,
                  onToggle: (bool value) => _toggle(m, value),
                  onEditKeyword: _busyId == m.id ? null : () => _editKeyword(m),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResults(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.search_off_rounded, size: 18, color: Design.text.withAlpha(90)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(130)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPluginDirectoryCard() {
    final Color accent = Design.accent;
    final Color text = Design.text;
    final Color statusColor = _pluginDirectoryStatusError ? Colors.red.shade400 : accent;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: text.withAlpha(16)),
      ),
      child: Row(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.folder_rounded, size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Text(
                  'Installation folder',
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: FontWeight.w700,
                    color: text.withAlpha(235),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppPaths.pluginsDirectory,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 0.5,
                    height: 1.25,
                    color: text.withAlpha(140),
                  ),
                ),
                if (_pluginDirectoryStatus.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  Text(
                    _pluginDirectoryStatus,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 1,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Change installation folder',
            waitDuration: const Duration(milliseconds: 400),
            child: InkWell(
              onTap: _pluginDirectoryBusy ? null : _changePluginDirectory,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withAlpha(60)),
                ),
                child: _pluginDirectoryBusy
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(Icons.edit_location_alt_rounded, size: 14, color: accent),
                          const SizedBox(width: 5),
                          Text(
                            'CHANGE',
                            style: TextStyle(
                              fontSize: Design.baseFontSize - 1,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoUpdateCard() {
    final Color accent = Design.accent;
    final Color text = Design.text;
    final bool enabled = user.pluginAutoUpdate;

    return InkWell(
      onTap: _autoUpdateBusy ? null : () => _setAutoUpdate(!enabled),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
        decoration: BoxDecoration(
          color: enabled ? accent.withAlpha(10) : text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: enabled ? accent.withAlpha(30) : text.withAlpha(16)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: (enabled ? accent : text).withAlpha(enabled ? 24 : 12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.update_rounded, size: 16, color: enabled ? accent : text.withAlpha(130)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: C.start,
                children: <Widget>[
                  Text(
                    'Update plugins at startup',
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 1.5,
                      fontWeight: FontWeight.w700,
                      color: text.withAlpha(235),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Checks plugins.json and installs newer versions of your gallery plugins.',
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      height: 1.25,
                      color: text.withAlpha(140),
                    ),
                  ),
                  if (_autoUpdateError.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      _autoUpdateError,
                      style: TextStyle(
                        fontSize: Design.baseFontSize - 1,
                        fontWeight: FontWeight.w600,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 40,
              height: 30,
              child: Center(
                child: _autoUpdateBusy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                      )
                    : Transform.scale(
                        scale: 0.7,
                        child: Switch(
                          value: enabled,
                          activeThumbColor: accent,
                          onChanged: _setAutoUpdate,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledEmpty() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.extension_off_outlined, size: 44, color: Design.text.withAlpha(50)),
            const SizedBox(height: 14),
            Text(
              "No launcher plugins installed",
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w600,
                color: Design.text.withAlpha(160),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Install one from the Gallery, or drop a plugin folder into ${AppPaths.pluginsDirectory}.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(110)),
            ),
            const SizedBox(height: 16),
            _buildSubmitStrip(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Gallery mode
  // ---------------------------------------------------------------------------

  Widget _buildGallery() {
    if (_galleryLoading && _galleryEntries == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Design.accent),
          ),
        ),
      );
    }

    if (_galleryError.isNotEmpty && (_galleryEntries == null || _galleryEntries!.isEmpty)) {
      return _buildGalleryError();
    }

    final List<PluginGalleryEntry> entries = _galleryEntries ?? <PluginGalleryEntry>[];
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                "The gallery is empty for now.",
                style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(140)),
              ),
              const SizedBox(height: 12),
              _buildSubmitStrip(),
            ],
          ),
        ),
      );
    }

    final String query = _gallerySearchController.text.trim().toLowerCase();
    final List<String> categories = entries
        .map((PluginGalleryEntry entry) => entry.category.trim().isEmpty ? 'Other' : entry.category.trim())
        .toSet()
        .toList()
      ..sort((String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final String selectedCategory = categories.contains(_galleryCategory) ? _galleryCategory : '';
    final List<PluginGalleryEntry> categoryEntries = entries
        .where(
          (PluginGalleryEntry entry) =>
              selectedCategory.isEmpty ||
              (entry.category.trim().isEmpty ? 'Other' : entry.category.trim()) == selectedCategory,
        )
        .toList(growable: false);
    final List<PluginGalleryEntry> filteredEntries = categoryEntries
        .where(
          (PluginGalleryEntry entry) => _matchesSearch(query, <String>[
            entry.name,
            entry.id,
            entry.keyword,
            entry.description,
            entry.category,
            entry.author,
            entry.runtime,
          ]),
        )
        .toList(growable: false);

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: C.start,
          children: <Widget>[
            if (_installStatus.isNotEmpty) ...<Widget>[
              _buildStatusStrip(
                _installStatus,
                error: _installStatus.startsWith('Install failed') || _installStatus.contains('Failed:'),
              ),
              const SizedBox(height: 8),
            ],
            _buildSectionLabel(
              label: "Community Plugins",
              countText: query.isEmpty && selectedCategory.isEmpty
                  ? "${entries.length}"
                  : "${filteredEntries.length}/${entries.length}",
              icon: Icons.storefront_rounded,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Expanded(
                  child: _buildSearchField(
                    controller: _gallerySearchController,
                    hintText: "Search gallery...",
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: ModernDropdown<String>(
                    value: selectedCategory,
                    height: 40,
                    itemHeight: 36,
                    prefixIcon: Icon(Icons.category_outlined, size: 16, color: Design.accent),
                    decoration: BoxDecoration(
                      color: Design.accent.withAlpha(12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    dropdownMenuEntriesShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Design.text.withAlpha(24)),
                    ),
                    items: <ModernDropdownItem<String>>[
                      const ModernDropdownItem<String>(value: '', label: 'All categories'),
                      for (final String category in categories)
                        ModernDropdownItem<String>(value: category, label: category),
                    ],
                    onChanged: (String? category) => setState(() => _galleryCategory = category ?? ''),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (categoryEntries.any((PluginGalleryEntry entry) => entry.recommended)) ...<Widget>[
              _buildInstallRecommendedStrip(categoryEntries),
              const SizedBox(height: 8),
            ],
            if (filteredEntries.isEmpty)
              _buildNoSearchResults(
                query.isNotEmpty
                    ? selectedCategory.isEmpty
                        ? "No gallery plugins match your search."
                        : 'No plugins in "$selectedCategory" match your search.'
                    : 'No gallery plugins are available in "$selectedCategory".',
              )
            else
              for (final PluginGalleryEntry entry in filteredEntries) ...<Widget>[
                _GalleryCard(
                  entry: entry,
                  installedManifest: _findInstalledPlugin(entry.id),
                  installing: _installingId == entry.id,
                  onInstall: () => _install(entry),
                  onOpenHomepage: entry.homepage.isEmpty ? null : () => WinUtils.open(entry.homepage),
                ),
                const SizedBox(height: 8),
              ],
            _buildSubmitStrip(),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallRecommendedStrip(List<PluginGalleryEntry> entries) {
    final int pending = entries
        .where(
          (PluginGalleryEntry entry) =>
              entry.recommended && entry.installable && _findInstalledPlugin(entry.id) == null,
        )
        .length;
    final bool busy = _installingRecommended;
    return InkWell(
      onTap: busy || pending == 0 ? null : _installAllRecommended,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(pending == 0 ? 7 : 16),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Design.accent.withAlpha(pending == 0 ? 24 : 55)),
        ),
        child: Row(
          children: <Widget>[
            if (busy)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Design.accent),
              )
            else
              Icon(Icons.auto_awesome_rounded, size: 16, color: Design.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Install all Recommended Plugins',
                style: TextStyle(
                  fontSize: Design.baseFontSize + 0.5,
                  fontWeight: FontWeight.w700,
                  color: pending == 0 ? Design.text.withAlpha(105) : Design.text.withAlpha(220),
                ),
              ),
            ),
            _GalleryCard.pill(
              pending == 0 ? 'INSTALLED' : '$pending PENDING',
              Design.accent.withAlpha(20),
              pending == 0 ? Design.text.withAlpha(105) : Design.accent,
            ),
          ],
        ),
      ),
    );
  }

  /// Invitation to contribute a plugin — links to the GitHub submission
  /// template. Submissions are reviewed manually and added to the gallery.
  Widget _buildSubmitStrip() {
    return InkWell(
      onTap: () => WinUtils.open(_submitPluginUrl),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Design.accent.withAlpha(10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Design.accent.withAlpha(40)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.upload_rounded, size: 16, color: Design.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: C.start,
                children: <Widget>[
                  Text(
                    "Built a plugin? Submit it",
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 0.5,
                      fontWeight: FontWeight.w700,
                      color: Design.text.withAlpha(220),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Share it via GitHub — reviewed plugins are added to this gallery.",
                    style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(120)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.open_in_new_rounded, size: 13, color: Design.accent.withAlpha(180)),
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded, size: 44, color: Design.text.withAlpha(50)),
            const SizedBox(height: 14),
            Text(
              _galleryError,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(150)),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _loadGallery(force: true),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
                decoration: BoxDecoration(
                  color: Design.accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Design.accent.withAlpha(80)),
                ),
                child: Text(
                  'RETRY',
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Design.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStrip(String message, {bool error = false}) {
    final Color color = error ? Colors.red.shade400 : Design.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(40)),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSectionLabel({
    required String label,
    required String countText,
    required IconData icon,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Design.accent.withAlpha(28),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            countText,
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }
}

class _BrowserBridgeCard extends StatelessWidget {
  const _BrowserBridgeCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrowserBridgeStatus>(
      valueListenable: BrowserBridgeService.instance.statusNotifier,
      builder: (BuildContext context, BrowserBridgeStatus status, Widget? child) {
        final Color accent = Design.accent;
        final Color text = Design.text;
        final bool enabled = status.enabled;
        final (String, Color, IconData) state = switch (status.phase) {
          BrowserBridgePhase.disabled => (
              'Off · browser plugins cannot connect',
              text.withAlpha(120),
              Icons.power_settings_new_rounded,
            ),
          BrowserBridgePhase.starting => (
              'Starting on 127.0.0.1:${status.port}',
              accent,
              Icons.hourglass_top_rounded,
            ),
          BrowserBridgePhase.waiting => (
              'On · waiting for the Chromium extension',
              const Color(0xFFD18B47),
              Icons.link_off_rounded,
            ),
          BrowserBridgePhase.connected => (
              'Connected${status.extensionVersion.isEmpty ? '' : ' · extension ${status.extensionVersion}'}',
              const Color(0xFF3D9B72),
              Icons.link_rounded,
            ),
          BrowserBridgePhase.error => (
              status.error.isEmpty ? 'Could not start the connector' : status.error,
              const Color(0xFFC86464),
              Icons.error_outline_rounded,
            ),
        };

        return Container(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
          decoration: BoxDecoration(
            color: enabled ? accent.withAlpha(10) : text.withAlpha(7),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: enabled ? accent.withAlpha(30) : text.withAlpha(16)),
          ),
          child: Row(
            crossAxisAlignment: C.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: (enabled ? accent : text).withAlpha(enabled ? 28 : 14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.language_rounded, size: 16, color: enabled ? accent : text.withAlpha(130)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: C.start,
                  children: <Widget>[
                    Text(
                      'Persistent browser connector',
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 1.5,
                        fontWeight: FontWeight.w700,
                        color: text.withAlpha(enabled ? 235 : 150),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Keeps the extension paired while Tabame is running, so browser plugins open instantly. Install the connector below, then run the `browser` plugin to finish pairing.',
                      style: TextStyle(
                        fontSize: Design.baseFontSize - 0.5,
                        height: 1.25,
                        color: text.withAlpha(enabled ? 140 : 100),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: <Widget>[
                        _storeLink(label: 'Chrome Web Store', url: _chromeConnectorUrl, accent: accent),
                        _storeLink(label: 'Firefox Add-ons', url: _firefoxConnectorUrl, accent: accent),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: <Widget>[
                        Icon(state.$3, size: 12, color: state.$2),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            state.$1,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Design.baseFontSize - 1,
                              fontWeight: FontWeight.w600,
                              color: state.$2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 40,
                height: 30,
                child: Center(
                  child: status.phase == BrowserBridgePhase.starting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        )
                      : Transform.scale(
                          scale: 0.7,
                          child: Switch(
                            value: enabled,
                            activeThumbColor: accent,
                            onChanged: (bool value) => BrowserBridgeService.instance.setEnabled(value),
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _storeLink({required String label, required String url, required Color accent}) {
    return InkWell(
      onTap: () => WinUtils.open(url),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withAlpha(12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(42)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.open_in_new_rounded, size: 12, color: accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the plugin list: icon, name + keyword, description, on/off switch.
class _PluginCard extends StatefulWidget {
  const _PluginCard({
    required this.manifest,
    required this.busy,
    required this.onToggle,
    required this.onEditKeyword,
  });

  final PluginManifest manifest;
  final bool busy;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEditKeyword;

  @override
  State<_PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<_PluginCard> {
  bool _keywordHovered = false;

  @override
  Widget build(BuildContext context) {
    final PluginManifest manifest = widget.manifest;
    final bool enabled = manifest.enabled;
    final Color accent = Design.accent;
    final Color text = Design.text;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: enabled ? accent.withAlpha(10) : text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: enabled ? accent.withAlpha(30) : text.withAlpha(16)),
      ),
      child: Row(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: (enabled ? accent : text).withAlpha(enabled ? 28 : 14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              PluginIcons.resolve(manifest.icon),
              size: 16,
              color: enabled ? accent : text.withAlpha(130),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        manifest.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: FontWeight.w700,
                          color: text.withAlpha(enabled ? 235 : 150),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildKeywordBadge(manifest.keyword, enabled, accent),
                  ],
                ),
                if (manifest.description.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    manifest.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      height: 1.25,
                      color: text.withAlpha(enabled ? 140 : 100),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 30,
            child: Center(
              child: widget.busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                    )
                  : Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: enabled,
                        activeThumbColor: accent,
                        onChanged: widget.onToggle,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordBadge(String keyword, bool enabled, Color accent) {
    final bool editable = widget.onEditKeyword != null;
    final bool showEdit = editable && _keywordHovered;
    final Color foreground = accent.withAlpha(enabled || showEdit ? 255 : 150);
    final Widget badge = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: showEdit ? accent.withAlpha(38) : accent.withAlpha(enabled ? 22 : 12),
        borderRadius: BorderRadius.circular(999),
        border: showEdit ? Border.all(color: accent.withAlpha(80)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showEdit) ...<Widget>[
            Icon(Icons.edit_rounded, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            keyword,
            style: TextStyle(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: foreground,
            ),
          ),
        ],
      ),
    );

    return MouseRegion(
      cursor: editable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: editable ? (_) => setState(() => _keywordHovered = true) : null,
      onExit: editable ? (_) => setState(() => _keywordHovered = false) : null,
      child: editable
          ? Tooltip(
              message: 'Edit keyword',
              waitDuration: const Duration(milliseconds: 400),
              child: InkWell(
                onTap: widget.onEditKeyword,
                borderRadius: BorderRadius.circular(999),
                child: badge,
              ),
            )
          : badge,
    );
  }
}

class _PluginKeywordDialog extends StatefulWidget {
  const _PluginKeywordDialog({
    required this.initialKeyword,
    required this.occupiedKeywords,
  });

  final String initialKeyword;
  final Set<String> occupiedKeywords;

  @override
  State<_PluginKeywordDialog> createState() => _PluginKeywordDialogState();
}

class _PluginKeywordDialogState extends State<_PluginKeywordDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialKeyword);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final String keyword = _controller.text.trim();
    if (keyword.isEmpty) {
      setState(() => _error = 'Enter a keyword.');
      return;
    }
    if (widget.occupiedKeywords.contains(keyword.toLowerCase())) {
      setState(() => _error = 'That keyword is already used by another plugin.');
      return;
    }
    Navigator.of(context).pop(keyword);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: <Widget>[
          Icon(Icons.edit_rounded, size: 18, color: Design.accent),
          const SizedBox(width: 8),
          const Text('Edit plugin keyword'),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: TextField(
          controller: _controller,
          autofocus: true,
          selectAllOnFocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Keyword',
            hintText: 'e.g. weather',
            helperText: 'Type this keyword to start the plugin in the launcher.',
            errorText: _error,
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _save(),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// One gallery row: icon, name + keyword + runtime pills, description,
/// author/version meta, and the install action.
class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.entry,
    required this.installedManifest,
    required this.installing,
    required this.onInstall,
    this.onOpenHomepage,
  });

  final PluginGalleryEntry entry;
  final PluginManifest? installedManifest;
  final bool installing;
  final VoidCallback onInstall;
  final VoidCallback? onOpenHomepage;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color text = Design.text;
    final PluginManifest? manifest = installedManifest;
    final bool updateAvailable =
        manifest != null && PluginGallery.isRemoteVersionGreater(entry.version, manifest.version);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: text.withAlpha(16)),
      ),
      child: Row(
        crossAxisAlignment: C.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(PluginIcons.resolve(entry.icon), size: 16, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: C.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        entry.name,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1.5,
                          fontWeight: FontWeight.w700,
                          color: text.withAlpha(235),
                        ),
                      ),
                    ),
                    if (onOpenHomepage != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Tooltip(
                        message: 'Open homepage',
                        waitDuration: const Duration(milliseconds: 400),
                        child: InkWell(
                          onTap: onOpenHomepage,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.open_in_new_rounded, size: 13, color: text.withAlpha(110)),
                          ),
                        ),
                      ),
                    ]
                  ],
                ),
                if (entry.description.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    entry.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      height: 1.25,
                      color: text.withAlpha(140),
                    ),
                  ),
                ],
                if (entry.recommended || entry.category.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: <Widget>[
                      if (entry.recommended)
                        _pill('RECOMMENDED', accent.withAlpha(25), accent, icon: Icons.auto_awesome_rounded),
                      if (entry.category.trim().isNotEmpty)
                        _pill(entry.category, text.withAlpha(12), text.withAlpha(155), icon: Icons.sell_outlined),
                    ],
                  ),
                ],
                if (entry.author.isNotEmpty || entry.version.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    <String>[
                      if (entry.author.isNotEmpty) 'by ${entry.author}',
                      if (entry.version.isNotEmpty) 'v${entry.version}',
                    ].join(' · '),
                    style: TextStyle(fontSize: Design.baseFontSize - 1, color: text.withAlpha(100)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              _buildInstallAction(accent, text, updateAvailable),
              const SizedBox(height: 3),
              if (entry.keyword.isNotEmpty) ...<Widget>[
                _pill(entry.keyword, accent.withAlpha(22), accent),
              ],
              const SizedBox(height: 3),
              if (entry.runtime.isNotEmpty) ...<Widget>[
                _pill(entry.runtime, text.withAlpha(12), text.withAlpha(150)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstallAction(Color accent, Color text, bool updateAvailable) {
    if (installing) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
        ),
      );
    }
    if (updateAvailable) {
      return Tooltip(
        message: 'Update plugin',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: entry.installable ? onInstall : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: accent.withAlpha(28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withAlpha(80)),
            ),
            child: Text(
              'UPDATE',
              style: TextStyle(
                fontSize: Design.baseFontSize - 0.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: accent,
              ),
            ),
          ),
        ),
      );
    }
    if (installedManifest != null) {
      return Tooltip(
        message: 'Installed — tap to reinstall/update',
        waitDuration: const Duration(milliseconds: 400),
        child: InkWell(
          onTap: entry.installable ? onInstall : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: text.withAlpha(10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: text.withAlpha(24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.check_rounded, size: 12, color: text.withAlpha(150)),
                // const SizedBox(width: 4),
                // Text(
                //   'INSTALLED',
                //   style: TextStyle(
                //     fontSize: Design.baseFontSize - 0.5,
                //     fontWeight: FontWeight.w700,
                //     letterSpacing: 0.4,
                //     color: text.withAlpha(150),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: entry.installable ? onInstall : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: accent.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withAlpha(80)),
        ),
        child: Text(
          'INSTALL',
          style: TextStyle(
            fontSize: Design.baseFontSize - 0.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: accent,
          ),
        ),
      ),
    );
  }

  static Widget pill(String label, Color background, Color foreground, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 10, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color background, Color foreground, {IconData? icon}) =>
      pill(label, background, foreground, icon: icon);
}
