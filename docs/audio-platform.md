# Audio feature portability

This document records the Phase 7 migration boundary for Tabame's audio family:
system devices, mute/volume, optional per-process mixing, and media sessions.
It intentionally does not define Wayland policy.

## Shared contract

Shared widgets and orchestration use `lib/platform/audio_system_service.dart`:

- `AudioSystemService` exposes neutral input/output devices, normalized volume,
  explicit mute state, default-device selection, and optional process streams.
- `MediaSessionService` exposes neutral now-playing metadata and transport
  commands.
- Device, process, session, and application identifiers are opaque adapter-owned
  strings. Shared code never parses an `HWND`, `CGWindowID`, X11 ID, or another
  native handle.
- `AudioOrchestrator` owns endpoint snapshots, volume normalization, device
  volume maps, and mute toggling. Adapters only translate contract operations to
  native or user-session APIs.

The capability registry reports:

- `audioDeviceControl`: default devices, volume, and mute are available.
- `perProcessAudio`: exact process/stream volume control is available.
- `mediaSessions`: now-playing discovery and transport are available.

The audio and media UI disables itself with the adapter's reason when the
corresponding capability is unavailable. It does not probe a Windows method
channel from a widget.

## Windows adapter

`lib/platform/windows/windows_audio_service.dart` keeps the existing
`tabamewin32` implementation behind two injectable adapter boundaries:

- WASAPI endpoint enumeration, Windows role targeting, mute/volume, device
  volume, and per-process mixer control remain available.
- Windows SMTC metadata, artwork bytes, and transport commands remain available.
- Existing Windows system audio and volume-mixer settings entry points remain
  adapter-owned.
- Configured application media bindings are interpreted by the Windows adapter;
  custom Windows key sequences stay out of shared widgets.

Windows role flags (`console`, `multimedia`, and `communications`) are retained
for compatibility with existing settings. They are not part of the neutral
Linux semantics.

## Linux target backend

The selected target implementation is a Dart-only Linux user-session adapter in
`lib/platform/linux/linux_audio_service.dart`:

- `pactl info` and the PulseAudio-compatible `pactl` commands are preferred.
  This covers traditional PulseAudio and common `pipewire-pulse` sessions.
- `wpctl` is used as a fallback when `pactl` is not available.
- `playerctl` provides optional MPRIS media discovery and transport.
- Commands are passed as argument arrays with shell execution disabled. The
  adapter does not inspect X11/Wayland state and does not add display-server
  policy.
- Linux has one default endpoint per direction in this contract. Windows role
  flags are intentionally ignored when selecting a Linux default.
- Device IDs are refreshed from the current user session and are not persisted.
- An empty `playerctl --list-all` result is a successful “no players” state.
  Missing `playerctl` disables only media sessions, not system audio control.

The Linux adapter is intentionally deferred-safe: missing commands, a stopped
user audio service, and failed session commands produce unavailable/empty
results rather than preventing the launcher shell from starting.

## Intentional differences and deferred capabilities

- Linux per-process audio and peak metering are deferred. PulseAudio stream
  control and PipeWire PID control do not provide the same stable identity and
  peak-meter semantics as Windows session APIs, so the mixer panel is hidden
  when `perProcessAudio` is false.
- Linux MPRIS has multiple players and no guaranteed system-wide “current” SMTC
  session. Tabame treats the first player returned by `playerctl` as current for
  display and targets commands to one player; it never broadcasts normal
  transport commands to all players.
- Linux MPRIS artwork is an optional URI and is not downloaded by the adapter.
  Windows artwork bytes remain supported.
- Windows application-specific key sequences have no Linux equivalent. Linux
  configured application controls target a matching MPRIS player instead.
- macOS device control, per-process audio, and media sessions remain an
  explicit unavailable capability in this migration. They are not silently
  emulated by Windows APIs.
- The existing screen-recording capture-device path remains part of the
  recording family and is not changed by this audio migration.

## Regression coverage

`test/audio_platform_test.dart` covers:

- normalized shared endpoint orchestration and mute toggling;
- Windows adapter delegation through an injectable backend;
- Linux provider selection, device/default parsing, safe argument construction,
  volume/mute operations, default-device cycling, and `playerctl` session
  mapping;
- missing Linux commands as an explicit deferred capability.
