# Store candidate evidence

Create one directory per candidate version, for example:

```text
docs/release/evidence/2.0.0/<run-id>/
```

Keep the final signed artifact SHA-256, OS/build, VM/user/network conditions,
certification row IDs, sanitized logs, screenshots, and owner/date in the
release archive. Do not commit PFX files, passwords, tokens, private clipboard
or screen content, raw browser pairing files, or unredacted logs. Large or
sensitive evidence may remain in the protected release archive; this directory
only documents the naming and traceability convention.
