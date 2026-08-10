# Microsoft Store listing worksheet

**Status: draft worksheet — do not submit until the owner fills every `TBD`
field and attaches the exact signed candidate evidence.**

This worksheet is for the selected installer-listed `storeInstaller` route. It
is not MSIX metadata and must not be populated from the stale `msix_config`
values without Partner Center reconciliation.

## Identity and availability

| Partner Center field | Proposed value | Status/owner action |
| --- | --- | --- |
| Product/display name | Tabame | Confirm reservation is available |
| Publisher/display publisher | Far Se | Reconcile with approved Partner Center publisher |
| Product identity | TBD | Product owner reserves exact identity |
| Account type | TBD | Record individual/company account |
| Category | Utilities / Productivity (TBD) | Product owner selects final category |
| Markets | TBD | Product owner selects supported markets |
| Pricing | Free (TBD) | Product owner confirms |
| Privacy URL | `https://github.com/Far-Se/tabame/blob/main/docs/release/microsoft-store-privacy.md` | Legal owner must approve public stable URL |
| Support URL | `https://github.com/Far-Se/tabame/issues` | Support owner confirms public contact/process |
| Security contact | GitHub private advisory path until replaced | Security owner approves public reporting route |
| License | MIT; see repository `LICENSE` | Legal owner confirms third-party notices |

## Package and system requirements

| Field | Candidate value |
| --- | --- |
| Distribution route | Signed offline EXE listed by immutable HTTPS URL |
| Installer technology | Inno Setup 6.4.2 per-user EXE |
| Architecture | x64 only |
| Minimum OS | Windows 10 version 22H2, build 10.0.19045 |
| Installation scope | Per-user: `%LOCALAPPDATA%\Programs\Tabame` |
| App data | `%LOCALAPPDATA%\Tabame`; retained on uninstall |
| Silent install | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| Silent uninstall | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| Successful return codes | `0`, `3010` |
| Package version | `pubspec.yaml` version mapped to `major.minor.patch.0` |
| Installer URL | TBD immutable HTTPS URL; never overwrite a published URL |
| SHA-256 | TBD from final signed candidate |
| Tested source commit | TBD from candidate manifest |

## Store description draft

Tabame is a fast, keyboard-first Windows toolbox and quick menu. It brings your
windows, shortcuts, launcher, media controls, screen tools, clipboard history,
settings, and everyday utilities into one configurable surface. Tabame starts
as a normal user application and stays out of the way until you invoke it.

The first Store edition starts with the features that can be disclosed and
validated reliably. Startup is opt-in and reversible. Features that affect
other windows, global input, the clipboard, the screen, or external services
are user-invoked or require explicit consent and show a reduced mode when
Windows policy or an API is unavailable. Administrator access is never requested
silently at login.

The Store edition does not include the plugin gallery, executable/script plugin
hosting, arbitrary command or PowerShell templates, automatic npm/pip/bun
installation, ZIP self-update, or custom in-app install/uninstall. Updates and
installer lifecycle are provided by the Store-listed installer. See the privacy
policy and support links for data, retention, export, deletion, and limitations.

## Required listing assets

- [ ] Approved privacy policy URL and effective date.
- [ ] Approved support URL/contact and security response path.
- [ ] Current screenshots from the `storeInstaller` profile, not portable-only
      plugin/gallery or ZIP-update screens.
- [ ] App icon/tile files reviewed for branding and licensing; no
      machine-specific asset path.
- [ ] Final description, feature disclosures, dependencies, minimum OS,
      architecture, and installer switches reviewed.
- [ ] IARC questionnaire and content declarations completed by the owner.
- [ ] Release notes identify the exact version, signed artifact hash, and any
      reduced features.
- [ ] Certification notes link to deterministic rows in the certification
      matrix and the exact evidence directory.

## Version release-note template

```text
Tabame <version>

- Signed installer candidate: <immutable HTTPS URL>
- Architecture: x64
- Minimum OS: Windows 10 22H2 / Windows 11
- SHA-256: <hash>
- Updates: delivered through the Store-listed installer
- Store edition limitations: executable plugins/gallery and arbitrary command
  execution are disabled; sensitive integrations require consent
```
