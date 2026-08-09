import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../models/win32/win_utils.dart';
import '../platform_models.dart';
import 'win32_api.dart';
import 'windows_window_bridge.dart';

/// Native Windows implementation of [WindowsWindowBridge].
///
/// All Win32 handles are created, inspected, and consumed here. The neutral
/// watcher receives only [PlatformWindow] snapshots with an opaque identity.
class WindowsNativeWindowBridge implements WindowsWindowBridge {
  const WindowsNativeWindowBridge();

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  String get unavailableReason => 'The Windows window service is unavailable on this platform.';

  @override
  Future<List<PlatformWindow>> enumerate() async {
    if (!isAvailable) return const <PlatformWindow>[];

    final int currentProcessId = GetCurrentProcessId();
    final List<PlatformWindow> windows = <PlatformWindow>[];
    for (final int handle in _enumerateHandles()) {
      if (handle == 0 || IsWindow(handle) == 0 || !(_isVisible(handle))) continue;

      final int processId = _processId(handle);
      if (processId == 0 || processId == currentProcessId) continue;

      final String title = _windowText(handle);
      if (title.isEmpty || title == 'PopupHost') continue;

      final String executablePath = _processExecutable(processId);
      final String executable = _basename(executablePath);
      final String className = _windowClass(handle);
      final _WindowBounds bounds = _windowBounds(handle);
      final Object? icon =
          WinUtils.windowIcon(handle) ?? (executablePath.isNotEmpty ? WinUtils.extractIcon(executablePath) : null);
      windows.add(
        PlatformWindow(
          nativeId: '$handle',
          title: title,
          applicationName: executable.isNotEmpty ? executable : className,
          bundleIdentifier: executable,
          processId: processId,
          x: bounds.x,
          y: bounds.y,
          width: bounds.width,
          height: bounds.height,
          executable: executable,
          executablePath: executablePath,
          className: className,
          icon: icon,
          isOnScreen: true,
          isMinimized: IsIconic(handle) != 0,
        ),
      );
    }
    return windows;
  }

  @override
  Future<bool> activate(PlatformWindow window) async {
    final int? handle = int.tryParse(window.nativeId);
    if (handle == null || handle == 0 || IsWindow(handle) == 0) return false;
    if (IsIconic(handle) != 0) ShowWindow(handle, SW_RESTORE);
    return SetForegroundWindow(handle) != 0;
  }

  @override
  Future<String?> captureFocus() async {
    final int handle = GetForegroundWindow();
    if (handle == 0 || _processId(handle) == GetCurrentProcessId()) return null;
    return '$handle';
  }

  @override
  Future<bool> restoreFocus(String? token) async {
    final int? handle = token == null ? null : int.tryParse(token);
    if (handle == null || handle == 0 || IsWindow(handle) == 0) return false;
    if (IsIconic(handle) != 0) ShowWindow(handle, SW_RESTORE);
    return SetForegroundWindow(handle) != 0;
  }
}

final List<int> _windowEnumerationBuffer = <int>[];

int _windowEnumerationCallback(int handle, int lParam) {
  _windowEnumerationBuffer.add(handle);
  return 1;
}

List<int> _enumerateHandles() {
  _windowEnumerationBuffer.clear();
  EnumWindows(Pointer.fromFunction<WNDENUMPROC>(_windowEnumerationCallback, 0), 0);
  return List<int>.unmodifiable(_windowEnumerationBuffer);
}

bool _isVisible(int handle) => IsWindowVisible(handle) != 0;

int _processId(int handle) {
  final Pointer<Uint32> processId = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(handle, processId);
    return processId.value;
  } finally {
    calloc.free(processId);
  }
}

String _windowText(int handle) {
  final int length = GetWindowTextLength(handle);
  if (length <= 0) return '';
  final Pointer<Utf16> buffer = wsalloc(length + 1);
  try {
    GetWindowText(handle, buffer, length + 1);
    return buffer.toDartString();
  } finally {
    calloc.free(buffer);
  }
}

String _windowClass(int handle) {
  final Pointer<Utf16> buffer = wsalloc(256);
  try {
    GetClassName(handle, buffer, 256);
    return buffer.toDartString();
  } finally {
    calloc.free(buffer);
  }
}

String _processExecutable(int processId) {
  final int process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
  if (process == 0) return '';

  final Pointer<Utf16> imageName = wsalloc(MAX_PATH);
  final Pointer<Uint32> imageNameLength = calloc<Uint32>()..value = MAX_PATH;
  try {
    if (QueryFullProcessImageName(process, 0, imageName, imageNameLength) != 0) {
      return imageName.toDartString();
    }

    final Pointer<Utf16> moduleName = wsalloc(MAX_PATH);
    try {
      if (GetModuleFileNameEx(process, 0, moduleName, MAX_PATH) != 0) return moduleName.toDartString();
    } finally {
      calloc.free(moduleName);
    }
    return '';
  } finally {
    calloc.free(imageName);
    calloc.free(imageNameLength);
    CloseHandle(process);
  }
}

String _basename(String path) {
  if (path.isEmpty) return '';
  final String normalized = path.replaceAll('/', '\\');
  final int separator = normalized.lastIndexOf('\\');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

class _WindowBounds {
  const _WindowBounds(this.x, this.y, this.width, this.height);

  final double x;
  final double y;
  final double width;
  final double height;
}

_WindowBounds _windowBounds(int handle) {
  final Pointer<RECT> rect = calloc<RECT>();
  try {
    if (GetWindowRect(handle, rect) == 0) return const _WindowBounds(0, 0, 0, 0);
    return _WindowBounds(
      rect.ref.left.toDouble(),
      rect.ref.top.toDouble(),
      (rect.ref.right - rect.ref.left).toDouble(),
      (rect.ref.bottom - rect.ref.top).toDouble(),
    );
  } finally {
    calloc.free(rect);
  }
}
