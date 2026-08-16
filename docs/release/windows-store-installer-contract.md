# Windows Store installer contract

- **Phase:** 8 — Packaging, signing, and CI
- **Status:** Candidate path implemented; signing credentials and immutable hosting remain release-owner gates
- **Route:** `storeInstaller`
- **Artifact:** signed per-user Inno Setup EXE
- **Baseline:** Windows 10 22H2 (10.0.19045)+, x64

This document describes the installer-listed Store path. It is deliberately
separate from the portable ZIP path in
[`.github/workflows/windows-build.yml`](../../.github/workflows/windows-build.yml).
The Store workflow does not move the `Nightly` tag, create a GitHub release, or
upload/replace a ZIP asset.

## Version and layout

`pubspec.yaml` is the version source for a candidate. The workflow requires a
three-component numeric version and, for `store-v*` tags, requires the tag to
match that version exactly. A released Store version must never be reused or
downgraded. The installer metadata uses the corresponding four-component
Windows file version (`major.minor.patch.0`).

The installer uses Inno Setup 6.4.2 and installs per user to:

```text
%LOCALAPPDATA%\Programs\Tabame
```

Tabame app data remains separate at:

```text
%LOCALAPPDATA%\Tabame
```

Uninstall removes the managed application directory but does not remove the app
data root. The app's explicit **Delete all Tabame data** action remains separate.

## Candidate outputs

For version `2.0.0`, the workflow produces the following signed candidate files:

```text
tabame-v2.0.0-windows-store-installer.exe
tabame-v2.0.0-windows-store-installer.exe.sha256
tabame-v2.0.0-windows-store-installer.manifest.json
tabame-v2.0.0-windows-store-installer.sbom.cdx.json
tabame-v2.0.0-windows-store-installer.partner-center.json
```

The manifest records the source commit, source timestamp, profile, installed
file list, per-file SHA-256 values, install/data roots, and silent switches. The
CycloneDX document records the resolved Dart dependency graph from
`dart pub deps --json`. `LICENSE` and `THIRD-PARTY-NOTICES.txt` are staged with
the runtime.

The Partner Center metadata intentionally leaves `downloadUrl` empty. The
release owner must put the signed EXE at a new immutable HTTPS URL and fill that
field only after the final SHA-256 is known.

## Signing boundary

The signing job is protected by the `windows-store-signing` GitHub Environment.
It imports the base64 PFX only under `RUNNER_TEMP`, exposes the password only to
the signing process, and deletes the temporary certificate in an always-run
cleanup step. The following secrets are expected:

| Secret | Purpose |
| --- | --- |
| `TABAME_STORE_SIGNING_CERTIFICATE_BASE64` | CA-backed Authenticode PFX, base64 encoded |
| `TABAME_STORE_SIGNING_CERTIFICATE_PASSWORD` | PFX password |
| `TABAME_STORE_TIMESTAMP_URL` | RFC 3161 timestamp endpoint; defaults to DigiCert when omitted |
| `TABAME_STORE_SIGNER_SUBJECT` | Optional subject fragment used by verification |

No certificate, private key, password, or populated secret file belongs in the
repository. PR/manual validation with `sign: false` creates only an unsigned
candidate and cannot be submitted.

`sign-windows-store-installer.ps1` signs every PE file in the staged runtime.
Inno Setup's `SignTool` integration signs the generated setup executable and
`signedUninstaller` signs the uninstaller embedded in the installed product.
The verifier checks the final installer, the installed uninstaller, and every
installed PE when `-RequireSigned` is used. All signatures use SHA-256 and a
trusted timestamp.

## Silent lifecycle contract

The exact switches emitted in the manifest and metadata are:

```text
Install:   /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-
Uninstall: /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

Successful install/update return codes are `0` and `3010`. The CI smoke test
installs into an isolated directory, starts a harmless process at the installed
`tabame.exe` path, reinstalls the candidate, verifies that the installer closes
the process before replacing the binary, verifies an app-data sentinel survives,
and silently uninstalls. It does not launch the application or delete the real
app-data root. `CloseApplications=force` is intentional for unattended updates;
interactive users should save work before starting an update.

## Local use

On a Windows machine with Flutter, Inno Setup 6.4.2, and a release build:

```powershell
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeInstaller
flutter pub get
dart pub deps --json | Out-File dist\pub-deps.json -Encoding utf8
.\tool\release\package-windows-store-installer.ps1 `
  -ReleaseDir build\windows\x64\runner\Release `
  -StageDir dist\store-stage `
  -InstallerPath dist\tabame-v2.0.0-windows-store-installer.exe `
  -Sha256Path dist\tabame-v2.0.0-windows-store-installer.exe.sha256 `
  -ManifestPath dist\tabame-v2.0.0-windows-store-installer.manifest.json `
  -SbomPath dist\tabame-v2.0.0-windows-store-installer.sbom.cdx.json `
  -PartnerCenterMetadataPath dist\tabame-v2.0.0-windows-store-installer.partner-center.json `
  -Version 2.0.0 `
  -DependencyJsonPath dist\pub-deps.json
.\tool\release\verify-windows-store-installer.ps1 `
  -InstallerPath dist\tabame-v2.0.0-windows-store-installer.exe `
  -Sha256Path dist\tabame-v2.0.0-windows-store-installer.exe.sha256 `
  -ManifestPath dist\tabame-v2.0.0-windows-store-installer.manifest.json `
  -ExpectedVersion 2.0.0 `
  -RunSilentInstallSmoke
```

The local command above is an unsigned structure check. Signing requires the
protected CI environment or an equivalent temporary certificate setup; never
paste a production password into a shell history.

## External release gates

- Product owner reconciles Partner Center identity/publisher values with the
  local metadata before submission.
- Release owner supplies the CA-backed certificate and immutable HTTPS host.
- Security/legal owners approve the privacy, security, listing, and dependency
  artifacts.
- Certification evidence is recorded against the final signed hash.
