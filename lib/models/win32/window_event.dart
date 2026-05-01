// ignore_for_file: unused_element, constant_identifier_names, always_specify_types
import 'dart:ffi';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// ── FFI bindings ──────────────────────────────────────────────────────────────
final _user32 = DynamicLibrary.open('user32.dll');

typedef _WinEventProcNative = Void Function(IntPtr, Uint32, IntPtr, Int32, Int32, Uint32, Uint32);

typedef _SetWinEventHookNative = IntPtr Function(
    Uint32, Uint32, IntPtr, Pointer<NativeFunction<_WinEventProcNative>>, Uint32, Uint32, Uint32);
typedef _SetWinEventHookDart = int Function(int, int, int, Pointer<NativeFunction<_WinEventProcNative>>, int, int, int);

typedef _UnhookWinEventNative = Int32 Function(IntPtr);
typedef _UnhookWinEventDart = int Function(int);

typedef _PostThreadMessageNative = Int32 Function(Uint32, Uint32, IntPtr, IntPtr);
typedef _PostThreadMessageDart = int Function(int, int, int, int);

final _setWinEventHook = _user32.lookupFunction<_SetWinEventHookNative, _SetWinEventHookDart>('SetWinEventHook');
final _unhookWinEvent = _user32.lookupFunction<_UnhookWinEventNative, _UnhookWinEventDart>('UnhookWinEvent');
final _postThreadMessage =
    _user32.lookupFunction<_PostThreadMessageNative, _PostThreadMessageDart>('PostThreadMessageW');
typedef _GetAncestorNative = IntPtr Function(IntPtr hwnd, Uint32 gaFlags);
typedef _GetAncestorDart = int Function(int hwnd, int gaFlags);

final _getAncestor = _user32.lookupFunction<_GetAncestorNative, _GetAncestorDart>('GetAncestor');

const int GA_ROOT = 2;
// ── Constants ─────────────────────────────────────────────────────────────────
const int WINEVENT_OUTOFCONTEXT = 0x0000;
const int WINEVENT_SKIPOWNPROCESS = 0x0002;
const int EVENT_SYSTEM_MOVESIZEEND = 0x000B;
const int EVENT_SYSTEM_MOVESIZESTART = 0x000A;
const int EVENT_OBJECT_NAMECHANGE = 0x800C;
const int EVENT_OBJECT_LOCATIONCHANGE = 0x800B;
const int EVENT_SYSTEM_MINIMIZESTART = 0x0016; // window minimizing
const int EVENT_SYSTEM_MINIMIZEEND = 0x0017; // window restored
const int EVENT_SYSTEM_FOREGROUND = 0x0003; // focus changed
const int EVENT_OBJECT_DESTROY = 0x8001; // window closed
const int EVENT_OBJECT_CREATE = 0x8000; // window created

// ── Data class ────────────────────────────────────────────────────────────────
class WindowEvent {
  final int hwnd;
  final int event;
  final String title;
  final int x, y, width, height;

  WindowEvent({
    required this.hwnd,
    required this.event,
    required this.title,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  String get eventName => switch (event) {
        EVENT_SYSTEM_MOVESIZESTART => 'Moving/Resizing',
        EVENT_SYSTEM_MOVESIZEEND => 'Moved/Resized',
        EVENT_OBJECT_NAMECHANGE => 'Renamed',
        EVENT_OBJECT_LOCATIONCHANGE => 'Location changed',
        _ => 'Event 0x${event.toRadixString(16)}',
      };

  @override
  String toString() => '[$eventName] "${title.isEmpty ? '(no title)' : title}"'
      '  ${width}x$height @ ($x, $y)'
      '  hwnd=0x${hwnd.toRadixString(16)}';
}

// ── Worker isolate args ───────────────────────────────────────────────────────
class _WorkerArgs {
  final SendPort eventPort;
  final SendPort replyPort; // worker sends its shutdownSendPort through here
  _WorkerArgs(this.eventPort, this.replyPort);
}

// ── Worker isolate entry point ────────────────────────────────────────────────
void _workerMain(_WorkerArgs args) {
  final throttleMap = <int, int>{}; // hwnd → last-sent timestamp (ms)
  late NativeCallable<_WinEventProcNative> callable;

  void winEventProc(
    int hook,
    int event,
    int hwnd,
    int idObject,
    int idChild,
    int idThread,
    int time,
  ) {
    if (hwnd == 0) return;

    if (event == EVENT_OBJECT_DESTROY) {
      throttleMap.remove(hwnd);
      return; // don't forward destroy events unless you want them in the UI
    }
    // Skip child windows — only care about root top-level windows
    if (_getAncestor(hwnd, GA_ROOT) != hwnd) return;

    // Throttle high-frequency events
    if (event == EVENT_OBJECT_LOCATIONCHANGE || event == EVENT_SYSTEM_MOVESIZESTART) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = throttleMap[hwnd] ?? 0;
      if (now - last < 50) return;
      throttleMap[hwnd] = now;
    }

    final buf = wsalloc(512);
    GetWindowText(hwnd, buf, 512);
    final title = buf.toDartString();
    free(buf);

    final rect = calloc<RECT>();
    GetWindowRect(hwnd, rect);
    final x = rect.ref.left;
    final y = rect.ref.top;
    final w = rect.ref.right - x;
    final h = rect.ref.bottom - y;
    free(rect);

    args.eventPort.send(WindowEvent(
      hwnd: hwnd,
      event: event,
      title: title,
      x: x,
      y: y,
      width: w,
      height: h,
    ));
  }

  // isolateLocal: callback runs on this isolate's event loop only.
  // No ports held open on the main isolate — hot restart safe.
  callable = NativeCallable<_WinEventProcNative>.isolateLocal(winEventProc);

  const flags = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;
  final hooks = [
    _setWinEventHook(EVENT_SYSTEM_MOVESIZESTART, EVENT_SYSTEM_MOVESIZEEND, 0, callable.nativeFunction, 0, 0, flags),
    _setWinEventHook(EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_NAMECHANGE, 0, callable.nativeFunction, 0, 0, flags),
    _setWinEventHook(EVENT_OBJECT_DESTROY, EVENT_OBJECT_DESTROY, 0, callable.nativeFunction, 0, 0, flags),
  ];

  final threadId = GetCurrentThreadId();

  // Set up shutdown receiver and send its SendPort back to main
  final shutdownReceiver = RawReceivePort();
  shutdownReceiver.handler = (_) {
    for (final h in hooks) {
      _unhookWinEvent(h);
    }
    callable.close();
    shutdownReceiver.close();
    _postThreadMessage(threadId, WM_QUIT, 0, 0);
  };
  args.replyPort.send(shutdownReceiver.sendPort);

  // Win32 message pump — required for WINEVENT_OUTOFCONTEXT delivery,
  // and also pumps Dart's event loop so isolateLocal callbacks fire.
  final msg = calloc<MSG>();
  PeekMessage(msg, NULL, 0, 0, PM_NOREMOVE);
  while (GetMessage(msg, NULL, 0, 0) != 0) {
    TranslateMessage(msg);
    DispatchMessage(msg);
  }
  free(msg);
}

// ── Public API ────────────────────────────────────────────────────────────────
Isolate? _workerIsolate;
SendPort? _workerShutdownPort;

/// Starts the window watcher. Returns a [ReceivePort] that delivers
/// [WindowEvent]s on the main isolate. Safe to call again after hot restart —
/// any previous worker is killed first.
Future<ReceivePort> startWindowWatcher() async {
  await stopWindowWatcher();

  final eventPort = ReceivePort();
  final replyPort = ReceivePort();

  _workerIsolate = await Isolate.spawn(
    _workerMain,
    _WorkerArgs(eventPort.sendPort, replyPort.sendPort),
    debugName: 'WindowWatcherWorker',
  );

  // Wait for the worker to send back its shutdown SendPort
  _workerShutdownPort = await replyPort.first as SendPort;
  replyPort.close();

  return eventPort;
}

/// Graceful shutdown: signals the worker to unhook and quit, then hard-kills
/// it after a short grace period as a fallback.
Future<void> stopWindowWatcher() async {
  final worker = _workerIsolate;
  if (worker == null) return;

  _workerShutdownPort?.send(null);
  await Future.delayed(const Duration(milliseconds: 200));
  worker.kill(priority: Isolate.immediate);

  _workerIsolate = null;
  _workerShutdownPort = null;
}
