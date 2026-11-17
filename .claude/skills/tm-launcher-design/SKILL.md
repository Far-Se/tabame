---
name: tm-launcher-design
description: "Create or revise Tabame's Flutter launcher designs: frames, search bars, result rows, palettes, typography, and action dialogs. Use when adding a LauncherDesign or restyling the launcher, with a compact integration guide instead of reading every existing design. Does not cover launcher script plugins or quick-menu button panels."
---

# Tabame Launcher Design

Build a complete launcher appearance while retaining the shared search, selection, execution, preview, and plugin behavior. The user can choose any visual direction; existing designs establish integration contracts, not one mandatory aesthetic.

## Read only what the task needs

1. Read the repository's `AGENTS.md` and inspect the working tree before editing.
2. Use the registration map below to inspect the specific declarations and switch cases being changed. Use `rg -n` and bounded reads; avoid dumping `launcher.dart`, the token catalog, or every design.
3. For a new design, use [starter.md](references/starter.md) if a frame/search/row example would help. It captures the shared contracts without copying a large existing design.
4. Read [material-effects.md](references/material-effects.md) only for shaders, animated surfaces, or elaborate painted materials.
5. If an example is still needed, open one relevant source: `classic_launcher_design.dart` for a simple frame/search, `strata_launcher_design.dart` for a results panel/footer, or `satin_result_row.dart` for a compact row. Resolve their directories from the map. Some older examples hardcode colors or geometry; follow the current shared helpers below.

All paths are relative to the project root. In the table, `L/` means `lib/pages/launcher/`. Use a snake_case file slug, a lowerCamelCase enum value, and PascalCase classes, for example `paper_signal`, `paperSignal`, and `PaperSignalLauncherFrame`.

## Register a new design

For a revision, change only the relevant parts of this map. For a new design, account for every row; default branches can silently leave parts of the UI in the wrong style.

| File | Integration |
| --- | --- |
| `lib/models/design_settings.dart` | **Append** to `LauncherDesign`; never reorder existing entries, because preferences store `design.index`. Give multiword names an explicit `displayName`. Add a `LauncherDesignThemeSet` to `DesignSettings.createDefaultLauncherDesignThemes()`, keyed by that display name, with light and dark `defaultThemeColors(...)` presets. Include intended fonts, weights, radius, and base size. Existing display names are saved theme-map keys; renaming needs a migration. |
| `L/launcher_design.dart` | Put shared `<Name>Tokens` here when the design needs them across frame, rows, and dialogs. Use getters for live palette values and wrap custom type styles in `launcherTextStyle(...)`. Add `LauncherThemeData.is<Name>` only if something actually consumes it. |
| `L/launcher_design_config.dart` | Add a `LauncherDesignConfig.forDesign` case: search icon/size/font/hint, frame/control radii, list padding, and relevant flags (`usesDesignFont`, `outlinedControls`). This is a part of `launcher_design.dart`. |
| `L/launcher_palette.dart` | Add a `LauncherPalette.resolve` case. Supply `surface`, `onSurface`, `accent`, and `dim`, optionally `highlightColor`, `primary`, `modalSurface`, or `modalAccent`. This part of `launcher_design.dart` is the shared palette for the launcher and dialogs. |
| `L/launcher_designs/<slug>_launcher_design.dart` | Start with `part of '../launcher_design_builder.dart';`. Define `_slugOuterDecoration(...)`, `_<Name>SearchBar`, and public `<Name>LauncherFrame`. Add imports to the owning library, not this part. Keep private visual helpers here. |
| `L/launcher_design_builder.dart` | Add the `part` directive and cases in both `LauncherDesignBuilder.outerDecoration` and `buildSearchBar`. The outer decoration is also used by action dialogs. |
| `L/state/launcher_layout_mixin.dart` | Add the frame in `_buildLauncherFrame`, normally `<Name>LauncherFrame(child: buildBody())`; pass `resultCount` only if used. Preserve shared content and the resize overlay. Change `buildBody` only if the new geometry requires it. |
| `L/result/designs/<slug>_result_row.dart` and `L/result/result_row.dart` | Start the new file with `part of '../result_row.dart';`; implement a private extension on `LauncherResultRow`. Add its `part` directive and renderer case in `LauncherResultRow.build`. Reuse an existing renderer only when its appearance actually fits. |
| `L/widgets/launcher_section_header.dart` | Add the design's case in `_LauncherSectionHeader.build`. Use the supplied label and resolved accent; this header is also called from dialogs. An intentionally omitted header must still have an explicit case. |
| `L/state/launcher_theme_mixin.dart` | Set the design's text theme in `_buildDesignTheme` when it has a specific font. Keep `palette.applyTo(...)` and the existing user font override flow. |
| `L/launcher_modal_theme.dart` | Match dialog typography in `LauncherModalTokens.text`. Inspect `LauncherModalFrame` and its surface/header/footer styling; add only the treatments the design needs. A new enum case can compile while falling back to unrelated modal styling. |

The picker in `lib/widgets/itzy/quickmenu/button_menu_design.dart` and design search in `L/state/search_mixin.dart` enumerate `LauncherDesign.values`; they normally need no extra per-design registration. Persistence is already handled by `lib/models/classes/boxes/boxes_base.dart` and `lib/models/settings.dart`.

Ordinary designs need no new search logic in `lib/pages/launcher.dart`. If special preview chrome is required, use `L/widgets/launcher_file_preview_panel.dart` and `L/widgets/launcher_window_preview_panel.dart`; their shared behavior and default palette support should remain reusable. Shared material widgets belong in `L/widgets/`, shaders in `resources/shaders/`, and registered visual assets in `resources/` with the appropriate `pubspec.yaml` entry.

## Keep the shared widget contracts

### Search and frame

`_LauncherSearchBarContent` supplies `dragHandle`, `textField`, nullable `trailingBadge`, and `isSearching`. Present all four appropriately. Prefer `Expanded(child: _LauncherSearchField(content))` for the field plus its badge overlay. If laying out the badge yourself, retain the original `content.textField` and handle a null badge. Preserve the supplied drag handle, or an equivalent real drag region.

The search controller, focus, keyboard shortcuts, query callbacks, and results belong to the shared launcher. Do not create a replacement `TextField`, controller, result list, or execution path inside a design. Frames decorate the supplied `child`; they do not duplicate it. Keep result scrolling, plugin views, preview resizing, and height resizing reachable. For a footer use a bounded flexible body, and hide or wrap low-priority hints at narrow widths.

### Result rows

Use the existing `LauncherResultRow` fields and helpers:

- Wrap the row in `_interactive(...)`; it supplies tap, selected semantics, cursor, and hover selection **only when the pointer moves**. An `onEnter` selection handler makes keyboard navigation jump under a stationary mouse.
- Render the supplied `icon` and optional `badge`. Prefer `content` when non-null; it is a real custom widget, not a string to discard or reconstruct.
- Otherwise render `_titleText(style)` and `_subtitleText(style)`. They retain plugin inline markup, ellipsis, and `subtitleMaxLines`.
- Use `isSelected` for the selection treatment. Keep feedback immediate; if adding transitions, respect `isRepeating` so held arrow keys do not queue animations.
- Reserve space for selection glyphs to avoid shifting titles. Let rows grow for wrapping subtitles and larger text; prefer minimum height over a fixed height.
- Leave `onTap`/`onHover`, ranking, launch behavior, and action construction in the shared code.

## Make the visual system coherent

- Choose a clear material, typography, and selection treatment, then carry them through frame, search, headers, rows, previews, and dialogs. The launcher is a frequently used desktop search tool: keep the query and useful results prominent, with compact secondary labels and chrome.
- Put default colors in the design presets. For an ordinary customizable design, derive tokens from `user.launcherThemeColors.background`, `.text`, and `.accent`; derive panels, borders, dim text, and selection washes from them. In widgets use the resolved `Theme` or `LauncherTheme.accentOf(context)`. Avoid scattering unrelated fixed colors or quick-menu palette reads through the implementation.
- Derive contrast from the **resolved surface brightness**, which can differ from the app's brightness after user customization. Fixed art palettes in some existing designs are deliberate exceptions, not a default to copy. Use light/dark presets unless the requested art direction calls for a fixed palette.
- Use `launcherTextStyle(...)` for explicitly constructed design text styles, and retain `launcherTextTheme(...)` integration. Apply the same type voice in `LauncherModalTokens.text`: dialogs may live outside `LauncherTheme`, so use its fallback palette resolver rather than requiring `LauncherTheme.of(context)` there.
- Use `LauncherSurface(decoration: boxDecoration, child: ...)` for the outer frame. Use `.withLauncherCorners()` on rectangular `BoxDecoration`s and `LauncherClip` when descendants need clipping. Keep `outerDecoration` returning `BoxDecoration`; consumers apply the shared corner policy. Hardcoded `ClipRRect` or a separate frame border can bypass the user's round/squircle/bevel and radius settings.
- Prefer content that can shrink, wrap, or ellipsize at the configured launcher width. A footer or decorative heading must not crowd search, force an oversized minimum window, or steal space from the preview.
- Keep selection and text readable on the actual surface, including user palettes. Do not delay input or selection for animation. Decorative layers should not capture pointer events or add misleading semantics; use `IgnorePointer`/`ExcludeSemantics` where appropriate.
- Show actual result counts and existing commands. Verify any shortcut text against `L/state/keyboard_navigation_mixin.dart`; do not invent decorative controls, statuses, or keyboard hints that promise unavailable behavior.
- Follow local Dart conventions: explicit variable/collection types, relative imports, const constructors where possible, and the shared corner/font helpers. A visual design usually needs no new dependency or native API.

## Review and validate

Before running the one allowed analysis pass, review the integration map and search targeted branches for the new enum and any copied design name. Confirm all exhaustive switches are covered and default branches are intentional. Review these acceptance cases against the implementation; use an already available preview only when permitted:

- Empty query, loading, no matches, and many results; long titles and wrapping subtitles.
- Mouse movement versus keyboard selection, held arrows, Enter, actions, and dragging/resizing.
- Custom row content, badges, plugin markup and plugin views; file/window previews and dialogs.
- Light/dark and edited palettes, custom fonts and corner shapes, narrow windows and larger text.
- Reduced motion, hidden/inactive windows, and material fallback if effects are present.

Follow the current `AGENTS.md`. After changing Dart, from the project root use `dart` resolved from PATH, one command at a time:

```text
dart format <only Dart files changed in this task>
dart analyze <only Dart files changed in this task>
```

Run format once and analyze once. Do not use absolute Dart paths, `.bat` launchers, PATH changes, Dart MCP formatting, full-project analysis, `flutter build`, or `flutter run`. Do not run tests as part of this design workflow; consult `AGENTS.md` if its narrow existing `_test.dart` exception is relevant. On failure report the exact command, failure, and output as-is; report any later fixes without claiming an unperformed rerun. Do not build just to obtain a visual preview.

Finish with the design name, integration completed, actual checks and results, and any unverified runtime appearance or shader behavior. Static analysis does not establish visual quality or compile GLSL.
