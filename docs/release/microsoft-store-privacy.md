# Tabame — Personal Information - Privacy Policy

Last updated: October 10, 2026

This policy explains how Tabame, published by Far Se, accesses, stores, uses, and shares personal information. It applies to the Tabame desktop application, including the version distributed through the Microsoft Store.

## Our approach

Tabame is a desktop productivity application. Its core features work without a Tabame account, and their data is stored on your device. Tabame does not automatically send your clipboard history, activity history, files, or screen recordings to the developer. It does not include a developer-operated analytics or automatic crash-reporting service, sell personal information, or use your local content to build advertising profiles.

Some features contact external services. When you use or enable those features, information needed for them is sent to the relevant service as described below. The application can also download online resources, such as fonts and plugin listings, during normal use.

## Information accessed and used on your device

Depending on your settings and the features you use, Tabame may process:

| Information | Purpose |
| --- | --- |
| Preferences, shortcuts, hotkeys, snippets, bookmarks, and launcher history | Save your configuration and provide launcher and automation features. |
| Installed applications, running processes, window titles, file and folder paths, file metadata, and selected file contents | Find and launch items, manage windows, index folders, and perform file or media operations. |
| Clipboard text, formatted content, images, and copied file references | Provide clipboard history, pinned items, snippets, and clipboard actions. Copied content can contain personal or sensitive information. |
| Application usage, window titles, timestamps, and idle periods | Provide local Trktivity activity reports when tracking is enabled, according to your title and filter settings. |
| Screen images, recordings, captured text, and selected audio inputs | Provide screenshots, OCR, recording, and replay features. Rewindly maintains a local rolling recording buffer while enabled. |
| Keyboard and mouse events | Recognize hotkeys, gestures, snippet triggers, and other input features, including displaying keypresses when that feature is used. |
| Media libraries, playlists, artwork, notes, saved credentials, and authenticator entries | Provide the corresponding tools and integrations you configure. |
| Browser tab titles, URLs, and page data | Support browser features and plugin actions when the optional browser connector is enabled and paired. |
| Diagnostic messages and local logs | Record errors and help troubleshoot the application. Logs may contain paths, feature details, or information included in an error. |

These features use information to perform their stated functions. Local storage does not mean that every item is encrypted or inaccessible to other software running under your Windows account.

## Information sent to external services

External services receive the information included in a request and ordinary connection information, such as your IP address. Requests may occur automatically while an enabled feature is active. Examples include:

- **Weather and location:** Open-Meteo receives city searches or configured coordinates. Location lookup can contact IP-address and geolocation services, including ifconfig.me, ipwho.is, or ip-api.com, to estimate your location. Coordinates may also be used for sunrise and sunset calculations.
- **Translation and web searches:** Google Translate receives the text and language choices submitted for translation. Search engines and websites receive search terms, URLs, and any arguments or clipboard values included in a quicklink you open.
- **Image processing and uploads:** Using remove.bg sends the selected image and your API key to remove.bg. Screenshot upload actions send the selected image to the chosen host, such as Catbox, Imgur, Lightshot, or a custom upload destination. Uploaded images may be accessible through a public link.
- **Connected accounts and media servers:** Integrations send authentication details and relevant requests to the service you configure. For example, Notion receives search queries and an integration token; music servers receive authentication and media requests. The Claude usage feature reads locally stored Claude Code credentials to request usage information from Anthropic.
- **Online resources:** GitHub and content hosts serve plugin listings, downloads, sponsor information, and other resources. Fonts, website icons, authenticator logos, currency rates, and color information may be requested from providers such as Google, Logo.dev, jsDelivr, currency-api, Frankfurter, and The Color API. Icon or logo requests can disclose a domain or search term. Non-Store editions may also contact GitHub for application updates; packaged Store installations use their distribution channel for updates.

These services have their own privacy policies and retention practices. They may process information in countries other than yours. Opening an external link, using a donation service, or signing into a connected service is also subject to that provider's terms and privacy policy.

## Plugins and the browser connector

Launcher plugins run external code on your computer. Depending on the plugin, they can access local files, receive launcher queries, store data, connect to online services, and use credentials you provide. Their data handling depends on the plugin and the services it uses.

The optional browser connector uses an authenticated connection on your own computer. Trusted plugins using the connector can access tab information and execute actions or scripts that read or modify webpages, including pages in your signed-in browser profile. A local connection does not prevent a plugin or webpage action from sending information to an external service. You can disable the connector and remove plugins you no longer use.

## Storage, security, and retention

Tabame stores settings, databases, caches, and logs in its application data folder. Open **Settings → Integration & Maintenance** to locate that folder. Older installations may also retain data under `%LOCALAPPDATA%\Tabame`; migration copies existing data without automatically deleting the old copy. Exports, screenshots, recordings, custom plugin folders, and backups may be stored elsewhere.

Protection varies by feature. Vault and authenticator features support encryption, and some credentials use Windows protection or Credential Manager. Other settings, cached content, and some integration keys may be stored as ordinary local files. Your device's access controls and the protection options you select therefore matter. Connections to custom servers or legacy endpoints may use unencrypted HTTP.

Saved information remains until you delete it or a feature's cleanup rules remove it. Clipboard history supports a configurable retention period; pinned items are retained separately. Rolling recordings and caches have their own cleanup behavior. Disabling a feature does not necessarily erase information it previously saved.

## Your choices and deleting information

You can review or change saved information through the relevant feature or the application data folder. You can disable clipboard history, activity tracking, recording, or the browser connector; adjust history retention and activity filters; remove saved entries; and disconnect integrations or remove plugins.

To remove remaining local data, locate the application data folder, exit Tabame, and delete the data you no longer want. Separately remove any legacy data, custom plugin folders, exports, recordings, backups, or saved credentials that you want deleted. Uninstalling the app may leave files saved outside the installation or package data folders. Revoke connected-account access with the relevant provider when needed.

Deleting a local file or disabling an integration does not delete information already uploaded to an external service. Use that service's deletion controls or contact its operator for removal. The developer cannot remotely access or delete information stored only on your device.

## Microsoft Store and support

Microsoft handles Store downloads, licensing, and its own diagnostic or account information under the [Microsoft Privacy Statement](https://privacy.microsoft.com/privacystatement).

If you submit a support request, the developer receives the information you choose to provide and uses it to investigate and respond. Public GitHub issues are visible to others. Do not include passwords, tokens, private clipboard contents, or unredacted logs in a public report.

## Contact and policy changes

For privacy questions or requests, contact Far Se through the [Tabame project issue tracker](https://github.com/Far-Se/tabame/issues). For a sensitive matter, ask how to share details privately before posting them.

This policy may be updated as Tabame's features or data practices change. The date above identifies the latest revision.
