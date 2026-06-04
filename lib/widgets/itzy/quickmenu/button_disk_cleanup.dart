import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class DiskCleanupButton extends StatelessWidget {
  const DiskCleanupButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Disk Cleanup",
      icon: const Icon(Icons.cleaning_services_rounded),
      child: () => const DiskCleanupPanel(),
    );
  }
}

class DiskCleanupPanel extends StatefulWidget {
  const DiskCleanupPanel({super.key});

  @override
  State<DiskCleanupPanel> createState() => _DiskCleanupPanelState();
}

class _DiskCleanupPanelState extends State<DiskCleanupPanel> {
  static const String _customFoldersKey = "diskCleanupCustomFolders";
  static const String _enabledDefaultsKey = "diskCleanupEnabledDefaults";
  static const String _defaultPathOverridesKey = "diskCleanupDefaultPathOverrides";

  final Map<String, _CleanupScanResult> _results = <String, _CleanupScanResult>{};
  List<String> _customFolders = <String>[];
  List<String> _enabledDefaultIds = <String>[];
  Map<String, String> _defaultPathOverrides = <String, String>{};
  bool _settingsMode = false;
  bool _scanning = false;
  List<String> _brokenApps = <String>[];
  bool _scanningBrokenApps = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _customFolders = Boxes.pref.getStringList(_customFoldersKey) ?? <String>[];
    _defaultPathOverrides = _loadDefaultPathOverrides();
    final List<_CleanupTarget> defaults = _defaultTargets();
    _enabledDefaultIds =
        Boxes.pref.getStringList(_enabledDefaultsKey) ?? defaults.map((_CleanupTarget e) => e.id).toList();
    unawaited(_scanAll());
    unawaited(_scanBrokenApps());
  }

  Map<String, String> _loadDefaultPathOverrides() {
    final String raw = Boxes.pref.getString(_defaultPathOverridesKey) ?? '{}';
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map((dynamic key, dynamic value) => MapEntry<String, String>(key.toString(), value.toString()));
    } catch (_) {
      return <String, String>{};
    }
  }

  List<_CleanupTarget> get _targets {
    final List<_CleanupTarget> defaults =
        _defaultTargets().where((_CleanupTarget target) => _enabledDefaultIds.contains(target.id)).toList();
    final List<_CleanupTarget> custom = _customFolders
        .map(
          (String path) => _CleanupTarget(
            id: 'custom:$path',
            title: _folderName(path),
            path: path,
            isDefault: false,
          ),
        )
        .toList();
    return <_CleanupTarget>[...defaults, ...custom];
  }

  Future<void> _scanAll() async {
    final List<_CleanupTarget> targets = _targets;
    setState(() {
      _scanning = true;
      _message = null;
      _results.clear();
    });

    final List<_CleanupTarget> existingTargets = <_CleanupTarget>[];
    for (final _CleanupTarget target in targets) {
      if (!mounted) return;
      final bool exists = await _targetExists(target);
      if (!mounted) return;
      if (!exists) {
        setState(() => _results[target.id] = _CleanupScanResult(target: target, exists: false, size: 0));
        continue;
      }
      existingTargets.add(target);
      setState(() => _results[target.id] = _CleanupScanResult.scanning(target));
    }

    for (final _CleanupTarget target in existingTargets) {
      if (!mounted) return;
      final _CleanupScanResult result = await _scanTarget(target);
      if (!mounted) return;
      setState(() => _results[target.id] = result);
    }

    if (!mounted) return;
    setState(() => _scanning = false);
  }

  Future<void> _scanBrokenApps() async {
    if (!mounted) return;
    setState(() => _scanningBrokenApps = true);
    try {
      final List<String> paths = <String>[
        "${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
        "${Platform.environment['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs",
      ];
      final List<String> invalidLinks = <String>[];
      for (final String path in paths) {
        final Directory directory = Directory(path);
        if (!directory.existsSync()) continue;
        for (final FileSystemEntity entry in directory.listSync(recursive: true)) {
          if (entry is File && entry.path.endsWith('.lnk')) {
            final String lnkPath = await convertLinkToPath(entry.path);
            if (lnkPath != "" && RegExp(r"^[A-Z]:").hasMatch(lnkPath) && !File(lnkPath).existsSync()) {
              invalidLinks.add(entry.path);
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _brokenApps = invalidLinks;
        _scanningBrokenApps = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanningBrokenApps = false);
    }
  }

  Future<void> _removeAllBrokenApps() async {
    setState(() {
      _scanningBrokenApps = true;
      _message = "Cleaning broken app entries...";
    });
    int total = 0;
    for (final String path in _brokenApps) {
      final File file = File(path);
      if (file.existsSync()) {
        file.deleteSync();
        total++;
      }
    }
    if (!mounted) return;
    await _scanBrokenApps();
    if (!mounted) return;
    setState(() {
      _scanningBrokenApps = false;
      _message = '$total Broken Links have been removed from Start Menu';
    });
  }

  Future<_CleanupScanResult> _scanTarget(_CleanupTarget target) async {
    try {
      final bool exists = await _targetExists(target);
      if (!exists) return _CleanupScanResult(target: target, exists: false, size: 0);
      final int size = target.isRecycleBin ? await _recycleBinSize() : await _directorySize(Directory(target.path));
      return _CleanupScanResult(target: target, exists: true, size: size);
    } catch (error) {
      return _CleanupScanResult(target: target, exists: false, size: 0, error: error.toString());
    }
  }

  Future<bool> _targetExists(_CleanupTarget target) async {
    if (target.isRecycleBin) return _recycleBinDirectories().any((Directory directory) => directory.existsSync());
    final Directory directory = Directory(target.path);
    return directory.existsSync();
  }

  Future<int> _directorySize(Directory directory) async {
    int total = 0;
    await _walkDirectory(directory, onFile: (File file) async {
      try {
        total += await file.length();
      } catch (_) {}
    });
    return total;
  }

  Future<void> _walkDirectory(Directory directory, {required Future<void> Function(File file) onFile}) async {
    Stream<FileSystemEntity> stream;
    try {
      stream = directory.list(followLinks: false);
    } catch (_) {
      return;
    }

    await for (final FileSystemEntity entity in stream.handleError((_) {})) {
      try {
        if (entity is File) {
          await onFile(entity);
        } else if (entity is Directory) {
          await _walkDirectory(entity, onFile: onFile);
        }
      } catch (_) {}
    }
  }

  Future<int> _recycleBinSize() async {
    int total = 0;
    for (final Directory directory in _recycleBinDirectories()) {
      if (!directory.existsSync()) continue;
      total += await _directorySize(directory);
    }
    return total;
  }

  List<Directory> _recycleBinDirectories() {
    return List<Directory>.generate(26, (int index) {
      final String drive = String.fromCharCode('A'.codeUnitAt(0) + index);
      return Directory('$drive:\\\$Recycle.Bin');
    });
  }

  Future<void> _deleteTarget(_CleanupTarget target) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Delete Cleanup Contents?"),
        content: Text("Delete the contents of ${target.title}?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _message = null;
      _results[target.id] =
          (_results[target.id] ?? _CleanupScanResult(target: target, exists: true, size: 0)).copyWith(deleting: true);
    });

    try {
      if (target.isRecycleBin) {
        await Process.run(
          'powershell.exe',
          <String>[
            '-NoProfile',
            '-NonInteractive',
            '-Command',
            'Clear-RecycleBin -Force -ErrorAction SilentlyContinue'
          ],
        );
      } else {
        await _deleteDirectoryContents(Directory(target.path));
      }
      final _CleanupScanResult result = await _scanTarget(target);
      if (!mounted) return;
      setState(() {
        _results[target.id] = result;
        _message = "Cleaned ${target.title}.";
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _results[target.id] = (_results[target.id] ?? _CleanupScanResult(target: target, exists: true, size: 0))
            .copyWith(deleting: false, error: error.toString());
      });
    }
  }

  Future<void> _deleteDirectoryContents(Directory directory) async {
    if (!_isSafeCleanupPath(directory.path)) {
      throw Exception("Refusing to clean this folder.");
    }
    if (!directory.existsSync()) return;

    await for (final FileSystemEntity entity in directory.list(followLinks: false).handleError((_) {})) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  bool _isSafeCleanupPath(String path) {
    final String normalized = path.replaceAll('/', '\\').trim();
    if (normalized.length <= 3) return false;
    final String lower = normalized.toLowerCase();
    final String windowsDir = (Platform.environment['WINDIR'] ?? 'C:\\Windows').toLowerCase();
    return lower != windowsDir && lower != windowsDir.replaceAll('/', '\\');
  }

  Future<void> _addFolder() async {
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select cleanup folder';
    final Directory? directory = picker.getDirectory();
    if (directory == null) return;

    final String path = directory.path;
    if (_customFolders.any((String item) => item.toLowerCase() == path.toLowerCase())) return;
    setState(() => _customFolders.add(path));
    await Boxes.updateSettings(_customFoldersKey, _customFolders);
    unawaited(_scanAll());
  }

  Future<void> _removeFolder(String path) async {
    setState(() => _customFolders.remove(path));
    await Boxes.updateSettings(_customFoldersKey, _customFolders);
    unawaited(_scanAll());
  }

  Future<void> _toggleDefault(String id, bool enabled) async {
    setState(() {
      if (enabled) {
        if (!_enabledDefaultIds.contains(id)) _enabledDefaultIds.add(id);
      } else {
        _enabledDefaultIds.remove(id);
      }
    });
    await Boxes.updateSettings(_enabledDefaultsKey, _enabledDefaultIds);
    unawaited(_scanAll());
  }

  Future<void> _editDefaultPath(_CleanupTarget target) async {
    if (target.isRecycleBin) return;
    final DirectoryPicker picker = DirectoryPicker()..title = 'Select ${target.title} folder';
    final Directory? directory = picker.getDirectory();
    if (directory == null) return;

    setState(() => _defaultPathOverrides[target.id] = directory.path);
    await Boxes.updateSettings(_defaultPathOverridesKey, jsonEncode(_defaultPathOverrides));
    unawaited(_scanAll());
  }

  Future<void> _resetDefaultPath(_CleanupTarget target) async {
    setState(() => _defaultPathOverrides.remove(target.id));
    await Boxes.updateSettings(_defaultPathOverridesKey, jsonEncode(_defaultPathOverrides));
    unawaited(_scanAll());
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _settingsMode ? "Disk Cleanup Settings" : "Disk Cleanup",
          accent: accent,
          icon: _settingsMode ? Icons.tune_rounded : Icons.cleaning_services_rounded,
          buttonIcon: _settingsMode ? Icons.cleaning_services_rounded : Icons.tune_rounded,
          buttonTooltip: _settingsMode ? "Cleanup" : "Settings",
          buttonPressed: () => setState(() => _settingsMode = !_settingsMode),
          extraActions: <Widget>[
            if (!_settingsMode)
              IconButton(
                tooltip: "Rescan",
                onPressed: _scanning ? null : () => unawaited(_scanAll()),
                icon: Icon(Icons.refresh_rounded, size: 14, color: accent),
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
        if (_scanning) LinearProgressIndicator(minHeight: 1.5, color: accent),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _settingsMode ? _buildSettings(accent, onSurface) : _buildCleanupList(accent, onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildCleanupList(Color accent, Color onSurface) {
    final List<_CleanupTarget> targets = _targets;
    final int totalSize = _results.values.fold(0, (int total, _CleanupScanResult result) => total + result.size);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: <Widget>[
        _SummaryCard(
          count: targets.length,
          size: totalSize,
          scanning: _scanning,
          accent: accent,
          onSurface: onSurface,
        ),
        if (_message != null) ...<Widget>[
          const SizedBox(height: 8),
          _InfoStrip(message: _message!, accent: accent, onSurface: onSurface),
        ],
        const SizedBox(height: 10),
        if (targets.isEmpty)
          _EmptyState(accent: accent, onSurface: onSurface, onSettings: () => setState(() => _settingsMode = true))
        else
          ...targets.map((_CleanupTarget target) {
            final _CleanupScanResult result = _results[target.id] ?? _CleanupScanResult.scanning(target);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CleanupRow(
                result: result,
                accent: accent,
                onSurface: onSurface,
                onDelete: result.exists && result.size > 0 && !result.deleting
                    ? () => unawaited(_deleteTarget(target))
                    : null,
              ),
            );
          }),
        // if (_scanningBrokenApps || _brokenApps.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _BrokenAppsRow(
            count: _brokenApps.length,
            scanning: _scanningBrokenApps,
            accent: accent,
            onSurface: onSurface,
            brokenLinks: _brokenApps,
            onClear: _brokenApps.isNotEmpty && !_scanningBrokenApps ? () => unawaited(_removeAllBrokenApps()) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildSettings(Color accent, Color onSurface) {
    final List<_CleanupTarget> defaults = _defaultTargets();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      children: <Widget>[
        _SectionLabel(label: "Default folders", count: defaults.length, accent: accent, onSurface: onSurface),
        const SizedBox(height: 8),
        ...defaults.map((_CleanupTarget target) {
          final bool enabled = _enabledDefaultIds.contains(target.id);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DefaultFolderRow(
              target: target,
              enabled: enabled,
              accent: accent,
              onSurface: onSurface,
              onChanged: (bool value) => unawaited(_toggleDefault(target.id, value)),
              onEdit: target.isRecycleBin ? null : () => unawaited(_editDefaultPath(target)),
              onReset: _defaultPathOverrides.containsKey(target.id) ? () => unawaited(_resetDefaultPath(target)) : null,
            ),
          );
        }),
        const SizedBox(height: 8),
        _SectionLabel(label: "Custom folders", count: _customFolders.length, accent: accent, onSurface: onSurface),
        const SizedBox(height: 8),
        if (_customFolders.isEmpty)
          _InfoStrip(message: "Add cache folders you want to scan and clean.", accent: accent, onSurface: onSurface)
        else
          ..._customFolders.map((String path) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CustomFolderRow(
                path: path,
                accent: accent,
                onSurface: onSurface,
                onRemove: () => unawaited(_removeFolder(path)),
              ),
            );
          }),
        const SizedBox(height: 8),
        InkWell(
          onTap: _addFolder,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: accent.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withAlpha(64)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.add_rounded, size: 16, color: accent),
                const SizedBox(width: 7),
                Text("Add Folder", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: accent)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<_CleanupTarget> _defaultTargets() {
    final String localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    return <_CleanupTarget>[
      _CleanupTarget(id: 'temp', title: 'Temp Folder', path: Directory.systemTemp.path, isDefault: true),
      const _CleanupTarget(
          id: 'recycle_bin', title: 'Recycle Bin', path: 'Recycle Bin', isDefault: true, isRecycleBin: true),
      ..._browserTargets(localAppData),
    ].map(_applyDefaultPathOverride).toList(growable: false);
  }

  _CleanupTarget _applyDefaultPathOverride(_CleanupTarget target) {
    final String? override = _defaultPathOverrides[target.id];
    if (override == null || override.trim().isEmpty || target.isRecycleBin) return target;
    return target.copyWith(path: override);
  }

  List<_CleanupTarget> _browserTargets(String localAppData) {
    if (localAppData.isEmpty) return <_CleanupTarget>[];
    final Map<String, String> profiles = <String, String>{
      'Chrome': '$localAppData\\Google\\Chrome\\User Data\\Default',
      'Edge': '$localAppData\\Microsoft\\Edge\\User Data\\Default',
      'Brave': '$localAppData\\BraveSoftware\\Brave-Browser\\User Data\\Default',
      'Opera': '$localAppData\\Opera Software\\Opera Stable',
      'Opera GX': '$localAppData\\Opera Software\\Opera GX Stable',
    };

    final List<_CleanupTarget> targets = <_CleanupTarget>[];
    for (final MapEntry<String, String> profile in profiles.entries) {
      for (final String folderName in const <String>['Code Cache', 'Service Worker']) {
        final String path = '${profile.value}\\$folderName';
        targets.add(
          _CleanupTarget(
            id: '${profile.key.toLowerCase().replaceAll(' ', '_')}_${folderName.toLowerCase().replaceAll(' ', '_')}',
            title: '${profile.key} $folderName',
            path: path,
            isDefault: true,
          ),
        );
      }
    }
    return targets;
  }

  static String _folderName(String path) {
    final List<String> parts = path.replaceAll('/', '\\').split('\\').where((String part) => part.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }
}

class _CleanupTarget {
  const _CleanupTarget({
    required this.id,
    required this.title,
    required this.path,
    required this.isDefault,
    this.isRecycleBin = false,
  });

  final String id;
  final String title;
  final String path;
  final bool isDefault;
  final bool isRecycleBin;

  _CleanupTarget copyWith({String? path}) {
    return _CleanupTarget(
      id: id,
      title: title,
      path: path ?? this.path,
      isDefault: isDefault,
      isRecycleBin: isRecycleBin,
    );
  }
}

class _CleanupScanResult {
  const _CleanupScanResult({
    required this.target,
    required this.exists,
    required this.size,
    this.scanning = false,
    this.deleting = false,
    this.error,
  });

  factory _CleanupScanResult.scanning(_CleanupTarget target) {
    return _CleanupScanResult(target: target, exists: true, size: 0, scanning: true);
  }

  final _CleanupTarget target;
  final bool exists;
  final int size;
  final bool scanning;
  final bool deleting;
  final String? error;

  _CleanupScanResult copyWith({bool? deleting, String? error}) {
    return _CleanupScanResult(
      target: target,
      exists: exists,
      size: size,
      scanning: scanning,
      deleting: deleting ?? this.deleting,
      error: error ?? this.error,
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.count,
    required this.size,
    required this.scanning,
    required this.accent,
    required this.onSurface,
  });

  final int count;
  final int size;
  final bool scanning;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withAlpha(14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withAlpha(36)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: accent.withAlpha(24), borderRadius: BorderRadius.circular(9)),
            child: Icon(Icons.storage_rounded, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  scanning ? "Scanning cleanup targets" : "Potential cleanup",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  "$count folder${count == 1 ? '' : 's'} selected",
                  style: TextStyle(fontSize: 11, color: onSurface.withAlpha(130)),
                ),
              ],
            ),
          ),
          Text(_formatBytes(size), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent)),
        ],
      ),
    );
  }
}

class _CleanupRow extends StatelessWidget {
  const _CleanupRow({
    required this.result,
    required this.accent,
    required this.onSurface,
    required this.onDelete,
  });

  final _CleanupScanResult result;
  final Color accent;
  final Color onSurface;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final bool unavailable = !result.exists || result.error != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(14)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            result.target.isRecycleBin ? Icons.delete_outline_rounded : Icons.folder_open_rounded,
            size: 17,
            color: unavailable ? onSurface.withAlpha(75) : accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  result.target.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  result.error ?? (result.exists ? result.target.path : "Folder not found"),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: onSurface.withAlpha(110)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (result.scanning || result.deleting)
            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
          else ...<Widget>[
            Text(
              result.exists ? _formatBytes(result.size) : "-",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: onSurface.withAlpha(140)),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: "Delete contents",
              onPressed: onDelete,
              icon: Icon(Icons.delete_sweep_rounded,
                  size: 17, color: onDelete == null ? onSurface.withAlpha(60) : Colors.redAccent),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultFolderRow extends StatelessWidget {
  const _DefaultFolderRow({
    required this.target,
    required this.enabled,
    required this.accent,
    required this.onSurface,
    required this.onChanged,
    this.onEdit,
    this.onReset,
  });

  final _CleanupTarget target;
  final bool enabled;
  final Color accent;
  final Color onSurface;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: enabled ? accent.withAlpha(14) : onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: enabled ? accent.withAlpha(42) : onSurface.withAlpha(14)),
      ),
      child: Row(
        children: <Widget>[
          Icon(target.isRecycleBin ? Icons.delete_outline_rounded : Icons.folder_rounded, size: 17, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(target.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: onSurface)),
                const SizedBox(height: 2),
                Text(target.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: onSurface.withAlpha(110))),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              tooltip: "Edit folder",
              onPressed: onEdit,
              icon: Icon(Icons.edit_rounded, size: 15, color: accent),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          if (onReset != null)
            IconButton(
              tooltip: "Reset folder",
              onPressed: onReset,
              icon: Icon(Icons.restart_alt_rounded, size: 15, color: onSurface.withAlpha(145)),
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          MiniToggleSwitch(value: enabled, activeThumbColor: accent, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _CustomFolderRow extends StatelessWidget {
  const _CustomFolderRow({
    required this.path,
    required this.accent,
    required this.onSurface,
    required this.onRemove,
  });

  final String path;
  final Color accent;
  final Color onSurface;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: onSurface.withAlpha(14)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.folder_copy_rounded, size: 17, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(path,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: onSurface)),
          ),
          IconButton(
            tooltip: "Remove",
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 16, color: Colors.redAccent.withAlpha(220)),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.count, required this.accent, required this.onSurface});

  final String label;
  final int count;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: onSurface)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: accent.withAlpha(22), borderRadius: BorderRadius.circular(999)),
          child: Text("$count", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: onSurface.withAlpha(20))),
      ],
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.message, required this.accent, required this.onSurface});

  final String message;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withAlpha(24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: onSurface.withAlpha(145))),
          ),
        ],
      ),
    );
  }
}

class _BrokenAppsRow extends StatefulWidget {
  const _BrokenAppsRow({
    required this.count,
    required this.scanning,
    required this.accent,
    required this.onSurface,
    required this.brokenLinks,
    this.onClear,
  });

  final int count;
  final bool scanning;
  final Color accent;
  final Color onSurface;
  final List<String> brokenLinks;
  final VoidCallback? onClear;

  @override
  State<_BrokenAppsRow> createState() => _BrokenAppsRowState();
}

class _BrokenAppsRowState extends State<_BrokenAppsRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (widget.count > 0 ? Colors.orange : widget.accent).withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.count > 0 ? Icons.link_off_rounded : Icons.link_rounded,
                  size: 18,
                  color: widget.count > 0 ? Colors.orange : widget.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Broken App SymLinks",
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: widget.onSurface),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.scanning
                          ? "Scanning..."
                          : (widget.count > 0
                              ? "${widget.count} broken Start Menu Symlinks found"
                              : "No broken symlinks found in Start Menu"),
                      style: TextStyle(fontSize: 11, color: widget.onSurface.withAlpha(140)),
                    ),
                  ],
                ),
              ),
              if (widget.count > 0 && !widget.scanning) ...<Widget>[
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: widget.onSurface.withAlpha(160)),
                  ),
                  tooltip: _expanded ? "Hide broken links" : "Show broken links",
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  onPressed: widget.onClear,
                  icon: const Icon(Icons.delete_sweep_rounded),
                  color: Colors.orange,
                  tooltip: "Clear all broken app entries",
                  iconSize: 20,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
              if (widget.scanning)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: widget.accent),
                ),
            ],
          ),
          if (_expanded && widget.brokenLinks.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: widget.onSurface.withAlpha(6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.onSurface.withAlpha(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.brokenLinks.map((String path) {
                  final String name = path.split('\\').last;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.insert_drive_file_outlined, size: 13, color: Colors.orange.withAlpha(180)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: widget.onSurface.withAlpha(160)),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accent, required this.onSurface, required this.onSettings});

  final Color accent;
  final Color onSurface;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(12)),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.cleaning_services_rounded, size: 34, color: accent.withAlpha(170)),
          const SizedBox(height: 10),
          Text("No cleanup folders enabled",
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: onSurface)),
          const SizedBox(height: 8),
          TextButton.icon(
              onPressed: onSettings, icon: const Icon(Icons.tune_rounded), label: const Text("Open Settings")),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return "0 B";
  const List<String> suffixes = <String>["B", "KB", "MB", "GB", "TB"];
  final int index = math.min((math.log(bytes) / math.log(1024)).floor(), suffixes.length - 1);
  final double value = bytes / math.pow(1024, index);
  return "${value.toStringAsFixed(index == 0 ? 0 : 1)} ${suffixes[index]}";
}
