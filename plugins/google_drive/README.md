# Google Drive plugin for Tabame

Search your Google Drive from the launcher. Type `gdrive` followed by a
filename. Enter opens a file in your browser or browses into a folder;
Escape (or the **⬆ Up** row) goes back out. Ctrl+K also offers **Open in
Browser**, **Copy Link**, and (for files) **Download**.

## 1. Create a Google OAuth client (one-time, ~2 minutes)

Google requires every app to have its own OAuth client — there's no shared
key this plugin can ship with.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/), create
   a project (or pick an existing one).
2. **APIs & Services → Library** → enable the **Google Drive API**.
3. **APIs & Services → OAuth consent screen** → set it up as **External**,
   add your own Google account as a **test user** (this keeps it private —
   no Google review needed for personal use).
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
   → Application type **Desktop app** → Create.
5. Click **Download JSON** on the client you just created.

## 2. Install the plugin

1. Copy this folder to:
   `%localappdata%\Tabame\plugins\gdrive\`
2. Rename the file you downloaded in step 5 to `client_secret.json` and
   drop it into that folder, replacing the placeholder — no manual editing
   needed, it's already in the right format.
3. Open the Tabame launcher and type `gdrive` — on first use it shows
   **Connect Google Drive**. Press Enter; a browser tab opens for you to
   sign in and approve access. Close the tab once it says you're signed in.

That's it — the plugin stores a refresh token (via Tabame's secret storage,
in Windows Credential Manager) so you won't need to sign in again.

## Notes

- Search matches on file **name** only (Drive's full-text search is a
  larger change — ask if you want it added).
- Scope is `drive.readonly` — the plugin can see and open your files but
  can't modify or delete anything.
- To disconnect, delete the plugin's stored credential in Windows
  Credential Manager (look for an entry under Tabame/gdrive), or ask to add
  a "Sign out" item to the plugin.
