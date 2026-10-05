# PDF Tools for Tabame

Type **`pdf`** in the launcher. Select a task, choose PDFs in the file picker,
fill in its options, and submit. Node.js 18+ must be available on PATH; no npm
packages are required.

## Install

Copy this folder to `%LOCALAPPDATA%\Tabame\plugins\pdf-tools\`, or to
`pdf-tools` inside your custom Tabame plugins directory. Reopen the launcher
to load it. The manifest is `plugin.json`; the entry script is `main.js`.

If qpdf is missing, the setup page offers **Install qpdf**. On Windows this runs:

```text
winget install --id QPDF.QPDF --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
```

Clicking Install accepts the package/source agreements. Windows may show an
administrator prompt. Installation stays active when the launcher is hidden;
reopen `pdf` to see its status. The installer is not cancellable from the plugin.
Quitting Tabame ends the plugin; a Windows installer already started by winget
may still finish.

If winget is unavailable, use **Official downloads**, then **Locate qpdf**.
The plugin checks `config.json`'s `qpdfPath`, `QPDF_EXECUTABLE`, PATH, common
Program Files/LocalAppData installations, and WinGet package/link folders.
It repeats detection after installation without changing PATH. Only the
optional executable path is saved in `config.json`.

Automatic installation and Windows installation-folder discovery are implemented
for Windows. macOS/Linux native integration is left as a multiplatform TODO;
a manually installed qpdf on PATH can run the ordinary file operations.

## Tasks

| Task | Options / behavior |
| --- | --- |
| Merge | Select multiple PDFs; specify file numbers such as `2,1,3` to set their order. Optionally interleave pages. |
| Split | One page per PDF, or groups of N pages. |
| Extract / reorder | Keep the selected pages in the specified order; duplicates are allowed. |
| Remove | Save every page except the selection. Removing all pages is rejected. |
| Reverse | Reverse the full page order. |
| Rotate | Clockwise, counterclockwise, 180 degrees, or reset rotation; all or selected pages. |
| Compress | Recompress streams and generate object streams. Optional lossy JPEG image optimization. Shows the size change. |
| Optimize for web | Linearize for compatible viewers. |
| Protect | AES-256 encryption with separate opening and owner passwords. |
| Remove password | Write an unencrypted copy using a known current password. |
| Inspect / check | Report page count, size, encryption and qpdf structural diagnostics. |
| Repair | Attempt structural recovery and rewrite a new PDF. |
| Flatten | Flatten existing visible form/annotation appearances. |

Page numbers start at **1**; `z` means the last page. Examples:

- `1-3,5,z`: first three pages, page five, then the last page.
- `z-1`: reverse order.
- `1-z:odd` / `1-z:even`: odd/even positions in the selected sequence.

Ranges are validated against the actual page count. Advanced qpdf range syntax
such as `r3` and `x2` is not accepted by these forms.

## Output and passwords

Each write operation creates an exclusive `PDF Tools-<task>-<suffix>` folder
inside the chosen output folder (the source folder by default). Existing files
and source PDFs are never overwritten. The result page opens files/folders and
offers Copy file / Copy all output paths actions.

Cancel stops qpdf and removes that run's partial PDFs. Hiding the launcher keeps
the task running; reopening `pdf` restores the operation/result. Exiting Tabame
terminates the plugin and attempts to remove partial output. A forced termination
can leave partial files in that run's folder.

Password fields are not saved to disk or echoed into render frames. Arguments
are passed to qpdf through its `@-` stdin mechanism, not shell commands or process
arguments. Diagnostics redact supplied passwords and qpdf's password-report lines.
New passwords must differ, contain no line breaks, be at most 127 UTF-8 bytes,
and not start with `-` or `@` for compatibility with older qpdf versions.

Merge outputs are **unencrypted**, and protected merge inputs must share the
entered password. Unlock files separately first if they use different passwords.
Split rejects encrypted input: first use Remove password to create an unlocked
copy. Other rewrites preserve input encryption unless explicitly encrypting or
decrypting.

## Limits

- qpdf does not provide OCR, Word conversion, PDF rendering, visual content
  editing, or image/text extraction. This plugin does not claim those features.
- Compression may not shrink an already optimized PDF. Optional image
  optimization is lossy and does not recompress existing JPEG images.
- Merge and split do not combine/preserve all document-level data such as
  bookmarks and attachments. Review interactive forms after page operations.
- Flatten relies on existing appearances; missing/stale appearances may leave
  fields interactive. It does not guarantee every form field will be flattened.
- Repair cannot restore missing content. qpdf exit code 3 means output was
  produced with warnings; these are shown instead of reported as a clean success.
- Rewriting a digitally signed PDF can invalidate its signature. Originals are
  preserved. The plugin does not validate signatures or guarantee PDF/A compliance.
- Selections are limited to one million pages/entries, and diagnostics to the last
  64,000 characters per output stream.

Implementation references: [qpdf command-line documentation](https://qpdf.readthedocs.io/en/stable/cli.html),
[official qpdf releases](https://github.com/qpdf/qpdf/releases), and
[WinGet package manifests](https://github.com/microsoft/winget-pkgs/tree/master/manifests/q/QPDF/QPDF).
