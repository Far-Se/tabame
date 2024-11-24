import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Represents a requested access right.
enum AccessRights {
  readOnly,
  writeOnly,
  allAccess;

  int get win32Value {
    switch (this) {
      case AccessRights.readOnly:
        return REG_SAM_FLAGS.KEY_READ;
      case AccessRights.writeOnly:
        return REG_SAM_FLAGS.KEY_WRITE;
      case AccessRights.allAccess:
        return REG_SAM_FLAGS.KEY_ALL_ACCESS;
    }
  }
}

class RegistryKeyInfo {
  final String className;
  final int subKeyCount;
  final int subKeyNameMaxLength;
  final int subKeyClassNameMaxLength;
  final int valuesCount;
  final int valueNameMaxLength;
  final int valueDataMaxSizeInBytes;
  final int securityDescriptorLength;
  final DateTime? lastWriteTime;

  const RegistryKeyInfo(this.className, this.subKeyCount, this.subKeyNameMaxLength, this.subKeyClassNameMaxLength, this.valuesCount, this.valueNameMaxLength,
      this.valueDataMaxSizeInBytes, this.securityDescriptorLength, this.lastWriteTime);
}

/// One of the predefined keys that point into one or more hives that Windows
/// stores.
///
/// An application can use handles to these keys as entry points to the
/// registry. Predefined keys help an application navigate in the registry and
/// make it possible to develop tools that allow a system administrator to
/// manipulate categories of data. Applications that add data to the registry
/// should always work within the framework of predefined keys, so
/// administrative tools can find and use the new data.
enum RegistryHive {
  /// Registry entries subordinate to this key define the physical state of the
  /// computer, including data about the bus type, system memory, and installed
  /// hardware and software.
  localMachine,

  /// Registry entries subordinate to this key define the preferences of the
  /// current user. These preferences include the settings of environment
  /// variables, data about program groups, colors, printers, network
  /// connections, and application preferences. This key makes it easier to
  /// establish the current user's settings; the key maps to the current user's
  /// branch in `HKEY_USERS`.
  currentUser,

  /// Registry entries subordinate to this key define the default user
  /// configuration for new users on the local computer and the user
  /// configuration for the current user.
  allUsers,

  /// Registry entries subordinate to this key define types (or classes) of
  /// documents and the properties associated with those types. Shell and COM
  /// applications use the information stored under this key.
  classesRoot,

  /// Contains information about the current hardware profile of the local
  /// computer system. The information under `HKEY_CURRENT_CONFIG` describes
  /// only the differences between the current hardware configuration and the
  /// standard configuration.
  currentConfig,

  /// Registry entries subordinate to this key allow you to access performance
  /// data. The data is not actually stored in the registry; the registry
  /// functions cause the system to collect the data from its source.
  performanceData;

  /// Returns the handle for a predefined key.
  int get win32Value {
    switch (this) {
      case RegistryHive.localMachine:
        return HKEY_LOCAL_MACHINE;
      case RegistryHive.currentUser:
        return HKEY_CURRENT_USER;
      case RegistryHive.allUsers:
        return HKEY_USERS;
      case RegistryHive.classesRoot:
        return HKEY_CLASSES_ROOT;
      case RegistryHive.currentConfig:
        return HKEY_CURRENT_CONFIG;
      case RegistryHive.performanceData:
        return HKEY_PERFORMANCE_DATA;
    }
  }
}

/// An individual node in the Windows registry.
///
/// Registry data is structured in a tree format. Each node in the tree is
/// called a key. Keys can contain data entries called values. Keys are somewhat
/// analagous to a directory in a file system, with values being analagous to
/// files.
///
/// Sometimes, the presence of a key is all the data that an application
/// requires; other times, an application opens a key and uses the values
/// associated with the key.
class RegistryKey {
  /// A handle to the current registry key
  final int hkey;

  const RegistryKey(this.hkey);

  /// Creates the specified registry key. If the key already exists, the
  /// function opens it. Note that key names are not case sensitive.
  RegistryKey createKey(String keyName) {
    final Pointer<Utf16> lpSubKey = keyName.toNativeUtf16();
    final Pointer<HKEY> phkResult = calloc<HKEY>();

    try {
      final int retcode = RegCreateKey(hkey, lpSubKey, phkResult);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }

      return RegistryKey(phkResult.value);
    } finally {
      free(lpSubKey);
      free(phkResult);
    }
  }

  /// Deletes a subkey and its values from the specified platform-specific view
  /// of the registry. Note that key names are not case sensitive.
  void deleteKey(String keyName) {
    final Pointer<Utf16> lpSubKey = keyName.toNativeUtf16();

    try {
      final int retcode = RegDeleteKey(hkey, lpSubKey);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }
    } finally {
      free(lpSubKey);
    }
  }

  /// Sets the data and type of a specified value under a registry key.
  void createValue(RegistryValue value) {
    final Pointer<Utf16> lpValueName = value.name.toNativeUtf16();
    final PointerData lpWin32Data = value.toWin32;

    try {
      final int retcode = RegSetValueEx(hkey, lpValueName, NULL, value.type.win32Value, lpWin32Data.data, lpWin32Data.lengthInBytes);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }
    } finally {
      free(lpValueName);
      free(lpWin32Data.data);
    }
  }

  /// Retrieves the type and data for the specified registry value.
  RegistryValue? getValue(String valueName, {String path = '', bool expandPaths = false}) {
    final Pointer<Utf16> lpSubKey = path.toNativeUtf16();
    final Pointer<Utf16> lpValue = valueName.toNativeUtf16();
    final Pointer<DWORD> pdwType = calloc<DWORD>();
    final Pointer<DWORD> pcbData = calloc<DWORD>();

    final int flags = expandPaths ? REG_ROUTINE_FLAGS.RRF_RT_ANY : REG_ROUTINE_FLAGS.RRF_RT_ANY | REG_ROUTINE_FLAGS.RRF_NOEXPAND;

    // Call first time to find out how much memory we need to allocate
    int retcode = RegGetValue(hkey, lpSubKey, lpValue, flags, pdwType, nullptr, pcbData);
    if (retcode == WIN32_ERROR.ERROR_FILE_NOT_FOUND) return null;

    // Now call for real to get the data we need.
    final Pointer<BYTE> pvData = calloc<BYTE>(pcbData.value);
    retcode = RegGetValue(hkey, lpSubKey, lpValue, flags, pdwType, pvData, pcbData);
    final RegistryValue registryValue = RegistryValue.fromWin32(lpValue.toDartString(), pdwType.value, pvData, pcbData.value);

    free(lpSubKey);
    free(lpValue);
    free(pdwType);
    free(pcbData);
    free(pvData);

    return registryValue;
  }

  /// Retrieves the string data for the specified registry value.
  String? getValueAsString(String valueName, {bool expandPaths = false}) {
    final RegistryValue? registryValue = getValue(valueName, expandPaths: expandPaths);

    if (registryValue != null && <RegistryValueType>[RegistryValueType.string, RegistryValueType.unexpandedString, RegistryValueType.link].contains(registryValue.type)) {
      return registryValue.data as String;
    } else {
      return null;
    }
  }

  /// Retrieves the integer data for the specified registry value.
  int? getValueAsInt(String valueName) {
    final RegistryValue? registryValue = getValue(valueName);

    if (registryValue != null &&
        <RegistryValueType>[
          RegistryValueType.int32,
          RegistryValueType.int64,
        ].contains(registryValue.type)) {
      return registryValue.data as int;
    } else {
      return null;
    }
  }

  /// Removes a named value from the specified registry key. Note that value
  /// names are not case sensitive.
  void deleteValue(String valueName) {
    final Pointer<Utf16> lpValueName = valueName.toNativeUtf16();

    try {
      final int retcode = RegDeleteValue(hkey, lpValueName);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }
    } finally {
      free(lpValueName);
    }
  }

  /// Changes the name of the specified registry key.
  void renameSubkey(String oldName, String newName) {
    final Pointer<Utf16> lpSubKeyName = oldName.toNativeUtf16();
    final Pointer<Utf16> lpNewKeyName = newName.toNativeUtf16();

    try {
      final int retcode = RegRenameKey(hkey, lpSubKeyName, lpNewKeyName);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }
    } finally {
      free(lpSubKeyName);
      free(lpNewKeyName);
    }
  }

  /// Retrieves information about the specified registry key.
  RegistryKeyInfo queryInfo() {
    return using((Arena arena) {
      final Pointer<Utf16> lpClass = arena<Uint16>(256).cast<Utf16>();
      final Pointer<DWORD> lpcchClass = arena<DWORD>()..value = 256;
      final Pointer<DWORD> lpcSubKeys = arena<DWORD>();
      final Pointer<DWORD> lpcbMaxSubKeyLen = arena<DWORD>();
      final Pointer<DWORD> lpcbMaxClassLen = arena<DWORD>();
      final Pointer<DWORD> lpcValues = arena<DWORD>();
      final Pointer<DWORD> lpcbMaxValueNameLen = arena<DWORD>();
      final Pointer<DWORD> lpcbMaxValueLen = arena<DWORD>();
      final Pointer<DWORD> lpcbSecurityDescriptor = arena<DWORD>();
      final Pointer<FILETIME> lpftLastWriteTime = arena<FILETIME>();

      final int retcode = RegQueryInfoKey(
          hkey,
          lpClass,
          lpcchClass,
          nullptr, // reserved, must be NULL
          lpcSubKeys,
          lpcbMaxSubKeyLen,
          lpcbMaxClassLen,
          lpcValues,
          lpcbMaxValueNameLen,
          lpcbMaxValueLen,
          lpcbSecurityDescriptor,
          lpftLastWriteTime);

      if (retcode != WIN32_ERROR.ERROR_SUCCESS) {
        throw WindowsException(HRESULT_FROM_WIN32(retcode));
      }

      final DateTime? lastWriteTime = convertToDartDateTime(lpftLastWriteTime);

      return RegistryKeyInfo(lpClass.toDartString(), lpcSubKeys.value, lpcbMaxSubKeyLen.value, lpcbMaxClassLen.value, lpcValues.value, lpcbMaxValueNameLen.value,
          lpcbMaxValueLen.value, lpcbSecurityDescriptor.value, lastWriteTime);
    });
  }

  /// Enumerates the values for the specified open registry key.
  Iterable<RegistryValue> get values sync* {
    final RegistryKeyInfo keyInfo = queryInfo();

    // Allocate enough length for the maximum value name (including extra for
    // the null terminator).
    final int nameMaxLength = keyInfo.valueNameMaxLength + 1;
    final LPWSTR lpName = wsalloc(nameMaxLength);
    final Pointer<DWORD> lpcchName = calloc<DWORD>();
    final Pointer<DWORD> lpType = calloc<DWORD>();
    final Pointer<BYTE> lpData = calloc<BYTE>(keyInfo.valueDataMaxSizeInBytes);
    final Pointer<DWORD> lpcchData = calloc<DWORD>();

    try {
      for (int idx = 0; idx < keyInfo.valuesCount; idx++) {
        // Set these sizes each time, since they're reset to the actual length
        // by the call.
        lpcchName.value = nameMaxLength;
        lpcchData.value = keyInfo.valueDataMaxSizeInBytes;

        final int retcode = RegEnumValue(hkey, idx, lpName, lpcchName, nullptr, lpType, lpData, lpcchData);
        if (retcode == WIN32_ERROR.ERROR_SUCCESS) {
          yield RegistryValue.fromWin32(lpName.toDartString(), lpType.value, lpData, lpcchData.value);
        }
      }
    } finally {
      free(lpName);
      free(lpcchName);
      free(lpType);
      free(lpData);
      free(lpcchData);
    }
  }

  /// Enumerates the values for the specified open registry key.
  Iterable<String> get subkeyNames sync* {
    final RegistryKeyInfo keyInfo = queryInfo();

    // Allocate enough length for the maximum key name (including extra for the
    // null terminator).
    final int keyNameLength = keyInfo.subKeyNameMaxLength + 1;
    final LPWSTR lpName = wsalloc(keyNameLength);
    final Pointer<DWORD> lpcchName = calloc<DWORD>();

    try {
      for (int idx = 0; idx < keyInfo.subKeyCount; idx++) {
        // Set this size each time, since it's reset to the actual length by the
        // call.
        lpcchName.value = keyNameLength;

        final int retcode = RegEnumKeyEx(hkey, idx, lpName, lpcchName, nullptr, nullptr, nullptr, nullptr);
        if (retcode == WIN32_ERROR.ERROR_SUCCESS) {
          yield lpName.toDartString();
        }
      }
    } finally {
      free(lpName);
      free(lpcchName);
    }
  }

  /// Closes a handle to the specified registry key.
  void close() {
    RegCloseKey(hkey);
  }
}

/// A data type stored in the Windows registry. These do not directly map onto
/// either Win32 or Dart types, but represent the kinds of entities that the
/// registry understands.
///
/// More information about the kinds of data that can be found in the registry
/// can be found here:
/// https://docs.microsoft.com/en-us/windows/win32/sysinfo/registry-value-types
enum RegistryValueType {
  /// Binary data in any form. This value is equivalent to the Windows API
  /// registry data type `REG_BINARY`.
  binary,

  /// A 32-bit binary number. This value is equivalent to the Windows API
  /// registry data type `REG_DWORD`.
  int32,

  /// A null-terminated string that contains unexpanded references to
  /// environment variables, such as %PATH%, that are expanded when the value is
  /// retrieved. This value is equivalent to the Windows API registry data type
  /// `REG_EXPAND_SZ`.
  unexpandedString,

  /// A null-terminated string that contains the target path of a symbolic link.
  /// This value is equivalent to the Windows API registry data type `REG_LINK`.
  link,

  /// An array of null-terminated strings, terminated by two null characters.
  /// This value is equivalent to the Windows API registry data type
  /// `REG_MULTI_SZ`.
  stringArray,

  /// No data type.
  none,

  /// A 64-bit binary number. This value is equivalent to the Windows API
  /// registry data type `REG_QWORD`.
  int64,

  /// A null-terminated string. This value is equivalent to the Windows API
  /// registry data type `REG_SZ`.
  string,

  /// An unsupported registry data type.
  unknown;

  /// Return the Win32 value that represents the stored type.
  int get win32Value {
    switch (this) {
      case RegistryValueType.binary:
        return REG_VALUE_TYPE.REG_BINARY;
      case RegistryValueType.int32:
        return REG_VALUE_TYPE.REG_DWORD;
      case RegistryValueType.unexpandedString:
        return REG_VALUE_TYPE.REG_EXPAND_SZ;
      case RegistryValueType.link:
        return REG_VALUE_TYPE.REG_LINK;
      case RegistryValueType.stringArray:
        return REG_VALUE_TYPE.REG_MULTI_SZ;
      case RegistryValueType.none:
        return REG_VALUE_TYPE.REG_NONE;
      case RegistryValueType.int64:
        return REG_VALUE_TYPE.REG_QWORD;
      case RegistryValueType.string:
        return REG_VALUE_TYPE.REG_SZ;
      default:
        throw ArgumentError.value(RegistryValueType.unknown, 'Unknown values cannot be stored.');
    }
  }

  /// Return a string representing the Win32 type stored.
  String get win32Type {
    switch (this) {
      case RegistryValueType.binary:
        return 'REG_BINARY';
      case RegistryValueType.int32:
        return 'REG_DWORD';
      case RegistryValueType.unexpandedString:
        return 'REG_EXPAND_SZ';
      case RegistryValueType.link:
        return 'REG_LINK';
      case RegistryValueType.stringArray:
        return 'REG_MULTI_SZ';
      case RegistryValueType.none:
        return 'REG_NONE';
      case RegistryValueType.int64:
        return 'REG_QWORD';
      case RegistryValueType.string:
        return 'REG_SZ';
      default:
        return '';
    }
  }
}

/// An individual data value in the Windows Registry.
class RegistryValue {
  final String name;
  final RegistryValueType type;
  final Object data;

  const RegistryValue(this.name, this.type, this.data);

  factory RegistryValue.fromWin32(String name, int type, Pointer<Uint8> byteData, int dataLength) {
    switch (type) {
      case REG_VALUE_TYPE.REG_SZ:
        return RegistryValue(name, RegistryValueType.string, byteData.cast<Utf16>().toDartString());
      case REG_VALUE_TYPE.REG_EXPAND_SZ:
        return RegistryValue(name, RegistryValueType.unexpandedString, byteData.cast<Utf16>().toDartString());
      case REG_VALUE_TYPE.REG_LINK:
        return RegistryValue(name, RegistryValueType.link, byteData.cast<Utf16>().toDartString());
      case REG_VALUE_TYPE.REG_MULTI_SZ:
        return RegistryValue(name, RegistryValueType.stringArray, byteData.cast<Utf16>().unpackStringArray(dataLength));
      case REG_VALUE_TYPE.REG_DWORD:
        return RegistryValue(name, RegistryValueType.int32, byteData.cast<DWORD>().value);
      case REG_VALUE_TYPE.REG_QWORD:
        return RegistryValue(name, RegistryValueType.int64, byteData.cast<QWORD>().value);
      case REG_VALUE_TYPE.REG_BINARY:
        return RegistryValue(name, RegistryValueType.binary, byteData.asTypedList(dataLength));
      case REG_VALUE_TYPE.REG_NONE:
        return RegistryValue(name, RegistryValueType.none, 0);
      default:
        return RegistryValue(name, RegistryValueType.unknown, 0);
    }
  }
  PointerData get toWin32 {
    switch (type) {
      case RegistryValueType.int32:
        final Pointer<DWORD> ptr = calloc<DWORD>()..value = data as int;
        return PointerData(ptr.cast<Uint8>(), sizeOf<DWORD>());
      case RegistryValueType.int64:
        final Pointer<QWORD> ptr = calloc<QWORD>()..value = data as int;
        return PointerData(ptr.cast<Uint8>(), sizeOf<QWORD>());
      case RegistryValueType.string:
      case RegistryValueType.unexpandedString:
      case RegistryValueType.link:
        final String strData = data as String;
        final Pointer<Utf16> ptr = strData.toNativeUtf16();
        return PointerData(ptr.cast<Uint8>(), strData.length * 2 + 1);
      case RegistryValueType.stringArray:
        final String strArray = (data as List<String>).map((String s) => '$s\x00').join();
        final Pointer<Utf16> ptr = strArray.toNativeUtf16();
        return PointerData(ptr.cast<Uint8>(), strArray.length * 2);
      case RegistryValueType.binary:
        final Uint8List dataList = Uint8List.fromList(data as List<int>);
        final Pointer<Uint8> ptr = dataList.allocatePointer();
        return PointerData(ptr, dataList.length);

      default:
        return PointerData(nullptr, 0);
    }
  }

  @override
  bool operator ==(Object other) => other is RegistryValue && other.name == name && other.type == type && other.data == data;

  @override
  int get hashCode => name.hashCode * data.hashCode;

  @override
  String toString() => '$name\t$type\t$data';
}

/// Represents the Windows Registry as a database.
///
/// Use this object to access the child keys and values within the registry.
///
/// You can either open a specific key within the registry or use one of the
/// predefined root keys (e.g. [localMachine], [currentUser], or [classesRoot]).
///
/// Example:
///
/// ```dart
/// final key = Registry.openPath(RegistryHive.localMachine,
///   path: r'Software\Microsoft\Windows NT\CurrentVersion');
/// ```
///
/// Once you have a key, you can view subkeys, create new keys, and create,
/// update, rename or delete values stored under that key.
class Registry {
  /// This class shouldn't be instantiated directly.
  Registry._();

  /// Opens a new key based on the given path.
  ///
  /// When you are finished with the key, you should close it and release the
  /// handle with the [RegistryKey.close] method.
  static RegistryKey openPath(RegistryHive hive, {String path = '', AccessRights desiredAccessRights = AccessRights.readOnly}) {
    final Pointer<HKEY> phKey = calloc<HKEY>();
    final Pointer<Utf16> lpSubKey = path.toNativeUtf16();
    try {
      final int lStatus = RegOpenKeyEx(hive.win32Value, lpSubKey, 0, desiredAccessRights.win32Value, phKey);

      if (lStatus == WIN32_ERROR.ERROR_SUCCESS) {
        return RegistryKey(phKey.value);
      } else {
        throw WindowsException(HRESULT_FROM_WIN32(lStatus));
      }
    } finally {
      free(phKey);
      free(lpSubKey);
    }
  }

  static RegistryKey get currentUser {
    // Instead of opening HKEY_CURRENT_USER, this calls the appropriate Windows
    // API, since the thread may be impersonating a different user (e.g. Run
    // As...)
    final Pointer<HKEY> phKey = calloc<HKEY>();

    try {
      final int lStatus = RegOpenCurrentUser(REG_SAM_FLAGS.KEY_ALL_ACCESS, phKey);
      if (lStatus == WIN32_ERROR.ERROR_SUCCESS) {
        return RegistryKey(phKey.value);
      } else {
        throw WindowsException(HRESULT_FROM_WIN32(lStatus));
      }
    } finally {
      free(phKey);
    }
  }

  static RegistryKey get localMachine => openPath(RegistryHive.localMachine, desiredAccessRights: AccessRights.readOnly);
  static RegistryKey get allUsers => openPath(RegistryHive.allUsers, desiredAccessRights: AccessRights.readOnly);
  static RegistryKey get performanceData => openPath(RegistryHive.performanceData, desiredAccessRights: AccessRights.readOnly);
  static RegistryKey get classesRoot => openPath(RegistryHive.classesRoot, desiredAccessRights: AccessRights.readOnly);
  static RegistryKey get currentConfig => openPath(RegistryHive.currentConfig, desiredAccessRights: AccessRights.readOnly);
}

class PointerData {
  final Pointer<Uint8> data;
  final int lengthInBytes;

  const PointerData(this.data, this.lengthInBytes);
}

/// Convert a Win32 `FILETIME` struct into its Dart equivalent.
DateTime? convertToDartDateTime(Pointer<FILETIME> lpFileTime) {
  if (lpFileTime == nullptr) return null;

  final Pointer<SYSTEMTIME> lpSystemTime = calloc<SYSTEMTIME>();
  try {
    final int result = FileTimeToSystemTime(lpFileTime, lpSystemTime);
    if (result == FALSE) return null;

    final SYSTEMTIME systemTime = lpSystemTime.ref;
    final DateTime dateTime =
        DateTime.utc(systemTime.wYear, systemTime.wMonth, systemTime.wDay, systemTime.wHour, systemTime.wMinute, systemTime.wSecond, systemTime.wMilliseconds);

    return dateTime;
  } finally {
    free(lpSystemTime);
  }
}
