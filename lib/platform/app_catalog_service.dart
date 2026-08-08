import 'dart:io';

import 'linux_app_catalog_provider.dart';
import 'macos_app_catalog_provider.dart';

/// A neutral installed-application record used by the portable launcher.
///
/// [launchTarget] is owned by the provider. It is an opaque path or desktop
/// entry reference to shared UI; Windows-specific AUMIDs remain optional
/// metadata rather than a portable identity.
class AppCatalogRecord {
  const AppCatalogRecord({
    required this.stableId,
    required this.name,
    required this.launchTarget,
    required this.sourcePath,
    required this.subtitle,
    this.appUserModelId = '',
    this.iconPath,
    this.desktopId,
    this.exec,
    this.parsingName = '',
    this.executable = '',
    this.arguments = '',
    this.stableIdentity = '',
  });

  final String stableId;
  final String name;
  final String launchTarget;
  final String sourcePath;
  final String subtitle;
  final String appUserModelId;
  final String? iconPath;
  final String? desktopId;
  final String? exec;

  /// Optional provider metadata retained for adapter-owned launch and icon work.
  /// It is never interpreted as a portable identity by shared UI.
  final String parsingName;
  final String executable;
  final String arguments;
  final String stableIdentity;

  AppCatalogRecord copyWith({
    String? stableId,
    String? name,
    String? launchTarget,
    String? sourcePath,
    String? subtitle,
    String? appUserModelId,
    String? iconPath,
    String? desktopId,
    String? exec,
    String? parsingName,
    String? executable,
    String? arguments,
    String? stableIdentity,
  }) {
    return AppCatalogRecord(
      stableId: stableId ?? this.stableId,
      name: name ?? this.name,
      launchTarget: launchTarget ?? this.launchTarget,
      sourcePath: sourcePath ?? this.sourcePath,
      subtitle: subtitle ?? this.subtitle,
      appUserModelId: appUserModelId ?? this.appUserModelId,
      iconPath: iconPath ?? this.iconPath,
      desktopId: desktopId ?? this.desktopId,
      exec: exec ?? this.exec,
      parsingName: parsingName ?? this.parsingName,
      executable: executable ?? this.executable,
      arguments: arguments ?? this.arguments,
      stableIdentity: stableIdentity ?? this.stableIdentity,
    );
  }
}

/// A discovery result that distinguishes an empty successful catalog from an
/// unavailable or failed provider. Existing records should not be deleted for
/// an incomplete snapshot.
class AppCatalogSnapshot {
  const AppCatalogSnapshot({
    required this.records,
    required this.complete,
    this.error,
  });

  final List<AppCatalogRecord> records;
  final bool complete;
  final String? error;
}

abstract interface class AppCatalogProvider {
  bool get isAvailable;
  String get unavailableReason;
  Future<AppCatalogSnapshot> discover();
  Future<bool> launch(AppCatalogRecord record);

  /// Lets an adapter populate an app icon cache without exposing native icon
  /// DTOs to shared code. Unsupported providers return false.
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath);
}

/// Neutral service used by both the portable shell and the Windows launcher
/// catalog. Platform-specific identities and icon loading stay in providers.
abstract class AppCatalogService {
  static AppCatalogService _instance = _selectDefault();

  static AppCatalogService get instance => _instance;

  static void register(AppCatalogService service) {
    _instance = service;
  }

  static AppCatalogService _selectDefault() {
    if (Platform.isMacOS) return PortableAppCatalogService(MacOSAppCatalogProvider());
    if (Platform.isLinux) return PortableAppCatalogService(LinuxAppCatalogProvider());
    return const UnavailableAppCatalogService();
  }

  const AppCatalogService();

  bool get isAvailable;
  String get unavailableReason;
  Future<AppCatalogSnapshot> discover();
  Future<bool> launch(AppCatalogRecord record);
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath);
}

class PortableAppCatalogService extends AppCatalogService {
  const PortableAppCatalogService(this.provider);

  final AppCatalogProvider provider;

  @override
  bool get isAvailable => provider.isAvailable;

  @override
  String get unavailableReason => provider.unavailableReason;

  @override
  Future<AppCatalogSnapshot> discover() => provider.discover();

  @override
  Future<bool> launch(AppCatalogRecord record) => provider.launch(record);

  @override
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath) =>
      provider.cacheIcon(record, destinationPath);
}

class UnavailableAppCatalogService extends AppCatalogService {
  const UnavailableAppCatalogService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Installed-app discovery is unavailable on this platform.';

  @override
  Future<AppCatalogSnapshot> discover() async {
    return const AppCatalogSnapshot(records: <AppCatalogRecord>[], complete: false);
  }

  @override
  Future<bool> launch(AppCatalogRecord record) async => false;

  @override
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath) async => false;
}
