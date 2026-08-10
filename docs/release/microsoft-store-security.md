# Tabame Microsoft Store security release record

**Status: candidate security record — security owner approval is required before
submission.**

This record is scoped to the installer-listed `storeInstaller` edition. It is
updated for each candidate and retained with the signed artifact manifest,
SBOM, certification evidence, and Partner Center submission record.

## Security boundaries

- The main process starts at normal user integrity. Login startup never implies
  elevation. A UAC request is explicit and limited to the requested action or
  session; cancellation leaves Tabame running.
- Installer-owned binaries live under `%LOCALAPPDATA%\Programs\Tabame` and are
  treated as immutable by Store-profile application code.
- App data lives under `%LOCALAPPDATA%\Tabame`; installer uninstall does not
  delete it. Secrets use the platform secret boundary or an explicit password
  export path.
- Store profiles reject executable plugins, gallery downloads, package-manager
  dependency installation, imported plugin execution, user PowerShell/command
  templates, script-like launcher targets, ZIP self-update, and custom binary
  lifecycle operations before network/process/filesystem side effects.
- Native integrations require explicit consent or invocation, report policy/API
  failure as reduced mode, and expose revoke/disable behavior where applicable.

## Threat model and mitigations

| Threat | Mitigation and evidence |
| --- | --- |
| Tampered installer or installed PE | CA-backed Authenticode signature, SHA-256 digest, trusted timestamp, post-package verification, and signature checks for every installed PE including the Inno uninstaller |
| Unsigned or mutable Store update | `storeInstaller` cannot use the portable ZIP updater; installer/Store lifecycle owns updates; every submission gets a new immutable URL |
| Remote code execution through extensions | `ExtensionPolicy` denies gallery/download/dependency/host paths in Store profiles; blocked manifests cannot bypass the policy through imported settings |
| Secret disclosure in diagnostics | Redacted logs, secret-safe settings export, no pairing tokens/vault/DPAPI values in diagnostics, and focused export/redaction tests |
| Privilege escalation | No automatic `runas`; explicit narrow elevation result; no general privileged command runner |
| Windows experience changed silently | Native integration consent coordinator and reduced modes; startup off by default and reversible |
| Supply-chain drift | Clean checkout, `pubspec.lock`, pinned Flutter channel/action, dependency graph JSON, CycloneDX SBOM, license review, malware scan, and source commit recorded in the manifest |
| Artifact confusion | Versioned filename, source commit, installer hash, profile, architecture, minimum OS, and silent switches are emitted together; tested hash must equal submitted hash |

## Build and signing controls

The separate workflow is
`.github/workflows/release-packaging-windows-store.yml`. It builds with:

```text
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeInstaller
```

The signing job is protected by the `windows-store-signing` GitHub Environment.
Certificate material is decoded only under the ephemeral runner temp directory,
never logged, and removed in an always-run cleanup step. Required signatures
use SHA-256 file and timestamp digests. Inno Setup signs both the setup
executable and generated uninstaller; the staging signer covers runtime EXE/DLL
and other PE files.

The certificate must chain to a CA accepted by the Microsoft Trusted Root
Program. The release owner records the non-secret signer subject, certificate
expiry, timestamp URL, and verification result in the candidate record. Never
record a PFX, password, private key, token, or raw secret value.

## Dependency and license provenance

The candidate includes:

- the exact source commit and `SOURCE_DATE_EPOCH`-derived timestamp;
- the checked-in `pubspec.lock` resolved through `dart pub deps --json`;
- a CycloneDX 1.5 SBOM;
- `LICENSE` and `THIRD-PARTY-NOTICES.txt` beside the runtime.

The release owner must review direct, transitive, Git, native, and installer
components for license compatibility and known vulnerabilities. The Git-based
`just_audio_windows` dependency is an explicit supply-chain review item.

## Operational response

Report vulnerabilities through the repository's private GitHub Security
Advisory path (`/security/advisories/new`) until a dedicated security contact
is approved. Do not put secrets, exploit payloads, private clipboard content,
or unredacted logs in a public issue. Security owners triage, reproduce in an
isolated environment, rotate affected credentials/certificates, and publish a
fixed signed candidate with a new immutable URL. The Phase 12 runbook defines
rollout halt and rollback without overwriting old artifacts.

## Required approvals before submission

- [ ] Certificate chain, signer subject, timestamp, and expiry reviewed.
- [ ] Final SBOM/dependency/license audit complete.
- [ ] Malware/Defender scan complete for the exact signed hash.
- [ ] Privacy policy, listing limitations, and security contact approved.
- [ ] Certification matrix has no open P0/P1 result.
- [ ] Partner Center identity and URL match the tested candidate.
