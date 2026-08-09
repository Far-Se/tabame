import 'dart:async';
import 'dart:convert';

import '../models/classes/save_settings.dart';
import '../platform/distribution_profile.dart';

enum NativeIntegrationId {
  globalHooks,
  windowAutomation,
  inputInjection,
  shellIntegration,
  clipboardHistory,
  screenCapture,
  screenRecording,
  ocr,
  contextMenu,
  processActions,
  browserBridge,
  notifications,
  quickSnap,
  audioControl,
  backgroundCapture,
}

enum NativeIntegrationStatus {
  disabled,
  available,
  running,
  blockedByUser,
  blockedByPolicy,
  unavailable,
  error,
}

extension NativeIntegrationStatusName on NativeIntegrationStatus {
  String get value => name;
}

class NativeIntegrationMetadata {
  const NativeIntegrationMetadata({
    required this.label,
    required this.disclosure,
    required this.reversible,
    required this.requiresConsent,
    this.requiresElevation = false,
  });

  final String label;
  final String disclosure;
  final bool reversible;
  final bool requiresConsent;

  /// Only integrations whose native operation genuinely needs elevation set
  /// this flag. A Store profile must not use its elevation restriction as a
  /// blanket block for otherwise-supported native integrations.
  final bool requiresElevation;
}

extension NativeIntegrationIdMetadata on NativeIntegrationId {
  String get value => name;
  String get id => name;

  NativeIntegrationMetadata get metadata {
    switch (this) {
      case NativeIntegrationId.globalHooks:
        return const NativeIntegrationMetadata(
          label: 'Global hooks',
          disclosure: 'Registers system-wide hooks for shortcuts and background input events.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.windowAutomation:
        return const NativeIntegrationMetadata(
          label: 'Window automation',
          disclosure: 'Reads and changes the position, focus, or state of other application windows.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.inputInjection:
        return const NativeIntegrationMetadata(
          label: 'Input injection',
          disclosure: 'Can synthesize keyboard or pointer input on the user’s behalf.',
          reversible: false,
          requiresConsent: true,
        );
      case NativeIntegrationId.shellIntegration:
        return const NativeIntegrationMetadata(
          label: 'Shell integration',
          disclosure: 'Connects Tabame actions to operating-system shell surfaces.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.clipboardHistory:
        return const NativeIntegrationMetadata(
          label: 'Clipboard history',
          disclosure: 'Observes clipboard changes and may retain clipboard history locally.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.screenCapture:
        return const NativeIntegrationMetadata(
          label: 'Screen capture',
          disclosure: 'Captures screen pixels when a capture action is requested.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.screenRecording:
        return const NativeIntegrationMetadata(
          label: 'Screen recording',
          disclosure: 'Captures screen pixels over time while recording is active.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.ocr:
        return const NativeIntegrationMetadata(
          label: 'Screen OCR',
          disclosure: 'Reads text from user-approved screen captures for recognition.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.contextMenu:
        return const NativeIntegrationMetadata(
          label: 'Context menu',
          disclosure: 'Adds Tabame actions to operating-system context menus.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.processActions:
        return const NativeIntegrationMetadata(
          label: 'Process actions',
          disclosure: 'Inspects or acts on running processes, including actions that may require elevation.',
          reversible: false,
          requiresConsent: true,
          requiresElevation: true,
        );
      case NativeIntegrationId.browserBridge:
        return const NativeIntegrationMetadata(
          label: 'Browser bridge',
          disclosure: 'Communicates with a supported browser integration to exchange requested actions.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.notifications:
        return const NativeIntegrationMetadata(
          label: 'Notifications',
          disclosure: 'Shows user-requested status and reminder notifications through the desktop environment.',
          reversible: true,
          requiresConsent: false,
        );
      case NativeIntegrationId.quickSnap:
        return const NativeIntegrationMetadata(
          label: 'Quick snap',
          disclosure: 'Moves selected windows into user-requested snap layouts and may observe window drags.',
          reversible: true,
          requiresConsent: true,
        );
      case NativeIntegrationId.audioControl:
        return const NativeIntegrationMetadata(
          label: 'Audio control',
          disclosure: 'Reads or changes the selected system audio endpoint and volume.',
          reversible: true,
          requiresConsent: false,
        );
      case NativeIntegrationId.backgroundCapture:
        return const NativeIntegrationMetadata(
          label: 'Background capture',
          disclosure: 'Continues an approved capture operation while Tabame is not foregrounded.',
          reversible: true,
          requiresConsent: true,
        );
    }
  }

  String get label => metadata.label;
  String get disclosure => metadata.disclosure;
  bool get reversible => metadata.reversible;
  bool get requiresConsent => metadata.requiresConsent;
  bool get requiresElevation => metadata.requiresElevation;
  bool get highRisk => metadata.requiresConsent;
}

/// Persists only the user's consent decisions for native integrations.
///
/// Implementations must not persist runtime diagnostics or native payloads.
abstract interface class NativeIntegrationConsentStore {
  bool hasConsent(NativeIntegrationId id);

  Future<bool> setConsent(NativeIntegrationId id, bool granted);
}

class InMemoryNativeIntegrationConsentStore implements NativeIntegrationConsentStore {
  InMemoryNativeIntegrationConsentStore({
    Iterable<NativeIntegrationId> initialConsents = const <NativeIntegrationId>[],
  }) : _consented = <NativeIntegrationId>{...initialConsents};

  final Set<NativeIntegrationId> _consented;

  Set<NativeIntegrationId> get consentedIds => Set<NativeIntegrationId>.unmodifiable(_consented);

  @override
  bool hasConsent(NativeIntegrationId id) => _consented.contains(id);

  @override
  Future<bool> setConsent(NativeIntegrationId id, bool granted) async {
    if (granted) {
      _consented.add(id);
    } else {
      _consented.remove(id);
    }
    return true;
  }
}

/// A consent store backed by the existing settings abstraction, without
/// loading the UI-owned [Boxes] registry.
class SaveSettingsNativeIntegrationConsentStore implements NativeIntegrationConsentStore {
  SaveSettingsNativeIntegrationConsentStore(this.settings);

  static const String keyPrefix = 'nativeIntegration.consent.';

  final SaveSettings settings;

  static Future<SaveSettingsNativeIntegrationConsentStore> create({SaveSettings? settings}) async {
    final SaveSettings resolvedSettings = settings ?? await SaveSettings.getInstance();
    return SaveSettingsNativeIntegrationConsentStore(resolvedSettings);
  }

  static String keyFor(NativeIntegrationId id) => '$keyPrefix${id.name}';

  @override
  bool hasConsent(NativeIntegrationId id) => settings.getBool(keyFor(id)) ?? false;

  @override
  Future<bool> setConsent(NativeIntegrationId id, bool granted) {
    if (granted) return settings.setBool(keyFor(id), true);
    return settings.remove(keyFor(id));
  }
}

class NativeIntegrationDiagnostic {
  const NativeIntegrationDiagnostic({
    required this.id,
    required this.label,
    required this.disclosure,
    required this.reversible,
    required this.requiresConsent,
    required this.consentRequired,
    required this.consent,
    required this.status,
    required this.reason,
    required this.reducedMode,
    required this.reducedModeReason,
    required this.allowed,
    required this.canStart,
  });

  final NativeIntegrationId id;
  final String label;
  final String disclosure;
  final bool reversible;
  final bool requiresConsent;
  final bool consentRequired;
  final bool consent;
  final NativeIntegrationStatus status;
  final String reason;
  final bool reducedMode;
  final String reducedModeReason;
  final bool allowed;
  final bool canStart;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id.name,
        'label': label,
        'disclosure': disclosure,
        'reversible': reversible,
        'requiresConsent': requiresConsent,
        'consentRequired': consentRequired,
        'consent': consent,
        'status': status.name,
        'reason': reason,
        'reducedMode': reducedMode,
        'reducedModeReason': reducedModeReason,
        'allowed': allowed,
        'canStart': canStart,
      };

  Map<String, Object?> toMap() => toJson();

  String toJsonString() => jsonEncode(toJson());
}

class NativeIntegrationDiagnosticsSnapshot {
  NativeIntegrationDiagnosticsSnapshot({
    required this.profile,
    required List<NativeIntegrationDiagnostic> diagnostics,
    required this.reducedMode,
    required this.reducedModeReason,
    this.changedId,
  }) : diagnostics = List<NativeIntegrationDiagnostic>.unmodifiable(diagnostics);

  final DistributionProfile profile;
  final List<NativeIntegrationDiagnostic> diagnostics;
  final bool reducedMode;
  final String reducedModeReason;
  final NativeIntegrationId? changedId;

  List<NativeIntegrationDiagnostic> get integrations => diagnostics;
  List<NativeIntegrationDiagnostic> get entries => diagnostics;

  NativeIntegrationDiagnostic? forId(NativeIntegrationId id) {
    for (final NativeIntegrationDiagnostic diagnostic in diagnostics) {
      if (diagnostic.id == id) return diagnostic;
    }
    return null;
  }

  List<Map<String, Object?>> toJsonList() => diagnostics
      .map<Map<String, Object?>>((NativeIntegrationDiagnostic diagnostic) => diagnostic.toJson())
      .toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
        'profile': profile.name,
        'reducedMode': reducedMode,
        'reducedModeReason': reducedModeReason,
        'changedId': changedId?.name,
        'integrations': toJsonList(),
      };

  Map<String, Object?> toMap() => toJson();

  String toJsonString() => jsonEncode(toJson());
}

class NativeIntegrationCoordinator {
  NativeIntegrationCoordinator({
    DistributionProfile? profile,
    NativeIntegrationConsentStore? consentStore,
    NativeIntegrationConsentStore? store,
  })  : profile = profile ?? DistributionProfileConfig.current,
        consentStore = consentStore ?? store ?? InMemoryNativeIntegrationConsentStore();

  factory NativeIntegrationCoordinator.forCurrentProfile({
    NativeIntegrationConsentStore? consentStore,
    NativeIntegrationConsentStore? store,
  }) {
    return NativeIntegrationCoordinator(
      profile: DistributionProfileConfig.current,
      consentStore: consentStore,
      store: store,
    );
  }

  static NativeIntegrationCoordinator _instance = NativeIntegrationCoordinator.forCurrentProfile();

  /// The coordinator used by application lifecycle code. Tests and embedders can
  /// replace it with [configure] without changing the native adapters.
  static NativeIntegrationCoordinator get instance => _instance;

  static void configure({
    DistributionProfile? profile,
    NativeIntegrationConsentStore? consentStore,
    NativeIntegrationConsentStore? store,
  }) {
    _instance = NativeIntegrationCoordinator(
      profile: profile ?? DistributionProfileConfig.current,
      consentStore: consentStore,
      store: store,
    );
  }

  static void register(NativeIntegrationCoordinator coordinator) {
    _instance = coordinator;
  }

  static const Set<NativeIntegrationId> highRiskIds = <NativeIntegrationId>{
    NativeIntegrationId.globalHooks,
    NativeIntegrationId.windowAutomation,
    NativeIntegrationId.inputInjection,
    NativeIntegrationId.shellIntegration,
    NativeIntegrationId.clipboardHistory,
    NativeIntegrationId.screenCapture,
    NativeIntegrationId.screenRecording,
    NativeIntegrationId.ocr,
    NativeIntegrationId.contextMenu,
    NativeIntegrationId.processActions,
    NativeIntegrationId.browserBridge,
    NativeIntegrationId.backgroundCapture,
  };

  final DistributionProfile profile;
  final NativeIntegrationConsentStore consentStore;
  final Map<NativeIntegrationId, _NativeIntegrationRuntimeState> _runtimeStates =
      <NativeIntegrationId, _NativeIntegrationRuntimeState>{};
  final StreamController<NativeIntegrationDiagnosticsSnapshot> _changes =
      StreamController<NativeIntegrationDiagnosticsSnapshot>.broadcast(sync: true);
  bool _disposed = false;

  NativeIntegrationConsentStore get store => consentStore;

  Stream<NativeIntegrationDiagnosticsSnapshot> get changes => _changes.stream;
  Stream<NativeIntegrationDiagnosticsSnapshot> get diagnosticsChanges => changes;
  Stream<NativeIntegrationDiagnosticsSnapshot> get onChanged => changes;
  bool get isDisposed => _disposed;

  bool hasConsent(NativeIntegrationId id) => consentStore.hasConsent(id);

  Future<bool> setConsent(NativeIntegrationId id, bool granted) async {
    final bool persisted = await consentStore.setConsent(id, granted);
    _emitChange(id);
    return persisted;
  }

  Future<bool> revokeConsent(NativeIntegrationId id) => setConsent(id, false);

  /// Records consent for a user-invoked operation. Background services must use
  /// [canStart] directly so a persisted setting never becomes implicit consent.
  Future<bool> authorizeInvocation(NativeIntegrationId id) async {
    if (_profileRequiresConsent(id) && !hasConsent(id)) {
      await setConsent(id, true);
    }
    return isAllowed(id);
  }

  /// Returns whether policy and the current consent decision permit the
  /// integration. Portable retains the legacy no-consent path unless a caller
  /// explicitly requests consent for this operation.
  bool isAllowed(NativeIntegrationId id, {bool requireConsent = false}) {
    return denialReason(id, requireConsent: requireConsent) == null;
  }

  /// Returns whether a new operation may be started. Runtime reports only add
  /// blockers; an integration with no report yet remains startable when policy
  /// allows it so existing portable call sites keep their behavior.
  bool canStart(NativeIntegrationId id, {bool requireConsent = false}) {
    if (!isAllowed(id, requireConsent: requireConsent)) return false;

    final _NativeIntegrationRuntimeState? state = _runtimeStates[id];
    if (state == null || !state.hasReport) return true;
    return state.status == NativeIntegrationStatus.available || state.status == NativeIntegrationStatus.running;
  }

  String? denialReason(NativeIntegrationId id, {bool requireConsent = false}) {
    final String? elevationReason = _elevationDenialReason(id);
    if (elevationReason != null) return elevationReason;

    final bool profileRequiresConsent = _profileRequiresConsent(id);
    if ((requireConsent || profileRequiresConsent) && !hasConsent(id)) {
      if (profileRequiresConsent) {
        return 'Explicit consent is required for this high-risk integration in the ${profile.name} profile.';
      }
      return 'Explicit consent was requested before this integration may run.';
    }
    return null;
  }

  NativeIntegrationStatus statusOf(NativeIntegrationId id) => _diagnosticFor(id).status;

  NativeIntegrationStatus runtimeStatusOf(NativeIntegrationId id) =>
      _runtimeStates[id]?.status ?? NativeIntegrationStatus.disabled;

  void reportAvailable(
    NativeIntegrationId id, {
    String? detail,
    String? reason,
    bool reducedMode = false,
  }) {
    _report(
      id,
      NativeIntegrationStatus.available,
      reason ?? detail ?? 'Native integration is available.',
      reducedMode: reducedMode,
    );
  }

  void reportRunning(
    NativeIntegrationId id, {
    String? detail,
    String? reason,
    bool reducedMode = false,
  }) {
    _report(
      id,
      NativeIntegrationStatus.running,
      reason ?? detail ?? 'Native integration is running.',
      reducedMode: reducedMode,
    );
  }

  void reportUnavailable(
    NativeIntegrationId id, {
    String? detail,
    String? reason,
    bool reducedMode = true,
  }) {
    _report(
      id,
      NativeIntegrationStatus.unavailable,
      reason ?? detail ?? 'The native integration is unavailable in this environment.',
      reducedMode: reducedMode,
    );
  }

  void reportError(
    NativeIntegrationId id, {
    String? detail,
    String? reason,
    bool reducedMode = false,
  }) {
    _report(
      id,
      NativeIntegrationStatus.error,
      reason ?? detail ?? 'The native integration reported an error.',
      reducedMode: reducedMode,
    );
  }

  void reportDisabled(
    NativeIntegrationId id, {
    String? detail,
    String? reason,
    bool reducedMode = false,
  }) {
    _report(
      id,
      NativeIntegrationStatus.disabled,
      reason ?? detail ?? 'The native integration is disabled.',
      reducedMode: reducedMode,
    );
  }

  NativeIntegrationDiagnosticsSnapshot get diagnosticsSnapshot => _buildSnapshot();
  NativeIntegrationDiagnosticsSnapshot get snapshot => diagnosticsSnapshot;
  List<NativeIntegrationDiagnostic> get diagnostics => diagnosticsSnapshot.diagnostics;
  List<NativeIntegrationDiagnostic> get diagnosticsList => diagnostics;
  Map<String, Object?> get diagnosticsJsonMap => diagnosticsSnapshot.toJson();
  String get diagnosticsJson => diagnosticsSnapshot.toJsonString();

  String toDiagnosticsJson() => diagnosticsJson;
  String diagnosticsJsonString() => diagnosticsJson;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _changes.close();
  }

  void _report(
    NativeIntegrationId id,
    NativeIntegrationStatus status,
    String reason, {
    required bool reducedMode,
  }) {
    final _NativeIntegrationRuntimeState state = _runtimeStates.putIfAbsent(
      id,
      () => _NativeIntegrationRuntimeState(),
    );
    final String safeReason = _sanitizeReason(reason);
    state.status = status;
    state.reason = safeReason;
    state.reducedMode = reducedMode;
    state.reducedModeReason = reducedMode ? safeReason : '';
    state.hasReport = true;
    _emitChange(id);
  }

  String? _elevationDenialReason(NativeIntegrationId id) {
    if (!id.metadata.requiresElevation) return null;
    final DistributionCapabilities capabilities = profile.capabilities;
    if (capabilities.runtimeElevation && capabilities.allowElevation) return null;
    return 'Elevation is unavailable for this integration in the ${profile.name} profile.';
  }

  bool _profileRequiresConsent(NativeIntegrationId id) {
    return profile != DistributionProfile.portable && id.metadata.requiresConsent;
  }

  NativeIntegrationDiagnostic _diagnosticFor(NativeIntegrationId id) {
    final NativeIntegrationMetadata metadata = id.metadata;
    final _NativeIntegrationRuntimeState? state = _runtimeStates[id];
    final bool consent = hasConsent(id);
    final bool consentRequired = _profileRequiresConsent(id);
    final String? elevationReason = _elevationDenialReason(id);

    late NativeIntegrationStatus status;
    late String reason;
    late bool reducedMode;
    late String reducedModeReason;

    if (elevationReason != null) {
      status = NativeIntegrationStatus.blockedByPolicy;
      reason = elevationReason;
      reducedMode = true;
      reducedModeReason = elevationReason;
    } else if (consentRequired && !consent) {
      status = NativeIntegrationStatus.blockedByUser;
      reason = 'Explicit consent is required before this high-risk integration can run.';
      reducedMode = true;
      reducedModeReason = reason;
    } else {
      status = state?.status ?? NativeIntegrationStatus.disabled;
      reason = state?.reason ?? 'No runtime status has been reported.';
      reducedMode = state?.reducedMode ?? false;
      reducedModeReason = state?.reducedModeReason ?? '';
      if (status == NativeIntegrationStatus.unavailable ||
          status == NativeIntegrationStatus.blockedByPolicy ||
          status == NativeIntegrationStatus.blockedByUser) {
        reducedMode = true;
        reducedModeReason = reducedModeReason.isEmpty ? reason : reducedModeReason;
      }
    }

    return NativeIntegrationDiagnostic(
      id: id,
      label: metadata.label,
      disclosure: metadata.disclosure,
      reversible: metadata.reversible,
      requiresConsent: metadata.requiresConsent,
      consentRequired: consentRequired,
      consent: consent,
      status: status,
      reason: reason,
      reducedMode: reducedMode,
      reducedModeReason: reducedModeReason,
      allowed: isAllowed(id),
      canStart: canStart(id),
    );
  }

  NativeIntegrationDiagnosticsSnapshot _buildSnapshot({NativeIntegrationId? changedId}) {
    final List<NativeIntegrationDiagnostic> diagnostics = <NativeIntegrationDiagnostic>[
      for (final NativeIntegrationId id in NativeIntegrationId.values) _diagnosticFor(id),
    ];
    final List<String> reducedReasons = <String>[];
    for (final NativeIntegrationDiagnostic diagnostic in diagnostics) {
      if (!diagnostic.reducedMode || diagnostic.reducedModeReason.isEmpty) continue;
      if (!reducedReasons.contains(diagnostic.reducedModeReason)) {
        reducedReasons.add(diagnostic.reducedModeReason);
      }
    }

    return NativeIntegrationDiagnosticsSnapshot(
      profile: profile,
      diagnostics: diagnostics,
      reducedMode: reducedReasons.isNotEmpty,
      reducedModeReason: reducedReasons.isEmpty ? '' : reducedReasons.join(' '),
      changedId: changedId,
    );
  }

  void _emitChange(NativeIntegrationId changedId) {
    if (_disposed) return;
    _changes.add(_buildSnapshot(changedId: changedId));
  }
}

class _NativeIntegrationRuntimeState {
  NativeIntegrationStatus status = NativeIntegrationStatus.disabled;
  String reason = 'No runtime status has been reported.';
  bool reducedMode = false;
  String reducedModeReason = '';
  bool hasReport = false;
}

String _sanitizeReason(String raw) {
  String value = raw.trim();
  if (value.isEmpty) return 'No diagnostic reason was provided.';

  final String lower = value.toLowerCase();
  if (lower.contains('clipboard')) {
    return 'Clipboard details were redacted from diagnostics.';
  }
  if (RegExp(
    r'\b(?:token|secret|password|credential|authorization|api[_ -]?key|access[_ -]?key)\b',
    caseSensitive: false,
  ).hasMatch(value)) {
    return 'Sensitive credential details were redacted from diagnostics.';
  }

  value = value.replaceAll(
    RegExp(r'''(?:[A-Za-z]:[\\/]|\\\\)[^"'<>|,\r\n]+'''),
    '[redacted path]',
  );
  value = value.replaceAll(
    RegExp(r'''(?<![A-Za-z0-9])/(?:[^"'<>|,\r\n/]+/)+[^"'<>|,\r\n]*'''),
    '[redacted path]',
  );
  value = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length > 240) value = '${value.substring(0, 237)}...';
  return value;
}
