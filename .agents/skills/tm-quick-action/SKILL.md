---
name: tm-quick-action
description: Build or revise Tabame quick menu top-bar buttons in `lib/widgets/itzy/quickmenu/button_*.dart`. Use when adding a new quick menu button, redesigning an existing button panel, or aligning a panel with the established Tabame "Instrument Panel" design language (high-density, technical, pro-audio/aviation-grade aesthetic).
---

# Top Bar Quick Menu

Build new Tabame quick menu buttons by matching the existing launcher-to-modal structure and the "Instrument Panel" design language used across bookmarks, apps, vault, currency converter, and timezone.

Use these files as the baseline references:

- `lib/widgets/itzy/quickmenu/button_bookmarks.dart`
- `lib/widgets/itzy/quickmenu/button_apps.dart`
- `lib/widgets/itzy/quickmenu/button_vault.dart`
- `lib/widgets/itzy/quickmenu/button_currency_converter.dart`
- `lib/widgets/itzy/quickmenu/button_timezone.dart`
- `lib/widgets/widgets/panel_header.dart`, `lib/widgets/widgets/quick_actions_item.dart`, `lib/models/util/quickmenu_modal.dart`

## 1. Design Philosophy

- **High Performance**: Interfaces should feel like professional tools (DAWs, IDEs, flight panels) — fast, utilitarian, desktop-oriented.
- **Information Density**: Maximize data visibility in small spaces without causing cognitive overload.
- **Tactile Feedback**: Every interaction (hover, drag, tap) must have immediate, precise visual feedback.
- **Distilled Aesthetics**: Ruthlessly remove generic "AI slop" or standard Material/Cupertino defaults. Avoid glossy/high-glow effects or saturated solid blocks. Use custom shapes, subtle outlines, and alpha-blended color to keep a technical, matte tone.

## 2. Core Pattern

Start with a small launcher widget that only opens the panel:

```dart
class ExampleButton extends StatelessWidget {
  const ExampleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Example",
      icon: const Icon(Icons.extension_rounded),
      onTap: () => showQuickMenuModal(
        context: context,
        child: const ExamplePanel(),
      ),
    );
  }
}
```

Follow this split:

- Keep the top-bar button thin. It should declare the label, icon, and modal entry point only.
- Put state, async work, controllers, and layout logic inside the panel widget.
- Prefer `StatelessWidget` for the launcher unless the button itself owns transient state.
- Use `showQuickMenuModal()` for most buttons. Pass `maxWidth` or `heightFactor` only when the interaction clearly needs it, like timezone.

## 3. Global Registration

Every new quick menu button **must** be registered in `lib/models/util/quick_action_list.dart`:

```dart
// 1. Add import at the top (alphabetical)
import '../../widgets/itzy/quickmenu/button_example.dart';

// 2. Add an entry to quickActionsMap — key is the button's identifier,
//    widget is a factory (not a const instance directly)
final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  ...
  "ExampleButton": QuickAction(
    icon: Icons.extension_rounded,
    widget: () => const ExampleButton(),
  ),
};
```

`QuickAction.name` is optional and rarely set — the map key is what drives discovery/pinning in settings and the top/bottom bars (see `lib/widgets/quickmenu/top_bar.dart`, `lib/widgets/quickmenu/bottom_bar.dart`, `lib/widgets/interface/quickmenu/quickactions_settings.dart`).

## 4. Panel Structure

Build the panel as a vertical layout with a strong header and one flexible content area:

```dart
class ExamplePanel extends StatefulWidget {
  const ExamplePanel({super.key});

  @override
  State<ExamplePanel> createState() => _ExamplePanelState();
}

class _ExamplePanelState extends State<ExamplePanel> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.start,
      children: <Widget>[
        const PanelHeader(
          title: "Example",
          icon: Icons.extension_rounded,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }
}
```

`PanelHeader` (`lib/widgets/widgets/panel_header.dart`) takes `title`, `icon`, and optionally `accent` (defaults to `Design.accent`), `buttonPressed` + `buttonIcon` (+ `buttonTooltip`) for a single trailing action, and `extraActions` for more. It also handles window-drag behavior — always put it first in the column, never recreate its drag/border chrome manually.

Prefer this hierarchy:

- `PanelHeader` first.
- `Flexible` body second.
- `WindowsScrollView`, `ListView`, or `MouseScrollWidget` inside the body depending on content density — never `SingleChildScrollView`.
- `Material(type: MaterialType.transparency)` around interactive body content when Ink reactions need a Material ancestor.

## 5. Design Tokens

Reference `Design` (`lib/models/settings.dart`) directly inside widget bodies — do not thread `accent`/`onSurface`-style colors through function parameters; that indirection is unnecessary now that `Design` is globally available.

- **Accent**: `Design.accent` — drives all interactive/selected state.
- **Text**: `Design.text` — replaces `Theme.of(context).colorScheme.onSurface`.
- **Base font size**: `Design.baseFontSize` — replaces hardcoded sizes; add an offset like `Design.baseFontSize + 2.5` for emphasis.
- **Border radius**: `Design.borderRadius` for theme-driven rounding when a fixed radius isn't called for.

### Typography

- **Body**: `Design.baseFontSize` to `Design.baseFontSize + 2` (≈11.5–13px).
- **Metadata/small labels**: `Design.baseFontSize - 1` to `Design.baseFontSize + 0.5` (≈9–11px).
- **Headings**: `Design.baseFontSize + 2.5` and up.
- **Letter spacing**: `0.3` to `0.7` for technical/uppercase labels.
- **Weights**: `FontWeight.w400` for content, `w600`/`w700` for labels, counts, and headings — never `w900`.

### Spacing & Rhythm

- **Panel padding**: `EdgeInsets.fromLTRB(8, 8, 8, 10)` for the main list/body.
- **Card spacing**: `SizedBox(height: 8)` between vertical cards.
- **Card inner padding**: `EdgeInsets.fromLTRB(10, 9, 10, 8)`.
- **Section spacing**: `SizedBox(height: 2)` between a header and its description; `SizedBox(height: 8-10)` before interactive controls (sliders, chips).
- **Outer padding**: `10px` (compact) to `14px` (comfortable).
- **Standard "bar" item heights**: `25px` or `30px`. Sliders are `20px` high.
- **Rounded corners**: usually `8`, `10`, `12`, `14`, `16`, or `18`.

### Colors

- Never use pure black/white. Use `withAlpha` to layer on the theme surface.
- Cards/rows background: `Design.text.withAlpha(7-8)`.
- Card/row border: `Design.text.withAlpha(16)`.
- Soft accent washes for cards/pills: `Design.accent.withAlpha(10)` to `Design.accent.withAlpha(28)`.
- Low-contrast separators: `Design.text.withAlpha(18)` to `Design.text.withAlpha(32)`.
- Hover (active): `Design.accent.withAlpha(60)`. Hover/selection (passive): `Design.accent.withAlpha(10-18)`.
- Selected/emphasized borders: `Design.accent.withAlpha(70-90)`.

## 6. Key Components & Patterns

### Section Labels

Divide content within a panel with labels instead of standard headers — pattern is icon + label + optional count pill + divider:

```dart
Widget _buildSectionLabel({required String label, required int count, required IconData icon}) {
  return Row(
    children: <Widget>[
      Icon(icon, size: 14, color: Design.accent),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: Design.baseFontSize + 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: Design.text,
        ),
      ),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
        child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
    ],
  );
}
```

### Configuration Cards

A vertical container grouping related settings (used for sidebars, modals, and narrow config panels like the QuickMenu Design panel):

```dart
Container(
  padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
  decoration: BoxDecoration(
    color: Design.text.withAlpha(7),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: Design.text.withAlpha(16)),
  ),
  child: Column(
    crossAxisAlignment: C.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(child: Column(...)), // Title & description
          _buildMetaChip(...),          // Value badge
        ],
      ),
      const SizedBox(height: 8),
      Slider(...), // Interactive control
    ],
  ),
)
```

Highlighted/active card state: background `Design.accent.withAlpha(10)`, border `Design.accent.withAlpha(30)`.

### Meta Chips

Compact badges for showing values (hex codes, percentages, toggles):

- **Shape**: `StadiumBorder` / `BorderRadius.circular(999)`.
- **Padding**: `EdgeInsets.symmetric(horizontal: 7, vertical: 3)`.
- **Visuals**: low-alpha colored background with high-alpha colored text, `fontWeight: FontWeight.w700`.

### Selection Rails (ChoiceChip)

Used for mode switching within a card:

- `ChoiceChip` with `visualDensity: VisualDensity.compact`.
- `labelStyle`: `fontSize: Design.baseFontSize + 1.5`.
- Selected color: `Design.accent.withAlpha(18)`.

### Color Swatches/Pickers

- Use a small swatch (20-22px circle) to show active colors.
- Use `InkWell` text labels (e.g. "Pick") instead of heavy buttons for secondary actions.

### Sticky Bottom Action Bar

Major actions like "Save Changes" or "Add Item" anchor at the bottom while content scrolls independently above:

```dart
Widget _buildFixedBottomBar({required String label, required VoidCallback onTap}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Design.text.withAlpha(15))),
    ),
    child: Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 32),
          decoration: BoxDecoration(
            color: Design.accent.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Design.accent.withAlpha(80), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: Design.baseFontSize + 1.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Design.accent,
            ),
          ),
        ),
      ),
    ),
  );
}
```

Avoid "screaming" solid backgrounds, heavy shadows, or glossy gradients — use a subtle accent fill with a more defined accent border instead, and precise single-pixel borders elsewhere.

Use these reference-specific patterns for inspiration:

- `button_bookmarks.dart`: compact hover rows, light accent bar, grouped sections, restrained text.
- `button_apps.dart`: collapsible category sections, grid-or-list body, simple empty state, low-noise chrome.
- `button_vault.dart`: stateful multi-step panel flow, header actions that change with mode, inline error strip.
- `button_currency_converter.dart`: prominent result card, input-first layout, data cards with light borders, loading states.
- `button_timezone.dart`: dual-mode panel with planner/settings toggle, chips, search field, structured result cards.

## 7. Interaction Rules

Design the panel for quick execution, not deep navigation:

- Make the first useful action obvious near the top.
- Keep primary flows inside one modal when possible.
- Prefer inline state transitions over opening nested dialogs unless destructive confirmation is required.
- Close the quick menu after launching an external app, file, or command.
- Do not hide critical actions behind hover-only affordances if the action is essential.
- Use hover feedback on desktop rows and cards — subtle hover tint plus an optional accent bar or trailing icon.
- For list items that should not be traversed with arrows/tabs, wrap them with `CancelTraversal(child:)`.

For button actions:

- Launch apps and files with `WinUtils.open(...)`.
- Close the quick menu after external execution with `QuickMenuFunctions.hideQuickMenu()` when that matches existing behavior.
- Persist settings with `Boxes.updateSettings(...)` and mirror to in-memory state.

### The "Volume Drag" (linear value gestures)

Standard pattern for linear values dragged vertically:

- `onVerticalDragStart`: reset the accumulator.
- `onVerticalDragUpdate`: accumulate `delta.dy`. Trigger every `10-15px` of movement.
- **Visuals**: show a feedback icon (e.g. `volume_up`/`volume_down`) temporarily.

### Multi-Tap

- **Left tap**: primary action (play/toggle).
- **Right tap**: secondary action (next/alternative).
- **Middle click (tertiary)**: destructive or "previous" action.

## 8. State And Async Guidance

Keep expensive work out of build methods unless it is trivial and synchronous.

Prefer:

- Load data in `initState()` when the panel opens.
- Store transient UI mode in the panel state object.
- Use request tokens or freshness checks for overlapping async work, like the currency converter.
- Dispose every controller, focus node, and scroll controller you create.
- Cache reusable results when the panel reads large or repeated datasets.
- Use placeholder, loading, and empty states deliberately. Every complex panel in the references has at least one.

Avoid:

- Heavy decode, scanning, or network work directly inside `build()`.
- Rewriting controller text from `build()`.
- Opening a modal from inside a top-bar button and then embedding another unnecessary modal flow immediately after.

## 9. Layout Selection

Choose the body layout based on the job:

- Use grouped list rows for quick launch collections like bookmarks.
- Use collapsible sections for categories with many entries like apps.
- Use forms with inline validation for creation or secure-entry flows like vault.
- Use a hero result card plus detail sections for utility tools like currency converter.
- Use a two-mode or tab-like layout when the feature has a main workflow and a configuration workflow, like timezone.
- Use configuration cards + meta chips + selection rails (section 6) for settings-style or sidebar-style content.

If the panel risks becoming long or multi-purpose:

- Keep one primary mode visible by default.
- Move setup and management into a secondary mode or settings toggle.
- Keep the header title and action icon synced with the current mode.

## 10. Empty, Error, And Loading States

Always design all three when the panel depends on data:

- **Empty state**: centered icon, one short heading or sentence, one short guidance line at most.
- **Error state**: inline strip or compact message, not a full-screen takeover unless the whole panel is blocked.
- **Loading state**: spinner or progress indicator near the active section, not a large blocking overlay unless required.

Keep message tone direct and practical. Existing panels use short operational text, not marketing copy.

## 11. Build Checklist

Before finishing a new quick menu button:

1. Confirm the launcher is a small `QuickActionItem`.
2. Confirm the modal opens through `showQuickMenuModal()`.
3. Confirm the panel starts with `PanelHeader`.
4. Confirm colors are read from `Design.accent` / `Design.text` directly, not threaded through parameters.
5. Confirm long content scrolls inside a `Flexible` body using `WindowsScrollView`/`ListView`/`MouseScrollWidget`.
6. Confirm controllers and async listeners are disposed.
7. Confirm settings are persisted through `Boxes.updateSettings(...)` when needed.
8. Confirm empty, loading, and error states exist where relevant.
9. Confirm the panel closes the quick menu after external execution if that matches the feature type.
10. Confirm the result still feels like a desktop utility tool — dense, technical, instrument-panel — not a generic mobile card stack.
11. Confirm the button is added to `quickActionsMap` in `lib/models/util/quick_action_list.dart` (import + map entry with `widget: () => const ExampleButton()`).

## 12. Practical Defaults

If the user asks for a new top-bar quick menu button and does not specify a style:

- Use a `QuickActionItem` launcher.
- Use `PanelHeader` with one optional trailing action button.
- Use a `Column` with one `Flexible` body.
- Use compact spacing and accent-tinted surfaces per the tokens in section 5.
- Use hover-driven list rows or configuration cards (section 6) rather than large decorative components.
- Preserve the existing Tabame quick menu tone: fast, utilitarian, polished, dense, and "instrument panel" precise.
