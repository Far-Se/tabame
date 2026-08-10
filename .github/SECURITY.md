# Security policy

## Supported versions

Security fixes are prepared for the latest signed Store candidate and the
current portable release when the issue affects both channels. The Store and
portable profiles have different update and extension policies; do not assume a
portable ZIP is an acceptable substitute for a Store candidate.

## Reporting a vulnerability

Please use GitHub's private Security Advisory flow:

<https://github.com/Far-Se/tabame/security/advisories/new>

Do not put credentials, private clipboard or screen content, PFX files, tokens,
exploit payloads, or unredacted logs in a public issue. If private advisories
are unavailable for the repository, contact the project owner through the
repository support channel and include only a minimal reproduction and a safe
contact method.

A useful report includes the affected version/profile, Windows version and
architecture, reproduction steps, impact, and any redacted logs. The release
owner acknowledges reports, reproduces them in an isolated environment, and
coordinates a signed fix and disclosure timeline.

## Release response

A confirmed installer or supply-chain issue blocks Partner Center submission and
halts rollout of the affected immutable URL. Preserve the prior signed
candidate, revoke or rotate affected credentials/certificates, update the
security record, and publish a new candidate rather than overwriting an old
artifact.
