// ignore_for_file: constant_identifier_names, non_constant_identifier_names

import 'dart:ffi' hide Size;

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'mixed.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────────────────────────────────────

final class APPBARDATA extends Struct {
  @Uint32()
  external int cbSize;

  external Pointer<IntPtr> hWnd;

  @Uint32()
  external int uCallbackMessage;

  @Uint32()
  external int uEdge;

  /// Inlined RECT (left, top, right, bottom).
  @Int32()
  external int rcLeft;
  @Int32()
  external int rcTop;
  @Int32()
  external int rcRight;
  @Int32()
  external int rcBottom;

  @IntPtr()
  external int lParam;
}

// ─────────────────────────────────────────────────────────────────────────────
// DLL handles
// ─────────────────────────────────────────────────────────────────────────────

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
final DynamicLibrary _comctl32 = DynamicLibrary.open('comctl32.dll');

// ─────────────────────────────────────────────────────────────────────────────
// user32.dll
// ─────────────────────────────────────────────────────────────────────────────

/// Synthesises a keystroke.
void keybd_event(int bVk, int bScan, int dwFlags, int dwExtraInfo) => _keybd_event(bVk, bScan, dwFlags, dwExtraInfo);

final void Function(int, int, int, int) _keybd_event = _user32
    .lookupFunction<Void Function(Uint8, Uint8, Uint32, IntPtr), void Function(int, int, int, int)>('keybd_event');

/// Retrieves information about the specified window.
int GetWindowLong(int hWnd, int nIndex) => _GetWindowLong(hWnd, nIndex);

final int Function(int, int) _GetWindowLong =
    _user32.lookupFunction<Int32 Function(IntPtr, Int32), int Function(int, int)>('GetWindowLongW');

typedef _DrawIconExNative = Int32 Function(
  IntPtr hdc,
  Int32 xLeft,
  Int32 yTop,
  IntPtr hIcon,
  Int32 cxWidth,
  Int32 cyHeight,
  Uint32 istepIfAniCur,
  IntPtr hbrFlickerFreeDraw,
  Uint32 diFlags,
);
typedef DrawIconExDart = int Function(
  int hdc,
  int xLeft,
  int yTop,
  int hIcon,
  int cxWidth,
  int cyHeight,
  int istepIfAniCur,
  int hbrFlickerFreeDraw,
  int diFlags,
);
const int DI_NORMAL = 0x0003;
final DrawIconExDart DrawIconEx = _user32.lookupFunction<_DrawIconExNative, DrawIconExDart>('DrawIconEx');

typedef MessageBeepNative = Int32 Function(Uint32 uType);
typedef MessageBeepDart = int Function(int uType);

final MessageBeepDart MessageBeep = _user32.lookupFunction<MessageBeepNative, MessageBeepDart>('MessageBeep');

// ─────────────────────────────────────────────────────────────────────────────
// kernel32.dll
// ─────────────────────────────────────────────────────────────────────────────

/// Retrieves the application user model ID for the specified process.
int GetApplicationUserModelId(
  int hProcess,
  Pointer<Uint32> applicationUserModelIdLength,
  Pointer<Utf16> applicationUserModelId,
) =>
    _GetApplicationUserModelId(hProcess, applicationUserModelIdLength, applicationUserModelId);

final int Function(int, Pointer<Uint32>, Pointer<Utf16>) _GetApplicationUserModelId = _kernel32.lookupFunction<
    Uint32 Function(IntPtr, Pointer<Uint32>, Pointer<Utf16>), int Function(int, Pointer<Uint32>, Pointer<Utf16>)>(
  'GetApplicationUserModelId',
);

/// Deconstructs an application user model ID into a package family name
/// and a package-relative application ID.
int ParseApplicationUserModelId(
  Pointer<Utf16> applicationUserModelId,
  Pointer<Uint32> packageFamilyNameLength,
  Pointer<Utf16> packageFamilyName,
  Pointer<Uint32> packageRelativeApplicationIdLength,
  Pointer<Utf16> packageRelativeApplicationId,
) =>
    _ParseApplicationUserModelId(
      applicationUserModelId,
      packageFamilyNameLength,
      packageFamilyName,
      packageRelativeApplicationIdLength,
      packageRelativeApplicationId,
    );

final int Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>)
    _ParseApplicationUserModelId = _kernel32.lookupFunction<
        Uint32 Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>),
        int Function(Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>, Pointer<Uint32>, Pointer<Utf16>)>(
  'ParseApplicationUserModelId',
);

/// Expands environment-variable strings and replaces them with the values
/// defined for the current user.
int ExpandEnvironmentStrings(Pointer<Utf16> lpSrc, Pointer<Utf16> lpDst, int nSize) =>
    _ExpandEnvironmentStrings(lpSrc, lpDst, nSize);

final int Function(Pointer<Utf16>, Pointer<Utf16>, int) _ExpandEnvironmentStrings = _kernel32.lookupFunction<
    Uint32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32), int Function(Pointer<Utf16>, Pointer<Utf16>, int)>(
  'ExpandEnvironmentStringsW',
);

// ─────────────────────────────────────────────────────────────────────────────
// shell32.dll
// ─────────────────────────────────────────────────────────────────────────────

/// Sends an appbar message to the system.
int SHAppBarMessage(int dwMessage, Pointer<APPBARDATA> pData) => _SHAppBarMessage(dwMessage, pData);

final int Function(int, Pointer<APPBARDATA>) _SHAppBarMessage =
    _shell32.lookupFunction<IntPtr Function(Uint32, Pointer<APPBARDATA>), int Function(int, Pointer<APPBARDATA>)>(
        'SHAppBarMessage');

/// Retrieves the current user notification state for the taskbar.
int SHQueryUserNotificationState(Pointer<Int32> pquns) => _SHQueryUserNotificationState(pquns);

final int Function(Pointer<Int32>) _SHQueryUserNotificationState = _shell32
    .lookupFunction<Int32 Function(Pointer<Int32>), int Function(Pointer<Int32>)>('SHQueryUserNotificationState');

/// Returns whether the current user is a member of the Administrator's group.
bool IsUserAnAdmin() => _IsUserAnAdmin();

final bool Function() _IsUserAnAdmin = _shell32.lookupFunction<Bool Function(), bool Function()>('IsUserAnAdmin');

/// Extracts large and small icons from the given file.
int ExtractIconEx(
  Pointer<Utf16> lpszFile,
  int nIconIndex,
  Pointer<IntPtr> phiconLarge,
  Pointer<IntPtr> phiconSmall,
  int nIcons,
) =>
    _ExtractIconEx(lpszFile, nIconIndex, phiconLarge, phiconSmall, nIcons);

final int Function(Pointer<Utf16>, int, Pointer<IntPtr>, Pointer<IntPtr>, int) _ExtractIconEx = _shell32.lookupFunction<
    Uint32 Function(Pointer<Utf16>, Int32, Pointer<IntPtr>, Pointer<IntPtr>, Uint32),
    int Function(Pointer<Utf16>, int, Pointer<IntPtr>, Pointer<IntPtr>, int)>(
  'ExtractIconExW',
);
// 1. Define the function signature in C
typedef SHChangeNotifyC = Void Function(
  Int32 wEventId,
  Uint32 uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);

// 2. Define the function signature in Dart
typedef SHChangeNotifyDart = void Function(
  int wEventId,
  int uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);
final SHChangeNotifyDart shChangeNotify =
    _shell32.lookupFunction<SHChangeNotifyC, SHChangeNotifyDart>('SHChangeNotify');

// ─────────────────────────────────────────────────────────────────────────────
// comctl32.dll
// ─────────────────────────────────────────────────────────────────────────────

/// Retrieves the icon for an image in the specified image list.
int ImageList_GetIcon(int himl, int i, int flags) => _ImageList_GetIcon(himl, i, flags);

final int Function(int, int, int) _ImageList_GetIcon =
    _comctl32.lookupFunction<IntPtr Function(IntPtr, Int32, Uint32), int Function(int, int, int)>('ImageList_GetIcon');

// ─────────────────────────────────────────────────────────────────────────────
// Window enumeration helpers
// ─────────────────────────────────────────────────────────────────────────────

final List<int> _enumWindowsBuffer = <int>[];

int _enumWindowsProc(int hWnd, int lParam) {
  _enumWindowsBuffer.add(hWnd);
  return 1;
}

/// Returns a list of handles for all top-level windows.
List<int> enumWindows() {
  _enumWindowsBuffer.clear();
  EnumWindows(Pointer.fromFunction<WNDENUMPROC>(_enumWindowsProc, 0), 0);
  return List<int>.unmodifiable(_enumWindowsBuffer);
}

final List<int> _enumChildBuffer = <int>[];

int _enumChildProc(int hWnd, int lParam) {
  _enumChildBuffer.add(hWnd);
  return 1;
}

/// Returns a list of handles for all child windows of [hWnd].
List<int> enumChildWindows(int hWnd) {
  _enumChildBuffer.clear();
  EnumChildWindows(hWnd, Pointer.fromFunction<WNDENUMPROC>(_enumChildProc, 0), 0);
  return List<int>.unmodifiable(_enumChildBuffer);
}

// ─────────────────────────────────────────────────────────────────────────────
// Monitor enumeration helpers
// ─────────────────────────────────────────────────────────────────────────────

final Map<int, Square> _monitorBuffer = <int, Square>{};

int _enumMonitorProc(int hMonitor, int hDC, Pointer<NativeType> lpRect, int lParam) {
  final RECT rect = Pointer<RECT>.fromAddress(lpRect.address).ref;
  _monitorBuffer[hMonitor] = Square(
    x: rect.left,
    y: rect.top,
    width: rect.right - rect.left,
    height: rect.bottom - rect.top,
    length: rect.right,
    wide: rect.bottom,
  );
  return 1;
}

/// Returns a map of monitor handles to their [Square] screen bounds.
Map<int, Square> enumMonitors() {
  _monitorBuffer.clear();
  EnumDisplayMonitors(NULL, nullptr, Pointer.fromFunction<MONITORENUMPROC>(_enumMonitorProc, 0), 0);
  return Map<int, Square>.unmodifiable(_monitorBuffer);
}
