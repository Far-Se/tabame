"use strict";

// Page map: task list -> task form -> operation -> result detail/file list.
// Setup and executable settings are separate destinations. Query filters only Home.
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");
const { spawn } = require("node:child_process");

const TASKS = {
  merge: ["Merge PDFs", "Combine files in your chosen order", "add", "Pages"],
  split: ["Split PDF", "One file per page, or groups of pages", "grid", "Pages"],
  extract: ["Extract / reorder pages", "Keep selected pages in any order", "copy", "Pages"],
  remove: ["Remove pages", "Save a copy without selected pages", "remove", "Pages"],
  reverse: ["Reverse pages", "Put the last page first", "sync", "Pages"],
  rotate: ["Rotate pages", "Turn all or selected pages", "refresh", "Pages"],
  compress: ["Compress PDF", "Lossless compression, with optional JPEG optimization", "download", "Optimize"],
  linearize: ["Optimize for web", "Allow compatible viewers to start loading pages sooner", "globe", "Optimize"],
  encrypt: ["Protect with password", "AES-256 password protection", "lock", "Security"],
  decrypt: ["Remove password", "Save an unlocked copy using a known password", "unlock", "Security"],
  check: ["Inspect / check PDF", "Page count, encryption and structural diagnostics", "info", "Maintenance"],
  repair: ["Repair PDF", "Attempt to recover structure and rewrite a new copy", "settings", "Maintenance"],
  flatten: ["Flatten forms / annotations", "Bake existing appearances into the pages", "document", "Maintenance"],
};
const CONFIG = path.join(__dirname, "config.json");
const DOWNLOAD = "https://github.com/qpdf/qpdf/releases";
const children = new Set();
const state = { route: "home", query: "", task: null, values: {}, qpdf: null,
  version: "", config: {}, job: null, result: null, setupError: "", closed: false, detached: false };
try { state.config = JSON.parse(fs.readFileSync(CONFIG, "utf8")); } catch { /* Defaults. */ }
if (!state.config || typeof state.config !== "object" || Array.isArray(state.config)) state.config = {};

function send(message) {
  if (!state.closed) process.stdout.write(JSON.stringify(message) + "\n");
}
function command(command, data = {}) { send({ type: "command", command, ...data }); }
function action(id, title, icon = "play") { return { id, title, icon }; }
function frame(view, title, data, rev = 0, history = "none") {
  send({ type: "render", rev, view,
    page: { id: `pdf:${state.route}`, title, history, preserveState: false,
      breadcrumbs: state.route === "home" ? [] : [{ id: "pdf:home", label: "PDF Tools" }] },
    elementId: `pdf-${state.route}`, canGoBack: state.route !== "home",
    placeholder: state.route === "home" ? "Find a PDF task..." : "Use the controls below",
    ...data });
}
function navigate(route, history = "push") {
  state.route = route;
  state.query = "";
  command("setQuery", { text: "" });
  render(0, history);
}
function size(bytes) {
  return bytes < 1024 * 1024 ? `${(bytes / 1024).toFixed(1)} KB` : `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}
function code(text) { return "\n\n````text\n" + String(text).replace(/`/g, "'") + "\n````"; }
function fileValues(value) {
  return (Array.isArray(value) ? value : value ? [value] : []).filter(v => typeof v === "string" && v.trim());
}
function field(id, type, label, extra = {}) {
  return { id, type, label, ...extra, value: type === "password" ? "" : state.values[id] ?? extra.value ?? "" };
}

// Windows-native integration only; ordinary qpdf operations remain portable.
function windowsCandidates() {
  if (process.platform !== "win32") {
    //TODO: Implement multiplatform
    return [];
  }
  const candidates = [];
  const scan = (directory, depth) => {
    if (depth < 0) return;
    let entries;
    try { entries = fs.readdirSync(directory, { withFileTypes: true }); } catch { return; }
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      if (entry.isFile() && entry.name.toLowerCase() === "qpdf.exe") candidates.push(full);
      else if (entry.isDirectory() && !entry.isSymbolicLink()) scan(full, depth - 1);
    }
  };
  for (const base of [process.env.ProgramFiles, process.env["ProgramFiles(x86)"],
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, "Programs"),
    process.env.LOCALAPPDATA && path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Packages")].filter(Boolean)) {
    try {
      for (const entry of fs.readdirSync(base, { withFileTypes: true })) {
        if (entry.isDirectory() && /^qpdf/i.test(entry.name)) scan(path.join(base, entry.name), 3);
      }
    } catch { /* Optional installation location. */ }
  }
  if (process.env.LOCALAPPDATA) candidates.push(path.join(process.env.LOCALAPPDATA, "Microsoft", "WinGet", "Links", "qpdf.exe"));
  return candidates;
}

function runProcess(executable, args, { input, job, timeout = 0 } = {}) {
  return new Promise((resolve, reject) => {
    if (state.closed || job?.cancelled) return reject(new Error("Cancelled."));
    const child = spawn(executable, args, { shell: false, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] });
    children.add(child);
    if (job) job.child = child;
    let stdout = "", stderr = "", timedOut = false;
    const append = (old, chunk) => (old + chunk).slice(-64000);
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", chunk => { stdout = append(stdout, chunk); });
    child.stderr.on("data", chunk => { stderr = append(stderr, chunk); });
    // A process can reject its arguments before stdin has finished writing.
    child.stdin.on("error", () => {});
    const timer = timeout ? setTimeout(() => { timedOut = true; child.kill(); }, timeout) : null;
    child.once("error", error => { clearTimeout(timer); children.delete(child); if (job) job.child = null; reject(error); });
    child.once("close", exitCode => {
      clearTimeout(timer);
      children.delete(child);
      if (job) job.child = null;
      if (job?.cancelled) reject(new Error("Cancelled."));
      else if (timedOut) reject(new Error("The command timed out."));
      else resolve({ code: exitCode, stdout: stdout.trim(), stderr: stderr.trim() });
    });
    child.stdin.end(input ?? "");
  });
}
async function discover() {
  state.qpdf = null;
  const candidates = [state.config.qpdfPath, process.env.QPDF_EXECUTABLE, "qpdf", ...windowsCandidates()].filter(Boolean);
  for (const candidate of [...new Set(candidates)]) {
    if (state.closed) return;
    try {
      const result = await runProcess(candidate, ["--version"], { timeout: 4000 });
      if (result.code === 0 && /qpdf version\s+\d/i.test(result.stdout)) {
        state.qpdf = candidate;
        state.version = result.stdout.split(/\r?\n/)[0];
        return;
      }
    } catch { /* Try the next location without changing PATH. */ }
  }
}

function render(rev = 0, history = "none", error = "") {
  if (state.job) {
    state.route = "progress";
    return frame("operation", state.job.title, { operation: { id: state.job.id,
      title: state.job.title, detail: state.job.detail, cancellable: state.job.kind !== "install" },
      canGoBack: false }, rev, history);
  }
  if (state.route === "settings") {
    return frame("form", "qpdf location", { form: { title: "Use an existing qpdf installation",
      error, submitLabel: "Save and detect", fields: [{ id: "qpdfPath", type: "filepicker", label: "qpdf executable",
        value: state.config.qpdfPath || "", description: "Optional. Leave empty to search PATH and Windows installation folders." }] } }, rev, history);
  }
  if (state.route === "setup" || !state.qpdf) {
    state.route = "setup";
    const windows = process.platform === "win32";
    const setupError = error || state.setupError;
    return frame("detail", "Set up qpdf", {
      detail: { markdown: "# qpdf is not installed\n\nPDF Tools uses qpdf to process documents locally. " +
        (windows ? "Install it with Windows Package Manager, or select an existing executable. Windows may ask for administrator approval." :
          "Automatic installation is available on Windows. Install qpdf manually and choose its executable below.") +
        (setupError ? code(setupError) : "") },
      floatingAction: [...(windows ? [action("install", "Install qpdf", "download")] : []),
        action("detect", "Check again", "refresh"), action("settings", "Locate qpdf", "folder")],
      actions: [action("download", "Official downloads", "globe")] }, rev, history);
  }
  if (state.route === "result" && state.result) return renderResult(rev, history);
  if (state.route.startsWith("task:") && TASKS[state.task]) return renderForm(rev, history, error);
  state.route = "home";
  const query = state.query.toLowerCase().trim();
  frame("list", "PDF Tools", {
    items: Object.entries(TASKS).filter(([id, task]) => `${id} ${task.join(" ")}`.toLowerCase().includes(query))
      .map(([id, [title, subtitle, icon, section]]) => ({ id, title, subtitle, icon, section })),
    empty: { title: "No matching tasks", hint: "Try merge, split, rotate, password or compress.", icon: "search" },
    banners: [{ id: "ready", style: "info", title: state.version,
      message: "Files stay on this computer. Each task saves into a new output folder." }],
    actions: [action("settings", "qpdf location", "settings"), action("detect", "Refresh qpdf", "refresh"), action("help", "qpdf documentation", "help")] }, rev, history);
}

function renderForm(rev, history, error) {
  const task = state.task;
  const merge = task === "merge";
  const fields = [field("files", "filepicker", merge ? "PDF files" : "PDF file", {
    required: true, extensions: ["pdf"], multiple: merge, watch: true,
    description: merge ? "Select two or more PDFs. The numbered order appears below." : "Choose the source PDF; it is never overwritten." })];
  if (merge) {
    const files = fileValues(state.values.files);
    fields.push(field("order", "text", "Merge order", { placeholder: "1,2,3", description:
      "Leave blank for selection order, or list every file number once. " + files.map((file, i) => `${i + 1}: ${path.basename(file)}`).join("; ") }));
    fields.push(field("collate", "checkbox", "Interleave pages (1 from each file, then 2, ...)", { value: false }));
  }
  if (["extract", "remove", "rotate"].includes(task)) fields.push(field("pages", "text", task === "remove" ? "Pages to remove" : "Pages", {
    required: true, value: task === "rotate" ? "1-z" : "",
    placeholder: "1-3,5,z", description: "Use page numbers starting at 1. z = last page. Examples: 1-3,5; z-1 reverses; 1-z:odd selects odd positions." }));
  if (task === "split") fields.push(field("group", "number", "Pages per output file", { required: true, min: 1, max: 1000000, value: 1 }));
  if (task === "rotate") fields.push(field("angle", "dropdown", "Rotation", { value: "+90", options: [
    { value: "+90", label: "90 degrees clockwise" }, { value: "+180", label: "180 degrees" },
    { value: "-90", label: "90 degrees counterclockwise" }, { value: "0", label: "Reset rotation" }] }));
  if (task === "compress") fields.push(field("lossy", "checkbox", "Also optimize images as JPEG (lossy)", {
    value: false, description: "Off by default. May reduce image quality. Existing JPEGs are not recompressed; a smaller file is not guaranteed." }));
  fields.push(field("password", "password", merge ? "Input password (shared by protected files)" : "Current password, if required", {
    description: merge ? "Use files with the same password, or unlock them individually first. The merged PDF is unencrypted." :
      "Leave empty for unprotected PDFs. Used only for this task." }));
  if (task === "encrypt") {
    fields.push(field("newPassword", "password", "New opening password", { required: true }));
    fields.push(field("confirmPassword", "password", "Confirm opening password", { required: true }));
    fields.push(field("ownerPassword", "password", "Owner password", { required: true,
      description: "Use a different password for managing document security. Keep both passwords somewhere safe." }));
  }
  if (task !== "check") fields.push(field("output", "folderpicker", "Save results in", {
    description: "Optional; defaults to the source folder. A new PDF Tools subfolder is created for every run." }));
  const notes = {
    merge: "Pages are combined into a new unencrypted PDF. Bookmarks and document-level data are not combined.",
    split: "Split files do not preserve document-level bookmarks or attachments. Encrypted inputs are rejected here; unlock a copy first.",
    repair: "Recovery is best effort. qpdf cannot reconstruct missing content; review the saved PDF and any warnings.",
    flatten: "Uses existing form and annotation appearances. Fields with missing or stale appearances may remain interactive.",
  };
  frame("form", TASKS[task][0], { form: { title: TASKS[task][0], submitLabel: task === "check" ? "Check PDF" : "Create PDF files", fields, error },
    ...(notes[task] ? { banners: [{ id: "task-note", style: "info", message: notes[task] }] } : {}) }, rev, history);
}

function renderResult(rev, history) {
  const result = state.result;
  const actions = [action("home", "More PDF tools", "home"), ...(state.task ? [action("again", "Run again", "refresh")] : [])];
  if (!result.files?.length) return frame("detail", result.title, {
    detail: { markdown: `# ${result.title}\n\n${result.text || ""}` }, floatingAction: actions,
    actions: [action("copyReport", "Copy report", "copy")] }, rev, history);
  frame("list", result.title, {
    banners: [{ id: "result", style: result.warning ? "warning" : "success", title: result.title, message: result.summary }],
    items: result.files.map((file, i) => ({ id: `output:${i}`, title: path.basename(file), subtitle: file,
      icon: "document", actions: [action("default", "Open PDF", "open"), action("copyFile", "Copy file", "copy")],
      preview: { markdown: result.text } })),
    preview: { enabled: true, wide: false }, floatingAction: [action("folder", "Open output folder", "folder"), ...actions],
    actions: [action("copyPaths", "Copy all output paths", "copy")] }, rev, history);
}

function safeString(value, label) {
  const text = String(value ?? "");
  if (/[\r\n\0]/.test(text)) throw new Error(`${label} cannot contain line breaks or NUL characters.`);
  return text;
}
function pageRange(raw, count) {
  // Resolve locally to reject out-of-range values before qpdf can clamp them.
  const text = String(raw || "").replace(/\s/g, "").toLowerCase();
  if (!/^(?:[1-9]\d*|z)(?:-(?:[1-9]\d*|z))?(?:,(?:[1-9]\d*|z)(?:-(?:[1-9]\d*|z))?)*(?::(?:odd|even))?$/.test(text)) {
    throw new Error("Use a page range such as 1-3,5,z or 1-z:odd.");
  }
  const [ranges, parity] = text.split(":");
  const pages = [];
  for (const range of ranges.split(",")) {
    const ends = range.split("-").map(value => value === "z" ? count : Number(value));
    const [first, last = first] = ends;
    if (ends.some(value => !Number.isSafeInteger(value) || value < 1 || value > count)) throw new Error(`Page numbers must be between 1 and ${count}.`);
    if (pages.length + Math.abs(last - first) + 1 > 1000000) throw new Error("Page selection is too large (maximum one million entries).");
    const direction = first <= last ? 1 : -1;
    for (let page = first; ; page += direction) { pages.push(page); if (page === last) break; }
  }
  const selected = parity ? pages.filter((_, i) => i % 2 === (parity === "odd" ? 0 : 1)) : pages;
  if (!selected.length) throw new Error("The page selection is empty.");
  return selected;
}

function redact(text, secrets) {
  for (const secret of secrets.filter(Boolean).sort((a, b) => b.length - a.length)) text = text.split(secret).join("[redacted]");
  // qpdf inspection can echo the supplied/recovered user password.
  return text.replace(/^.*(?:user|owner|supplied) password.*$/gim, "[password details omitted]");
}
async function qpdf(args, job, allowed = [0, 3]) {
  args.forEach(arg => safeString(arg, "Argument"));
  // @- is qpdf's line-delimited argument input: secrets never enter argv or a temporary file.
  const result = await runProcess(state.qpdf, ["@-"], { input: args.join("\n") + "\n", job });
  // Keep machine-readable stdout intact (a numeric password may equal a page count).
  const diagnostic = redact(result.stderr || result.stdout, job.secrets);
  if (!allowed.includes(result.code)) throw new Error(diagnostic || `qpdf exited with code ${result.code}.`);
  if (result.code === 3) job.warnings.push(diagnostic || "qpdf completed with warnings.");
  return result;
}
async function prepare(values) {
  const task = state.task;
  let files = fileValues(values.files).map(file => path.resolve(safeString(file, "File path")));
  if (files.length < (task === "merge" ? 2 : 1) || (task !== "merge" && files.length !== 1)) throw new Error(task === "merge" ? "Choose at least two PDFs." : "Choose exactly one PDF.");
  for (const file of files) {
    if (path.extname(file).toLowerCase() !== ".pdf" || !(await fs.promises.stat(file)).isFile()) throw new Error(`Not a PDF file: ${file}`);
  }
  if (task === "merge" && String(values.order || "").trim()) {
    const order = String(values.order).split(",").map(v => Number(v.trim()));
    if (order.length !== files.length || new Set(order).size !== files.length || order.some(v => !Number.isInteger(v) || v < 1 || v > files.length)) throw new Error("Merge order must list every file number exactly once, for example 2,1,3.");
    files = order.map(index => files[index - 1]);
  }
  const password = safeString(values.password, "Password");
  const newPassword = safeString(values.newPassword, "New password");
  const ownerPassword = safeString(values.ownerPassword, "Owner password");
  if (task === "encrypt") {
    if (!newPassword || newPassword !== values.confirmPassword) throw new Error("Enter and confirm the same non-empty opening password.");
    if (!ownerPassword || ownerPassword === newPassword) throw new Error("Enter a non-empty owner password different from the opening password.");
    // Legacy encryption syntax treats leading option/argument-file prefixes specially.
    if (/^[-@]/.test(newPassword) || /^[-@]/.test(ownerPassword)) throw new Error("New passwords must not start with - or @.");
    if (Buffer.byteLength(newPassword) > 127 || Buffer.byteLength(ownerPassword) > 127) throw new Error("Passwords must be at most 127 UTF-8 bytes.");
  }
  const group = Number(values.group ?? 1);
  if (task === "split" && (!Number.isInteger(group) || group < 1 || group > 1000000)) throw new Error("Pages per file must be an integer from 1 to 1000000.");
  if (task === "rotate" && !["+90", "+180", "-90", "0"].includes(values.angle)) throw new Error("Choose a rotation from the menu.");
  const parent = path.resolve(safeString(values.output || path.dirname(files[0]), "Output folder"));
  if (task !== "check" && !(await fs.promises.stat(parent)).isDirectory()) throw new Error("Choose an existing output folder.");
  if (task === "split" && parent.includes("%d")) throw new Error("Choose an output folder whose path does not contain %d (reserved by qpdf for split page numbers).");
  return { task, files, parent, password, newPassword, ownerPassword, group, values };
}

function beginJob(kind, title, detail) {
  const job = { id: `pdf-${Date.now()}`, kind, title, detail, child: null, cancelled: false, warnings: [], secrets: [], directory: null };
  state.job = job;
  command("background", { retain: true });
  navigate("progress", "push");
  return job;
}
function finishJob(job, result) {
  if (state.job !== job) return;
  state.job = null;
  state.result = result;
  state.route = "result";
  if (state.closed) return;
  render(0, "replace");
  if (state.detached) command("notify", { title: "PDF Tools", text: result.title });
  // Keep a completed result available on reattach. Release retention on Home/back.
}
async function discardPartial(job) {
  if (!job.directory) return "";
  try {
    // Only this run's exclusive mkdtemp directory; never recurse or follow links.
    const directory = path.resolve(job.directory);
    if (path.dirname(directory) !== job.parent || !path.basename(directory).startsWith(`PDF Tools-${job.task}-`)) throw new Error("Unexpected output directory.");
    const stat = await fs.promises.lstat(directory);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error("Output directory changed.");
    for (const entry of await fs.promises.readdir(directory, { withFileTypes: true })) {
      if (entry.isFile() && entry.name.toLowerCase().endsWith(".pdf")) await fs.promises.unlink(path.join(directory, entry.name));
    }
    await fs.promises.rmdir(directory);
    return "";
  } catch { return `\n\nPartial output may remain in: ${job.directory}`; }
}
async function processPDF(plan, job) {
  const { task, files, parent, password, newPassword, ownerPassword, group, values } = plan;
  job.secrets = [password, newPassword, ownerPassword];
  job.parent = parent;
  job.task = task;
  try {
    const input = [`--password=${password}`, files[0]];
    const countResult = await qpdf([...input, "--show-npages"], job);
    const count = Number(countResult.stdout);
    if (!Number.isSafeInteger(count) || count < 1 || count > 1000000) throw new Error("The PDF must contain between 1 and 1000000 pages.");
    if (task === "check") {
      const check = await qpdf([...input, "--check"], job, [0, 2, 3]);
      const encryption = await qpdf([...input, "--show-encryption"], job);
      const sourceSize = (await fs.promises.stat(files[0])).size;
      if (job.cancelled) throw new Error("Cancelled.");
      finishJob(job, { title: check.code === 2 ? "PDF has structural errors" : check.code === 3 || job.warnings.length ? "PDF checked with warnings" : "PDF check complete",
        text: `${count} pages · ${size(sourceSize)}\n\n${files[0]}` +
          code(redact([check.stdout, check.stderr, encryption.stdout, encryption.stderr, ...job.warnings].filter(Boolean).join("\n\n"), job.secrets)) });
      return;
    }
    // qpdf --split-pages constructs empty documents. Avoid silently dropping encryption.
    if (task === "split") {
      const encrypted = await qpdf([...input, "--is-encrypted"], job, [0, 2]);
      if (encrypted.code === 0) throw new Error("Unlock a copy with Remove password before splitting. Split outputs are unencrypted.");
    }
    let selected;
    if (["extract", "remove", "rotate"].includes(task)) selected = pageRange(values.pages, count);
    if (task === "remove") {
      const removed = new Set(selected);
      selected = Array.from({ length: count }, (_, i) => i + 1).filter(page => !removed.has(page));
      if (!selected.length) throw new Error("Cannot remove every page. Keep at least one page.");
    }
    if (job.cancelled) throw new Error("Cancelled.");
    job.directory = await fs.promises.mkdtemp(path.join(parent, `PDF Tools-${task}-`));
    // A fixed filename also avoids qpdf's %d substitution affecting source filenames.
    const output = path.join(job.directory, task === "split" ? "pages.pdf" : `${task}.pdf`);
    let args = [...input];
    switch (task) {
      case "merge":
        args = ["--empty", ...(values.collate === true ? ["--collate"] : []), "--pages"];
        for (const file of files) args.push(file, `--password=${password}`, "1-z");
        args.push("--");
        break;
      case "split": args.push(`--split-pages=${group}`); break;
      case "extract": case "remove": args.push("--pages", ".", selected.join(","), "--"); break;
      case "reverse": args.push("--pages", ".", "z-1", "--"); break;
      case "rotate": args.push(`--rotate=${values.angle}:${selected.join(",")}`); break;
      case "compress":
        args.push("--object-streams=generate", "--compress-streams=y", "--recompress-flate", "--compression-level=9");
        if (values.lossy === true) args.push("--optimize-images");
        break;
      case "linearize": args.push("--linearize"); break;
      case "encrypt": args.push("--encrypt", newPassword, ownerPassword, "256", "--"); break;
      case "decrypt": args.push("--decrypt"); break;
      case "flatten": args.push("--flatten-annotations=all"); break;
      case "repair": break; // qpdf attempts structural recovery when reading, then rewrites.
      default: throw new Error("Unknown PDF task.");
    }
    args.push(output);
    job.detail = "Writing PDF files. Results will be available here when finished.";
    render();
    await qpdf(args, job);
    const outputs = (await fs.promises.readdir(job.directory)).filter(name => /\.pdf$/i.test(name)).sort().map(name => path.join(job.directory, name));
    if (!outputs.length) throw new Error("qpdf did not create any PDF files.");
    let bytes = 0;
    for (const file of outputs) {
      const stat = await fs.promises.stat(file);
      if (!stat.size) throw new Error("qpdf created an empty output file.");
      bytes += stat.size;
    }
    const originalBytes = (await Promise.all(files.map(file => fs.promises.stat(file)))).reduce((sum, stat) => sum + stat.size, 0);
    let summary = `${outputs.length} file${outputs.length === 1 ? "" : "s"} · ${size(bytes)}`;
    if (task === "compress") summary += bytes < originalBytes ? ` · ${((1 - bytes / originalBytes) * 100).toFixed(1)}% smaller` : " · Already optimized; this copy is not smaller";
    if (job.warnings.length) summary += " · Review qpdf warnings in the preview";
    if (job.cancelled) throw new Error("Cancelled.");
    finishJob(job, { title: job.warnings.length ? "PDF files saved with warnings" : "PDF files saved", summary,
      files: outputs, directory: job.directory, warning: job.warnings.length > 0,
      text: `${summary}\n\nSaved in: ${job.directory}` + (job.warnings.length ? code([...new Set(job.warnings)].join("\n\n")) : "") });
  } catch (error) {
    const remaining = await discardPartial(job);
    finishJob(job, { title: job.cancelled ? "PDF task cancelled" : "Could not process PDF",
      text: code(redact(error.message, job.secrets)) + remaining });
  } finally {
    job.secrets = [];
  }
}

async function installQpdf() {
  if (process.platform !== "win32") {
    //TODO: Implement multiplatform
    render(0, "none", "Automatic installation is only available on Windows.");
    return;
  }
  state.setupError = "";
  const job = beginJob("install", "Installing qpdf", "Windows Package Manager is installing QPDF.QPDF. Approve the Windows prompt if one appears. You can close the launcher and return later.");
  try {
    const result = await runProcess("winget", ["install", "--id", "QPDF.QPDF", "--exact", "--source", "winget",
      "--accept-source-agreements", "--accept-package-agreements", "--disable-interactivity"], { job });
    await discover();
    if (state.closed) return;
    if (!state.qpdf) throw new Error((result.stdout + "\n" + result.stderr).trim() || "Installation did not produce a detectable qpdf executable. Use Locate qpdf or the official downloads.");
    state.job = null;
    command("toast", { text: `${state.version} is ready`, style: "success" });
    if (state.detached) command("notify", { title: "PDF Tools", text: "qpdf is installed. PDF tools are ready." });
    navigate("home", "replace");
    if (!state.detached) command("background", { retain: false });
  } catch (error) {
    state.job = null;
    state.route = "setup";
    const reason = error.code === "ENOENT" ? "Windows Package Manager (winget) is unavailable. Install App Installer from Microsoft Store, or use Official downloads and Locate qpdf." : error.message;
    state.setupError = reason;
    render(0, "replace", reason);
    if (state.detached) command("notify", { title: "PDF Tools", text: "qpdf installation needs attention. Reopen PDF Tools." });
  }
}

let submitting = false;
async function handle(message) {
  if (!message || typeof message !== "object") return;
  const rev = Number.isInteger(message.rev) ? message.rev : 0;
  if (message.type === "close") return shutdown();
  if (message.type === "detach") { state.detached = true; return; }
  if (message.type === "attach") { state.detached = false; render(); return; }
  if (message.type === "cancel") {
    if (state.job?.kind === "pdf" && (!message.id || message.id === state.job.id)) {
      state.job.cancelled = true;
      state.job.detail = "Cancelling and removing partial output...";
      state.job.child?.kill();
      render(rev);
    }
    return;
  }
  if (message.type === "init" || message.type === "query") {
    state.query = String(message.text ?? message.query ?? "");
    render(rev);
    return;
  }
  if (state.job || submitting) return;
  if (message.pageId && message.pageId !== `pdf:${state.route}`) return;
  if (message.type === "back" || message.type === "navigate") {
    const target = message.targetPageId || message.toPageId || "pdf:home";
    if (target === `pdf:task:${state.task}` && TASKS[state.task]) navigate(`task:${state.task}`, "none");
    else { command("background", { retain: false }); navigate(state.qpdf ? "home" : "setup", "none"); }
    return;
  }
  if (message.type === "change" && state.route.startsWith("task:")) {
    state.values = { ...state.values, ...message.values };
    render(rev);
    return;
  }
  if (message.type === "submit") {
    submitting = true;
    try {
      if (state.route === "settings") {
        const executable = String(message.values?.qpdfPath || "").trim();
        if (executable && (!path.isAbsolute(executable) || !(await fs.promises.stat(executable)).isFile())) throw new Error("Choose an existing executable with an absolute path.");
        state.config = { qpdfPath: executable };
        await fs.promises.writeFile(CONFIG, JSON.stringify(state.config, null, 2) + "\n");
        await discover();
        state.setupError = state.qpdf ? "" : "No working qpdf executable was found. Choose qpdf.exe or install qpdf.";
        navigate(state.qpdf ? "home" : "setup", "replace");
      } else if (state.route.startsWith("task:")) {
        state.values = { ...state.values, ...message.values };
        const plan = await prepare({ ...state.values });
        if (state.closed) return;
        const job = beginJob("pdf", TASKS[plan.task][0], "Reading the source PDF...");
        // Never send secrets back in a render frame or save them in configuration.
        for (const key of ["password", "newPassword", "confirmPassword", "ownerPassword"]) delete state.values[key];
        void processPDF(plan, job);
      }
    } catch (error) { render(0, "none", error.message); }
    finally { submitting = false; }
    return;
  }
  if (message.type !== "action") return;
  const verb = message.action === "default" ? message.id : message.action;
  if (state.route === "home" && Object.hasOwn(TASKS, verb)) {
    state.task = verb;
    state.values = {};
    navigate(`task:${verb}`);
  } else if (verb === "install") { void installQpdf(); }
  else if (verb === "settings") navigate("settings");
  else if (verb === "detect") {
    submitting = true;
    frame("list", "Finding qpdf", { loading: true, loadingText: "Checking qpdf installations...", items: [] });
    try {
      await discover();
      state.setupError = state.qpdf ? "" : "qpdf was not found. Install it or choose its executable.";
      navigate(state.qpdf ? "home" : "setup", "replace");
    } finally { submitting = false; }
  } else if (verb === "download") command("open", { url: DOWNLOAD });
  else if (verb === "help") command("open", { url: "https://qpdf.readthedocs.io/en/stable/cli.html" });
  else if (verb === "home") { command("background", { retain: false }); navigate("home", "replace"); }
  else if (verb === "again" && state.task) navigate(`task:${state.task}`, "replace");
  else if (state.route === "result" && state.result) {
    const result = state.result;
    if (verb === "folder" && result.directory) command("open", { path: result.directory });
    else if (verb === "copyPaths") command("copy", { text: (result.files || []).join("\r\n") });
    else if (verb === "copyReport") command("copy", { text: result.text || "" });
    else if (/^output:\d+$/.test(message.id || "")) {
      const file = result.files?.[Number(message.id.split(":")[1])];
      if (file && message.action === "default") command("open", { path: file });
      else if (file && verb === "copyFile") command("copyFile", { path: file });
    }
  }
}

function shutdown() {
  if (state.closed) return;
  state.closed = true;
  if (state.job) {
    state.job.cancelled = true;
  }
  for (const child of children) child.kill();
  input.close();
  process.stdin.destroy();
  // Let child close handlers remove partial files, but never outlive host grace.
  setTimeout(() => process.exit(0), 1500).unref();
}
process.stdout.on("error", shutdown);
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
frame("list", "PDF Tools", { loading: true, loadingText: "Finding qpdf...", items: [] });
const ready = discover();
input.on("line", line => {
  let message;
  try { message = JSON.parse(line); } catch { return; }
  if (message?.type === "close") { shutdown(); return; }
  void ready.then(() => state.closed ? undefined : handle(message)).catch(() => {
    if (!state.closed) command("toast", { text: "Could not handle this PDF Tools request. Try again.", style: "error" });
  });
});
input.on("close", shutdown);
