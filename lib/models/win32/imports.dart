// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'mixed.dart';

// #region (collapsed) DLL IMPORT

/// [USER32]

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

void keybd_event(int bVk, int bScan, int dwFlags, int dwExtraInfo) => _keybd_event(bVk, bScan, dwFlags, dwExtraInfo);
final void Function(int bVk, int bScan, int dwFlags, int dwExtraInfo) _keybd_event =
    _user32.lookupFunction<Void Function(Uint8 bVk, Uint8 bScan, Uint32 dwFlags, IntPtr dwExtraInfo), void Function(int bVk, int bScan, int dwFlags, int dwExtraInfo)>(
        'keybd_event');

int GetClassName(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount) => _GetClassName(hWnd, lpClassName, nMaxCount);
final int Function(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount) _GetClassName =
    _user32.lookupFunction<Int32 Function(IntPtr hWnd, Pointer<Utf16> lpClassName, Int32 nMaxCount), int Function(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount)>(
        'GetClassNameW');

int GetWindowLong(int hWnd, int nIndex) => _GetWindowLong(hWnd, nIndex);
final int Function(int hWnd, int nIndex) _GetWindowLong =
    _user32.lookupFunction<Int32 Function(IntPtr hWnd, Int32 nIndex), int Function(int hWnd, int nIndex)>('GetWindowLongW');

/// [KERNEL32]
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
int QueryFullProcessImageName(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize) =>
    _QueryFullProcessImageName(hProcess, dwFlags, lpExeName, lpdwSize);
final int Function(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize) _QueryFullProcessImageName = _kernel32.lookupFunction<
    Int32 Function(IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize),
    int Function(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize)>('QueryFullProcessImageNameW');

int GetApplicationUserModelId(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId) =>
    _GetApplicationUserModelId(hProcess, applicationUserModelIdLength, applicationUserModelId);
final int Function(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId) _GetApplicationUserModelId =
    _kernel32.lookupFunction<Uint32 Function(IntPtr hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId),
        int Function(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId)>('GetApplicationUserModelId');

int ParseApplicationUserModelId(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId) =>
    _ParseApplicationUserModelId(applicationUserModelId, packageFamilyNameLength, packageFamilyName, packageRelativeApplicationIdLength, packageRelativeApplicationId);
final int Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId) _ParseApplicationUserModelId =
    _kernel32.lookupFunction<
        Uint32 Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
            Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId),
        int Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
            Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId)>('ParseApplicationUserModelId');

/// [GDI]

final DynamicLibrary _gdi32 = DynamicLibrary.open('gdi32.dll');

int CreateRectRgn(int x1, int y1, int x2, int y2) => _CreateRectRgn(x1, y1, x2, y2);
final int Function(int x1, int y1, int x2, int y2) _CreateRectRgn =
    _gdi32.lookupFunction<IntPtr Function(Int32 x1, Int32 y1, Int32 x2, Int32 y2), int Function(int x1, int y1, int x2, int y2)>('CreateRectRgn');

/// [SHELL]
final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');

int SHQueryUserNotificationState(Pointer<Int32> pquns) => _SHQueryUserNotificationState(pquns);
final int Function(Pointer<Int32> pquns) _SHQueryUserNotificationState =
    _shell32.lookupFunction<Int32 Function(Pointer<Int32> pquns), int Function(Pointer<Int32> pquns)>('SHQueryUserNotificationState');

bool IsUserAnAdmin() => _IsUserAnAdmin();
final bool Function() _IsUserAnAdmin = _shell32.lookupFunction<Bool Function(), bool Function()>('IsUserAnAdmin');

// #endregion

// #region (collapsed) lowlevelFunction Helpers
List<int> __helperWinsList = <int>[];
int enumWindowsProc(int hWnd, int lParam) {
  __helperWinsList.add(hWnd);
  return 1;
}

List<int> enumWindows() {
  __helperWinsList.clear();
  final Pointer<NativeFunction<EnumWindowsProc>> wndProc = Pointer.fromFunction<EnumWindowsProc>(enumWindowsProc, 0);
  EnumWindows(wndProc, 0);
  return <int>[...__helperWinsList];
}

List<int> __helpEnumChildWins = <int>[];
int helperChildEnumWindowFunc(int w, int p) {
  __helpEnumChildWins.add(w);
  return 1;
}

List<int> enumChildWins(int hWnd) {
  final Pointer<NativeFunction<EnumWindowsProc>> wndProc = Pointer.fromFunction<EnumWindowsProc>(helperChildEnumWindowFunc, 0);
  __helpEnumChildWins.clear();
  //this was outside this function when i moved it..
  EnumChildWindows(hWnd, wndProc, 0);
  return <int>[...__helpEnumChildWins];
}

final Map<int, Square> __helperMonitorList = <int, Square>{};
//! added RECT
int helperGetMonitorInfo(int hMonitor, int hDC, Pointer<RECT> lpRect, int lParam) {
  final Pointer<RECT> monitorInfo = Pointer<RECT>.fromAddress(lpRect.address);
  __helperMonitorList[hMonitor] = Square(
      x: monitorInfo.ref.left,
      y: monitorInfo.ref.top,
      width: monitorInfo.ref.right - monitorInfo.ref.left,
      height: monitorInfo.ref.bottom - monitorInfo.ref.top,
      length: monitorInfo.ref.right,
      wide: monitorInfo.ref.bottom);
  return 1;
}

Map<int, Square> enumMonitors() {
  __helperMonitorList.clear();
  EnumDisplayMonitors(NULL, nullptr, Pointer.fromFunction<MonitorEnumProc>(helperGetMonitorInfo, 0), 0);
  return <int, Square>{...__helperMonitorList};
}
// #endregion
