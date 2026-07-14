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

2. **Create `config.json`** next to `main.js` (copy `config.example.json`):

   ```json
   {
     "clientId": "your_trakt_client_id",
     "clientSecret": "your_trakt_client_secret",
     "tmdbApiKey": ""
   }
   ```

   - `clientId` — required for search & browsing.
   - `clientSecret` — required for logging in (watchlist / history / calendar).
   - `tmdbApiKey` — **optional**. A free [TMDB](https://www.themoviedb.org/settings/api)
     v3 API key. With it, results show real **poster thumbnails** in a grid;
     without it, they fall back to icons. Trakt itself serves no images.

3. **Install:** drop this folder into `%localappdata%\Tabame\plugins\trakt\`,
   then re-open the launcher (it rescans on every open) and type `trakt`.

## Logging in

Run **Log in to Trakt** from the command list. The plugin uses Trakt's OAuth
**device flow**: it shows a short code, opens `trakt.tv/activate` in your
browser, you enter the code and approve — the plugin polls in the background and
signs you in automatically. Your password is never seen by the plugin.

Tokens are stored in `tokens.json` in this folder and refreshed automatically.
**Log out** deletes them. Don't commit `tokens.json` or `config.json`.

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
