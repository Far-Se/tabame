import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'macos_bootstrap.dart';
import 'macos_permission_service.dart';
import 'macos_platform_channel.dart';

/// Non-blocking permission onboarding for the portable macOS shell.
class MacOSPermissionOnboarding extends StatefulWidget {
  const MacOSPermissionOnboarding({super.key});

  @override
  State<MacOSPermissionOnboarding> createState() => _MacOSPermissionOnboardingState();
}

class _MacOSPermissionOnboardingState extends State<MacOSPermissionOnboarding> with WidgetsBindingObserver {
  MacOSPermissionSnapshot? _snapshot;
  bool _loading = true;
  MacOSPermission? _working;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    final MacOSPermissionSnapshot snapshot = await MacOSPermissionService.instance.refresh();
    await MacOSBootstrap.refreshCapabilities();
    if (!mounted) return;
    setState(() {
      _snapshot = snapshot;
      _loading = false;
    });
  }

  Future<void> _request(MacOSPermission permission) async {
    setState(() => _working = permission);
    try {
      final MacOSPermissionState state = await MacOSPermissionService.instance.request(permission);
      if (!state.isGranted) await MacOSPermissionService.instance.openSettings(permission);
    } finally {
      if (mounted) {
        setState(() => _working = null);
        await _refresh();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS || _loading || _snapshot == null) return const SizedBox.shrink();

    final MacOSPermissionSnapshot snapshot = _snapshot!;
    final bool needsAttention = MacOSPermission.values.any(
      (MacOSPermission permission) => !snapshot.stateFor(permission).isGranted,
    );
    if (!needsAttention) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.shield_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'MACOS CAPABILITIES',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh permission status',
                  visualDensity: VisualDensity.compact,
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                ),
              ],
            ),
            const Text(
              'Tabame starts safely in reduced mode. Grant only the permissions for features you use.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 4),
            for (final MacOSPermission permission in MacOSPermission.values)
              _permissionRow(context, permission, snapshot.stateFor(permission)),
          ],
        ),
      ),
    );
  }

  Widget _permissionRow(BuildContext context, MacOSPermission permission, MacOSPermissionState state) {
    final bool granted = state.isGranted;
    final bool working = _working == permission;
    final String status = granted
        ? 'Granted'
        : state.status == MacOSPermissionStatus.notDetermined
            ? 'Not requested'
            : state.status == MacOSPermissionStatus.denied
                ? 'Denied'
                : 'Unavailable';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: <Widget>[
          Icon(
            granted ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 17,
            color: granted ? Colors.green : Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${permission.displayName} · $status', style: const TextStyle(fontSize: 12)),
          ),
          if (!granted)
            TextButton(
              onPressed: working ? null : () => _request(permission),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(working ? 'Opening…' : 'Set up'),
            ),
        ],
      ),
    );
  }
}
