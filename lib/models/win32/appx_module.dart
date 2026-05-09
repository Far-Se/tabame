// ignore_for_file: non_constant_identifier_names, always_specify_types, dead_code

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:xml/xml.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data class
// ─────────────────────────────────────────────────────────────────────────────

class AppxPackage {
  final String fullName;
  final String familyName;
  final String installLocation;

  const AppxPackage({
    required this.fullName,
    required this.familyName,
    required this.installLocation,
  });

  // Parses "Name_Version_Arch_ResourceId_PublisherId" → display name
  String get displayName => fullName.split('_').first;

  @override
  String toString() => 'AppxPackage($displayName  →  $installLocation)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FFI: GetPackagePathByFullName
// ─────────────────────────────────────────────────────────────────────────────

typedef _GetPackagePathNative = Int32 Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>);
typedef _GetPackagePathDart = int Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>);

final _GetPackagePathDart _getPackagePathByFullName = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<_GetPackagePathNative, _GetPackagePathDart>('GetPackagePathByFullName');

/// Resolves [fullName] → install path, or `null` on failure.
/// Works without elevation for packages registered to the current user.
String? getPackagePathByFullName(String fullName) {
  final Pointer<Utf16> pName = fullName.toNativeUtf16();
  final Pointer<Uint32> pLen = calloc<Uint32>();
  try {
    // Pass 1 — get required buffer length (returns ERROR_INSUFFICIENT_BUFFER=122)
    _getPackagePathByFullName(pName, pLen, nullptr);
    if (pLen.value == 0) return null;

    final Pointer<Uint16> pBuf = calloc<Uint16>(pLen.value);
    try {
      final int rc = _getPackagePathByFullName(pName, pLen, pBuf.cast<Utf16>());
      if (rc != ERROR_SUCCESS) return null;
      return pBuf.cast<Utf16>().toDartString(length: pLen.value - 1);
    } finally {
      calloc.free(pBuf);
    }
  } finally {
    calloc.free(pName);
    calloc.free(pLen);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FFI: GetPackagesByPackageFamily  (kernel32, Windows 8+)
//
//  LONG GetPackagesByPackageFamily(
//    PCWSTR  packageFamilyName,
//    UINT32 *count,          // in/out
//    PWSTR  *packageFullNames, // out array of PWSTR (may be NULL)
//    UINT32 *bufferLength,   // in/out total WCHAR buffer
//    PWSTR   buffer          // out flat WCHAR buffer backing the array
//  );
// ─────────────────────────────────────────────────────────────────────────────

typedef _GetPackagesByFamilyNative = Int32 Function(Pointer<Utf16> familyName, Pointer<Uint32> count,
    Pointer<Pointer<Utf16>> fullNames, Pointer<Uint32> bufferLength, Pointer<Utf16> buffer);
typedef _GetPackagesByFamilyDart = int Function(Pointer<Utf16> familyName, Pointer<Uint32> count,
    Pointer<Pointer<Utf16>> fullNames, Pointer<Uint32> bufferLength, Pointer<Utf16> buffer);

final _GetPackagesByFamilyDart _getPackagesByFamily = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<_GetPackagesByFamilyNative, _GetPackagesByFamilyDart>('GetPackagesByPackageFamily');

/// Returns all full-names registered under [familyName] for the current user.
/// Useful when you already know the family name and want the versioned path.
List<String> getPackagesByFamily(String familyName) {
  final Pointer<Utf16> pFamily = familyName.toNativeUtf16();
  final Pointer<Uint32> pCount = calloc<Uint32>();
  final Pointer<Uint32> pBufLen = calloc<Uint32>();

  try {
    // Pass 1 — discover count + buffer size
    _getPackagesByFamily(pFamily, pCount, nullptr, pBufLen, nullptr);
    if (pCount.value == 0) return const <String>[];

    final pFullNames = calloc<Pointer<Utf16>>(pCount.value);
    final Pointer<Uint16> pBuffer = calloc<Uint16>(pBufLen.value);

    try {
      final int rc = _getPackagesByFamily(pFamily, pCount, pFullNames, pBufLen, pBuffer.cast<Utf16>());
      if (rc != ERROR_SUCCESS) return const <String>[];

      return List.generate(pCount.value, (int i) {
        return pFullNames[i].toDartString();
      });
    } finally {
      calloc.free(pFullNames);
      calloc.free(pBuffer);
    }
  } finally {
    calloc.free(pFamily);
    calloc.free(pCount);
    calloc.free(pBufLen);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registry helpers
// ─────────────────────────────────────────────────────────────────────────────

int _openKey(int hive, String subKey, [int samFlags = KEY_READ]) {
  final Pointer<HKEY> hKey = calloc<HKEY>();
  final Pointer<Utf16> lpSub = subKey.toNativeUtf16();
  try {
    final int rc = RegOpenKeyEx(hive, lpSub, 0, samFlags, hKey);
    if (rc != ERROR_SUCCESS) return 0;
    return hKey.value;
  } finally {
    calloc.free(lpSub);
    calloc.free(hKey);
  }
}

List<String> _enumSubKeyNames(int hKey) {
  final List<String> names = <String>[];
  final Pointer<Uint16> buf = calloc<Uint16>(512);
  final Pointer<DWORD> len = calloc<DWORD>();
  try {
    for (int i = 0;; i++) {
      len.value = 512;
      final int rc = RegEnumKeyEx(hKey, i, buf.cast<Utf16>(), len, nullptr, nullptr, nullptr, nullptr);
      if (rc == ERROR_NO_MORE_ITEMS) break;
      if (rc != ERROR_SUCCESS) break;
      names.add(buf.cast<Utf16>().toDartString(length: len.value));
    }
  } finally {
    calloc.free(buf);
    calloc.free(len);
  }
  return names;
}

String? _readStringValue(int hKey, String valueName) {
  final Pointer<Utf16> lpValue = valueName.toNativeUtf16();
  final Pointer<DWORD> dataType = calloc<DWORD>();
  final Pointer<DWORD> dataSize = calloc<DWORD>();
  try {
    // Query size first
    int rc = RegQueryValueEx(hKey, lpValue, nullptr, dataType, nullptr, dataSize);
    if (rc != ERROR_SUCCESS) return null;
    if (dataType.value != REG_SZ && dataType.value != REG_EXPAND_SZ) return null;

    final Pointer<Uint8> buf = calloc<Uint8>(dataSize.value);
    try {
      rc = RegQueryValueEx(hKey, lpValue, nullptr, dataType, buf, dataSize);
      if (rc != ERROR_SUCCESS) return null;
      // dataSize is in bytes; each WCHAR = 2 bytes; subtract null terminator
      final int charCount = (dataSize.value ~/ 2) - 1;
      return buf.cast<Utf16>().toDartString(length: charCount);
    } finally {
      calloc.free(buf);
    }
  } finally {
    calloc.free(lpValue);
    calloc.free(dataType);
    calloc.free(dataSize);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy 1 — HKCU per-user package repository
//
// HKCU\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\
//   CurrentVersion\AppModel\Repository\Packages\<PackageFullName>
//     → PackageID\Path  (REG_SZ)  — the install location
//
// Readable without elevation. Contains every package staged for the current
// user (both WindowsApps machine-wide and user-specific installs).
// ─────────────────────────────────────────────────────────────────────────────

const String _kHkcuPackagesKey = r'SOFTWARE\Classes\Local Settings\Software\Microsoft'
    r'\Windows\CurrentVersion\AppModel\Repository\Packages';

List<AppxPackage> _getPackagesFromHkcu() {
  final int hRoot = _openKey(HKEY_CURRENT_USER, _kHkcuPackagesKey);
  if (hRoot == 0) return const <AppxPackage>[];

  final List<AppxPackage> packages = <AppxPackage>[];
  try {
    for (final String fullName in _enumSubKeyNames(hRoot)) {
      final int hPkg = _openKey(HKEY_CURRENT_USER, '$_kHkcuPackagesKey\\$fullName');
      if (hPkg == 0) continue;

      try {
        // "PackageID" sub-key holds the "Path" value
        final int hPkgId = _openKey(HKEY_CURRENT_USER, '$_kHkcuPackagesKey\\$fullName\\PackageID');

        String? path;
        if (hPkgId != 0) {
          path = _readStringValue(hPkgId, 'Path');
          RegCloseKey(hPkgId);
        }

        // Fallback: resolve via kernel32 API
        path ??= getPackagePathByFullName(fullName);
        if (path == null) continue;

        // Derive family name: everything up to the last '_' segment
        final String family = _familyFromFullName(fullName);

        packages.add(AppxPackage(
          fullName: fullName,
          familyName: family,
          installLocation: path,
        ));
      } finally {
        RegCloseKey(hPkg);
      }
    }
  } finally {
    RegCloseKey(hRoot);
  }
  return packages;
}

// ─────────────────────────────────────────────────────────────────────────────
// Strategy 2 — PackageManager state store  (another non-elevated location)
//
// HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel\StateRepository\
//   Cache\Package\Data\<index>
//     PackageFullName  (REG_SZ)
//
// This key is world-readable and lists machine-wide (provisioned) packages.
// ─────────────────────────────────────────────────────────────────────────────

const String _kStateRepoKey = r'SOFTWARE\Microsoft\Windows\CurrentVersion\AppModel'
    r'\StateRepository\Cache\Package\Data';

List<AppxPackage> _getPackagesFromStateRepo() {
  final int hRoot = _openKey(HKEY_LOCAL_MACHINE, _kStateRepoKey);
  if (hRoot == 0) return const <AppxPackage>[];

  final List<AppxPackage> packages = <AppxPackage>[];
  try {
    for (final String index in _enumSubKeyNames(hRoot)) {
      final int hEntry = _openKey(HKEY_LOCAL_MACHINE, '$_kStateRepoKey\\$index');
      if (hEntry == 0) continue;

      try {
        final String? fullName = _readStringValue(hEntry, 'PackageFullName');
        if (fullName == null || fullName.isEmpty) continue;

        final String? path = getPackagePathByFullName(fullName);
        if (path == null) continue;

        packages.add(AppxPackage(
          fullName: fullName,
          familyName: _familyFromFullName(fullName),
          installLocation: path,
        ));
      } finally {
        RegCloseKey(hEntry);
      }
    }
  } finally {
    RegCloseKey(hRoot);
  }
  return packages;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Enumerates all AppX / MSIX packages visible to the current user without
/// requiring elevation.
///
/// Tries two registry locations and merges results (deduped by fullName).
List<AppxPackage> getAllAppxPackages() {
  if (!Platform.isWindows) {
    throw UnsupportedError('getAllAppxPackages() is Windows-only.');
  }

  final Set<String> seen = <String>{};
  final List<AppxPackage> result = <AppxPackage>[];

  void add(List<AppxPackage> list) {
    for (final AppxPackage p in list) {
      if (seen.add(p.fullName)) result.add(p);
    }
  }

  // Strategy 1: per-user HKCU repository (staged + user installs)
  add(_getPackagesFromHkcu());

  // Strategy 2: machine-wide state repository (provisioned packages)
  add(_getPackagesFromStateRepo());

  return result;
}

/// If you already know the [familyName] (e.g. from a config file), use this
/// to get the current versioned path without any registry walking.
///
/// Example family name: "Microsoft.WindowsCalculator_8wekyb3d8bbwe"
AppxPackage? getAppxPackageByFamily(String familyName) {
  final List<String> fullNames = getPackagesByFamily(familyName);
  for (final String fullName in fullNames) {
    final String? path = getPackagePathByFullName(fullName);
    if (path != null) {
      return AppxPackage(
        fullName: fullName,
        familyName: familyName,
        installLocation: path,
      );
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// "Name_Version_Arch_Resource_PublisherId" → "Name_PublisherId"
String _familyFromFullName(String fullName) {
  final List<String> parts = fullName.split('_');
  if (parts.length < 2) return fullName;
  return '${parts.first}_${parts.last}';
}
// lib/src/appx_launcher.dart
//
// For each AppX package:
//  1. Parse AppxManifest.xml  → Application Id, display name, icon path
//  2. Build the AUMID         → PackageFamilyName!ApplicationId
//  3. Launch via              → IApplicationActivationManager::ActivateApplication
//  4. Resolve icon            → SHGetFileInfo on the shell:AppsFolder item
//                               OR read the logo path from the manifest
//
// No elevation required. No PowerShell.

// ─────────────────────────────────────────────────────────────────────────────
// Data classes
// ─────────────────────────────────────────────────────────────────────────────

class AppxApp {
  /// e.g. "Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookForWindows"
  final String aumid;

  /// Human-readable name (from manifest or resource string)
  final String displayName;

  /// Absolute path to the best available icon (PNG/scale-100 preferred)
  final String? iconPath;

  /// The package this app belongs to
  final String packageFullName;
  final String packageFamilyName;
  final String installLocation;

  const AppxApp({
    required this.aumid,
    required this.displayName,
    required this.packageFullName,
    required this.packageFamilyName,
    required this.installLocation,
    this.iconPath,
  });

  @override
  String toString() => 'AppxApp($displayName  [$aumid])';
}

// ─────────────────────────────────────────────────────────────────────────────
// Manifest parser
//
// AppxManifest.xml lives at the root of every package install directory.
// It contains one or more <Application> elements, each with:
//   Id            → used to build the AUMID
//   VisualElements uap:VisualElements Square44x44Logo  → icon
//   DisplayName   → may be "ms-resource:AppName" (resource ref)
// ─────────────────────────────────────────────────────────────────────────────

class _ManifestApp {
  final String applicationId;
  final String displayName; // raw value, may be "ms-resource:…"
  final String square44Logo; // relative path, may contain "scale-100" etc.

  const _ManifestApp({
    required this.applicationId,
    required this.displayName,
    required this.square44Logo,
  });
}

class _ManifestInfo {
  final String packageFamilyName; // from Identity element
  final List<_ManifestApp> apps;
  const _ManifestInfo({required this.packageFamilyName, required this.apps});
}

_ManifestInfo? _parseManifest(String installLocation) {
  final File manifestFile = File('$installLocation\\AppxManifest.xml');
  if (!manifestFile.existsSync()) return null;

  try {
    final XmlDocument doc = XmlDocument.parse(manifestFile.readAsStringSync());

    // ── Package identity ──────────────────────────────────────────────────
    // <Identity Name="…" Publisher="…" … />
    // Family name = Name + "_" + publisherId (last segment of publisher hash)
    // We can read it from the registry or derive it. Easiest: read manifest
    // and call PackageFamilyNameFromId via FFI, but the simplest non-FFI way
    // is to just look it up from the fullName we already have.
    // Pass it in via the caller instead (see getAllAppxApps below).

    final List<_ManifestApp> apps = <_ManifestApp>[];

    // Namespace-agnostic search — manifests use several uap* namespaces
    final Iterable<XmlElement> applicationElements = doc.findAllElements('Application');
    for (final XmlElement app in applicationElements) {
      final String appId = app.getAttribute('Id') ?? '';
      if (appId.isEmpty) continue;

      // VisualElements can be under uap:VisualElements or just VisualElements
      final XmlElement? ve =
          app.findAllElements('VisualElements').firstOrNull ?? app.findAllElements('uap:VisualElements').firstOrNull;

      final String rawDisplayName = ve?.getAttribute('DisplayName') ?? app.getAttribute('DisplayName') ?? '';

      // Square44x44Logo is the taskbar/Start-menu sized icon
      final String logo44 = ve?.getAttribute('Square44x44Logo') ?? '';

      apps.add(_ManifestApp(
        applicationId: appId,
        displayName: rawDisplayName,
        square44Logo: logo44,
      ));
    }

    return _ManifestInfo(
      packageFamilyName: '', // filled in by caller
      apps: apps,
    );
  } catch (_) {
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Icon resolution
//
// The manifest logo path looks like:
//   "Assets\Square44x44Logo.png"
//   "Assets\Square44x44Logo.scale-100.png"
//   "Images\AppIcon.png"
//
// Windows stores scale variants as:
//   Assets\Square44x44Logo.scale-100.png
//   Assets\Square44x44Logo.scale-150.png
//   Assets\Square44x44Logo.scale-200.png
//
// When the manifest has "Assets\Square44x44Logo.png" we must probe for the
// scale-suffixed variants ourselves because the plain .png may not exist.
// ─────────────────────────────────────────────────────────────────────────────

/// Preferred scale suffixes, highest quality first.
const List<String> _kScales = <String>['scale-200', 'scale-150', 'scale-100', 'scale-125'];

String? _resolveIconPath(String installLocation, String relativeLogo) {
  if (relativeLogo.isEmpty) return null;

  final String base = '$installLocation\\$relativeLogo';

  // 1. Try the path exactly as written in the manifest
  if (File(base).existsSync()) return base;

  // 2. Try inserting scale suffix before the extension
  //    "Assets\Logo.png" → "Assets\Logo.scale-200.png"
  final int dotIdx = base.lastIndexOf('.');
  if (dotIdx != -1) {
    final String stem = base.substring(0, dotIdx);
    final String ext = base.substring(dotIdx); // ".png"
    for (final String scale in _kScales) {
      final String candidate = '$stem.$scale$ext';
      if (File(candidate).existsSync()) return candidate;
    }
  }

  // 3. Try "contrast-*" / "targetsize-*" / "altform-*" variants in same folder
  final Directory dir = Directory(base.substring(0, base.lastIndexOf('\\')));
  if (dir.existsSync()) {
    final String stem = base.substring(base.lastIndexOf('\\') + 1, dotIdx == -1 ? null : dotIdx);
    try {
      final List<File> match = dir
          .listSync()
          .whereType<File>()
          .where((File f) =>
              f.path.toLowerCase().contains(stem.toLowerCase()) && (f.path.endsWith('.png') || f.path.endsWith('.jpg')))
          .toList()
        ..sort((File a, File b) => a.path.length.compareTo(b.path.length));
      if (match.isNotEmpty) return match.first.path;
    } catch (_) {}
  }

  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Resource string resolution  ("ms-resource:AppName")
//
// Proper resolution requires MrmDumpPriFile / MRT (pkg://…/resources.pri).
// A pragmatic fallback for a launcher: use the package directory name or
// the applicationId, which is always human-readable.
// ─────────────────────────────────────────────────────────────────────────────

String _resolveDisplayName(String raw, String installLocation, String applicationId) {
  if (!raw.startsWith('ms-resource:')) return raw.isEmpty ? applicationId : raw;

  // Try to read from resources.pri via SHLoadIndirectString (shell32)
  // Format: @{PackageFullName?ms-resource://PackageName/Resources/String}
  // We skip full MRT and just use the applicationId as the display name,
  // which is readable (e.g. "Microsoft.OutlookForWindows").
  return applicationId;
}

// ─────────────────────────────────────────────────────────────────────────────
// FFI: IApplicationActivationManager
//
// CoCreateInstance(CLSID_ApplicationActivationManager) →
//   IApplicationActivationManager::ActivateApplication(aumid, …)
//
// This is exactly what the Start Menu uses to launch AppX apps.
// ─────────────────────────────────────────────────────────────────────────────

// {2e941141-7f97-4756-ba1d-9decde894a3d}
final Pointer<GUID> _IID_IApplicationActivationManager = GUIDFromString('{2e941141-7f97-4756-ba1d-9decde894a3d}');
// {45BA127D-10A8-46EA-8AB7-56EA9078943C}
final Pointer<GUID> _CLSID_ApplicationActivationManager = GUIDFromString('{45BA127D-10A8-46EA-8AB7-56EA9078943C}');

// IApplicationActivationManager vtable layout (after QueryInterface/AddRef/Release):
//   index 3: ActivateApplication
//   index 4: ActivateForFile
//   index 5: ActivateForProtocol
typedef _ActivateApplicationNative = Int32 Function(
    Pointer obj, Pointer<Utf16> appUserModelId, Pointer<Utf16> arguments, Uint32 options, Pointer<Uint32> processId);
typedef _ActivateApplicationDart = int Function(
    Pointer obj, Pointer<Utf16> appUserModelId, Pointer<Utf16> arguments, int options, Pointer<Uint32> processId);

/// Launches an AppX app by its AUMID.
///
/// Returns the PID of the launched process, or throws on failure.
int launchAppxByAumid(String aumid) {
  // CoInitializeEx must have been called on this thread already.
  // In a Flutter app the framework calls it; in a pure Dart CLI add:
  //   CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  final ppv = calloc<Pointer>();
  final int hr = CoCreateInstance(
    _CLSID_ApplicationActivationManager,
    nullptr,
    CLSCTX_LOCAL_SERVER,
    _IID_IApplicationActivationManager,
    ppv,
  );

  if (FAILED(hr)) {
    calloc.free(ppv);
    throw WindowsException(hr);
  }

  final Pointer<NativeType> pObj = ppv.value;
  calloc.free(ppv);

  // vtable: 0=QI 1=AddRef 2=Release 3=ActivateApplication
  final vtbl = pObj.cast<Pointer<Pointer<NativeFunction>>>().value;
  final _ActivateApplicationDart activateFn =
      vtbl[3].cast<NativeFunction<_ActivateApplicationNative>>().asFunction<_ActivateApplicationDart>();

  final Pointer<Utf16> pAumid = aumid.toNativeUtf16();
  final Pointer<Uint32> pPid = calloc<Uint32>();

  try {
    final int activateHr = activateFn(pObj, pAumid, nullptr, 0 /* AO_NONE */, pPid);
    if (FAILED(activateHr)) throw WindowsException(activateHr);
    return pPid.value;
  } finally {
    calloc.free(pAumid);
    calloc.free(pPid);
    // Release the COM object
    final int Function(Pointer<NativeType>) releaseFn =
        vtbl[2].cast<NativeFunction<Int32 Function(Pointer)>>().asFunction<int Function(Pointer)>();
    releaseFn(pObj);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public API — build AppxApp list from already-enumerated packages
// ─────────────────────────────────────────────────────────────────────────────

/// Call this after getAllAppxPackages() from your previous code.
///
/// ```dart
/// final packages = getAllAppxPackages();
/// final apps     = getAllAppxApps(packages);
/// ```
List<AppxApp> getAllAppxApps(List<AppxPackage> packages) {
  final List<AppxApp> apps = <AppxApp>[];

  for (final AppxPackage pkg in packages) {
    final _ManifestInfo? manifest = _parseManifest(pkg.installLocation);
    if (manifest == null) continue;

    for (final _ManifestApp mApp in manifest.apps) {
      // AUMID = PackageFamilyName + "!" + Application.Id
      final String aumid = '${pkg.familyName}!${mApp.applicationId}';

      final String displayName = _resolveDisplayName(mApp.displayName, pkg.installLocation, mApp.applicationId);

      final String? iconPath = _resolveIconPath(pkg.installLocation, mApp.square44Logo);

      apps.add(AppxApp(
        aumid: aumid,
        displayName: displayName,
        packageFullName: pkg.fullName,
        packageFamilyName: pkg.familyName,
        installLocation: pkg.installLocation,
        iconPath: iconPath,
      ));
    }
  }

  return apps;
}
