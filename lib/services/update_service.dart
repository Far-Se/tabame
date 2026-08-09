import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/win32/win_utils.dart';
import '../platform/app_paths.dart';
import '../platform/distribution_profile.dart';

enum UpdateManagement {
  portableZip,
  installerManaged,
  storeManaged,
}

class UpdateServiceCapabilities {
  const UpdateServiceCapabilities({
    required this.management,
    required this.canCheckRemoteReleases,
    required this.canInstall,
    required this.message,
  });

  factory UpdateServiceCapabilities.forProfile(DistributionProfile profile) {
    switch (profile) {
      case DistributionProfile.portable:
        return const UpdateServiceCapabilities(
          management: UpdateManagement.portableZip,
          canCheckRemoteReleases: true,
          canInstall: true,
          message: 'Portable ZIP releases can be checked and installed from GitHub.',
        );
      case DistributionProfile.storeInstaller:
        return const UpdateServiceCapabilities(
          management: UpdateManagement.installerManaged,
          canCheckRemoteReleases: false,
          canInstall: false,
          message: 'Updates are delivered by the signed Store-listed installer.',
        );
      case DistributionProfile.storeMsix:
        return const UpdateServiceCapabilities(
          management: UpdateManagement.storeManaged,
          canCheckRemoteReleases: false,
          canInstall: false,
          message: 'Updates are delivered by Microsoft Store and MSIX.',
        );
    }
  }

  final UpdateManagement management;
  final bool canCheckRemoteReleases;
  final bool canInstall;
  final String message;
}

class UpdateRelease {
  const UpdateRelease({required this.version, required this.downloadUrl});

  final String version;
  final String downloadUrl;
}

enum VersionComparison {
  upgradeAvailable,
  same,
  downgrade,
  invalid,
}

class VersionPolicy {
  VersionPolicy._();

  static VersionComparison compare(String current, String candidate) {
    final String normalizedCandidate = candidate.trim().toLowerCase();
    if (normalizedCandidate == 'nightly') return VersionComparison.same;

    final List<int>? currentParts = _parse(current);
    final List<int>? candidateParts = _parse(candidate);
    if (currentParts == null || candidateParts == null) return VersionComparison.invalid;

    for (int index = 0; index < currentParts.length; index++) {
      if (candidateParts[index] > currentParts[index]) return VersionComparison.upgradeAvailable;
      if (candidateParts[index] < currentParts[index]) return VersionComparison.downgrade;
    }
    return VersionComparison.same;
  }

  static List<int>? _parse(String value) {
    String normalized = value.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    normalized = normalized.split(RegExp(r'[-+]')).first;
    if (normalized.isEmpty) return null;

    final List<String> components = normalized.split('.');
    if (components.length > 4 || components.any((String component) => int.tryParse(component) == null)) {
      return null;
    }
    final List<int> result = components.map(int.parse).toList();
    while (result.length < 4) {
      result.add(0);
    }
    return result;
  }
}

enum UpdateCheckState {
  latest,
  available,
  managedByInstaller,
  managedByStore,
  unavailable,
  downgradeRejected,
}

class UpdateCheckResult {
  const UpdateCheckResult({
    required this.state,
    required this.message,
    this.release,
    this.installResult,
  });

  final UpdateCheckState state;
  final String message;
  final UpdateRelease? release;
  final UpdateInstallResult? installResult;
}

enum UpdateInstallState {
  started,
  blocked,
  failed,
}

class UpdateInstallResult {
  const UpdateInstallResult({required this.state, required this.message});

  const UpdateInstallResult.started([
    this.message = 'The portable update download has started.',
  ]) : state = UpdateInstallState.started;

  const UpdateInstallResult.blocked(this.message) : state = UpdateInstallState.blocked;

  const UpdateInstallResult.failed(this.message) : state = UpdateInstallState.failed;

  final UpdateInstallState state;
  final String message;
}

abstract interface class UpdateServiceAdapter {
  Future<UpdateRelease?> fetchLatestRelease();

  Future<UpdateInstallResult> install(UpdateRelease release);
}

class UpdateService {
  UpdateService({required this.profile, required this.adapter});

  factory UpdateService.forCurrentProfile({UpdateServiceAdapter? adapter}) {
    final DistributionProfile profile = DistributionProfileConfig.current;
    return UpdateService(
      profile: profile,
      adapter: adapter ?? const GithubZipUpdateAdapter(),
    );
  }

  final DistributionProfile profile;
  final UpdateServiceAdapter adapter;

  UpdateServiceCapabilities get capabilities => UpdateServiceCapabilities.forProfile(profile);

  Future<UpdateCheckResult> checkForUpdates({required String currentVersion, bool autoInstall = false}) async {
    switch (capabilities.management) {
      case UpdateManagement.portableZip:
        break;
      case UpdateManagement.installerManaged:
        return const UpdateCheckResult(
          state: UpdateCheckState.managedByInstaller,
          message: 'Updates are delivered by the signed Store-listed installer.',
        );
      case UpdateManagement.storeManaged:
        return const UpdateCheckResult(
          state: UpdateCheckState.managedByStore,
          message: 'Updates are delivered by Microsoft Store and MSIX.',
        );
    }

    try {
      final UpdateRelease? release = await adapter.fetchLatestRelease();
      if (release == null) {
        return const UpdateCheckResult(
          state: UpdateCheckState.unavailable,
          message: 'No compatible release was found.',
        );
      }

      switch (VersionPolicy.compare(currentVersion, release.version)) {
        case VersionComparison.same:
          return const UpdateCheckResult(
            state: UpdateCheckState.latest,
            message: 'Latest version installed.',
          );
        case VersionComparison.upgradeAvailable:
          final UpdateInstallResult? installResult = autoInstall ? await installUpdate(release) : null;
          return UpdateCheckResult(
            state: UpdateCheckState.available,
            message: installResult?.message ?? 'A newer portable release is available.',
            release: release,
            installResult: installResult,
          );
        case VersionComparison.downgrade:
          return const UpdateCheckResult(
            state: UpdateCheckState.downgradeRejected,
            message: 'The available release is older than this installation; no downgrade was started.',
          );
        case VersionComparison.invalid:
          return const UpdateCheckResult(
            state: UpdateCheckState.unavailable,
            message: 'The release version could not be compared safely; no update was started.',
          );
      }
    } catch (error) {
      return UpdateCheckResult(
        state: UpdateCheckState.unavailable,
        message: 'Update check failed: $error',
      );
    }
  }

  Future<UpdateInstallResult> installUpdate(UpdateRelease release) async {
    if (!capabilities.canInstall) {
      return UpdateInstallResult.blocked(capabilities.message);
    }
    if (release.downloadUrl.trim().isEmpty || release.version.trim().isEmpty) {
      return const UpdateInstallResult.failed('The update release did not contain a valid version and download URL.');
    }
    try {
      return await adapter.install(release);
    } catch (error) {
      return UpdateInstallResult.failed('Update installation failed: $error');
    }
  }
}

class GithubZipUpdateAdapter implements UpdateServiceAdapter {
  const GithubZipUpdateAdapter();

  static const String _releaseApi = 'https://api.github.com/repos/far-se/tabame/releases';

  @override
  Future<UpdateRelease?> fetchLatestRelease() async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      throw UnsupportedError('Portable ZIP updates are currently Windows-only.');
    }

    final http.Response response = await http.get(Uri.parse(_releaseApi));
    if (response.statusCode != 200) return null;
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! List<dynamic> || decoded.isEmpty || decoded.first is! Map<dynamic, dynamic>) return null;

    final Map<dynamic, dynamic> release = decoded.first as Map<dynamic, dynamic>;
    final String version = release['tag_name']?.toString() ?? '';
    final dynamic rawAssets = release['assets'];
    if (version.isEmpty || rawAssets is! List<dynamic>) return null;

    for (final dynamic rawAsset in rawAssets) {
      if (rawAsset is! Map<dynamic, dynamic>) continue;
      final String name = rawAsset['name']?.toString() ?? '';
      final String? downloadUrl = rawAsset['browser_download_url']?.toString();
      if (name.toLowerCase().endsWith('.zip') && downloadUrl != null && downloadUrl.isNotEmpty) {
        return UpdateRelease(version: version, downloadUrl: downloadUrl);
      }
    }
    return null;
  }

  @override
  Future<UpdateInstallResult> install(UpdateRelease release) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return const UpdateInstallResult.blocked('Portable ZIP updates are currently Windows-only.');
    }

    final String safeVersion = release.version.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final String updateArchivePath = AppPaths.temporaryPath('tabame_$safeVersion.zip');
    await WinUtils.downloadFile(release.downloadUrl, updateArchivePath, () {
      final String installDirectory = File(Platform.resolvedExecutable).parent.path;
      WinUtils.open(
        'powershell.exe',
        arguments: '-Command "Start-Sleep -Seconds 1; '
            'Expand-Archive '
            '-LiteralPath \\"$updateArchivePath\\" '
            '-DestinationPath \\"$installDirectory\\" -Force; '
            'Invoke-Item \\"$installDirectory\\tabame.exe\\";"',
      );
      if (kReleaseMode) {
        Timer(const Duration(milliseconds: 100), () {
          WinUtils.closeAllTabameExProcesses();
          exit(0);
        });
      }
    });
    return const UpdateInstallResult.started();
  }
}
