import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Describes the kind of item to open.
enum LaunchType {
  /// A URL – e.g. `"https://flutter.dev"` or `"ftp://server/path"`
  url,

  /// A folder path – e.g. `r"E:\Projects\myproject"`
  folder,

  /// A file with a registered handler – e.g. `r"E:\Images\avatar.png"`
  file,

  /// An executable – e.g. `r"C:\Games\Counter Strike\game.exe"`
  app,

  /// A shell command with arguments – e.g.
  ///   `r'powershell -File "E:\SCRIPTS\tempRemove.ps1"'`
  ///   `'cmd /c shutdown /s'`
  ///   `r'code E:\Projects\My Projects\project'`
  command,
}

/// Launches URLs, folders, files, apps and shell commands on Windows
/// **without** inheriting the caller's elevated (admin) token.
///
/// ## Auto-detection
///
/// When [LaunchType] is omitted, [detect] is called to infer the type:
///
/// 1. **URL** – starts with a known URI scheme (`http://`, `https://`,
///    `ftp://`, `ftps://`, `mailto:`, `ms-`, `steam:`, …).
/// 2. **Folder** – exists on disk and [FileSystemEntity.isDirectorySync]
///    returns `true`; or the string ends with `\` / `/`.
/// 3. **App** – exists on disk and has a `.exe` extension.
/// 4. **File** – exists on disk (any other extension).
/// 5. **Command** – everything else (e.g. `powershell …`, `cmd …`, `code …`).
///
/// ## De-elevation strategy
///
/// Explorer always runs at the interactive user's medium IL.  For URLs,
/// folders, files and executables we delegate to `explorer.exe` so the child
/// inherits Explorer's token instead of our elevated one.
///
/// Commands are wrapped in `cmd /min /c start "" …` which lets Windows use
/// PATH look-up and avoids a flashing console window.
///
/// A plain [ShellExecuteEx] fallback is used if Explorer dispatch fails.
class Launcher {
  // ──────────────────────────────────────────────────────────────────────────
  // Public API
  // ──────────────────────────────────────────────────────────────────────────

  /// Opens [target], optionally forcing a [type].
  ///
  /// When [type] is `null` the correct [LaunchType] is detected automatically
  /// via [detect].
  ///
  /// Returns `true` if the launch was dispatched successfully.
  static bool open(String target, {LaunchType? type}) {
    final LaunchType resolvedType = type ?? detect(target);
    return _launch(target, resolvedType);
  }

  /// Infers the [LaunchType] for [target] without opening it.
  ///
  /// Detection order (first match wins):
  /// 1. URL scheme  → [LaunchType.url]
  /// 2. Existing directory  → [LaunchType.folder]
  /// 3. Trailing path separator  → [LaunchType.folder]
  /// 4. Existing `.exe` file  → [LaunchType.app]
  /// 5. Any other existing file  → [LaunchType.file]
  /// 6. Known shell command prefix  → [LaunchType.command]
  /// 7. Contains spaces with flags-like arguments  → [LaunchType.command]
  /// 8. Fallback  → [LaunchType.file]
  static LaunchType detect(String target) {
    final String t = target.trim();

    // 1. URL schemes ──────────────────────────────────────────────────────────
    if (_looksLikeUrl(t)) return LaunchType.url;

    // 2 & 3. Folder ───────────────────────────────────────────────────────────
    if (t.endsWith('\\') || t.endsWith('/')) return LaunchType.folder;
    if (_existsAsDirectory(t)) return LaunchType.folder;

    // 4. Existing executable ──────────────────────────────────────────────────
    if (_existsAsFile(t) && _hasExtension(t, 'exe')) return LaunchType.app;

    // 5. Any other existing file ──────────────────────────────────────────────
    if (_existsAsFile(t)) return LaunchType.file;

    // At this point the target does NOT exist on disk as-is.
    // It is either a shell command (powershell, cmd, code, …) or a bare path
    // that we couldn't verify (network path, env-var path, etc.).

    // 6 & 7. Shell command heuristics ─────────────────────────────────────────
    if (_looksLikeCommand(t)) return LaunchType.command;

    // 8. Fallback – treat as a file/path and let the shell decide.
    return LaunchType.file;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Detection helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// URI schemes that should be opened as URLs.
  static const List<String> _urlSchemes = <String>[
    'http://',
    'https://',
    'ftp://',
    'ftps://',
    'mailto:',
    'file://',
    'steam:',
    'ms-',
    'slack:',
    'zoommtg:',
    'msteams:',
    'spotify:',
  ];

  static bool _looksLikeUrl(String t) {
    final String lower = t.toLowerCase();
    return _urlSchemes.any((String s) => lower.startsWith(s));
  }

  /// Shell executables that are never standalone file paths.
  static const List<String> _knownShellCommands = <String>[
    'cmd', 'cmd.exe',
    'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe',
    'wsl', 'wsl.exe',
    'bash', 'bash.exe',
    'python', 'python.exe', 'python3', 'python3.exe',
    'node', 'node.exe',
    'code', 'code.exe', // VS Code
    'notepad', 'notepad.exe',
    'msiexec', 'msiexec.exe',
    'reg', 'reg.exe',
    'sc', 'sc.exe',
    'net', 'net.exe',
    'taskkill', 'taskkill.exe',
    'shutdown', 'shutdown.exe',
    'runas', 'runas.exe',
    'start',
    'echo', 'set', 'setx', 'cd', 'dir', 'del', 'copy', 'move',
    'mkdir', 'rmdir', 'rd', 'ren', 'rename', 'type',
  ];

  static bool _looksLikeCommand(String t) {
    // Extract the first token (before any space, ignoring leading quotes).
    final String unquoted = t.startsWith('"') ? t.substring(1) : t;
    final int spaceIdx = unquoted.indexOf(' ');
    final String firstToken = (spaceIdx == -1 ? unquoted : unquoted.substring(0, spaceIdx)).toLowerCase().replaceAll('"', '');

    if (_knownShellCommands.contains(firstToken)) return true;

    // Heuristic: has spaces AND contains flag-like tokens (-, /)
    // e.g. "shutdown /s /t 0" or "net stop spooler"
    if (t.contains(' ')) {
      final List<String> tokens = t.split(' ');
      final bool hasFlags = tokens.any((String tok) => tok.startsWith('-') || tok.startsWith('/'));
      if (hasFlags) return true;
    }

    return false;
  }

  static bool _existsAsDirectory(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static bool _existsAsFile(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static bool _hasExtension(String path, String ext) => path.toLowerCase().endsWith('.$ext');

  // ──────────────────────────────────────────────────────────────────────────
  // Launch dispatcher
  // ──────────────────────────────────────────────────────────────────────────

  static bool _launch(String target, LaunchType type) {
    switch (type) {
      case LaunchType.url:
      case LaunchType.folder:
      case LaunchType.file:
      case LaunchType.app:
        return _openViaExplorer(target);

      case LaunchType.command:
        final (String exe, String args) = _splitCommand(target);
        return _openCommandViaShell(exe, args);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // De-elevated open via explorer.exe
  // ──────────────────────────────────────────────────────────────────────────

  static bool _openViaExplorer(String target) {
    final String quotedTarget = '"$target"';
    final Pointer<Utf16> lpFile = 'explorer.exe'.toNativeUtf16();
    final Pointer<Utf16> lpParams = quotedTarget.toNativeUtf16();

    final Pointer<SHELLEXECUTEINFO> sei = calloc<SHELLEXECUTEINFO>()
      ..ref.cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..ref.fMask = 0x00000000
      ..ref.hwnd = NULL
      ..ref.lpVerb = nullptr
      ..ref.lpFile = lpFile
      ..ref.lpParameters = lpParams
      ..ref.lpDirectory = nullptr
      ..ref.nShow = SW_SHOWNORMAL;

    try {
      final bool ok = ShellExecuteEx(sei) != 0;
      if (ok) return true;
    } finally {
      free(lpFile);
      free(lpParams);
      free(sei);
    }

    return _shellExecuteDirect(target, verb: 'open');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Command via  cmd /min /c start "" <exe> [args]
  // ──────────────────────────────────────────────────────────────────────────

  static bool _openCommandViaShell(String exe, String args) {
    // Use `cmd /c <exe> [args]` — /c executes the command then exits
    // automatically.  SW_HIDE + 0x00008000 together suppress both
    // the cmd window and any console window the child might create.
    final String quotedExe = exe.contains(' ') ? '"$exe"' : exe;
    final String cmdArgs = '/c $quotedExe${args.isEmpty ? '' : ' $args'}';

    final Pointer<Utf16> lpFile = 'cmd.exe'.toNativeUtf16();
    final Pointer<Utf16> lpParams = cmdArgs.toNativeUtf16();

    final Pointer<SHELLEXECUTEINFO> sei = calloc<SHELLEXECUTEINFO>()
      ..ref.cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..ref.fMask = 0x00008000 | 0x00000000
      ..ref.hwnd = NULL
      ..ref.lpVerb = nullptr
      ..ref.lpFile = lpFile
      ..ref.lpParameters = lpParams
      ..ref.lpDirectory = nullptr
      ..ref.nShow = SW_HIDE; // hide the cmd window entirely

    try {
      final bool ok = ShellExecuteEx(sei) != 0;
      if (ok) return true;
    } finally {
      free(lpFile);
      free(lpParams);
      free(sei);
    }

    return _shellExecuteDirect(exe, args: args);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Fallback: direct ShellExecuteEx
  // ──────────────────────────────────────────────────────────────────────────

  static bool _shellExecuteDirect(
    String file, {
    String args = '',
    String verb = 'open',
  }) {
    final Pointer<Utf16> lpFile = file.toNativeUtf16();
    final Pointer<Utf16> lpVerb = verb.toNativeUtf16();
    final Pointer<Utf16> lpParams = args.isEmpty ? nullptr : args.toNativeUtf16();

    final Pointer<SHELLEXECUTEINFO> sei = calloc<SHELLEXECUTEINFO>()
      ..ref.cbSize = sizeOf<SHELLEXECUTEINFO>()
      ..ref.fMask = 0x00000000
      ..ref.hwnd = NULL
      ..ref.lpVerb = lpVerb
      ..ref.lpFile = lpFile
      ..ref.lpParameters = lpParams == nullptr ? nullptr : lpParams
      ..ref.lpDirectory = nullptr
      ..ref.nShow = SW_SHOWNORMAL;

    try {
      return ShellExecuteEx(sei) != 0;
    } finally {
      free(lpFile);
      free(lpVerb);
      if (lpParams != nullptr) free(lpParams);
      free(sei);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper: "exe args" → ("exe", "args")
  // ──────────────────────────────────────────────────────────────────────────

  static (String exe, String args) _splitCommand(String command) {
    command = command.trim();

    if (command.startsWith('"')) {
      final int closing = command.indexOf('"', 1);
      if (closing == -1) return (command, '');
      return (
        command.substring(1, closing),
        command.substring(closing + 1).trim(),
      );
    }

    final int spaceIdx = command.indexOf(' ');
    if (spaceIdx == -1) return (command, '');
    return (
      command.substring(0, spaceIdx),
      command.substring(spaceIdx + 1).trim(),
    );
  }
}
