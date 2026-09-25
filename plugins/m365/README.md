# Microsoft 365 Agenda for Tabame

Type `m365` to see upcoming events from your primary Outlook calendar and your
latest inbox messages. Type `m365 <words>` to filter the next 30 days of events
and search mail across your mailbox. Press Enter on an online meeting to join
it; Enter on other events or messages opens them in Outlook. Ctrl+K offers
preview, link, copy, refresh, account settings, and sign-out actions.

This plugin uses Node.js 18 or newer, Microsoft Graph, and Tabame's built-in
storage. It has no npm dependencies. Calendar and mail access is read-only.

## One-time Microsoft setup

Microsoft requires an app registration so the plugin can request delegated
access to your account. The **Application (client) ID** is public; you do not
need or use a client secret.

1. Open [Microsoft Entra app registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) and create a new registration. Select the supported account types you need. Choose **Accounts in any organizational directory and personal Microsoft accounts** if you want either account type.
2. Copy the **Application (client) ID** from the registration's Overview page.
3. Under **Authentication → Advanced settings**, set **Allow public client flows** to **Yes**. Device-code sign-in does not need a redirect URI.
4. Under **API permissions → Add a permission → Microsoft Graph → Delegated permissions**, add `Calendars.Read` and `Mail.Read`. Some organizations require an administrator to approve these permissions.
5. Install the plugin, reopen Tabame's Launcher, type `m365`, and enter the client ID. Leave **Tenant** as `common` for work or personal accounts, or enter your organization tenant ID.
6. Choose **Sign in with Microsoft**. Tabame opens Microsoft's sign-in page and displays a short code. Enter the code in the browser and approve the permissions. Reopen `m365` after sign-in if the Launcher closed while the browser was open.

The plugin also asks Microsoft for `offline_access` so it can renew access
without another sign-in. Tabame stores the refresh and access tokens in its
secret storage (Windows Credential Manager on Windows). The client ID and tenant
are stored in the plugin's ordinary settings store. No tokens go into a
`config.json` file or the repository.

## Install

Copy this folder to:

```text
%LOCALAPPDATA%\Tabame\plugins\m365\
```

Reopen the Launcher after installing or changing the plugin so Tabame rescans
the folder. The plugin is also listed in Tabame's plugin gallery.

## Scope

- The initial agenda shows up to 20 events from the primary calendar in the next 30 days and eight recent inbox messages.
- Search filters those upcoming events and asks Microsoft Graph to search mail. Mail searches cover the signed-in user's mailbox, including folders beyond the inbox.
- Meeting joins use the event's online meeting URL. Other rows open the Outlook web link returned by Microsoft Graph.
- The plugin does not create, modify, send, or delete calendar events or mail.

The implementation follows Microsoft's documentation for [device-code sign-in](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-device-code), [calendar views](https://learn.microsoft.com/en-us/graph/api/user-list-calendarview?view=graph-rest-1.0), and [mail search](https://learn.microsoft.com/en-us/graph/search-query-parameter). Work or school account policies may block device-code sign-in or require administrator consent.
