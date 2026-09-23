# Launcher material effects

Read only when the design calls for shaders, animated materials, or substantial custom painting. Ordinary frames and rows can stay in Flutter decorations and static painters.

## Choose the smallest relevant reference

Paths below are relative to `lib/pages/launcher/` unless they start with `resources/`.

| Need | Existing reference and what to reuse |
| --- | --- |
| Finite pointer response that settles at idle | `widgets/satin_surface.dart`: one surface controller, paint notifications, high-contrast fallback, focus/lifecycle handling. Integration is in `launcher_designs/satin_launcher_design.dart`. |
| One clock shared by several surfaces | `widgets/liquid_metal_surface.dart`: `LiquidMetalMotion`, cached programs by asset, per-surface shaders, and generation checks when assets change. Optical Glass also uses this infrastructure. |
| Interaction-driven marks that decay | `widgets/capillary_surface.dart`: motion scope and paper/ink surfaces. Inspect only if the design needs this kind of state. |
| Lightweight repeating decoration inside the builder library | `widgets/launcher_animation.dart`: `_syncRepeatingAnimation` handles reduced motion and ticker mode. It does **not** replace window focus and application lifecycle handling for a material widget. |

## Rendering and ownership

- Put reusable material widgets in `lib/pages/launcher/widgets/<slug>_surface.dart`. Unlike design part files, these can be ordinary libraries with their own imports. Import them in the builder and other consumers that need them.
- Put fragment programs in `resources/shaders/<slug>.frag` and register each under `flutter: shaders:` in `pubspec.yaml`. Declare ordinary images under assets instead. Read the matching existing Dart painter and shader together when adapting their uniform contract.
- Document and match float-uniform order/count and any sampler indexes. Do not claim a procedural highlight or caustic shader refracts desktop pixels when it never samples them.
- Cache `FragmentProgram` loading, create a shader instance per independently painted surface, and dispose those instances. Start asynchronous loading outside `build`; check `mounted` and reject stale completions if the asset can change. Failed loading must leave usable themed content with a static fallback.
- Drive animation through `CustomPainter(repaint: ...)` or a small paint-only listener. Isolate stable text/results with `RepaintBoundary`; do not rebuild the launcher or list on every tick. `shouldRepaint` must account for changes to palette and other paint inputs.
- Keep shader detail away from reading areas. Prefer one frame material with quieter row/preview surfaces; apply a shader to every row only when needed and bounded. Keep decorative overlays out of hit testing and semantics.
- Use `LauncherSurface`/`LauncherClip` and the current corner policy for widget geometry. If a shader draws its own outline, ensure it agrees with the clip when the user changes radius or corner shape; a fixed rounded-distance field does not automatically support bevels or squircles.

## Motion and readability

- Input, keyboard selection, and execution remain immediate. Prefer finite, interaction-driven motion unless ambient motion is part of the requested design.
- Honor `MediaQuery.disableAnimationsOf(context)` and `TickerMode.valuesOf(context).enabled`. Reduced motion should retain a readable static surface and visible selection without pointer trails or moving highlights.
- Stop activity on window blur/minimization and inactive app lifecycle; resume only when all relevant conditions allow it. Existing material widgets use `WindowListener` and `WidgetsBindingObserver`. Remove listeners and dispose controllers/notifiers on teardown.
- Use high-contrast handling when the material affects legibility, following Satin's flat surface and stronger selection outline. Avoid making readable text depend on a particular shader frame.
- A clock shared by multiple surfaces belongs above them. Dialog routes outside that scope need their own bounded clock or a static fallback, not an accidental permanent loop per control.

## Integration and evidence

Keep launcher, modal, and preview palettes aligned. `LauncherModalFrame` may need a material wrapper and a transparent inner surface so its normal fill does not cover the effect. File/window previews can retain a solid reading surface; add special wrappers only where the requested material requires them. Arbitrary plugin widgets still need usable contrast and input.

Follow the main skill's validation limits. Dart analysis does not compile GLSL, show pixels, measure frame rate, or verify input hit testing. Report these as unverified unless there is actual permitted runtime evidence. A visual-only design normally needs no C++ changes; if native APIs are required, follow `AGENTS.md`'s Windows implementation and `//TODO: Implement multiplatform` rule.
