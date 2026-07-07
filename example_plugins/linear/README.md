# Linear plugin for the Tabame launcher

Create, search and manage Linear issues, projects, documents and notifications
straight from the launcher.

## Install

1. Copy this folder to `%localappdata%\Tabame\plugins\linear\`.
2. Create `config.json` next to `main.js` (copy `config.example.json`):

   ```json
   { "apiKey": "lin_api_xxx", "defaultTeamKey": "ENG" }
   ```

   - **apiKey** — a *Personal API key* from **Linear → Settings → API**.
   - **defaultTeamKey** — optional; the team new issues/projects are created in
     (defaults to your first team). Use the team's short key, e.g. `ENG`.
3. Make sure `node` (Node 18+) is on your PATH. To use Bun instead, set
   `"runtime": "bun"` in `plugin.json`.
4. Open the launcher and type the keyword **`lin`**.

## Usage

Typing `lin ` shows the command list. Pick one to drill in; the text after the
keyword becomes that command's search/input. Keys:

- **Enter** — run the highlighted item's default action (open / create / drill in).
- **Ctrl+K** — per-item action menu (open, copy URL, copy branch, assign to me,
  mark as done, …).
- **Esc** — leave the plugin. Select **◀ Back to commands** to return to the root.

### Commands

| Command | What it does |
|---|---|
| Create Issue / Create Issue for Myself | Type a title, Enter creates it in your default team (self-assigns for the second) |
| Search Issues | Full-text search across all projects |
| My Issues / Created Issues | Issues assigned to / created by you (type to filter) |
| Active Cycle | Issues in each team's active cycle |
| Search Projects / Custom Views / Documents | Browse and open in Linear |
| Create Project | Type a name, Enter creates it in your default team |
| Notifications / Unread Notifications | Read your latest notifications |
| Quick Add Comment to Issue | Type `ENG-123 your comment body`, Enter posts it |
| Favorites | Open your Linear favorites |

Clipboard and "open in browser" are handled by the plugin itself (via `clip` and
`start`), so they work without any extra launcher support.

## Notes

- All Linear access uses the GraphQL API at `https://api.linear.app/graphql`.
- No npm dependencies — plain JS using the runtime's global `fetch`.
- Errors (bad key, network, GraphQL) render as an in-launcher message and are not
  fatal to the process.
