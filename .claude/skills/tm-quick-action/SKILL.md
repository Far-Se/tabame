---
name: tm-quick-action
description: Build or revise Tabame quick menu top-bar buttons in `lib/widgets/itzy/quickmenu/button_*.dart`. Use when adding a new quick menu button, redesigning an existing button panel, or aligning a panel with the established Tabame top-bar modal patterns, interaction style, and visual language.
---

# Top Bar Quick Menu

Build new Tabame quick menu buttons by matching the existing launcher-to-modal structure and the established panel styling used in bookmarks, apps, vault, currency converter, and timezone.

Use these files as the baseline references:

- `lib/widgets/itzy/quickmenu/button_bookmarks.dart`
- `lib/widgets/itzy/quickmenu/button_apps.dart`
- `lib/widgets/itzy/quickmenu/button_vault.dart`
- `lib/widgets/itzy/quickmenu/button_currency_converter.dart`
- `lib/widgets/itzy/quickmenu/button_timezone.dart`

## Core Pattern

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

## Global Registration

Every new quick menu button **must** be registered in two global files to enable hotkey mapping and action discovery:

### 1. Register for Hotkeys

Add your unique page key (e.g., `"Example"`) to the `quickMenuPages` list in `lib/models/classes/hotkeys.dart`:

```dart
static const List<String> quickMenuPages = <String>[
  ...
  "Example", // Add here
];
```

### 2. Register for Action Map

Import your launcher button and add an entry to the `quickActionsMap` in `lib/models/util/quick_action_list.dart`:

```dart
// 1. Add import at the top
import '../../widgets/itzy/quickmenu/button_example.dart';

// 2. Add to quickActionsMap
final Map<String, QuickAction> quickActionsMap = <String, QuickAction>{
  ...
  "ExampleButton": QuickAction(
    name: "ExampleButton",
    icon: Icons.extension_rounded,
    widget: const ExampleButton(),
  ),
};
```

## Panel Structure

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
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: "Example",
          accent: userSettings.themeColors.accentColor,
          boldFont: true,
          icon: Icons.extension_rounded,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: _buildBody(onSurface),
          ),
        ),
      ],
    );
  }
}
```

Prefer this hierarchy:

- `PanelHeader` first.
- `Flexible` body second.
- `SingleChildScrollView`, `ListView`, or `MouseScrollWidget` inside the body depending on content density.
- `Material(type: MaterialType.transparency)` around interactive body content when Ink reactions need a Material ancestor.

## Design Language

Match the existing quick menu visual language:

- Read accent from `userSettings.themeColors.accentColor`.
- Read text color from `Theme.of(context).colorScheme.onSurface`.
- Use rounded corners, usually `8`, `10`, `12`, `14`, `16`, or `18`.
- Use soft accent washes such as `accent.withAlpha(10)` to `accent.withAlpha(28)` for cards and pills.
- Use low-contrast separators such as `onSurface.withAlpha(18)` to `onSurface.withAlpha(32)`.
- Prefer compact typography: `10` to `13` for supporting text, `13` to `16` for headings.
- Keep the panel visually dense but not cramped. Existing panels feel quick, utility-first, and desktop-oriented.

Use these reference-specific patterns:

- `button_bookmarks.dart`: compact hover rows, light accent bar, grouped sections, restrained text.
- `button_apps.dart`: collapsible category sections, grid-or-list body, simple empty state, low-noise chrome.
- `button_vault.dart`: stateful multi-step panel flow, header actions that change with mode, inline error strip.
- `button_currency_converter.dart`: prominent result card, input-first layout, data cards with light borders, loading states.
- `button_timezone.dart`: dual-mode panel with planner/settings toggle, chips, search field, structured result cards.

## Interaction Rules

Design the panel for quick execution, not deep navigation:

- Make the first useful action obvious near the top.
- Keep primary flows inside one modal when possible.
- Prefer inline state transitions over opening nested dialogs unless destructive confirmation is required.
- Close the quick menu after launching an external app, file, or command.
- Do not hide critical actions behind hover-only affordances if the action is essential.
- Use hover feedback on desktop rows and cards. Existing buttons rely on subtle hover tint plus optional accent bar or trailing icon.
- For list items, wrap items that do not need to be traversed with arrows/tabs with CancelTraversal(child:).
  For button actions:
- Launch apps and files with `WinUtils.open(...)`.
- Close the quick menu after external execution with `QuickMenuFunctions.hideQuickMenu()` when that matches existing behavior.
- Persist settings with `Boxes.updateSettings(...)` and mirror to in-memory state.

## State And Async Guidance

Keep expensive work out of build methods unless it is trivial and synchronous.

Prefer these patterns:

- Load data in `initState()` when the panel opens.
- Store transient UI mode in the panel state object.
- Use request tokens or freshness checks for overlapping async work, like the currency converter.
- Dispose every controller, focus node, and scroll controller you create.
- Cache reusable results when the panel reads large or repeated datasets.
- Use placeholder, loading, and empty states deliberately. Every complex panel in the references has at least one.

Avoid these patterns:

- Heavy decode, scanning, or network work directly inside `build()`.
- Rewriting controller text from `build()`.
- Opening a modal from inside a top-bar button and then embedding another unnecessary modal flow immediately after.

## Layout Selection

Choose the body layout based on the job:

- Use grouped list rows for quick launch collections like bookmarks.
- Use collapsible sections for categories with many entries like apps.
- Use forms with inline validation for creation or secure-entry flows like vault.
- Use a hero result card plus detail sections for utility tools like currency converter.
- Use a two-mode or tab-like layout when the feature has a main workflow and a configuration workflow, like timezone.

If the panel risks becoming long or multi-purpose:

- Keep one primary mode visible by default.
- Move setup and management into a secondary mode or settings toggle.
- Keep the header title and action icon synced with the current mode.

## Empty, Error, And Loading States

Always design all three when the panel depends on data.

Follow these conventions:

- Empty state: centered icon, one short heading or sentence, one short guidance line at most.
- Error state: inline strip or compact message, not a full-screen takeover unless the whole panel is blocked.
- Loading state: spinner or progress indicator near the active section, not a large blocking overlay unless required.

Keep message tone direct and practical. Existing panels use short operational text, not marketing copy.

## Build Checklist

Before finishing a new quick menu button:

1. Confirm the launcher is a small `QuickActionItem`.
2. Confirm the modal opens through `showQuickMenuModal()`.
3. Confirm the panel starts with `PanelHeader`.
4. Confirm accent, text colors, and hover states match the existing quick menu style.
5. Confirm long content scrolls inside a `Flexible` body.
6. Confirm controllers and async listeners are disposed.
7. Confirm settings are persisted through `Boxes.updateSettings(...)` when needed.
8. Confirm empty, loading, and error states exist where relevant.
9. Confirm the panel closes the quick menu after external execution if that matches the feature type.
10. Confirm the result still feels like a desktop utility tool, not a generic mobile card stack.
11. Confirm the page key is added to `quickMenuPages` in `lib/models/classes/hotkeys.dart`.
12. Confirm the button is added to `quickActionsMap` in `lib/models/util/quick_action_list.dart`.

## Practical Defaults

If the user asks for a new top-bar quick menu button and does not specify a style:

- Use a `QuickActionItem` launcher.
- Use `PanelHeader` with one optional action button.
- Use a `Column` with one `Flexible` body.
- Use compact spacing and accent-tinted surfaces.
- Use hover-driven list rows or simple cards rather than large decorative components.
- Preserve the existing Tabame quick menu tone: fast, utilitarian, polished, and dense.
