import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../pages/launcher/plugins/plugin_manifest.dart';
import '../pages/launcher/plugins/plugin_protocol.dart';
import '../pages/launcher/plugins/plugin_registry.dart';
import '../pages/quicksnap_portable.dart';
import 'app_catalog_service.dart';
import 'app_paths.dart';
import 'clipboard_service.dart';
import 'file_picker_service.dart';

import '../services/notification_coordinator.dart';
import 'platform_capabilities.dart';
import 'platform_models.dart';
import 'portable_clipboard_history.dart';
import 'portable_file_search.dart';
import 'portable_plugin_session.dart';
import 'portable_settings.dart';
import 'portable_window_service.dart';
import 'macos/macos_bootstrap.dart';
import 'macos/macos_permission_onboarding.dart';
import 'linux/linux_bootstrap.dart';
import 'linux/linux_platform_channel.dart';

/// Cross-platform launcher/quick-menu MVP.
///
/// This shell intentionally avoids the Windows taskbar, hook, and window graph.
/// It supplies the first useful shared workflow on macOS/Linux: discover and
/// launch apps, search files, run plugins, change theme settings, notify, and
/// quit cleanly.
class PortableShell extends StatefulWidget {
  const PortableShell({super.key, required this.settings, this.initialQuery = ''});

  final PortableSettings settings;
  final String initialQuery;

  @override
  State<PortableShell> createState() => _PortableShellState();
}

enum _PortableMode { launcher, plugins, clipboard, quicksnap, settings, plugin }

class _PortableShellState extends State<PortableShell> {
  final TextEditingController _queryController = TextEditingController();
  final PortableFileSearchService _fileSearch = const PortableFileSearchService();

  _PortableMode _mode = _PortableMode.launcher;
  AppCatalogSnapshot? _catalog;
  List<AppCatalogRecord> _visibleApps = const <AppCatalogRecord>[];
  List<PortableFileResult> _fileResults = const <PortableFileResult>[];
  List<PluginManifest> _plugins = const <PluginManifest>[];
  PortablePluginSession? _pluginSession;
  PluginManifest? _activePlugin;
  PluginRenderFrame? _pluginFrame;
  String _status = '';
  bool _loading = true;
  int _searchGeneration = 0;
  Timer? _searchDebounce;
  StreamSubscription<LinuxCapabilitySnapshot>? _linuxCapabilitySubscription;
  StreamSubscription<PlatformCapabilities>? _macosCapabilitySubscription;

  @override
  void initState() {
    super.initState();
    _queryController.text = widget.initialQuery;
    _queryController.addListener(_onQueryChanged);
    if (Platform.isLinux) {
      _linuxCapabilitySubscription = LinuxBootstrap.capabilityChanges.listen((LinuxCapabilitySnapshot _) {
        if (mounted) setState(() {});
      });
    } else if (Platform.isMacOS) {
      _macosCapabilitySubscription = MacOSBootstrap.capabilityChanges.listen((PlatformCapabilities _) {
        if (mounted) setState(() {});
      });
    }
    unawaited(_loadPortableData());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    final StreamSubscription<LinuxCapabilitySnapshot>? linuxCapabilitySubscription = _linuxCapabilitySubscription;
    _linuxCapabilitySubscription = null;
    if (linuxCapabilitySubscription != null) unawaited(linuxCapabilitySubscription.cancel());
    final StreamSubscription<PlatformCapabilities>? macosCapabilitySubscription = _macosCapabilitySubscription;
    _macosCapabilitySubscription = null;
    if (macosCapabilitySubscription != null) unawaited(macosCapabilitySubscription.cancel());
    _queryController
      ..removeListener(_onQueryChanged)
      ..dispose();
    unawaited(_pluginSession?.stop());
    super.dispose();
  }

  Future<void> _loadPortableData() async {
    try {
      await PluginRegistry.load();
      final AppCatalogSnapshot discovered = await AppCatalogService.instance.discover();
      final AppCatalogSnapshot catalog = await _cacheMacOSIcons(discovered);
      if (!mounted) return;
      setState(() {
        _plugins =
            List<PluginManifest>.unmodifiable(PluginRegistry.manifests.where((PluginManifest item) => item.enabled));
        _catalog = catalog;
        _visibleApps = const <AppCatalogRecord>[];
        _loading = false;
      });
      await _search();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Portable services are partially unavailable: $error';
      });
    }
  }

  void _onQueryChanged() {
    if (_pluginSession?.isRunning == true) {
      _pluginSession!.sendQuery(_queryController.text);
    }
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_search());
    });
  }

  Future<void> _search() async {
    final int generation = ++_searchGeneration;
    final String rawQuery = _queryController.text.trim();
    final String query = rawQuery.toLowerCase().startsWith('app ') ? rawQuery.substring(4).trim() : rawQuery;
    final AppCatalogSnapshot? catalog = _catalog;
    if (catalog == null) return;

    final List<AppCatalogRecord> apps = query.isEmpty
        ? catalog.records.take(24).toList(growable: false)
        : catalog.records
            .where((AppCatalogRecord record) =>
                record.name.toLowerCase().contains(query) || record.subtitle.toLowerCase().contains(query))
            .take(24)
            .toList(growable: false);
    final List<PortableFileResult> files = query.length < 2
        ? const <PortableFileResult>[]
        : await _fileSearch.search(
            query,
            roots: widget.settings.searchRoots.isEmpty ? null : widget.settings.searchRoots,
          );
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _visibleApps = apps;
      _fileResults = files;
    });
  }

  Future<AppCatalogSnapshot> _cacheMacOSIcons(AppCatalogSnapshot snapshot) async {
    if (!Platform.isMacOS || snapshot.records.isEmpty) return snapshot;

    final List<AppCatalogRecord> records = <AppCatalogRecord>[];
    for (final AppCatalogRecord record in snapshot.records) {
      final String destination = AppPaths.cachePath(
        'icon_cache/macos_${record.stableId.hashCode}.png',
        forWrite: true,
      );
      final File iconFile = File(destination);
      if (iconFile.existsSync() || await AppCatalogService.instance.cacheIcon(record, destination)) {
        records.add(record.copyWith(iconPath: destination));
      } else {
        records.add(record);
      }
    }
    return AppCatalogSnapshot(records: records, complete: snapshot.complete, error: snapshot.error);
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _status = 'Refreshing applications…';
    });
    await _loadPortableData();
    if (mounted) setState(() => _status = 'Catalog refreshed.');
  }

  Future<void> _launchApp(AppCatalogRecord record) async {
    final bool launched = await AppCatalogService.instance.launch(record);
    if (!mounted) return;
    if (launched) {
      setState(() => _status = 'Launched ${record.name}.');
      await PortableWindowService.hide();
    } else {
      setState(() => _status = 'Could not launch ${record.name}.');
    }
  }

  Future<void> _openFile(PortableFileResult result) async {
    final bool opened = await _fileSearch.open(result);
    if (!mounted) return;
    setState(() => _status = opened ? 'Opened ${result.name}.' : 'Could not open ${result.name}.');
  }

  Future<void> _addSearchFolder() async {
    final DirectoryPicker request = DirectoryPicker()..title = 'Select a folder to search';
    final Directory? folder = await FilePickerService.instance.pickDirectoryAsync(request);
    if (folder == null || folder.path.trim().isEmpty) {
      _showStatus(FilePickerService.instance.isAvailable
          ? 'Folder selection cancelled.'
          : FilePickerService.instance.unavailableReason);
      return;
    }
    await widget.settings.addSearchRoot(folder.path);
    await _search();
    _showStatus('Added ${folder.path} to search folders.');
  }

  Future<void> _activatePlugin(PluginManifest manifest) async {
    await _pluginSession?.stop();
    final PortablePluginSession session = PortablePluginSession(
      manifest: manifest,
      settings: widget.settings,
      onFrame: (PluginRenderFrame? frame) {
        if (!mounted) return;
        setState(() => _pluginFrame = frame);
      },
      onStatus: _showStatus,
      onHide: _leavePlugin,
    );
    setState(() {
      _activePlugin = manifest;
      _pluginSession = session;
      _pluginFrame = null;
      _mode = _PortableMode.plugin;
    });
    final String query = PluginRegistry.queryAfterKeyword(_queryController.text, manifest);
    await session.start(query);
  }

  Future<void> _leavePlugin() async {
    await _pluginSession?.stop();
    if (!mounted) return;
    setState(() {
      _pluginSession = null;
      _activePlugin = null;
      _pluginFrame = null;
      _mode = _PortableMode.launcher;
    });
  }

  Future<void> _testNotification() async {
    final bool shown = await NotificationCoordinator.instance.show(
      title: 'Tabame portable shell',
      body: 'Desktop notifications are connected.',
    );
    _showStatus(shown ? 'Notification sent.' : NotificationCoordinator.instance.unavailableReason);
  }

  void _showStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
  }

  void _setMode(_PortableMode mode) {
    if (_mode == _PortableMode.plugin && mode != _PortableMode.plugin) unawaited(_leavePlugin());
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Tabame',
          theme: widget.settings.theme,
          home: _buildHome(),
        );
      },
    );
  }

  Widget _buildHome() {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          children: <Widget>[
            Text('TABAME',
                style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2.4, color: widget.settings.accentColor)),
            const SizedBox(width: 10),
            const Text('PORTABLE SHELL', style: TextStyle(fontSize: 11, letterSpacing: 1.2)),
          ],
        ),
        actions: <Widget>[
          IconButton(tooltip: 'Refresh catalog', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          const IconButton(
              tooltip: 'Minimize', onPressed: PortableWindowService.hide, icon: Icon(Icons.remove_rounded)),
          const IconButton(tooltip: 'Quit', onPressed: PortableWindowService.close, icon: Icon(Icons.close_rounded)),
          const SizedBox(width: 8),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
        child: Column(
          children: <Widget>[
            _buildSearchField(),
            const SizedBox(height: 10),
            _buildModeBar(),
            if (Platform.isLinux) _buildLinuxWaylandNotice(),
            if (Platform.isMacOS) const MacOSPermissionOnboarding(),
            if (_status.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_status,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(child: _buildModeContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _queryController,
      autofocus: true,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: 'Search apps, files, or type a plugin keyword',
        suffixIcon: _queryController.text.isEmpty
            ? null
            : IconButton(onPressed: _queryController.clear, icon: const Icon(Icons.clear_rounded)),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onSubmitted: (_) {
        final PluginManifest? plugin = PluginRegistry.matchKeyword(_queryController.text.trim());
        if (plugin != null) unawaited(_activatePlugin(plugin));
      },
    );
  }

  Widget _buildModeBar() {
    return Row(
      children: <Widget>[
        _modeButton('Launcher', Icons.rocket_launch_rounded, _PortableMode.launcher),
        const SizedBox(width: 8),
        _modeButton('Plugins', Icons.extension_rounded, _PortableMode.plugins),
        if (PlatformCapabilities.current.clipboardMonitoring) ...<Widget>[
          const SizedBox(width: 8),
          _modeButton('Clipboard', Icons.content_paste_search_rounded, _PortableMode.clipboard),
        ],
        if (PlatformCapabilities.current.quickSnap) ...<Widget>[
          const SizedBox(width: 8),
          _modeButton('QuickSnap', Icons.view_quilt_rounded, _PortableMode.quicksnap),
        ],
        const SizedBox(width: 8),
        _modeButton('Settings', Icons.tune_rounded, _PortableMode.settings),
        const Spacer(),
        Text(
          Platform.isMacOS
              ? 'macOS'
              : Platform.isLinux
                  ? 'Linux'
                  : 'portable',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }

  Widget _modeButton(String label, IconData icon, _PortableMode mode) {
    final bool selected = _mode == mode;
    return OutlinedButton.icon(
      onPressed: () => _setMode(mode),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        backgroundColor: selected ? widget.settings.accentColor.withAlpha(45) : null,
      ),
    );
  }

  Widget _buildLinuxWaylandNotice() {
    final LinuxCapabilitySnapshot snapshot = LinuxBootstrap.capabilitySnapshot;
    final bool probePending = snapshot.displayServer == 'unknown';
    if (!snapshot.isWaylandOnly && !(probePending && LinuxBootstrap.sessionLooksWayland)) {
      return const SizedBox.shrink();
    }

    final List<String> unavailable = <String>[
      if (!snapshot.windowEnumeration) 'window listing/activation',
      if (!snapshot.monitorGeometry) 'monitor-aware popup placement',
      if (!snapshot.clipboardMonitoring) 'clipboard history',
    ];
    final HotkeyRegistrationResult? summon = LinuxBootstrap.summonResult;
    final bool summonRegistered = summon?.registered == true;
    final String summonMessage = summonRegistered
        ? 'Global summon shortcut registered.'
        : 'Global summon shortcut unavailable; keep the visible Tabame window as the manual fallback.';
    final String detail = probePending
        ? 'Wayland capabilities are still being detected; restricted actions remain disabled. $summonMessage'
        : unavailable.isEmpty
            ? summonMessage
            : '$summonMessage Unavailable here: ${unavailable.join(', ')}.';
    final String compositor = snapshot.waylandCompositor == 'unknown' || snapshot.waylandCompositor == 'not-wayland'
        ? 'Wayland'
        : snapshot.waylandCompositor;
    final String captureMessage = snapshot.hasCaptureInfrastructure
        ? 'ScreenCast portal and PipeWire were detected, but capture still requires an implemented adapter and user consent.'
        : 'Screen capture and recording remain unavailable without a portal-approved adapter.';

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.info_outline_rounded),
        title: Text('Wayland reduced mode · $compositor'),
        subtitle: Text('$detail $captureMessage'),
      ),
    );
  }

  Widget _buildModeContent() {
    switch (_mode) {
      case _PortableMode.launcher:
        return _buildLauncherView();
      case _PortableMode.plugins:
        return _buildPluginsView();
      case _PortableMode.clipboard:
        return const PortableClipboardHistoryPanel();
      case _PortableMode.quicksnap:
        return const PortableQuickSnapPanel();
      case _PortableMode.settings:
        return _buildSettingsView();
      case _PortableMode.plugin:
        return _buildPluginView();
    }
  }

  Widget _buildLauncherView() {
    final AppCatalogSnapshot? catalog = _catalog;
    final List<AppCatalogRecord> apps = _visibleApps;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: <Widget>[
        _sectionHeader(
          'APPLICATIONS',
          catalog == null || catalog.records.length == apps.length
              ? '${apps.length} discovered'
              : '${apps.length} of ${catalog.records.length} shown',
        ),
        if (apps.isEmpty)
          _emptyRow('No applications found yet. Refresh after installing an app.')
        else
          for (final AppCatalogRecord app in apps) _appRow(app),
        if (_fileResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _sectionHeader('FILES', '${_fileResults.length} matches'),
          for (final PortableFileResult result in _fileResults) _fileRow(result),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _addSearchFolder,
          icon: const Icon(Icons.create_new_folder_outlined),
          label: const Text('Add a folder to search'),
        ),
        if (catalog?.complete == false && catalog?.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Catalog warning: ${catalog!.error}', style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _appRow(AppCatalogRecord app) {
    final String? iconPath = app.iconPath;
    final Widget fallback = Icon(Icons.apps_rounded, color: widget.settings.accentColor);
    return ListTile(
      dense: true,
      leading: iconPath == null || !File(iconPath).existsSync()
          ? fallback
          : Image.file(
              File(iconPath),
              width: 24,
              height: 24,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback,
            ),
      title: Text(app.name),
      subtitle: Text(app.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.launch_rounded, size: 18),
      onTap: () => _launchApp(app),
    );
  }

  Widget _fileRow(PortableFileResult result) {
    return ListTile(
      dense: true,
      leading: Icon(result.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
      title: Text(result.name),
      subtitle: Text(result.path, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
      onTap: () => _openFile(result),
    );
  }

  Widget _buildPluginsView() {
    if (_plugins.isEmpty) return _emptyRow('No enabled plugins found in the platform plugin folder.');
    return ListView(
      children: <Widget>[
        _sectionHeader('PLUGINS', '${_plugins.length} enabled'),
        for (final PluginManifest plugin in _plugins)
          ListTile(
            dense: true,
            leading: Icon(Icons.extension_rounded, color: widget.settings.accentColor),
            title: Text(plugin.name),
            subtitle: Text('${plugin.keyword} · ${plugin.runtime}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _activatePlugin(plugin),
          ),
      ],
    );
  }

  Widget _buildPluginView() {
    final PluginManifest? plugin = _activePlugin;
    final PluginRenderFrame? frame = _pluginFrame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            TextButton.icon(
                onPressed: _leavePlugin, icon: const Icon(Icons.arrow_back_rounded), label: const Text('Back')),
            const SizedBox(width: 8),
            Text(plugin?.name ?? 'Plugin', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: frame == null
              ? const Center(child: CircularProgressIndicator())
              : frame.error != null
                  ? Center(child: Text(frame.error!))
                  : ListView(
                      children: <Widget>[
                        if (frame.detailMarkdown != null) SelectableText(frame.detailMarkdown!),
                        if (frame.empty != null) _emptyRow('${frame.empty!.title}\n${frame.empty!.hint}'),
                        for (final PluginItem item in frame.items)
                          Card(
                            child: ListTile(
                              title: Text(item.title),
                              subtitle:
                                  Text(item.subtitle, maxLines: item.subtitleLines, overflow: TextOverflow.ellipsis),
                              onTap: () => _pluginSession?.sendSelect(item.id),
                              trailing: item.actions.isEmpty
                                  ? null
                                  : PopupMenuButton<String>(
                                      onSelected: (String action) => _pluginSession?.sendAction(item.id, action),
                                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                                        for (final PluginAction action in item.actions)
                                          PopupMenuItem<String>(value: action.id, child: Text(action.title)),
                                      ],
                                    ),
                            ),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildSettingsView() {
    return ListView(
      children: <Widget>[
        _sectionHeader('PORTABLE SETTINGS', 'saved under AppPaths'),
        SwitchListTile.adaptive(
          title: const Text('Dark theme'),
          subtitle: const Text('Use the technical dark launcher palette.'),
          value: widget.settings.darkMode,
          onChanged: widget.settings.setDarkMode,
        ),
        ListTile(
          leading: Icon(Icons.content_paste_search_rounded, color: widget.settings.accentColor),
          title: const Text('Clipboard text history'),
          subtitle: Text(PlatformCapabilities.current.clipboardMonitoring
              ? 'Text changes are captured through the active platform adapter.'
              : ClipboardService.instance.unavailableReason),
          enabled: PlatformCapabilities.current.clipboardMonitoring,
          onTap: PlatformCapabilities.current.clipboardMonitoring ? () => _setMode(_PortableMode.clipboard) : null,
        ),
        Builder(
          builder: (BuildContext context) {
            final bool notificationsAvailable =
                PlatformCapabilities.current.systemNotifications && NotificationCoordinator.instance.isAvailable;
            return ListTile(
              leading: Icon(Icons.notifications_outlined, color: widget.settings.accentColor),
              title: const Text('Test desktop notification'),
              subtitle: Text(notificationsAvailable
                  ? 'Uses the available desktop notification backend.'
                  : NotificationCoordinator.instance.unavailableReason),
              enabled: notificationsAvailable,
              onTap: notificationsAvailable ? _testNotification : null,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_open_outlined),
          title: const Text('Add search folder'),
          subtitle: Text(widget.settings.searchRoots.isEmpty
              ? 'No custom folders configured.'
              : widget.settings.searchRoots.join('\n')),
          onTap: _addSearchFolder,
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.visibility_off_outlined),
          title: Text('Windows-only integrations hidden'),
          subtitle:
              Text('Taskbar hooks, window enumeration, system controls, and QuickActions remain Windows-specific.'),
        ),
        const ListTile(
          leading: Icon(Icons.power_settings_new_rounded),
          title: Text('Quit Tabame'),
          onTap: PortableWindowService.close,
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String detail) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Row(
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4, color: widget.settings.accentColor)),
          const Spacer(),
          Text(detail, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }

  Widget _emptyRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}
