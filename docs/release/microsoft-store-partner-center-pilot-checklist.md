# Microsoft Store Partner Center pilot checklist

- **Status:** prepared, not submitted
- **Route:** `storeInstaller` signed offline EXE listed by immutable HTTPS URL
- **Owner:** release/product owner
- **Rule:** do not submit an unsigned artifact, a mutable URL, or a hash that was
  not used by the certification matrix.

## Identity and account

- [ ] Product reservation completed; exact product name recorded.
- [ ] Partner Center product identity and publisher reconciled with
      [`ADR 0001`](../decisions/0001-store-distribution-route.md).
- [ ] Individual/company account type recorded.
- [ ] Display name, publisher name, legal entity, and support contact approved.
- [ ] Product ID, submission ID, revision, and pilot audience recorded in the
      protected pilot record (never record credentials).

## Privacy, security, and listing

- [ ] Approved public privacy URL is reachable without authentication.
- [ ] Approved public support URL and vulnerability-reporting route are live.
- [ ] Listing worksheet completed: category, markets, pricing, age rating/IARC,
      dependencies, minimum OS, x64 architecture, installer behavior, and
      Store-edition limitations.
- [ ] Current Store-profile screenshots and icon/tile assets attached.
- [ ] Certification notes reference deterministic rows and the exact evidence
      directory.
- [ ] Third-party license/dependency audit, SBOM review, and Defender/malware
      scan completed.

## Exact candidate

- [ ] Clean checkout and source commit recorded.
- [ ] `pubspec.yaml` version, four-component installer version, and Partner
      Center version agree.
- [ ] Signed installer, signed installed PE files, and signed uninstaller
      verified with a trusted timestamp.
- [ ] SHA-256 file and manifest agree.
- [ ] Immutable HTTPS URL created and retained; URL is not a GitHub workflow
      artifact URL with an expiration/retention policy.
- [ ] URL, architecture, language, version, installer type, silent switches,
      and return codes copied to Partner Center metadata.
- [ ] Certification matrix has no open P0/P1 issue and its artifact hash equals
      this candidate hash.

## Pilot submission and feedback

- [ ] Limited audience/flight selected where available.
- [ ] Clean install, upgrade, uninstall, offline, startup, UAC, native consent,
      reduced-mode, and Store-edition gate notes are ready for reviewers.
- [ ] Submission sent; ID and timestamp recorded.
- [ ] Reviewer questions answered without hiding or test-detecting behavior.
- [ ] Pilot install/support feedback captured by exact version/hash.
- [ ] Certification result recorded as pass or with an exact remediation item.
- [ ] Go/no-go decision approved by product, release, security, and privacy
      owners.
- [ ] Rollback URL and prior signed candidate are confirmed before widening.
