# TV Shows Tracker (Tabame plugin)

Track TV shows via TMDB: browse a calendar of the current season's episodes,
see when it starts/ends and when the next episode airs, and view episode
ratings as an inline sparkline graph.

## Setup

1. Get a free TMDB API key (v3 auth): https://www.themoviedb.org/settings/api
2. Copy this whole folder to:
   `%localappdata%\Tabame\plugins\tv-shows-tracker\`
3. In that folder, create `config.json`:
   ```json
   { "tmdb_api_key": "YOUR_TMDB_V3_API_KEY" }
   ```
4. Open the Tabame launcher and type `shows`.

Tabame will auto-install the `requests` package into `.pluginlibs` the first
time it runs.

## Usage

- `shows` — lists your tracked shows. Type to filter locally.
- **Ctrl+K → "Add show from TMDB"** (or **Ctrl+N**) — search TMDB by name and
  add a show. Adding fetches the show's *current* season (the one that's
  airing, or the most recently aired one if the show is between seasons or
  ended).
- **Enter** on a tracked show — opens a season view:
  - **📊 Season overview** row (selected by default) — the preview pane shows
    season start/end dates, next air date, status, and a sparkline of episode
    ratings for the season.
  - Each episode below shows its air date, whether it's aired or upcoming,
    and its rating; select one to see its overview in the preview pane.
- **Ctrl+K** on a show or in the season view — Refresh from TMDB, Remove
  show, or Open on TMDB.

## Notes

- Tracked show data (season, episodes, ratings) is cached locally in
  `data.json` in this folder so the list loads instantly; use **Refresh**
  to pull the latest air dates/ratings from TMDB.
- "Current season" is determined from TMDB's `next_episode_to_air` /
  `last_episode_to_air` fields.
