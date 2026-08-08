import 'dart:async';

import 'package:flutter/material.dart';

import '../platform/monitor_service.dart';
import '../platform/platform_models.dart';
import '../platform/quick_snap_service.dart';
import '../platform/window_service.dart';

/// Small manual QuickSnap surface for target platforms without the Windows
/// drag-trigger overlay. It intentionally exposes only neutral window and
/// monitor data; adapters own the Accessibility/X11/native identifiers.
class PortableQuickSnapPanel extends StatefulWidget {
  const PortableQuickSnapPanel({super.key});

  @override
  State<PortableQuickSnapPanel> createState() => _PortableQuickSnapPanelState();
}

class _PortableQuickSnapPanelState extends State<PortableQuickSnapPanel> {
  static const List<_PortableSnapZone> _zones = <_PortableSnapZone>[
    _PortableSnapZone(
      label: 'Full screen',
      icon: Icons.fullscreen_rounded,
      zone: PlatformSnapZone(left: 0, top: 0, right: 1, bottom: 1),
    ),
    _PortableSnapZone(
      label: 'Left half',
      icon: Icons.vertical_split_rounded,
      zone: PlatformSnapZone(left: 0, top: 0, right: 0.5, bottom: 1),
    ),
    _PortableSnapZone(
      label: 'Right half',
      icon: Icons.vertical_split_rounded,
      zone: PlatformSnapZone(left: 0.5, top: 0, right: 1, bottom: 1),
    ),
    _PortableSnapZone(
      label: 'Top-left',
      icon: Icons.grid_view_rounded,
      zone: PlatformSnapZone(left: 0, top: 0, right: 0.5, bottom: 0.5),
    ),
    _PortableSnapZone(
      label: 'Top-right',
      icon: Icons.grid_view_rounded,
      zone: PlatformSnapZone(left: 0.5, top: 0, right: 1, bottom: 0.5),
    ),
    _PortableSnapZone(
      label: 'Bottom-left',
      icon: Icons.grid_view_rounded,
      zone: PlatformSnapZone(left: 0, top: 0.5, right: 0.5, bottom: 1),
    ),
    _PortableSnapZone(
      label: 'Bottom-right',
      icon: Icons.grid_view_rounded,
      zone: PlatformSnapZone(left: 0.5, top: 0.5, right: 1, bottom: 1),
    ),
  ];

  List<PlatformWindow> _windows = const <PlatformWindow>[];
  List<PlatformMonitor> _monitors = const <PlatformMonitor>[];
  PlatformWindow? _selectedWindow;
  String? _selectedMonitorId;
  bool _loading = true;
  String _status = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _status = '';
    });
    final QuickSnapService snap = QuickSnapService.instance;
    if (!snap.isAvailable) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final List<PlatformMonitor> monitors = await MonitorService.instance.enumerate();
    final List<PlatformWindow> windows = await WindowService.instance.enumerate();
    if (!mounted) return;
    setState(() {
      _monitors = monitors;
      _windows = windows;
      _selectedWindow = windows.isEmpty ? null : windows.first;
      _selectedMonitorId = monitors.isEmpty ? null : monitors.first.identity;
      _loading = false;
    });
  }

  Future<void> _snap(_PortableSnapZone zone) async {
    final PlatformWindow? window = _selectedWindow;
    PlatformMonitor? monitor;
    if (_selectedMonitorId != null) {
      for (final PlatformMonitor candidate in _monitors) {
        if (candidate.identity == _selectedMonitorId) {
          monitor = candidate;
          break;
        }
      }
    }
    if (window == null || monitor == null) return;

    await WindowService.instance.activate(window);
    final bool applied = await QuickSnapService.instance.snap(
      window: window,
      monitor: monitor,
      zone: zone.zone,
      gap: 8,
    );
    if (!mounted) return;
    setState(() => _status = applied ? '${zone.label} applied.' : 'Could not move that window.');
  }

  @override
  Widget build(BuildContext context) {
    final QuickSnapService service = QuickSnapService.instance;
    if (!service.isAvailable) {
      return _UnavailableQuickSnap(message: service.unavailableReason);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('QUICKSNAP', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(onPressed: _refresh, tooltip: 'Refresh windows', icon: const Icon(Icons.refresh_rounded)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          service.supportsDragTriggers
              ? 'Choose a window and a monitor-relative zone.'
              : 'Manual placement is available. Drag-triggered snapping is not provided by this platform.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        if (_windows.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.window_outlined),
              title: Text('No windows available'),
              subtitle: Text('Grant the platform window permissions, then refresh.'),
            ),
          )
        else ...<Widget>[
          DropdownButtonFormField<PlatformWindow>(
            initialValue: _selectedWindow,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Window', border: OutlineInputBorder(), isDense: true),
            items: <DropdownMenuItem<PlatformWindow>>[
              for (final PlatformWindow window in _windows)
                DropdownMenuItem<PlatformWindow>(
                  value: window,
                  child: Text(
                    window.title.isEmpty ? window.applicationName : '${window.applicationName} — ${window.title}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (PlatformWindow? value) => setState(() => _selectedWindow = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedMonitorId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Monitor', border: OutlineInputBorder(), isDense: true),
            items: <DropdownMenuItem<String>>[
              for (int index = 0; index < _monitors.length; index++)
                DropdownMenuItem<String>(
                  value: _monitors[index].identity,
                  child: Text(_monitors[index].isPrimary ? 'Primary display' : 'Display ${index + 1}'),
                ),
            ],
            onChanged: (String? value) => setState(() => _selectedMonitorId = value),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final _PortableSnapZone zone in _zones)
                OutlinedButton.icon(
                  onPressed: () => _snap(zone),
                  icon: Icon(zone.icon, size: 17),
                  label: Text(zone.label),
                ),
            ],
          ),
        ],
        if (_status.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(_status, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }
}

class _PortableSnapZone {
  const _PortableSnapZone({required this.label, required this.icon, required this.zone});

  final String label;
  final IconData icon;
  final PlatformSnapZone zone;
}

class _UnavailableQuickSnap extends StatelessWidget {
  const _UnavailableQuickSnap({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.view_quilt_outlined),
              const SizedBox(width: 12),
              Flexible(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}
