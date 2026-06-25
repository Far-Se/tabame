# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Tabame is a Windows-only Flutter desktop app that replaces the taskbar with a "QuickMenu" — a hotkey-summoned popup with audio/media controls, pinned apps, a window switcher, an app launcher, bookmarks, timers, clipboard history, color picker, screenshot tools, and many other small utilities. It's a single Win32 desktop app built with `window_manager` for frameless/transparent windows and a custom `tabamewin32` Flutter plugin for native Win32 interop (global hooks, media session, hotkeys).

## Commands

- Run/debug: run `flutter run -d windows`.
- Build release: `flutter build windows`.
- Lint: `flutter analyze` (uses `analysis_options.yaml`, based on `package:lints/recommended.yaml` with `always_specify_types`, `prefer_relative_imports`, and const-preferring rules enabled).
- Tests: `flutter test` (all), `flutter test test/launcher_core_test.dart` (single file).
- The `tabamewin32` directory is a separate local Flutter plugin package (path dependency in `pubspec.yaml`) containing the native Win32 glue — edit it like a normal Flutter plugin (Dart in `tabamewin32/lib`, C++ in `tabamewin32/windows`).

## Architecture

### Startup flow

`lib/main.dart` parses CLI arguments first — Tabame relaunches itself as a separate process for several auxiliary windows (`-spotlight`, `-editor`, `-screenCapture`, `-screenRecording`, `-screenDraw`, `-colorPicker`, `-msgbox`, `-run`), each its own minimal entry point in `lib/pages/`. If none match, it goes through `AppStartup` (`lib/logic/app_startup.dart`): admin-relaunch check → register services/hooks → `window_manager` setup (frameless, transparent, always-on-top for QuickMenu; normal window for the Interface/settings page) → `runApp(Tabame)`.

### Multi-window-via-single-exe pattern

There isn't a router with multiple windows in one process — each "extra" surface (spotlight search, photo editor, screen capture/draw/recording, color picker, message boxes, run-status) is a _new process launch_ of the same exe with a flag, handled at the top of `main()`. When adding a new standalone overlay/tool, follow this pattern rather than trying to open a second Flutter window in-process.

### Core domains (under `lib/`)

- `models/globals.dart` — global mutable app state (`Globals` static class: window sizes, current page/QuickMenu sub-page, focused window rect, etc.) and shared enums (`Pages`, `QuickMenuPage`).
- `models/settings.dart` / `models/classes/save_settings.dart` / `models/classes/boxes.dart` — user settings persistence ("Boxes" is the settings/config object model, loaded at startup before window setup decides QuickMenu vs Interface size).
- `models/win32/` — direct Win32 API wrappers (window handles, hooks) built on top of `package:win32` and the `tabamewin32` plugin.
- `models/db/` — SQLite-backed stores (`file_index_db.dart` for the file/app search index, `music_library_db.dart` for the local music library).
- `pages/launcher/` — the app launcher feature, organized as its own mini-architecture: `core/` (query parsing, result model, executor, search state), `search/` (per-source search handlers — windows, desktop, bookmarks — behind a common `search_handler.dart` interface), `result/` (result row widgets per result type), `services/` (app catalog, action execution). Launcher queries support prefix sigils to scope the search mode (e.g. `.` = windows only, `>`/`?` = files only, `'`/`b` = bookmarks, `;` = desktop, `n` = Notion, `$`/bare word = function/timer commands) — see `launcher_query.dart` and `test/launcher_core_test.dart` for the exact grammar.
- `widgets/itzy/quickmenu/` — the QuickMenu's individual feature buttons, one file per button (`button_*.dart`). This is the place to look for/add a QuickMenu feature; each button is largely self-contained (UI + the action it triggers).
- `widgets/itzy/interface/`, `pages/interface.dart` — the "Interface" window (settings/sidebar app), separate from the QuickMenu popup.
- `pages/quickmenu_designs/` — alternate QuickMenu visual layouts/themes.
- `services/` — longer-running background services (file indexer, music indexer/artwork cache, wallpaper service) consumed by the DB layer and UI.
- `logic/error_handler.dart` — central error logger (`ErrorLogger`); both `FlutterError.onError` and `PlatformDispatcher.instance.onError` are wired to it in release mode, plus a `runZonedGuarded` catch-all in `main()`. Use this rather than ad-hoc logging for anything that should land in `errors.log` under `%localappdata%/Tabame`.

### Conventions

- Use `WindowsScrollView` (`lib/widgets/widgets/windows_scroll.dart`) instead of `SingleChildScrollView` everywhere, for a consistent native-feeling scroll experience.
- UI follows the "Instrument Panel" design language described in `.impeccable.md`: high density, minimal padding, sharp low-opacity borders, subtle gradients only on key CTAs (not glows), `FontWeight.w600`/`w700` for UI text (never `w900`).
- Imports are relative (`prefer_relative_imports` lint).
- `.dartx` files (e.g. `lib/services/file_indexer.dartx`, `lib/pages/launcher.dartx`) are intentionally-excluded/old code kept for reference; they are not compiled.

