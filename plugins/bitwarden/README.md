# Bitwarden plugin for Tabame

This plugin brings the core Bitwarden Raycast workflow to the Tabame launcher:

- Search and fuzzy-filter vault items by name, username, URI, type, or card brand.
- Open a full item detail page with masked sensitive fields.
- Copy or paste usernames, passwords, TOTP codes, notes, card fields, identity fields, SSH keys, and custom fields.
- Open a login URI, toggle the Bitwarden favorite flag, sync, lock, or log out.
- Generate passwords and passphrases with Bitwarden's own CLI.
- Create login items and folders.

## Requirements

The plugin uses the official Bitwarden CLI (`bw`) and does not bundle it. Install
the CLI separately or set its absolute path in `config.json`:

```json
{
  "cli_path": "C:/Program Files/Bitwarden CLI/bw.exe"
}
```

Copy `config.example.json` to `config.json` if you need a custom CLI path,
self-hosted server, certificate bundle, launch syncing, or favicon loading.

The first-time setup can use either route:

1. Run `bw login` in a terminal (or configure the CLI for your server).
2. Type `bw` in Tabame and enter the master password in the unlock form, or choose **Configure API Key** to enter a Bitwarden personal API key.
3. Reopen the launcher after installing the plugin. Tabame rescans plugins every time the launcher opens.

The unlock session token and optional API credentials are stored through
Tabame's secret storage, not in `config.json`. The vault cache and full item
details are kept in memory only.

## Install

Copy this folder to:

```text
%localappdata%\\Tabame\\plugins\\bitwarden\\
```

Then reopen the launcher and type `bw`.
