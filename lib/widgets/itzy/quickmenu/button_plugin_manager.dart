import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../pages/launcher/plugins/plugin_icons.dart';
import '../../../pages/launcher/plugins/plugin_manifest.dart';
import '../../../pages/launcher/plugins/plugin_registry.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';
import '../../widgets/windows_scroll.dart';

/// Top-bar entry point for the Launcher Plugins manager.
class PluginManagerButton extends StatelessWidget {
  const PluginManagerButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Launcher Plugins",
      icon: const Icon(Icons.extension_outlined),
      onTap: () => showQuickMenuModal(
        context: context,
        child: const PluginManagerPanel(),
      ),
    );
  }
}

/// Lists every installed launcher plugin and lets the user reload the folder or
/// toggle each plugin on/off. Enabling/disabling flips the `"enabled"` key in
/// the plugin's `plugin.json`; the launcher only surfaces enabled plugins.
class PluginManagerPanel extends StatefulWidget {
  const PluginManagerPanel({super.key});

  @override
  State<PluginManagerPanel> createState() => _PluginManagerPanelState();
}

class _PluginManagerPanelState extends State<PluginManagerPanel> {
  bool _reloading = false;
  String? _busyId;

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

  @override
  Widget build(BuildContext context) {
    final List<PluginManifest> plugins = PluginRegistry.manifests;
    final int enabledCount = plugins.where((PluginManifest m) => m.enabled).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        PanelHeader(
          title: "Launcher Plugins",
          icon: Icons.extension_rounded,
          buttonIcon: _reloading ? Icons.hourglass_bottom_rounded : Icons.refresh_rounded,
          buttonTooltip: "Reload plugins",
          buttonPressed: _reloading ? null : _reload,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: plugins.isEmpty ? _buildEmpty() : _buildList(plugins, enabledCount),
          ),
        ),
      ],
    );
  }

  Widget _buildList(List<PluginManifest> plugins, int enabledCount) {
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
        child: Column(
          crossAxisAlignment: C.start,
          children: <Widget>[
            _buildSectionLabel(
              label: "Installed",
              count: plugins.length,
              enabledCount: enabledCount,
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

  Widget _buildSectionLabel({
    required String label,
    required int count,
    required int enabledCount,
  }) {
    return Row(
      children: <Widget>[
        Icon(Icons.extension_rounded, size: 14, color: Design.accent),
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
            "$enabledCount/$count",
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildEmpty() {
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
              "Drop a plugin folder into %localappdata%\\Tabame\\plugins, then reload.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(110)),
            ),
          ],
        ),
      ),
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
