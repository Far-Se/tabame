# Google Calendar plugin for Tabame

This plugin turns the launcher into a real Google Calendar client. Type `cal`
for the month view, switch to **Agenda** in the calendar header, search the
visible date range, and use Ctrl+K to create or manage events.

## One-time Google setup

Google requires each user to provide a personal OAuth client; no shared secret
is shipped with the plugin.

1. Open the [Google Cloud Console](https://console.cloud.google.com/).
2. Create or select a project.
3. Under **APIs & Services → Library**, enable **Google Calendar API**.
4. Configure **Google Auth platform**. For a private External testing app, add
   your own Google account under **Audience → Test users**.
5. Under **Google Auth platform → Clients**, create an OAuth client with
   application type **Desktop app**.
6. Download its JSON file, rename it to `client_secret.json`, and place it next
   to `main.py` in this plugin folder.
7. Reopen the Tabame launcher, type `cal`, and choose **Connect**.

The refresh token is stored through Tabame's secret storage in Windows
Credential Manager. It is not written to the plugin folder.

## Everyday use

- `cal` — month view for the current date.
- Use the header arrows, **Today**, **Month**, and **Agenda** controls to browse.
- Type after `cal` to filter events in the visible date range.
- `cal agenda` — open the 30-day agenda directly.
- Ctrl+K → **New event** — create a detailed event with guests and notes.
- Ctrl+K → **Quick add** — use Google's natural-language event parser.
- Enter on an event — inspect its details without leaving the launcher.
- Ctrl+K on an event — view details, join its meeting, edit, copy, or delete it.

The plugin shows the primary calendar plus every calendar marked as selected in
Google Calendar. Event and calendar writes use the full Calendar scope; deleting
an event or changing its guest list can send Google invitation updates.

## Install location

Copy this folder to:

```text
%localappdata%\Tabame\plugins\gcal\
```

Reopen the launcher after installing or changing the plugin so Tabame rescans it.
