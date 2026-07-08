import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import '../models/globals.dart';
import '../models/util/system_power.dart';
import '../models/win32/win_utils.dart';

/// Conditional keep-awake and "when it finishes" automations.
///
/// Extends the plain Always Awake toggle with rules that are evaluated on a
/// 5-second tick:
///  - keep the system awake while a named process is running,
///  - keep the system awake while network throughput stays above a threshold,
///  - fire an action (notify / sleep / hibernate / shutdown / lock) when a
///    watched process exits or when network transfer goes idle.
///
/// Rules are session-scoped by design ("while this render/download runs") —
/// they are not persisted across app restarts. The manual Always Awake toggle
/// keeps its existing [WinUtils.alwaysAwakeRun] path; this service only adds
/// its own execution-state assertions on top and never clears the manual one.
class AwakeGuard {
  AwakeGuard._();

  static const Duration tickInterval = Duration(seconds: 5);

  /// Consecutive below-threshold ticks before a network automation fires
  /// (6 ticks × 5s = 30s of calm, so short pauses don't trigger it).
  static const int networkIdleTicksToFire = 6;

  static final List<ProcessAwakeRule> processRules = <ProcessAwakeRule>[];
  static NetworkAwakeRule? networkRule;
  static final List<ProcessAutomation> processAutomations = <ProcessAutomation>[];
  static NetworkAutomation? networkAutomation;

  /// Bumped whenever rules change or an automation fires, so open panels and
  /// the top-bar button can repaint.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Human-readable line describing what the guard is currently doing.
  static String statusLine = "Idle";

  /// Last measured network throughput (bytes/second, in + out), or -1 when
  /// the network is not being sampled.
  static double lastNetworkBytesPerSec = -1;

  static Timer? _timer;
  static bool _forcing = false;

  static bool get isForcing => _forcing;

  static bool get hasWork =>
      processRules.isNotEmpty || networkRule != null || processAutomations.isNotEmpty || networkAutomation != null;

  static void _notifyChanged() {
    revision.value++;
    if (hasWork) {
      _timer ??= Timer.periodic(tickInterval, (Timer _) => _tick());
      _tick();
    } else {
      _timer?.cancel();
      _timer = null;
      _stopForcing();
      statusLine = "Idle";
      lastNetworkBytesPerSec = -1;
      _prevOctets = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Rule management
  // ---------------------------------------------------------------------------

  static void addProcessRule(String exe) {
    final String normalized = _normalizeExe(exe);
    if (normalized.isEmpty) return;
    if (processRules.any((ProcessAwakeRule r) => r.exe == normalized)) return;
    processRules.add(ProcessAwakeRule(normalized));
    _notifyChanged();
  }

  static void removeProcessRule(ProcessAwakeRule rule) {
    processRules.remove(rule);
    _notifyChanged();
  }

  static void setNetworkRule(NetworkAwakeRule? rule) {
    networkRule = rule;
    _notifyChanged();
  }

  static void addProcessAutomation(String exe, AwakeAutomationAction action) {
    final String normalized = _normalizeExe(exe);
    if (normalized.isEmpty) return;
    processAutomations
        .removeWhere((ProcessAutomation automation) => automation.exe == normalized && automation.action == action);
    processAutomations.add(ProcessAutomation(normalized, action));
    _notifyChanged();
  }

  static void removeProcessAutomation(ProcessAutomation automation) {
    processAutomations.remove(automation);
    _notifyChanged();
  }

  static void setNetworkAutomation(NetworkAutomation? automation) {
    networkAutomation = automation;
    _notifyChanged();
  }

  static String _normalizeExe(String exe) {
    String value = exe.trim().toLowerCase();
    if (value.isEmpty) return value;
    if (!value.endsWith('.exe')) value = '$value.exe';
    return value;
  }

  // ---------------------------------------------------------------------------
  // Tick
  // ---------------------------------------------------------------------------

  static void _tick() {
    Set<String>? running;
    if (processRules.isNotEmpty || processAutomations.isNotEmpty) {
      running = listRunningProcesses();
    }

    final bool needNetwork = networkRule != null || networkAutomation != null;
    if (needNetwork) {
      lastNetworkBytesPerSec = _sampleNetworkRate();
    } else {
      lastNetworkBytesPerSec = -1;
      _prevOctets = null;
    }

    // --- keep-awake conditions -------------------------------------------------
    String? forceReason;
    for (final ProcessAwakeRule rule in processRules) {
      rule.isRunning = running!.contains(rule.exe);
      if (rule.isRunning && forceReason == null) forceReason = "${rule.exe} running";
    }
    if (forceReason == null && networkRule != null && lastNetworkBytesPerSec >= 0) {
      if (lastNetworkBytesPerSec >= networkRule!.thresholdBytesPerSec) {
        forceReason = "network active (${formatRate(lastNetworkBytesPerSec)})";
      }
    }

    if (forceReason != null) {
      _forcing = true;
      // Re-assert every tick; the flag combination matches WinUtils.alwaysAwakeRun.
      SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_AWAYMODE_REQUIRED);
      statusLine = "Keeping awake — $forceReason";
    } else {
      _stopForcing();
      statusLine = hasWork ? "Watching — conditions not met" : "Idle";
    }

    // --- automations -------------------------------------------------------------
    final List<ProcessAutomation> firedProcess = <ProcessAutomation>[];
    for (final ProcessAutomation automation in processAutomations) {
      final bool isRunning = running!.contains(automation.exe);
      if (isRunning) {
        automation.seenRunning = true;
      } else if (automation.seenRunning) {
        firedProcess.add(automation);
      }
    }
    for (final ProcessAutomation automation in firedProcess) {
      processAutomations.remove(automation);
      _fire(automation.action, "${automation.exe} has exited");
    }

    final NetworkAutomation? netAuto = networkAutomation;
    if (netAuto != null && lastNetworkBytesPerSec >= 0) {
      if (lastNetworkBytesPerSec >= netAuto.thresholdBytesPerSec) {
        netAuto.armed = true;
        netAuto.idleTicks = 0;
      } else if (netAuto.armed) {
        netAuto.idleTicks++;
        if (netAuto.idleTicks >= networkIdleTicksToFire) {
          networkAutomation = null;
          _fire(netAuto.action, "network transfer finished");
        }
      }
    }

    revision.value++;
  }

  static void _stopForcing() {
    if (!_forcing) return;
    _forcing = false;
    // Don't clear the manual Always Awake assertion — its own 45s timer in
    // WinUtils.alwaysAwakeRun owns that state.
    if (!Globals.alwaysAwake) SetThreadExecutionState(ES_CONTINUOUS);
  }

  static void _fire(AwakeAutomationAction action, String reason) {
    if (action == AwakeAutomationAction.notify) {
      WinUtils.msgBox("Awake Guard", "Done: $reason.", speak: "Done: $reason");
      _notifyChanged();
      return;
    }
    final SystemPowerAction? power = SystemPowerAction.byToken(action.name);
    power?.execute();
    _notifyChanged();
  }

  static String formatRate(double bytesPerSec) {
    if (bytesPerSec >= 1024 * 1024) return "${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s";
    if (bytesPerSec >= 1024) return "${(bytesPerSec / 1024).toStringAsFixed(0)} KB/s";
    return "${bytesPerSec.toStringAsFixed(0)} B/s";
  }

  // ---------------------------------------------------------------------------
  // Process enumeration (Toolhelp32 snapshot — one cheap kernel call, no
  // per-process OpenProcess like EnumProcesses-based paths need)
  // ---------------------------------------------------------------------------

  /// Returns the lowercase exe names of all running processes.
  static Set<String> listRunningProcesses() {
    final Set<String> names = <String>{};
    final int snapshot = _createToolhelp32Snapshot(_th32csSnapProcess, 0);
    if (snapshot == INVALID_HANDLE_VALUE || snapshot == 0) return names;

    final Pointer<_PROCESSENTRY32W> entry = calloc<_PROCESSENTRY32W>();
    try {
      entry.ref.dwSize = sizeOf<_PROCESSENTRY32W>();
      if (_process32FirstW(snapshot, entry) != 0) {
        do {
          final String name = _readExeName(entry.ref);
          if (name.isNotEmpty) names.add(name.toLowerCase());
        } while (_process32NextW(snapshot, entry) != 0);
      }
    } finally {
      free(entry);
      CloseHandle(snapshot);
    }
    return names;
  }

  static String _readExeName(_PROCESSENTRY32W entry) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 260; i++) {
      final int char = entry.szExeFile[i];
      if (char == 0) break;
      buffer.writeCharCode(char);
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Network throughput (iphlpapi GetIfTable byte counters, summed over all
  // non-loopback interfaces; rate is the delta between two samples)
  // ---------------------------------------------------------------------------

  static ({int octets, DateTime at})? _prevOctets;

  /// Total in+out throughput in bytes/second since the previous sample, or -1
  /// while a baseline sample is still being collected.
  static double _sampleNetworkRate() {
    final int? total = _readTotalOctets();
    if (total == null) return -1;
    final DateTime now = DateTime.now();
    final ({int octets, DateTime at})? prev = _prevOctets;
    _prevOctets = (octets: total, at: now);
    if (prev == null) return -1;
    final double seconds = now.difference(prev.at).inMilliseconds / 1000.0;
    if (seconds <= 0) return -1;
    final int delta = total - prev.octets;
    // 32-bit interface counters wrap; skip the sample instead of reporting a
    // bogus negative spike.
    if (delta < 0) return -1;
    return delta / seconds;
  }

  static int? _readTotalOctets() {
    final Pointer<Uint32> sizePtr = calloc<Uint32>();
    Pointer<Uint8> buffer = nullptr;
    try {
      int result = _getIfTable(nullptr, sizePtr, 0);
      if (result != _errorInsufficientBuffer && result != NO_ERROR) return null;
      if (sizePtr.value == 0) return null;
      buffer = calloc<Uint8>(sizePtr.value);
      result = _getIfTable(buffer, sizePtr, 0);
      if (result != NO_ERROR) return null;

      final int numEntries = buffer.cast<Uint32>().value;
      // MIB_IFTABLE: DWORD dwNumEntries; MIB_IFROW table[] — rows start at
      // offset 4 (MIB_IFROW is 4-byte aligned).
      final Pointer<_MibIfRow> rows = Pointer<_MibIfRow>.fromAddress(buffer.address + 4);
      int total = 0;
      for (int i = 0; i < numEntries; i++) {
        final _MibIfRow row = (rows + i).ref;
        if (row.dwType == _ifTypeSoftwareLoopback) continue;
        total += row.dwInOctets + row.dwOutOctets;
      }
      return total;
    } catch (_) {
      return null;
    } finally {
      if (buffer != nullptr) free(buffer);
      free(sizePtr);
    }
  }
}

enum AwakeAutomationAction {
  notify,
  sleep,
  hibernate,
  shutdown,
  lock;

  String get label {
    switch (this) {
      case AwakeAutomationAction.notify:
        return "Notify";
      case AwakeAutomationAction.sleep:
        return "Sleep";
      case AwakeAutomationAction.hibernate:
        return "Hibernate";
      case AwakeAutomationAction.shutdown:
        return "Shut Down";
      case AwakeAutomationAction.lock:
        return "Lock";
    }
  }
}

class ProcessAwakeRule {
  ProcessAwakeRule(this.exe);
  final String exe;
  bool isRunning = false;
}

class NetworkAwakeRule {
  NetworkAwakeRule(this.thresholdBytesPerSec);
  final int thresholdBytesPerSec;
}

class ProcessAutomation {
  ProcessAutomation(this.exe, this.action) : seenRunning = false;
  final String exe;
  final AwakeAutomationAction action;
  bool seenRunning;
}

class NetworkAutomation {
  NetworkAutomation(this.thresholdBytesPerSec, this.action);
  final int thresholdBytesPerSec;
  final AwakeAutomationAction action;
  bool armed = false;
  int idleTicks = 0;
}

// -----------------------------------------------------------------------------
// FFI bindings not covered by package:win32
// -----------------------------------------------------------------------------

// Win32 constants not exposed by package:win32 (original names:
// TH32CS_SNAPPROCESS, ERROR_INSUFFICIENT_BUFFER, IF_TYPE_SOFTWARE_LOOPBACK).
const int _th32csSnapProcess = 0x00000002;
const int _errorInsufficientBuffer = 122;
const int _ifTypeSoftwareLoopback = 24;

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final DynamicLibrary _iphlpapi = DynamicLibrary.open('iphlpapi.dll');

final int Function(int flags, int processId) _createToolhelp32Snapshot = _kernel32.lookupFunction<
    IntPtr Function(Uint32 dwFlags, Uint32 th32ProcessID),
    int Function(int flags, int processId)>('CreateToolhelp32Snapshot');

final int Function(int snapshot, Pointer<_PROCESSENTRY32W> entry) _process32FirstW = _kernel32.lookupFunction<
    Int32 Function(IntPtr hSnapshot, Pointer<_PROCESSENTRY32W> lppe),
    int Function(int snapshot, Pointer<_PROCESSENTRY32W> entry)>('Process32FirstW');

final int Function(int snapshot, Pointer<_PROCESSENTRY32W> entry) _process32NextW = _kernel32.lookupFunction<
    Int32 Function(IntPtr hSnapshot, Pointer<_PROCESSENTRY32W> lppe),
    int Function(int snapshot, Pointer<_PROCESSENTRY32W> entry)>('Process32NextW');

final int Function(Pointer<Uint8> table, Pointer<Uint32> size, int order) _getIfTable = _iphlpapi.lookupFunction<
    Uint32 Function(Pointer<Uint8> pIfTable, Pointer<Uint32> pdwSize, Int32 bOrder),
    int Function(Pointer<Uint8> table, Pointer<Uint32> size, int order)>('GetIfTable');

final class _PROCESSENTRY32W extends Struct {
  @Uint32()
  external int dwSize;
  @Uint32()
  external int cntUsage;
  @Uint32()
  external int th32ProcessID;
  @IntPtr()
  external int th32DefaultHeapID;
  @Uint32()
  external int th32ModuleID;
  @Uint32()
  external int cntThreads;
  @Uint32()
  external int th32ParentProcessID;
  @Int32()
  external int pcPriClassBase;
  @Uint32()
  external int dwFlags;
  @Array<Uint16>(260)
  external Array<Uint16> szExeFile;
}

// Matches the Win32 MIB_IFROW layout (iphlpapi).
final class _MibIfRow extends Struct {
  @Array<Uint16>(256)
  external Array<Uint16> wszName;
  @Uint32()
  external int dwIndex;
  @Uint32()
  external int dwType;
  @Uint32()
  external int dwMtu;
  @Uint32()
  external int dwSpeed;
  @Uint32()
  external int dwPhysAddrLen;
  @Array<Uint8>(8)
  external Array<Uint8> bPhysAddr;
  @Uint32()
  external int dwAdminStatus;
  @Uint32()
  external int dwOperStatus;
  @Uint32()
  external int dwLastChange;
  @Uint32()
  external int dwInOctets;
  @Uint32()
  external int dwInUcastPkts;
  @Uint32()
  external int dwInNUcastPkts;
  @Uint32()
  external int dwInDiscards;
  @Uint32()
  external int dwInErrors;
  @Uint32()
  external int dwInUnknownProtos;
  @Uint32()
  external int dwOutOctets;
  @Uint32()
  external int dwOutUcastPkts;
  @Uint32()
  external int dwOutNUcastPkts;
  @Uint32()
  external int dwOutDiscards;
  @Uint32()
  external int dwOutErrors;
  @Uint32()
  external int dwOutQLen;
  @Uint32()
  external int dwDescrLen;
  @Array<Uint8>(256)
  external Array<Uint8> bDescr;
}
