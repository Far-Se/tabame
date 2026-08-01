# RSS & Read Later

`rss` is a dependency-free RSS/Atom reader for the Tabame launcher. It is
designed as a small personal reading dashboard rather than a single-feed
search command.

## What it includes

- **New Articles** — unread stories from every enabled feed, with source, age,
  category, tags, and a split preview pane.
- **Read Later** — save stories, add private notes, edit tags/categories, and
  keep saved articles safe from cache pruning.
- **Nested categories** — create categories and subcategories such as
  `Technology / Frontend / CSS`; feeds and articles can be assigned at any
  level.
- **Feed management** — add, edit, enable/disable, refresh, copy, and remove
  RSS/Atom subscriptions.
- **Manual articles** — add a URL from a newsletter, chat, or another source
  even when it does not have an RSS feed.
- **OPML import/export** — import subscriptions from another reader; OPML
  folders become categories. Export both subscriptions and a JSON backup of
  the library.
- **Background refresh** — refresh one feed or all feeds without blocking the
  launcher. Failed feeds stay visible with their last error.
- **Article detail view** — read the feed-provided summary/content in Tabame or
  open the original article in the browser.

## Usage

Type `rss` in the launcher. The root dashboard shows New Articles, Read Later,
categories, feeds, and management shortcuts. Type after the keyword to search
across article titles, summaries, notes, tags, feed names, and categories.

On an article:

- **Enter** — open the original article; optionally mark it read.
- **Ctrl+K → Read summary here** — open a full-width detail view.
- **Ctrl+K → Mark as read/unread** — change its unread state.
- **Ctrl+K → Save for Read Later** — preserve it in the reading queue.
- **Ctrl+K → Edit article** — change category, tags, notes, and saved state.

On a feed or category, **Enter** opens its article list. Ctrl+K provides
refresh, edit, copy, and delete actions where appropriate. Destructive feed,
category, and article actions are confirmation-gated.

## Adding feeds and categories

The add-feed form accepts RSS, RSS 2, RDF-style RSS, and Atom URLs. A custom
display name is optional; leaving it blank uses the feed's published title.
The category dropdown supports the complete nested category path. The
`Save & Refresh` button fetches the feed immediately.

Categories have a parent dropdown, color, and description. Deleting a category
moves its feeds and articles to the parent (or Uncategorized). Uncategorized
cannot be deleted.

## Storage and privacy

The library is stored through Tabame's per-plugin storage under the key
`rss-read-later-state`. Feed URLs, article summaries, notes, and tags stay on
the machine. The plugin does not send data to a third-party service; it only
requests the feed URLs you add.

The export form writes a timestamped JSON backup and OPML file to a folder you
choose. Exporting cached articles includes their summaries, notes, categories,
and Read Later state.
