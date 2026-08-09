import '../platform/distribution_profile.dart';

/// Where a launcher extension came from. These origins are intentionally
/// separate: a curated gallery entry is not the same trust boundary as a
/// bundled extension or a file the user dropped into the plugin folder.
enum PluginSource {
  bundled,
  firstPartyGallery,
  thirdPartyGallery,
  localUserAuthored,
}

extension PluginSourceName on PluginSource {
  String get value => name;

  String get displayName => switch (this) {
        PluginSource.bundled => 'Bundled',
        PluginSource.firstPartyGallery => 'First-party gallery',
        PluginSource.thirdPartyGallery => 'Third-party gallery',
        PluginSource.localUserAuthored => 'Local user-authored',
      };
}

PluginSource parsePluginSource(Object? value, {PluginSource fallback = PluginSource.localUserAuthored}) {
  if (value is! String) return fallback;
  switch (value.trim().toLowerCase()) {
    case 'bundled':
      return PluginSource.bundled;
    case 'firstpartygallery':
    case 'first-party-gallery':
    case 'first_party_gallery':
      return PluginSource.firstPartyGallery;
    case 'thirdpartygallery':
    case 'third-party-gallery':
    case 'third_party_gallery':
      return PluginSource.thirdPartyGallery;
    case 'localuserauthored':
    case 'local-user-authored':
    case 'local_user_authored':
      return PluginSource.localUserAuthored;
    default:
      return fallback;
  }
}

/// Compile-time distribution policy for executable extensions and other
/// user-authored dynamic-code surfaces.
///
/// Store profiles deliberately have no executable extension source enabled in
/// the first release. The policy is still modelled by source and trust fields
/// so a future reviewed extension can be added without weakening the default
/// gate or relying on package identity/runtime settings.
class ExtensionPolicy {
  const ExtensionPolicy._({
    required this.profile,
    required this.canExecutePlugins,
    required this.canFetchPluginGallery,
    required this.canInstallRemotePlugins,
    required this.canInstallPluginDependencies,
    required this.canEditLocalPluginConfiguration,
    required this.canRunUserCommandTemplates,
    required this.canRunArbitraryPowerShell,
    required this.preservePluginData,
    required this.allowedPluginSources,
    required this.allowedPluginIds,
    required this.allowedPublishers,
    required this.requiresVerifiedArtifacts,
    required this.requiresExplicitConsent,
  });

  final DistributionProfile profile;

  /// Whether an external runtime may be started for a plugin at all.
  final bool canExecutePlugins;

  /// Whether the app may fetch the remote gallery index.
  final bool canFetchPluginGallery;

  /// Whether a remote plugin archive/file set may be downloaded and installed.
  final bool canInstallRemotePlugins;

  /// Whether npm, pip, or bun may be invoked to populate plugin dependencies.
  final bool canInstallPluginDependencies;

  /// Whether settings may enable/rename local executable plugins.
  final bool canEditLocalPluginConfiguration;

  /// Whether user-provided command templates may be executed.
  final bool canRunUserCommandTemplates;

  /// Whether arbitrary PowerShell commands may be executed.
  final bool canRunArbitraryPowerShell;

  /// Store uninstall must not remove existing user plugin data.
  final bool preservePluginData;

  /// Future Store extensions must be explicitly allow-listed by origin.
  final Set<PluginSource> allowedPluginSources;
  final Set<String> allowedPluginIds;
  final Set<String> allowedPublishers;
  final bool requiresVerifiedArtifacts;
  final bool requiresExplicitConsent;

  static ExtensionPolicy forProfile(DistributionProfile profile) {
    final bool portable = profile == DistributionProfile.portable;
    return ExtensionPolicy._(
      profile: profile,
      canExecutePlugins: portable && profile.capabilities.executablePlugins,
      canFetchPluginGallery: portable,
      canInstallRemotePlugins: portable,
      canInstallPluginDependencies: portable,
      canEditLocalPluginConfiguration: portable,
      canRunUserCommandTemplates: portable,
      canRunArbitraryPowerShell: portable,
      preservePluginData: true,
      allowedPluginSources: portable
          ? const <PluginSource>{
              PluginSource.bundled,
              PluginSource.firstPartyGallery,
              PluginSource.thirdPartyGallery,
              PluginSource.localUserAuthored,
            }
          : const <PluginSource>{},
      // Empty Store allow-lists are intentional: no Store extension is
      // approved in the first release.
      allowedPluginIds: const <String>{},
      allowedPublishers: const <String>{},
      requiresVerifiedArtifacts: !portable,
      requiresExplicitConsent: !portable,
    );
  }

  static ExtensionPolicy get current => forProfile(DistributionProfileConfig.current);

  bool allowsPluginSource(PluginSource source) => canExecutePlugins && allowedPluginSources.contains(source);

  bool allowsGallerySource(PluginSource source) {
    if (!canInstallRemotePlugins) return false;
    return source == PluginSource.firstPartyGallery || source == PluginSource.thirdPartyGallery;
  }

  bool canInstallDependenciesFor(String runtime) {
    if (!canInstallPluginDependencies) return false;
    final String normalized = runtime.trim().toLowerCase();
    return normalized.contains('py') || normalized.contains('node') || normalized.contains('bun');
  }

  /// Final execution decision. Settings/imported JSON can request `enabled`,
  /// but they cannot grant a source, publisher, artifact verification, or
  /// consent that the selected profile does not allow.
  bool canExecutePlugin({
    required String id,
    required PluginSource source,
    required bool enabled,
    String publisher = '',
    bool artifactHashVerified = false,
    bool signatureVerified = false,
    bool consentGranted = false,
  }) {
    if (!enabled || !allowsPluginSource(source)) return false;
    if (!requiresVerifiedArtifacts && !requiresExplicitConsent) return true;
    final String normalizedId = id.trim().toLowerCase();
    final String normalizedPublisher = publisher.trim().toLowerCase();
    return allowedPluginIds.contains(normalizedId) &&
        allowedPublishers.contains(normalizedPublisher) &&
        artifactHashVerified &&
        signatureVerified &&
        consentGranted;
  }

  String get pluginDisabledMessage =>
      'Executable launcher plugins and the plugin gallery are disabled in this distribution.';

  String get dependencyInstallDisabledMessage =>
      'Automatic plugin dependency installation is disabled in this distribution.';

  String get userCommandDisabledMessage =>
      'User-provided command and PowerShell execution is disabled in this distribution.';

  /// Script-like paths must not be handed to the shell as an implicit execution
  /// request by a Store launcher. This is deliberately conservative.
  bool isUnreviewedCodePath(String path) {
    final String normalized = path.trim().toLowerCase().replaceAll('\\', '/');
    final int extensionIndex = normalized.lastIndexOf('.');
    final String extension = extensionIndex >= 0 ? normalized.substring(extensionIndex) : '';
    const Set<String> scriptExtensions = <String>{
      '.ps1',
      '.psm1',
      '.bat',
      '.cmd',
      '.vbs',
      '.js',
      '.mjs',
      '.cjs',
      '.py',
      '.rb',
      '.pl',
      '.sh',
    };
    return scriptExtensions.contains(extension);
  }

  /// Blocks a user-authored target that would route directly to a script or a
  /// general-purpose runtime. Built-in fixed actions do not use this flag.
  bool blocksUserTarget(String target) {
    if (canRunUserCommandTemplates) return false;
    final String normalized = target.trim().toLowerCase().replaceAll('\\', '/');
    if (isUnreviewedCodePath(normalized) || normalized.contains('executionpolicy')) return true;
    const Set<String> runtimes = <String>{
      'powershell',
      'pwsh',
      'cmd',
      'python',
      'node',
      'bun',
      'npm',
      'pip',
    };
    final Iterable<String> words = normalized.split(RegExp(r'''[\s/\\:"']+'''));
    for (final String rawWord in words) {
      final String word = rawWord.replaceFirst(RegExp(r'\.(exe|cmd)$'), '');
      if (runtimes.contains(word) || word.startsWith('python3')) return true;
    }
    return false;
  }
}
