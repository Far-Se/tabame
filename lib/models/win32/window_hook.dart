// ignore_for_file: unused_element, constant_identifier_names, always_specify_types

import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

final _user32 = DynamicLibrary.open('user32.dll');

typedef _LowLevelKeyboardProcNative = IntPtr Function(
  Int32 nCode,
  IntPtr wParam,
  IntPtr lParam,
);

typedef _SetWindowsHookExNative = IntPtr Function(
  Int32 idHook,
  Pointer<NativeFunction<_LowLevelKeyboardProcNative>> lpfn,
  IntPtr hMod,
  Uint32 dwThreadId,
);

typedef _SetWindowsHookExDart = int Function(
  int idHook,
  Pointer<NativeFunction<_LowLevelKeyboardProcNative>> lpfn,
  int hMod,
  int dwThreadId,
);

typedef _CallNextHookExNative = IntPtr Function(
  IntPtr hhk,
  Int32 nCode,
  IntPtr wParam,
  IntPtr lParam,
);

typedef _CallNextHookExDart = int Function(
  int hhk,
  int nCode,
  int wParam,
  int lParam,
);

typedef _UnhookWindowsHookExNative = Int32 Function(IntPtr hhk);
typedef _UnhookWindowsHookExDart = int Function(int hhk);

typedef _PostThreadMessageNative = Int32 Function(
  Uint32 idThread,
  Uint32 msg,
  IntPtr wParam,
  IntPtr lParam,
);

typedef _PostThreadMessageDart = int Function(
  int idThread,
  int msg,
  int wParam,
  int lParam,
);

final _setWindowsHookEx = _user32.lookupFunction<_SetWindowsHookExNative, _SetWindowsHookExDart>(
  'SetWindowsHookExW',
);

final _callNextHookEx = _user32.lookupFunction<_CallNextHookExNative, _CallNextHookExDart>(
  'CallNextHookEx',
);

final _unhookWindowsHookEx = _user32.lookupFunction<_UnhookWindowsHookExNative, _UnhookWindowsHookExDart>(
  'UnhookWindowsHookEx',
);

final _postThreadMessage = _user32.lookupFunction<_PostThreadMessageNative, _PostThreadMessageDart>(
  'PostThreadMessageW',
);

const int WH_KEYBOARD_LL = 13;
const int HC_ACTION = 0;

class _KeyboardBlockerArgs {
  final SendPort replyPort;
  final Duration? autoRestoreAfter;

  _KeyboardBlockerArgs(this.replyPort, this.autoRestoreAfter);
}

void _keyboardBlockerWorkerMain(_KeyboardBlockerArgs args) {
  late NativeCallable<_LowLevelKeyboardProcNative> callable;

  int hook = 0;
  bool shuttingDown = false;

  int lowLevelKeyboardProc(int nCode, int wParam, int lParam) {
    try {
      if (nCode >= 0 && !shuttingDown) {
        return 1;
      }

      return _callNextHookEx(hook, nCode, wParam, lParam);
    } catch (_) {
      return 0;
    }
  }

  callable = NativeCallable<_LowLevelKeyboardProcNative>.isolateLocal(
    lowLevelKeyboardProc,
    exceptionalReturn: 0,
  );

  hook = _setWindowsHookEx(
    WH_KEYBOARD_LL,
    callable.nativeFunction,
    NULL,
    0,
  );

  final int threadId = GetCurrentThreadId();

  void shutdown() {
    if (shuttingDown) return;
    shuttingDown = true;

    if (hook != 0) {
      _unhookWindowsHookEx(hook);
      hook = 0;
    }

    _postThreadMessage(threadId, WM_QUIT, 0, 0);
  }

  final shutdownReceiver = RawReceivePort();
  shutdownReceiver.handler = (_) {
    shutdownReceiver.close();
    shutdown();
  };

  args.replyPort.send(shutdownReceiver.sendPort);

  Timer? timer;
  final autoRestoreAfter = args.autoRestoreAfter;
  if (autoRestoreAfter != null) {
    timer = Timer(autoRestoreAfter, () {
      shutdownReceiver.close();
      shutdown();
    });
  }

  final msg = calloc<MSG>();

  // Force creation of this thread's message queue.
  PeekMessage(msg, NULL, 0, 0, PM_NOREMOVE);

  while (GetMessage(msg, NULL, 0, 0) != 0) {
    TranslateMessage(msg);
    DispatchMessage(msg);
  }

  timer?.cancel();
  free(msg);

  callable.close();
}

Isolate? _keyboardBlockerIsolate;
SendPort? _keyboardBlockerShutdownPort;

/// Blocks keyboard input globally.
///
/// Strongly recommended: always pass [autoRestoreAfter].
Future<void> startKeyboardBlocker({
  Duration autoRestoreAfter = const Duration(seconds: 10),
}) async {
  await stopKeyboardBlocker();

  final replyPort = ReceivePort();

  _keyboardBlockerIsolate = await Isolate.spawn(
    _keyboardBlockerWorkerMain,
    _KeyboardBlockerArgs(replyPort.sendPort, autoRestoreAfter),
    debugName: 'KeyboardBlockerWorker',
  );

  _keyboardBlockerShutdownPort = await replyPort.first as SendPort;
  replyPort.close();
}

/// Restores keyboard input.
Future<void> stopKeyboardBlocker() async {
  final worker = _keyboardBlockerIsolate;
  if (worker == null) return;

  _keyboardBlockerShutdownPort?.send(null);

  await Future.delayed(const Duration(milliseconds: 200));
  worker.kill(priority: Isolate.immediate);

  _keyboardBlockerIsolate = null;
  _keyboardBlockerShutdownPort = null;
}
