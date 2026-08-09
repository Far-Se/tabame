import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/clipboard_history.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../../platform/hotkey_service.dart';
import '../../platform/quick_snap_service.dart';
import '../../platform/windows/tabamewin32_api.dart';
import '../../services/browser_bridge_service.dart';
import '../../services/clipboard_history_coordinator.dart';
import '../../services/mouse_gestures_service.dart';
import '../../services/native_integration_coordinator.dart';
import '../../services/rewindly_service.dart';
import '../widgets/windows_scroll.dart';

/// A capabilities/consent page for native integrations.
///
/// This page deliberately renders only the coordinator's safe diagnostic DTOs;
/// it never displays browser pairing tokens, clipboard entries, or raw native
/// paths/errors.
class NativeIntegrationDiagnosticsPage extends StatefulWidget {
  const NativeIntegrationDiagnosticsPage({super.key});

  @override
  State<NativeIntegrationDiagnosticsPage> createState() => _NativeIntegrationDiagnosticsPageState();
}

class _NativeIntegrationDiagnosticsPageState extends State<NativeIntegrationDiagnosticsPage> {
  late final NativeIntegrationCoordinator _coordinator;
  late NativeIntegrationDiagnosticsSnapshot _snapshot;
  StreamSubscription<NativeIntegrationDiagnosticsSnapshot>? _changes;
  final Set<NativeIntegrationId> _busy = <NativeIntegrationId>{};

  @override
  void initState() {
    super.initState();
    _coordinator = NativeIntegrationCoordinator.instance;
    _snapshot = _coordinator.diagnosticsSnapshot;
    _changes = _coordinator.changes.listen((NativeIntegrationDiagnosticsSnapshot snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _setConsent(NativeIntegrationId id, bool granted) async {
    if (!_busy.add(id)) return;
    try {
      if (granted) {
        await _coordinator.setConsent(id, true);
        await _startAfterConsent(id);
      } else {
        await _stopBeforeRevocation(id);
      }
    } finally {
      _busy.remove(id);
      if (mounted) setState(() => _snapshot = _coordinator.diagnosticsSnapshot);
    }
  }

  Future<void> _startAfterConsent(NativeIntegrationId id) async {
    switch (id) {
      case NativeIntegrationId.clipboardHistory:
        await ClipboardHistoryStore.setEnabled(true);
        await ClipboardHistoryCoordinator.instance.start();
      case NativeIntegrationId.browserBridge:
        await BrowserBridgeService.instance.setEnabled(true);
      case NativeIntegrationId.screenRecording:
        user.rewindlyEnabled = true;
        await Boxes.updateSettings('rewindlyEnabled', true);
        final bool started = await RewindlyService.instance.start();
        if (!started) {
          user.rewindlyEnabled = false;
          await Boxes.updateSettings('rewindlyEnabled', false);
          await _coordinator.revokeConsent(id);
        }
      case NativeIntegrationId.quickSnap:
        await QuickSnapService.instance.enable();
      default:
        // The nearby feature action owns one-shot integrations. Consent is
        // still recorded here so that a subsequent background start is clear.
        break;
    }
  }

  Future<void> _stopBeforeRevocation(NativeIntegrationId id) async {
    switch (id) {
      case NativeIntegrationId.clipboardHistory:
        await ClipboardHistoryCoordinator.instance.stop();
        await ClipboardHistoryStore.setEnabled(false);
      case NativeIntegrationId.browserBridge:
        await BrowserBridgeService.instance.setEnabled(false);
      case NativeIntegrationId.screenRecording:
        await RewindlyService.instance.stop();
        user.rewindlyEnabled = false;
        await Boxes.updateSettings('rewindlyEnabled', false);
        await _coordinator.revokeConsent(id);
      case NativeIntegrationId.quickSnap:
        await QuickSnapService.instance.disable();
        await _coordinator.revokeConsent(id);
      case NativeIntegrationId.globalHooks:
        await HotkeyService.instance.unregisterBindings();
        MouseGesturesService.instance.dispose();
        await _coordinator.revokeConsent(id);
      case NativeIntegrationId.backgroundCapture:
        await enableTrcktivity(false);
        user.trktivityEnabled = false;
        await Boxes.updateSettings('trktivityEnabled', false);
        await _coordinator.revokeConsent(id);
      case NativeIntegrationId.shellIntegration:
        await WinUtils.toggleTaskbar(visible: true);
        user.hideTaskbarOnStartup = false;
        await Boxes.updateSettings('hideTaskbarOnStartup', false);
        await _coordinator.revokeConsent(id);
      default:
        await _coordinator.revokeConsent(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = Theme.of(context).colorScheme.primary;
    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Native Integrations',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Consent, capability, and reduced-mode status for features that observe or change Windows state.',
              style: TextStyle(color: onSurface.withValues(alpha: 0.68)),
            ),
            const SizedBox(height: 10),
            _buildSummary(accent, onSurface),
            const SizedBox(height: 12),
            for (final NativeIntegrationDiagnostic diagnostic in _snapshot.diagnostics)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDiagnosticCard(diagnostic, accent, onSurface),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(Color accent, Color onSurface) {
    final int reduced = _snapshot.diagnostics.where((NativeIntegrationDiagnostic value) => value.reducedMode).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            reduced == 0 ? Icons.verified_outlined : Icons.shield_outlined,
            color: reduced == 0 ? Colors.greenAccent : accent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reduced == 0
                  ? 'All reported integrations are available.'
                  : '$reduced integration${reduced == 1 ? '' : 's'} currently use reduced mode or need consent.',
              style: TextStyle(color: onSurface.withValues(alpha: 0.8)),
            ),
          ),
          Text(
            _snapshot.profile.name,
            style: TextStyle(fontFamily: 'Consolas', color: onSurface.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticCard(NativeIntegrationDiagnostic diagnostic, Color accent, Color onSurface) {
    final bool busy = _busy.contains(diagnostic.id);
    final bool hasConsentToggle = diagnostic.requiresConsent;
    final Color statusColor = _statusColor(diagnostic.status, accent);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_statusIcon(diagnostic.status), color: statusColor, size: 19),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  diagnostic.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
              Text(
                _statusLabel(diagnostic.status),
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 11),
              ),
              if (hasConsentToggle) ...<Widget>[
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: diagnostic.consent,
                  onChanged: busy ? null : (bool value) => _setConsent(diagnostic.id, value),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            diagnostic.disclosure,
            style: TextStyle(color: onSurface.withValues(alpha: 0.7), height: 1.25),
          ),
          const SizedBox(height: 5),
          Text(
            diagnostic.reducedMode ? diagnostic.reducedModeReason : diagnostic.reason,
            style: TextStyle(color: onSurface.withValues(alpha: 0.55), fontSize: 12),
          ),
          if (diagnostic.reversible || diagnostic.consentRequired) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              diagnostic.reversible
                  ? 'Reversible · disable or revoke from this page.'
                  : 'Not automatically reversible.',
              style: TextStyle(color: onSurface.withValues(alpha: 0.42), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(NativeIntegrationStatus status, Color accent) {
    switch (status) {
      case NativeIntegrationStatus.running:
        return Colors.greenAccent;
      case NativeIntegrationStatus.available:
        return accent;
      case NativeIntegrationStatus.blockedByPolicy:
      case NativeIntegrationStatus.error:
        return Colors.orangeAccent;
      case NativeIntegrationStatus.blockedByUser:
      case NativeIntegrationStatus.disabled:
      case NativeIntegrationStatus.unavailable:
        return Colors.white54;
    }
  }

  IconData _statusIcon(NativeIntegrationStatus status) {
    switch (status) {
      case NativeIntegrationStatus.running:
        return Icons.play_circle_outline_rounded;
      case NativeIntegrationStatus.available:
        return Icons.check_circle_outline_rounded;
      case NativeIntegrationStatus.blockedByPolicy:
        return Icons.policy_outlined;
      case NativeIntegrationStatus.blockedByUser:
        return Icons.lock_outline_rounded;
      case NativeIntegrationStatus.error:
        return Icons.error_outline_rounded;
      case NativeIntegrationStatus.unavailable:
        return Icons.portable_wifi_off_rounded;
      case NativeIntegrationStatus.disabled:
        return Icons.pause_circle_outline_rounded;
    }
  }

  String _statusLabel(NativeIntegrationStatus status) {
    switch (status) {
      case NativeIntegrationStatus.blockedByPolicy:
        return 'POLICY BLOCKED';
      case NativeIntegrationStatus.blockedByUser:
        return 'CONSENT NEEDED';
      default:
        return status.name.toUpperCase();
    }
  }
}
