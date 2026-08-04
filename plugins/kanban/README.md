# Kanban Workspace

A local, dependency-free Kanban workspace built for Tabame's launcher plugin
protocol. Type `kanban` to open it.

## Highlights

- Draggable Kanban cards with per-column WIP limits.
- Stable pages, native back history, and clickable breadcrumbs.
- Rich create/edit forms for boards and cards.
- Fast board filters such as `priority:high`, `assignee:alex`, `tag:bug`,
  `column:review`, and `due:overdue`.
- Paginated board, activity, and archive views.
- Card details, quick moves, priorities, duplication, archive/restore, and
  confirmed deletion through Ctrl+K actions.
- Per-plugin persistence through Tabame storage, with JSON clipboard
  import/export for backup and portability.

## Getting around

- `Enter` opens the highlighted board or card.
- Drag a card to move or reorder it.
- `Ctrl+K` opens contextual actions.
- `Ctrl+N` creates a board on the board index and a card inside a board.
- `Escape`, the back button, or a breadcrumb returns to the previous page.
- Scroll near the end of a long list to load the next page.

The first run creates a starter board that doubles as a compact walkthrough.
All data stays local in Tabame's `.tabame-store.json` for this plugin.

## Install

Copy this folder to:

```text
%localappdata%\Tabame\plugins\kanban\
```

Reopen the launcher, then type `kanban`. Python 3 must be available on `PATH`.
