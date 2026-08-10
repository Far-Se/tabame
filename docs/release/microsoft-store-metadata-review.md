# Microsoft Store metadata review checklist

This small checklist keeps the public listing, privacy worksheet, and signed
artifact metadata synchronized. It is intentionally separate from the future
MSIX manifest.

- [ ] `pubspec.yaml` version matches the installer manifest and Partner Center
      version.
- [ ] `storeInstaller` is the compiled profile; no portable ZIP updater or
      custom uninstall is exposed.
- [ ] Product identity/publisher values are copied from Partner Center, not
      inferred from the local `msix_config`.
- [ ] Architecture is x64 and minimum Windows version is 10.0.19045.
- [ ] Privacy/support/license URLs are public, approved, and reachable.
- [ ] Store exclusions (gallery, executable plugins, arbitrary commands, ZIP
      self-update) are stated in the listing.
- [ ] Startup, UAC, native consent, clipboard, capture, browser bridge, and
      external-service behavior are disclosed.
- [ ] Screenshots are from the Store profile and contain no private data.
- [ ] IARC/content declarations and dependencies are complete.
- [ ] Listing URL, installer filename, silent switches, return codes, source
      commit, and SHA-256 match the signed candidate record.
