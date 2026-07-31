# Mail — Tabame plugin

Read and send email from the Tabame launcher over IMAP or POP3 (receiving)
and SMTP (sending). Works with Gmail, Yahoo, and any other mail server that
speaks these standard protocols. No extra packages required — it's built
entirely on the Python standard library.

## Install

1. Copy `plugin.json` and `main.py` into:
   ```
   %localappdata%\Tabame\plugins\mail\
   ```
2. Open the Tabame launcher (it rescans plugins on open — no restart needed).
3. Type `mail`.

## Adding an account

Type `mail`, then press **Ctrl+K** (or use the empty-state button) and choose
**Add account**. Pick a provider from the dropdown — choosing **Gmail** or
**Yahoo** auto-fills the correct server, port, and encryption settings for
you. Choosing **Custom / other server** clears those fields so you can type
your own.

Whichever provider you pick, you still need to supply:

- **Account name** — any label you want, just for your own reference
- **Email address**
- **Password / app password** — see below, this is _not_ always your normal
  login password
- **Login username** — leave blank to default to your email address; only
  needed if your server uses a separate username

After saving, the plugin runs a quick connection test in the background and
shows a toast telling you whether it connected.

---

## Gmail

Google blocks plain-password IMAP/SMTP login. You must use an **app
password** instead of your real Google password.

1. Turn on **2-Step Verification** on your Google account, if it isn't
   already (required — app passwords aren't available without it):
   `https://myaccount.google.com/security`
2. Go to `https://myaccount.google.com/apppasswords`
3. Create a new app password (name it anything, e.g. "Tabame Mail")
4. Copy the 16-character code Google gives you

In the plugin's Add account form:

- Provider: **Gmail**
- Email: your full `@gmail.com` address
- Password: the app password from step 4 (not your Google account password)

Prefilled server settings (you shouldn't need to touch these):

|                 | Host             | Port | Encryption |
| --------------- | ---------------- | ---- | ---------- |
| Incoming (IMAP) | `imap.gmail.com` | 993  | SSL/TLS    |
| Outgoing (SMTP) | `smtp.gmail.com` | 587  | STARTTLS   |

If IMAP still appears disabled after this, check
**Gmail → Settings → Forwarding and POP/IMAP** and make sure IMAP access is
turned on.

---

## Yahoo

Yahoo also blocks plain-password access. You need a Yahoo **app password**.

1. Sign in to Yahoo Mail → profile icon → **Manage your account**
2. Go to **Security** → **External Connections** (also called "Other ways
   to sign in" on some accounts)
3. Turn on **Two-Step Verification** if it isn't already on — Yahoo requires
   this before it will let you generate an app password
4. Click **Generate app password** / **Create app password**, name it, and
   copy the code

In the plugin's Add account form:

- Provider: **Yahoo**
- Email: your full Yahoo address
- Password: the app password (not your normal Yahoo password)

Prefilled server settings:

|                 | Host                  | Port | Encryption |
| --------------- | --------------------- | ---- | ---------- |
| Incoming (IMAP) | `imap.mail.yahoo.com` | 993  | SSL/TLS    |
| Outgoing (SMTP) | `smtp.mail.yahoo.com` | 587  | STARTTLS   |

(Port 465 with SSL/TLS also works for SMTP if you'd rather use that instead
of 587/STARTTLS.)

---

## Any other server (custom / work / self-hosted)

Choose **Custom / other server** as the provider. You'll need these details
from your email provider or IT department:

- **Receive via** — IMAP (recommended: syncs read/unread state, folders,
  supports delete) or POP3 (simpler, but the plugin can only list/read/
  delete — POP3 has no concept of "read" status)
- **Incoming server host** and **port**
- **Incoming encryption** — SSL/TLS (usually port 993 for IMAP / 995 for
  POP3), STARTTLS (usually port 143 / 110), or None
- **Outgoing (SMTP) host** and **port** (commonly 465 for SSL/TLS, or 587
  for STARTTLS)
- **Outgoing encryption** — same three options as above
- **Login username** — often your full email address, but some servers use
  a separate username (e.g. just `jdoe` instead of `jdoe@company.com`)
- **Password** — whatever your server expects. If it's protected by 2FA,
  you'll likely need an app-specific password the same way Gmail/Yahoo
  require one — check with your provider.

A couple of things worth knowing for self-hosted or internal servers:

- TLS certificates are verified normally. A self-signed certificate that
  isn't trusted by your system will fail to connect — install it into your
  system's trust store first, or use a certificate from a real CA
  (Let's Encrypt, etc.).
- If your server is only reachable on a private network or VPN, make sure
  you're connected to that network before opening the inbox in the plugin.

---

## Using it day to day

- **Enter** on an account → opens its inbox (most recent 40 messages).
  Type to search the currently loaded messages by subject or sender.
- **Enter** on an email → opens the full message. IMAP accounts
  automatically mark it as read.
- **Ctrl+K** on an account → Compose, Test connection, or Remove account.
- **Ctrl+K** on an email → Reply, Delete, Mark as unread (IMAP only).
- **Ctrl+K** on the account list or inbox → Compose new email, Refresh.

## Where your data is stored

- Account settings (name, email, server, port, etc.) are stored in
  Tabame's per-plugin storage.
- Passwords/app passwords are stored in the **Windows Credential Manager**,
  never written to a plaintext file. They're only read back into memory
  briefly, right before each connection.

## Troubleshooting

**`AUTHENTICATIONFAILED` / "Invalid credentials"**
Almost always means the server wants an app password, not your normal
login password (see the Gmail/Yahoo sections above), or the username is
wrong (try your full email address if a short username doesn't work).

**Connects but shows no messages / wrong folder**
The plugin always reads the `INBOX` folder specifically — mail filed into
other folders/labels won't show up.

**Times out / can't connect at all**
Double-check host, port, and encryption match what your provider publishes.
Also confirm nothing (firewall, VPN, antivirus) is blocking outbound
connections on that port.

**Self-hosted server with a self-signed certificate**
Connections will fail TLS verification. Install the certificate into your
system's trust store, or switch the server to a certificate from a trusted
CA.
