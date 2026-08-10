# Extension and dynamic-code policy contract

- **Phase:** 6 — Plugin and dynamic-code policy
- **Status:** Implemented; signed Store candidate path exists; certification validation remains outstanding
- **Selected first Store route:** `storeInstaller`
- **Portable route:** Existing executable plugin behavior remains available
- **Related feature contract:** [`microsoft-store-feature-contract.md`](microsoft-store-feature-contract.md)

This contract separates extension provenance from runtime permission. A plugin's
manifest, `enabled` setting, gallery label, or imported configuration can describe
a plugin, but none of those values can grant execution in a Store profile.

## Extension classes

| Class               | Current repository meaning                                                                              | Portable profile                                                         | First Store release                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| Bundled             | Code shipped as part of a reviewed Tabame artifact. No bundled executable plugin is currently enabled.  | May execute if intentionally shipped and registered.                     | No executable bundled extension is enabled. A future one requires a reviewed contract amendment. |
| First-party gallery | Entries from the official `resources/plugins.json` feed, currently hosted by the Tabame repository.     | May be fetched and installed using the existing gallery flow.            | Gallery fetch and installation are disabled.                                                     |
| Third-party gallery | An entry explicitly marked as coming from a non-first-party gallery/publisher.                          | May use the portable gallery adapter when the user invokes installation. | Gallery fetch and installation are disabled.                                                     |
| Local user-authored | A plugin folder dropped or configured by the user, including legacy data with no trusted origin marker. | May be discovered and executed.                                          | Existing manifests are preserved for data retention, but are not matched or executed.            |

Gallery installation records origin metadata in `.tabame-origin.json` so the
registry can classify the source. This metadata is diagnostic provenance, not a
Store trust grant. Missing, malformed, or user-edited provenance falls back to
`localUserAuthored`.

## Profile gates

`ExtensionPolicy` derives from the compile-time `DistributionProfile` and is the
single policy boundary for executable extensions and user-authored command
surfaces.

### Portable

- Existing local plugin discovery, process hosting, protocol behavior, and
  gallery installation remain available.
- Missing Python/Node/Bun dependencies may be installed after the user selects
  the explicit install action.
- Existing user-authored CLI and PowerShell command workflows remain available.
- Existing custom screen-upload PowerShell hosts remain available.

### Store profiles

Both `storeInstaller` and `storeMsix` currently deny all four executable plugin
classes. The following operations fail before network, filesystem, process, or
shell work begins:

- remote gallery index fetch and remote plugin file/ZIP installation;
- execution of a local, bundled, first-party, or third-party plugin process;
- automatic `npm`, `pip`, or `bun` dependency installation;
- local plugin enable/rename configuration changes;
- plugin process protocol side effects, because no plugin process can start.

The plugin manager shows an unavailable state rather than Gallery, Make Your Own,
or installation controls. Existing plugin manifests and folders are not deleted.
The launcher registry may read them for data-preservation UX, but it never adds a
blocked manifest to the keyword route.

If a future Store build retains any plugin, the policy must be amended to require
all of the following before execution:

1. an allow-listed manifest and publisher;
2. an immutable artifact with a verified signature and hash-pinned content;
3. explicit user consent at installation/activation;
4. a restricted protocol and filesystem capability set;
5. removal and per-plugin failure isolation; and
6. matching Store listing and certification disclosures.

No such Store extension is approved by this contract.

## Configuration and import boundary

The following are deliberately defense-in-depth gates rather than UI-only rules:

- `PluginRegistry` keeps blocked manifests out of keyword matching even when
  imported JSON says `"enabled": true`.
- `PluginRegistry.setEnabled` and `setKeyword` are unavailable for Store profiles.
- Duplicate-keyword repair is read-only in Store scans.
- `LauncherPluginHost.activate` and both dependency installers re-check policy
  immediately before process/package-manager execution.
- `PluginGallery.install` re-checks policy before downloading or writing anything.
- The host and portable session both re-check the final manifest execution
  decision, so a stale route or direct caller cannot restore Store execution.

## User-provided command and PowerShell surfaces

User-authored command templates are not treated as built-in allow-listed actions.
Store profiles disable or reject:

- custom Quick Action entries of type `Run Command`;
- CLI bookmark PowerShell execution and parameterized command sheets;
- folder actions that open CMD/PowerShell/Terminal shells;
- custom screen-upload PowerShell commands;
- implicit launcher execution of script-like files (`.ps1`, `.bat`, `.cmd`,
  `.vbs`, `.js`, `.mjs`, `.cjs`, `.py`, `.rb`, `.pl`, and `.sh`);
- user-provided targets that resolve to general-purpose runtimes or an
  `ExecutionPolicy` override.

The Store profile may still use fixed, app-owned PowerShell calls required by a
separate reviewed feature contract. This policy does not classify those
allow-listed built-in actions as user command templates.

## Evidence

Focused tests in `test/extension_policy_test.dart` cover:

- all four extension classes under portable and Store profiles;
- first-party versus third-party gallery classification;
- missing provenance falling back to local user-authored;
- imported `enabled: true` manifests being rejected by the Store registry gate;
- dependency, PowerShell, script-path, and runtime-target rejection.

The existing `test/plugin_protocol_test.dart` remains a parser/protocol test only;
it does not imply that a Store profile may start a plugin host.

This phase did not package, sign, publish, or certify an artifact. The separate
Phase 8 Store candidate path now packages/signs; immutable hosting, certification,
and Partner Center publication remain later release gates.
