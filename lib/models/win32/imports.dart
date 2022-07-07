// ignore_for_file: public_member_api_docs, sort_constructors_first, non_constant_identifier_names

import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart' hide Size;

import 'mixed.dart';

// #region (collapsed) DLL IMPORT

/// [USER32]

final _user32 = DynamicLibrary.open('user32.dll');

void keybd_event(int bVk, int bScan, int dwFlags, int dwExtraInfo) => _keybd_event(bVk, bScan, dwFlags, dwExtraInfo);
final _keybd_event =
    _user32.lookupFunction<Void Function(Uint8 bVk, Uint8 bScan, Uint32 dwFlags, IntPtr dwExtraInfo), void Function(int bVk, int bScan, int dwFlags, int dwExtraInfo)>(
        'keybd_event');

int GetClassName(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount) => _GetClassName(hWnd, lpClassName, nMaxCount);
final _GetClassName =
    _user32.lookupFunction<Int32 Function(IntPtr hWnd, Pointer<Utf16> lpClassName, Int32 nMaxCount), int Function(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount)>(
        'GetClassNameW');

/// [KERNEL32]
final _kernel32 = DynamicLibrary.open('kernel32.dll');
int QueryFullProcessImageName(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize) =>
    _QueryFullProcessImageName(hProcess, dwFlags, lpExeName, lpdwSize);
final _QueryFullProcessImageName = _kernel32.lookupFunction<Int32 Function(IntPtr hProcess, Uint32 dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize),
    int Function(int hProcess, int dwFlags, Pointer<Utf16> lpExeName, Pointer<Uint32> lpdwSize)>('QueryFullProcessImageNameW');

int GetApplicationUserModelId(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId) =>
    _GetApplicationUserModelId(hProcess, applicationUserModelIdLength, applicationUserModelId);
final _GetApplicationUserModelId = _kernel32.lookupFunction<
    Uint32 Function(IntPtr hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId),
    int Function(int hProcess, Pointer<Uint32> applicationUserModelIdLength, Pointer<Utf16> applicationUserModelId)>('GetApplicationUserModelId');

int ParseApplicationUserModelId(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId) =>
    _ParseApplicationUserModelId(applicationUserModelId, packageFamilyNameLength, packageFamilyName, packageRelativeApplicationIdLength, packageRelativeApplicationId);
final _ParseApplicationUserModelId = _kernel32.lookupFunction<
    Uint32 Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId),
    int Function(Pointer<Utf16> applicationUserModelId, Pointer<Uint32> packageFamilyNameLength, Pointer<Utf16> packageFamilyName,
        Pointer<Uint32> packageRelativeApplicationIdLength, Pointer<Utf16> packageRelativeApplicationId)>('ParseApplicationUserModelId');

/// [GDI]

final _gdi32 = DynamicLibrary.open('gdi32.dll');

int CreateRectRgn(int x1, int y1, int x2, int y2) => _CreateRectRgn(x1, y1, x2, y2);
final _CreateRectRgn = _gdi32.lookupFunction<IntPtr Function(Int32 x1, Int32 y1, Int32 x2, Int32 y2), int Function(int x1, int y1, int x2, int y2)>('CreateRectRgn');

/// [SHELL]
final _shell32 = DynamicLibrary.open('shell32.dll');

int SHQueryUserNotificationState(Pointer<Int32> pquns) => _SHQueryUserNotificationState(pquns);
final _SHQueryUserNotificationState = _shell32.lookupFunction<Int32 Function(Pointer<Int32> pquns), int Function(Pointer<Int32> pquns)>('SHQueryUserNotificationState');

bool IsUserAnAdmin() => _IsUserAnAdmin();
final _IsUserAnAdmin = _shell32.lookupFunction<Bool Function(), bool Function()>('IsUserAnAdmin');

// #endregion

// #region (collapsed) lowlevelFunction Helpers
var __helperWinsList = <int>[];
int enumWindowsProc(int hWnd, int lParam) {
  __helperWinsList.add(hWnd);
  return 1;
}

List<int> enumWindows() {
  final wndProc = Pointer.fromFunction<EnumWindowsProc>(enumWindowsProc, 0);
  __helperWinsList.clear();
  EnumWindows(wndProc, 0);
  // calloc<Nothing>
  // free(wndProc);
  return __helperWinsList;
}

var __helpEnumChildWins = <int>[];
int helperChildEnumWindowFunc(int w, int p) {
  __helpEnumChildWins.add(w);
  return 1;
}

List enumChildWins(hWnd) {
  final wndProc = Pointer.fromFunction<EnumWindowsProc>(helperChildEnumWindowFunc, 0);
  __helpEnumChildWins.clear();
  //this was outside this function when i moved it..
  EnumChildWindows(hWnd, wndProc, 0);
  // calloc<Nothing>
  // free(wndProc);
  return __helpEnumChildWins;
}

final __helperMonitorList = <int, Square>{};
int helperGetMonitorInfo(int hMonitor, int hDC, Pointer lpRect, int lParam) {
  final monitorInfo = Pointer<RECT>.fromAddress(lpRect.address);
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
  return __helperMonitorList;
}
// #endregion
