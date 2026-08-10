# Microsoft Store certification matrix

- **Status:** release-blocking matrix prepared; clean-VM execution is still required
- **Route:** `storeInstaller`
- **Artifact under test:** exact signed EXE and SHA-256 recorded per run
- **Baseline:** Windows 10 22H2 (10.0.19045)+, x64; Windows 11 x64

Do not mark a row `PASS` without recording the exact candidate hash, date, OS
build, and evidence path. Store feature rows reference the detailed behavior
contract in [`microsoft-store-feature-contract.md`](microsoft-store-feature-contract.md).
Evidence belongs under `docs/release/evidence/<candidate-version>/` or a protected
release archive. Do not commit credentials, private clipboard/screen content,
PFX files, or unredacted logs.

## Status values

`NOT RUN` is the initial state. Use `PASS`, `FAIL`, or `BLOCKED` with a short
reason. Any P0/P1 failure blocks submission; a row cannot be waived because it
is inconvenient for the Store profile.

## Release-blocking rows

| ID | Area | Artifact/profile | OS/build | Preconditions | Steps | Expected result | Owner | Status | Run date | Artifact SHA-256 | Evidence path | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| CERT-PKG-01 | Clean install | signed `storeInstaller` EXE | Win10 22H2 x64 | Clean standard-user VM | Run silent install with recorded switches; inspect installed files | Install exits 0/3010; version/layout/signatures match manifest | Release | NOT RUN | TBD | TBD | TBD | |
| CERT-PKG-02 | Clean install | signed `storeInstaller` EXE | Win11 x64 | Clean standard-user VM | Repeat CERT-PKG-01 | Same result on supported Win11 build | Release | NOT RUN | TBD | TBD | TBD | |
| CERT-PKG-03 | Authenticode | signed EXE | Win10/11 x64 | Final candidate and certificate chain | Verify setup, uninstaller, and every installed PE | SHA-256, trusted timestamp, and expected signer are valid | Security | NOT RUN | TBD | TBD | TBD | |
| CERT-PKG-04 | Version/hash | signed EXE + manifest/SBOM | Win10/11 | Candidate files from one workflow run | Compare version, source commit, manifest, SBOM, and checksum | No metadata/hash/version mismatch | Release | NOT RUN | TBD | TBD | TBD | |
| CERT-LIFE-01 | Silent install | signed EXE | Win10 22H2 x64 | Standard user, offline | Install with `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` | No unexpected UI/UAC; return 0/3010; app files present | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-LIFE-02 | Upgrade | signed EXE | Win10/11 x64 | Previous Store candidate installed and app closed/running | Install new candidate over prior version | Version advances; settings/data remain; no binary corruption | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-LIFE-03 | Portable coexistence | Store + existing portable ZIP | Win10/11 x64 | Separate install locations and existing `%LOCALAPPDATA%\Tabame` | Install Store candidate after portable copy and reverse | Channels do not overwrite each other's managed binaries or settings unexpectedly | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-LIFE-04 | Uninstall/data retention | signed EXE | Win10/11 x64 | Create settings, secret, DB, and sentinel | Silent uninstall, reinstall, inspect data | Managed binaries removed; app data is retained; secrets are not exported | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-START-01 | Startup opt-in | `storeInstaller` | Win10/11 | Standard user | Enable, sign out/in, disable, inspect Startup Apps | Startup is reversible, no duplicate, no UAC at login | QA | NOT RUN | TBD | TBD | TBD | `STORE-START-01` |
| CERT-ELEV-01 | UAC accept/cancel | `storeInstaller` | Win10/11 | Standard user and admin account at medium IL | Start normally; invoke explicit elevation; accept and cancel | No automatic UAC; cancel preserves app; elevated action is scoped | QA | NOT RUN | TBD | TBD | TBD | `STORE-ELEV-01` |
| CERT-NATIVE-01 | Native consent | `storeInstaller` | Win10/11 | Clean settings | Exercise hooks, shell, taskbar, clipboard, capture, OCR, browser bridge | No hidden Windows change; denial/revocation leaves a usable reduced mode | Product | NOT RUN | TBD | TBD | TBD | `STORE-HOOK-01`, `STORE-SHELL-01` |
| CERT-NATIVE-02 | State restoration | `storeInstaller` | Win10/11, Explorer restart/sleep | Consent enabled where applicable | Toggle taskbar/shell features; restart Explorer; sleep/wake; exit | Prior Windows state is restored or failure is visible and safe | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-PLUGIN-01 | Extension gate | `storeInstaller` | Win10/11, offline | Seed local plugin/config and gallery URL | Open plugin manager/launcher; attempt imported activation/fetch/install | No gallery/network/dependency/process execution; data is preserved | Security | NOT RUN | TBD | TBD | TBD | `STORE-PLUGIN-01/02` |
| CERT-EXEC-01 | Command gate | `storeInstaller` | Win10/11 | Imported command templates and script targets | Invoke fixed built-in action and blocked custom/script action | Allow-listed action works; arbitrary command/PowerShell is rejected | Security | NOT RUN | TBD | TBD | TBD | `STORE-EXEC-01` |
| CERT-CAPTURE-01 | Capture/record/OCR | `storeInstaller` | Win10/11, multi-monitor | Consent/invocation available | Capture selected region, cancel, record/stop, OCR | No background capture; selected operation and reduced failure are clear | Product | NOT RUN | TBD | TBD | TBD | `STORE-CAPTURE-01/02` |
| CERT-CLIP-01 | Clipboard | `storeInstaller` | Win10/11 | History disabled then explicitly enabled | Copy text/image, pause, clear, restart | No collection while off/paused; clear works; launcher remains usable | Product | NOT RUN | TBD | TBD | TBD | `STORE-CLIP-01` |
| CERT-BROWSER-01 | Browser bridge | `storeInstaller` | Win10/11, offline/online | Explicit pair/revoke | Pair, send one supported request, revoke, inspect listener/token | Loopback only; revoke stops requests and rotates pairing state | Security | NOT RUN | TBD | TBD | TBD | `STORE-BROWSER-01` |
| CERT-OFFLINE-01 | Offline startup | `storeInstaller` | Win10/11 | Network disabled | Start, open launcher/settings, invoke unavailable network feature | Core shell starts; no retry loop; external feature reports reduced state | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-DPI-01 | Display behavior | `storeInstaller` | Win10/11 | Multiple monitors and mixed DPI | Move/summon windows, change display scale, sleep/wake | No crash; placement/focus and reduced behavior remain usable | QA | NOT RUN | TBD | TBD | TBD | |
| CERT-LOG-01 | Privacy/log redaction | `storeInstaller` | Win10/11 | Generate errors and export settings | Inspect redacted logs/export | No token, password, pairing secret, clipboard value, or raw private path leakage | Security | NOT RUN | TBD | TBD | TBD | |
| CERT-SUPPORT-01 | Links/disclosures | `storeInstaller` | Win10/11 | Network available | Open Privacy, Support, License, version/build links in settings | Public approved URLs load and match listing/policy | Product | NOT RUN | TBD | TBD | TBD | |
| CERT-DEFENDER-01 | SmartScreen/Defender | signed EXE | Win10/11 | Clean security baseline | Download/launch/install exact candidate; record prompts/detections | Signer/hash are expected; no unexplained detection or blocked core install | Security | NOT RUN | TBD | TBD | TBD | |
| CERT-ROLLBACK-01 | Rollback | Store listing + prior URL | Win10/11 | Pilot owner can halt rollout | Withdraw/stop candidate and reinstall retained prior URL | Prior immutable artifact remains available; data/schema remain compatible | Release | NOT RUN | TBD | TBD | TBD | |

## Evidence checklist per candidate

- [ ] Candidate filename, version, source SHA, signer subject, and SHA-256 copied
      from the manifest.
- [ ] VM snapshot/build, user integrity, network state, monitor/DPI state, and
      date recorded.
- [ ] Logs are redacted before archive; screenshots contain no private data.
- [ ] Failures have a P0/P1/P2/P3 severity and a linked remediation decision.
- [ ] The exact tested hash is copied to the Partner Center pilot record.
