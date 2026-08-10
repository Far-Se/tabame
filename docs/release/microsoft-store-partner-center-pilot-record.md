# Microsoft Store Partner Center pilot record

Copy this template once per pilot submission. Keep the completed record with
release evidence. Never put passwords, PFX material, API tokens, private
Partner Center credentials, or unredacted user data in this file.

## Submission identity

| Field | Value |
| --- | --- |
| Product name | TBD |
| Partner Center product ID | TBD |
| Submission ID/revision | TBD |
| Publisher identity | TBD — reconcile before submission |
| Account type | TBD |
| Pilot audience/flight | TBD |
| Submission date/time (UTC) | TBD |
| Product/release owner | TBD |
| Support contact | TBD |

## Exact artifact

| Field | Value |
| --- | --- |
| App version | TBD |
| Installer version | TBD (`major.minor.patch.0`) |
| Installer filename | TBD |
| Architecture | x64 |
| Minimum Windows version | 10.0.19045 |
| Source commit | TBD |
| SHA-256 | TBD |
| Signer subject | TBD |
| Certificate expiry | TBD |
| Timestamp URL | TBD |
| Immutable HTTPS URL | TBD |
| Silent install switches | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` |
| Silent uninstall switches | `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART` |
| Expected return codes | `0`, `3010` |
| Manifest/SBOM paths | TBD |
| Certification evidence path | TBD |

## Submission results

| Field | Value |
| --- | --- |
| Privacy URL | TBD |
| Support URL | TBD |
| Listing worksheet revision | TBD |
| IARC/content declaration status | TBD |
| Certification status | NOT SUBMITTED |
| Reviewer questions | None recorded |
| Pilot feedback | None recorded |
| P0/P1 issues | None recorded |
| Remediation decision | TBD |
| Go/no-go decision | TBD |
| Rollback URL/candidate | TBD |
| Approval owners/date | Product: TBD; Release: TBD; Security: TBD; Privacy: TBD |

## Credential handling

The workflow uses the protected `windows-store-signing` environment. The
Partner Center account, certificate store, hosting credentials, and any API
credentials are referenced by protected secret names or vault records only;
they are not copied into this record.
