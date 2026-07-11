# GitHub — Tabame launcher plugin

Search and manage GitHub without leaving the launcher: pull requests, issues,
repositories, branches, Actions workflow runs, notifications, discussions,
projects, profile stats, and repo/directory downloads.

Type **`gh`** in the launcher to open the command list.

## Setup

1. Create a Personal Access Token at <https://github.com/settings/tokens>.
   - **Classic token** scopes: `repo`, `workflow`, `notifications`,
     `read:project`, `read:org`.
   - **Fine-grained tokens** work too, with equivalent repository/account
     permissions (Contents, Issues, Pull requests, Actions, Notifications,
     Projects read).
2. Type `gh` in the launcher — the first run shows a token form. Paste the
   token and press Enter. It is validated against the API and stored in
   `config.json` next to `main.js`.

Alternatively, copy `config.example.json` to `config.json` and paste the token
there, or set the `GITHUB_TOKEN` / `GH_TOKEN` environment variable.

## Commands

| Command | What it does |
|---|---|
| My Pull Requests | PRs you created, were asked to review, or that mention you (sectioned) |
| Search Pull Requests | Global PR search — supports GitHub qualifiers (`repo:`, `org:`, `label:`…) |
| Create Pull Request | Pick a repo → form with head/base branch dropdowns, draft checkbox |
| My Issues | Issues assigned to you, created by you, or mentioning you |
| Search Issues | Global issue search |
| Create Issue | Pick a repo → form with title, body, labels, assign-to-me |
| My Latest Repositories | Your repos (incl. orgs & private) by latest push |
| My Starred Repositories | Repos you starred |
| Search Repositories | Filter your public & private repos by name |
| Create Branch | Pick a repo → name + source-branch form |
| Download Repository | Pick a repo → download the ZIP, browse folders, download a single directory or file (with progress) |
| Workflow Runs | Pick a repo → inspect, re-run, re-run failed jobs, or cancel Actions runs |
| Notifications | Your inbox — open, mark one/all as read |
| Unread Notifications | Only the unread ones; a live unread badge also shows on the root list |
| Search Discussions / My Discussions | GraphQL-backed discussion search |
| My Projects | Your Projects (v2) — needs `read:project` on classic tokens |
| My GitHub Stats | Followers, stars received, PRs/issues/commits + a contribution sparkline |

Raycast's macOS *menu bar* commands are adapted to the launcher: the unread
notification count appears as a badge on the root command list, and profile
stats live in **My GitHub Stats**.

## Tips

- **Enter** opens the highlighted thing in the browser; **Ctrl+K** shows more
  actions (copy URL, copy clone URL, re-run workflow, mark read…).
- **Tab** on a repository autocompletes its `owner/repo` into the query.
- **Escape** walks back up (list → repo picker → command list) before exiting.
- In any repo picker you can type any `owner/repo` you have access to, even if
  it is not in your own list.
- Downloads go to your `Downloads` folder by default; change it via
  **Set Personal Access Token** (it also holds the download-folder setting).
