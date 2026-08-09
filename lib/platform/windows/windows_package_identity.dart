import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../distribution_profile.dart';

typedef _GetCurrentPackageFullNameNative = Uint32 Function(Pointer<Uint32>, Pointer<Utf16>);
typedef _GetCurrentPackageFullNameDart = int Function(Pointer<Uint32>, Pointer<Utf16>);

class PackageIdentityProbeResult {
  const PackageIdentityProbeResult({
    required this.status,
    this.packageFullName,
    required this.diagnostic,
  });

  final PackageIdentityStatus status;
  final String? packageFullName;
  final String diagnostic;
}

class WindowsPackageIdentity {
  WindowsPackageIdentity._();

  static const int _errorSuccess = 0;
  static const int _errorInsufficientBuffer = 122;
  static const int _appModelErrorNoPackage = 15700;

  static _GetCurrentPackageFullNameDart? _getCurrentPackageFullName;
  static bool _lookupAttempted = false;

  static PackageIdentityProbeResult probe() {
    if (!Platform.isWindows) {
      return const PackageIdentityProbeResult(
        status: PackageIdentityStatus.notWindows,
        diagnostic: 'Package identity checks are Windows-only.',
      );
    }

    final _GetCurrentPackageFullNameDart? getPackageFullName = _function;
    if (getPackageFullName == null) {
      return const PackageIdentityProbeResult(
        status: PackageIdentityStatus.unavailable,
        diagnostic: 'GetCurrentPackageFullName is unavailable.',
      );
    }

    final Pointer<Uint32> length = calloc<Uint32>();
    try {
      int result = getPackageFullName(length, nullptr);
      if (result == _appModelErrorNoPackage) {
        return const PackageIdentityProbeResult(
          status: PackageIdentityStatus.notPackaged,
          diagnostic: 'The process has no Windows package identity.',
        );
      }
      if (result != _errorInsufficientBuffer && result != _errorSuccess) {
        return PackageIdentityProbeResult(
          status: PackageIdentityStatus.unavailable,
          diagnostic: 'GetCurrentPackageFullName failed with error $result.',
        );
      }
      if (length.value == 0) {
        return const PackageIdentityProbeResult(
          status: PackageIdentityStatus.unavailable,
          diagnostic: 'GetCurrentPackageFullName returned an empty identity.',
        );
      }

      final Pointer<Uint16> buffer = calloc<Uint16>(length.value);
      try {
        result = getPackageFullName(length, buffer.cast<Utf16>());
        if (result != _errorSuccess) {
          return PackageIdentityProbeResult(
            status: PackageIdentityStatus.unavailable,
            diagnostic: 'GetCurrentPackageFullName failed with error $result.',
          );
        }
        final int characterCount = length.value > 0 ? length.value - 1 : 0;
        return PackageIdentityProbeResult(
          status: PackageIdentityStatus.packaged,
          packageFullName: buffer.cast<Utf16>().toDartString(length: characterCount),
          diagnostic: 'The process has Windows package identity.',
        );
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(length);
    }
  }

  static _GetCurrentPackageFullNameDart? get _function {
    if (_lookupAttempted) return _getCurrentPackageFullName;
    _lookupAttempted = true;
    try {
      _getCurrentPackageFullName = DynamicLibrary.open('kernel32.dll')
          .lookupFunction<_GetCurrentPackageFullNameNative, _GetCurrentPackageFullNameDart>(
        'GetCurrentPackageFullName',
      );
    } catch (_) {
      _getCurrentPackageFullName = null;
    }
    return _getCurrentPackageFullName;
  }
}
