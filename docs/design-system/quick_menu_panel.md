# Quick Menu Panel

`QuickMenuPanel` lives in `lib/widgets/widgets/quick_menu_panel.dart`.

Use it for top-bar quick-menu popups that follow the standard Tabame pattern:

- `PanelHeader` at the top
- one flexible body region below it
- optional header actions
- optional body scrolling or mouse-wheel support

## When To Use It

Use `QuickMenuPanel` when the popup is structurally a standard quick-menu tool and the unique work happens inside the body content.

Good fits:

- bookmark and launcher panels
- utility tools with one main surface
- settings/planner popups that share the standard header chrome

Avoid it when:

- the popup needs a custom container shell or border treatment
- the header is stateful in a way that does not map to `PanelHeader`
- the layout is multi-stage enough that the shell itself becomes feature-specific

## Supported Options

- `title`, `accent`, `boldFont`, `icon`: standard header inputs
- `buttonPressed`, `buttonIcon`, `buttonTooltip`: primary header action
- `secondaryButtonPressed`, `secondaryButtonIcon`, `secondaryButtonTooltip`: secondary header action
- `body`: panel content
- `bodyPadding`: shared padding around the body
- `scrollable`: wraps the body in `SingleChildScrollView`
- `useMouseScroll`: wraps the body in `MouseScrollWidget`
- `materialBody`: provides a transparent `Material` ancestor for ink interactions

## Migration Rule

Extract only the repeated shell. Keep feature-specific layout, state, and interaction logic inside the panel body widgets.
