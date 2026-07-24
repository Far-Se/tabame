import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../pages/launcher/plugins/plugin_gallery.dart';
import '../../../pages/launcher/plugins/plugin_icons.dart';
import '../../../pages/launcher/plugins/plugin_manifest.dart';
import '../../../pages/launcher/plugins/plugin_registry.dart';
import '../../widgets/modal_button.dart';
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

enum _PanelMode { installed, gallery, makeYourOwn }

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

  List<PluginGalleryEntry>? _galleryEntries;
  bool _galleryLoading = false;
  String _galleryError = '';
  String? _installingId;
  String _installStatus = '';

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

  Future<void> _toggle(PluginManifest manifest, bool enabled) async {
    setState(() => _busyId = manifest.id);
    await PluginRegistry.setEnabled(manifest, enabled);
    if (!mounted) return;
    setState(() => _busyId = null);
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

  void _switchMode(_PanelMode mode) {
    if (_mode == mode) return;
    setState(() => _mode = mode);
    if (mode == _PanelMode.gallery && _galleryEntries == null) _loadGallery();
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
    return Row(
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

1. Copy [TABAME_PLUGIN_SKILL.md](https://github.com/Far-Se/tabame/blob/main/plugins/TABAME_PLUGIN_SKILL.md).
2. Open your favorite AI coding site or app and paste the file.
3. Tell the AI what plugin you need, with detailed instructions for how it should work.
4. Create a new folder in `%localappdata%/tabame/plugins/` for your plugin.
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
    final int enabledCount = plugins.where((PluginManifest m) => m.enabled).length;
    if (plugins.isEmpty) return _buildInstalledEmpty();

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: C.start,
          children: <Widget>[
            _buildSectionLabel(
              label: "Installed",
              countText: "$enabledCount/${plugins.length}",
              icon: Icons.extension_rounded,
            ),
            const SizedBox(height: 8),
            for (final PluginManifest m in plugins) ...<Widget>[
              _PluginCard(
                manifest: m,
                busy: _busyId == m.id,
                onToggle: (bool value) => _toggle(m, value),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInstalledEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              "Install one from the Gallery, or drop a plugin folder into %localappdata%\\Tabame\\plugins.",
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

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: C.start,
          children: <Widget>[
            if (_installStatus.isNotEmpty) ...<Widget>[
              _buildStatusStrip(_installStatus, error: _installStatus.startsWith('Install failed')),
              const SizedBox(height: 8),
            ],
            _buildSectionLabel(
              label: "Community Plugins",
              countText: "${entries.length}",
              icon: Icons.storefront_rounded,
            ),
            const SizedBox(height: 8),
            for (final PluginGalleryEntry entry in entries) ...<Widget>[
              _GalleryCard(
                entry: entry,
                installed: PluginGallery.isInstalled(entry.id),
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

/// One row in the plugin list: icon, name + keyword, description, on/off switch.
class _PluginCard extends StatelessWidget {
  const _PluginCard({
    required this.manifest,
    required this.busy,
    required this.onToggle,
  });

  final PluginManifest manifest;
  final bool busy;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withAlpha(enabled ? 22 : 12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        manifest.keyword,
                        style: TextStyle(
                          fontSize: Design.baseFontSize - 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                          color: accent.withAlpha(enabled ? 255 : 150),
                        ),
                      ),
                    ),
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
              child: busy
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
                        onChanged: onToggle,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One gallery row: icon, name + keyword + runtime pills, description,
/// author/version meta, and the install action.
class _GalleryCard extends StatelessWidget {
  const _GalleryCard({
    required this.entry,
    required this.installed,
    required this.installing,
    required this.onInstall,
    this.onOpenHomepage,
  });

  final PluginGalleryEntry entry;
  final bool installed;
  final bool installing;
  final VoidCallback onInstall;
  final VoidCallback? onOpenHomepage;

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color text = Design.text;

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
              _buildInstallAction(accent, text),
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

  Widget _buildInstallAction(Color accent, Color text) {
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
    if (installed) {
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

  Widget _pill(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Design.baseFontSize - 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: foreground,
        ),
      ),
    );
  }
}
