# Trakt plugin

Search movies & shows on [Trakt.tv](https://trakt.tv), browse trending/popular,
and — after a one-time login — manage your **watchlist**, **watched history**,
and see your upcoming **calendar**, all from the Tabame launcher.

- **Keyword:** `trakt`
- **Runtime:** Node 18+ (or Bun) — plain JS, no dependencies.

## Setup

1. **Create a Trakt API app.** Sign in at Trakt, open
   [trakt.tv/oauth/applications](https://trakt.tv/oauth/applications) → **New
   Application**. Set the **Redirect URI** to:

   ```
   urn:ietf:wg:oauth:2.0:oob
   ```

   Save it, then copy the **Client ID** and **Client Secret**.

2. **Enter the credentials in Tabame.** Open the launcher, type `trakt`, and
   fill in the setup form. The Client Secret is stored in Windows Credential
   Manager rather than a plaintext configuration file. The form includes
   **Copy URL** and **Copy URI** buttons for creating the Trakt application.

   - **Client ID** — required for search & browsing.
   - **Client Secret** — required for logging in (watchlist / history / calendar).
   - **TMDB v3 API Key** — optional. A free [TMDB](https://www.themoviedb.org/settings/api)
     key adds real poster thumbnails; without it, results use icons.

3. **Install:** drop this folder into `%localappdata%\Tabame\plugins\trakt\`,
   then re-open the launcher (it rescans on every open) and type `trakt`.

## Logging in

Run **Log in to Trakt** from the command list. The plugin uses Trakt's OAuth
**device flow**: it shows a short code, opens `trakt.tv/activate` in your
browser, you enter the code and approve — the plugin polls in the background and
signs you in automatically. Your password is never seen by the plugin.

Credentials entered in the form are stored by Tabame. Existing environment
variables and `config.json` files are still read as a backwards-compatible
migration path. Tokens are stored in `tokens.json` and refreshed automatically;
**Log out** deletes them.

## Usage

Type `trakt` for the command list, or `trakt <title>` — the top command is
**Search Movies & Shows**, so typing a title searches right away.

- **Enter** on a result opens it on Trakt.
- **Ctrl+K** on a result: Open on Trakt / IMDb, Copy Title, and (when logged in)
  Add to / Remove from Watchlist, Mark as Watched.
- The right-hand **preview pane** shows the poster, overview, rating, genres,
  runtime and links for the highlighted title.
- **Escape** steps back one screen (and exits at the command list).

## Development

Set `"dev": true` in `plugin.json` for hot-reload + an on-screen debug console
while you iterate. Set it back to `false` before sharing.
