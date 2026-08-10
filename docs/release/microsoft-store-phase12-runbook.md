# Microsoft Store release and maintenance runbook

- **Route:** `storeInstaller`
- **Status:** operational runbook prepared; external signing/hosting/Partner
  Center gates remain open
- **Portable path:** remains `.github/workflows/windows-build.yml` and is never
  replaced by this runbook

This runbook is the repeatable sequence for a Store candidate. A maintainer may
prepare a candidate from a clean checkout, but cannot submit until the external
certificate, immutable host, public policy/support URLs, Partner Center
identity, and Windows certification evidence are available.

## 1. Preflight a clean checkout

1. Check out the release commit and verify the working tree is clean:

   ```powershell
   git status --short
   git rev-parse HEAD
   git log -1 --format=%ct
   ```

2. Read `pubspec.yaml`, `pubspec.lock`, the selected-route ADR, the feature
   contract, the privacy/security/listing artifacts, and the previous pilot
   record.
3. Confirm the version is a new three-component numeric version. Update
   `pubspec.yaml`; do not reuse a Store version or tag. The installer maps it to
   `major.minor.patch.0`.
4. Confirm the Windows baseline remains Windows 10 22H2+/x64 and that any new
   system integration, external service, personal-data surface, or executable
   download has triggered the Phase 7 and Phase 9 reviews.
5. Run the dependency/license and vulnerability review against `pubspec.lock`,
   including Git/native dependencies. Keep the review with the candidate.

## Version mapping

| Release surface                  | Version for a `2.0.0` candidate                        | Rule                                                                        |
| -------------------------------- | ------------------------------------------------------ | --------------------------------------------------------------------------- |
| `pubspec.yaml`                   | `2.0.0`                                                | Source value for the candidate workflow; three numeric components required  |
| Runtime build display            | `v2.0.0`                                               | Must match the app version shown by Tabame and the release notes            |
| Store installer metadata         | `2.0.0` / Windows file version `2.0.0.0`               | Generated from the `pubspec.yaml` value; never hand-edit the artifact       |
| Store artifact filename          | `tabame-v2.0.0-windows-store-installer.exe`            | Versioned and immutable; never reuse a published filename/URL               |
| Partner Center listing           | `2.0.0` (use the field format Partner Center requests) | Copy from the final signed metadata/manifest and tested hash                |
| Official portable GitHub release | tag `v2.0.0`, asset `tabame-v2.0.0-windows.zip`        | Remains owned by `windows-build.yml`; do not substitute it for Store output |
| Nightly portable release         | tag `Nightly`, asset `tabame-nightly-windows.zip`      | Independent channel; never move this tag from the Store workflow            |

The release owner must update the app/runtime display value and `pubspec.yaml`
together, verify the generated installer metadata, and record the source commit.
A Store version is monotonically increasing even if the portable nightly channel
moves independently.

## 2. Build and verify the Store profile

Use the protected workflow for the release candidate:

```text
gh workflow run release-packaging-windows-store.yml -f sign=true -f run_install_smoke=true
```

The workflow:

1. runs the shared Windows import check, Flutter analysis, and Flutter tests;
2. builds with `TABAME_DISTRIBUTION_PROFILE=storeInstaller`;
3. stages only runtime files, `LICENSE`, and third-party notices;
4. creates the EXE, SHA-256, manifest, SBOM, and Partner Center metadata;
5. signs every staged PE with SHA-256 and a trusted timestamp;
6. signs the Inno setup EXE and generated uninstaller;
7. runs silent install/reinstall/uninstall/data-retention checks; and
8. uploads a versioned workflow artifact for the release owner.

The `windows-store-signing` environment must be protected by review. The
certificate PFX is decoded only in runner temp and removed in the always-run
cleanup. Never use a repository file, command-line literal, or log message for
the certificate/password.

For local unsigned structure work, use the commands in
[`windows-store-installer-contract.md`](windows-store-installer-contract.md).
An unsigned artifact is never a submission candidate.

## 3. Review candidate outputs

Download the signed workflow artifact and verify, without editing it:

- installer and `.sha256` agree;
- manifest `artifactType`, route, version, architecture, OS baseline, source
  commit, installed file hashes, data root, and silent switches are correct;
- SBOM matches the checked-in lock/dependency graph;
- Partner Center metadata has the final hash and no stale URL;
- signatures and timestamp validate on a clean Windows machine; and
- no PDB, developer path, secret, or unintended staging file is present.

Run the dependency/license audit, malware/Defender scan, and security review
against the exact signed hash. Attach sanitized output to
`docs/release/evidence/<version>/<run-id>/` or the protected release archive.

## 4. Install and certification gate

Execute every `CERT-*` row in
[`microsoft-store-certification-matrix.md`](microsoft-store-certification-matrix.md)
on clean Windows 10 22H2 and Windows 11 x64 VMs. Include standard users,
administrator accounts at medium integrity, multiple displays/DPI scales,
offline startup, startup policy states, Defender/SmartScreen, Explorer restart,
sleep/wake, and the exact enabled Store features. Record the final installer
hash on every row.

Do not submit with an open P0/P1 issue. A failure caused by the Store profile is
not waived; fix it or amend the product contract and listing before proceeding.

## 5. Publish an immutable installer URL

The Store route is an installer listed by URL, not a GitHub workflow artifact
with short retention. The release owner must:

1. upload the exact signed EXE and checksum/metadata to approved HTTPS hosting;
2. use a new versioned path for every candidate;
3. enable retention, access monitoring, and availability checks;
4. never replace bytes at a published URL; and
5. copy the final URL and hash to the Partner Center metadata and pilot record.

If hosting is unavailable, stop at the candidate stage. Do not substitute the
portable ZIP, a mutable `latest` URL, or an unsigned local file.

## 6. Partner Center pilot

Complete [`microsoft-store-partner-center-pilot-checklist.md`](microsoft-store-partner-center-pilot-checklist.md), copy the exact artifact facts into
[`microsoft-store-partner-center-pilot-record.md`](microsoft-store-partner-center-pilot-record.md), and submit only after product, release,
security, privacy, and certification owners approve. Use the limited pilot/
flight audience supported by Partner Center. Archive the submission ID,
reviewer questions, certification report, screenshots, metadata export, tested
hash, and pilot feedback. Never add Partner Center credentials to the record.

If certification rejects a feature, add the exact finding to the feature
contract and address the root cause in a focused change. Do not hide behavior
from automated tests or change the listing without changing the product.

## 7. Rollout and rollback

- Start with the approved pilot audience; widen only after the recorded go/no-go
  decision.
- Monitor install failures, signature/SmartScreen reports, support issues,
  crashes, policy denials, and external-service failures by version and hash.
- To halt rollout, pause/withdraw the Store submission or flight according to
  Partner Center controls. Preserve the previous immutable installer URL.
- For an installer-hosting incident, stop advertising the new URL, retain the
  prior signed candidate, and publish a corrected candidate at a new URL. Never
  overwrite the affected bytes.
- Preserve `%LOCALAPPDATA%\Tabame` compatibility. If a schema migration is
  required, make it versioned, non-destructive, rollback-safe, and test it before
  resubmission.
- Record the incident, exact affected hash, user impact, mitigation, and
  certification/support follow-up.

## 8. Ongoing maintenance cadence

| Cadence                                                                                       | Check                                                                                                                                         | Owner/evidence               |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------- |
| Every candidate                                                                               | Store-profile regression, certification matrix, privacy/listing diff, dependency/license audit, SBOM, malware scan, signed hash review        | Release + QA + Security      |
| Monthly                                                                                       | Review Store feature contract, external destinations, logs/exports, support/security reports, and portable/Store divergence                   | Product + Privacy + Security |
| 90/60/30 days before expiry                                                                   | Check Authenticode certificate and timestamp/signing service expiry; renew through protected secret rotation and run a signed smoke candidate | Release owner                |
| Each dependency update                                                                        | Re-run dependency/license/vulnerability review and candidate tests; inspect Git/native source changes                                         | Engineering + Security       |
| Each feature with system integration, executable download, personal data, or external service | Re-run Phase 7 consent/reduced-mode review and Phase 9 privacy/listing review                                                                 | Product + QA                 |
| Each Partner Center change                                                                    | Archive identity, capability/listing/certification notes and update pilot record                                                              | Product/release owner        |

## 9. Portable channel separation

Portable releases continue through `.github/workflows/windows-build.yml` with
`package-windows.ps1`, ZIP checksums, nightly tag movement, official release
naming, and GitHub release upload. Do not add Store signing secrets to that
workflow, replace its ZIP, or make a Store profile the portable default.
