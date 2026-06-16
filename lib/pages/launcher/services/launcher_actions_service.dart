part of '../../launcher_actions_panel.dart';

class LauncherActionsBuilder {
  static Future<List<LauncherAction>> build(
    BuildContext context,
    LauncherSearchResultItem item,
  ) async {
    if (item.isFile) {
      final bool isDir = item.entity is Directory;
      return isDir ? _buildFolderActions(item.entity!.path) : _buildFileActions(item.entity!.path);
    }
    if (item.isApp) return _buildAppActions(item.appResult!);
    if (item.isWindow) return _buildWindowActions(item.window!);
    if (item.isBookmark) return _buildBookmarkActions(context, item.bookmarkResult!);
    if (item.isNotion) return _buildNotionActions(item.notionResult!);
    if (item.quickAction != null) return _buildQuickActionActions(context, item.quickAction!);
    return <LauncherAction>[];
  }

  // == Files ==================================================================

  static IconData _iconForVerb(String verb) {
    switch (verb.toLowerCase()) {
      case 'open':
        return Icons.open_in_new_rounded;
      case 'edit':
        return Icons.edit_rounded;
      case 'print':
        return Icons.print_rounded;
      case 'delete':
        return Icons.delete_outline_rounded;
      case 'rename':
        return Icons.drive_file_rename_outline_rounded;
      case 'properties':
        return Icons.info_outline_rounded;
      case 'cut':
        return Icons.content_cut_rounded;
      case 'copy':
        return Icons.content_copy_rounded;
      case 'paste':
        return Icons.content_paste_rounded;
      case 'runas':
        return Icons.shield_outlined;
      default:
        return Icons.arrow_forward_ios_rounded;
    }
  }

  static Future<List<LauncherAction>> _buildFileActions(String path) async {
    final List<LauncherAction> actions = <LauncherAction>[
      // == Built-in primary actions ==
      LauncherAction(
        label: 'Open',
        icon: Icons.open_in_new_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          WinUtils.open(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run as Administrator',
        icon: Icons.shield_outlined,
        subtitle: 'Elevated privileges',
        onExecute: (_) {
          WinUtils.runAsAdmin(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run with Parameters',
        icon: Icons.tune_rounded,
        subtitle: 'Specify arguments before launching',
        keepPanelOpen: true,
        onExecute: (BuildContext ctx) async {
          final TextEditingController controller = TextEditingController();
          final String? args = await showDialog<String>(
            context: ctx,
            builder: (_) => _ParametersDialog(
              title: 'Run "${p.basename(path)}" with parameters',
              controller: controller,
            ),
          );
          controller.dispose();
          if (args == null) return;
          WinUtils.open(path, arguments: args);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open Containing Folder',
        icon: Icons.folder_open_rounded,
        onExecute: (_) {
          WinUtils.open('explorer.exe', arguments: '/select,"$path"', parseParamaters: true);
        },
      ),
      LauncherAction(
        label: 'Copy Path',
        icon: Icons.content_copy_rounded,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: path)),
      ),
      LauncherAction(
        label: 'Copy File',
        icon: Icons.content_paste_go_outlined,
        onExecute: (_) => ClipboardExtension.copyFile(path),
      ),
      LauncherAction(
        label: 'Copy Filename',
        icon: Icons.title_rounded,
        subtitle: p.basename(path),
        onExecute: (_) => Clipboard.setData(ClipboardData(text: p.basename(path))),
      ),
      const LauncherAction.separator(label: 'Shell'),
    ];

    // == Shell context-menu items ==
    final List<ShellMenuItem> shellActions = await ShellContextMenu.getMenuItems(path);
    final List<LauncherAction> newList = <LauncherAction>[];
    for (final ShellMenuItem action in shellActions) {
      if (<String>["Cut", "Copy"].contains(action.verb)) continue;
      newList.add(LauncherAction(
        label: action.label,
        icon: action.iconBytes == null ? _iconForVerb(action.label) : null,
        iconImage: action.iconBytes,
        onExecute: (_) => Win32.invokeShellMenuItem(path, Win32.hWnd, verb: action.verb, id: action.id),
      ));
    }
    actions.addAll(newList);

    if (shellActions.isEmpty) {
      // Graceful fallback when native bridge isn't available
      actions.addAll(<LauncherAction>[
        LauncherAction(
          label: 'Open with',
          icon: Icons.open_with_rounded,
          onExecute: (_) {
            WinUtils.open('shell:AppsFolder', arguments: '', parseParamaters: false);
            // The standard "Open With" dialog via openwith.exe
            WinUtils.open('openwith.exe', arguments: '"$path"', parseParamaters: true);
          },
        ),
        LauncherAction(
          label: 'Show Properties',
          icon: Icons.info_outline_rounded,
          onExecute: (_) {
            WinUtils.open('properties', arguments: path, parseParamaters: true);
          },
        ),
      ]);
    }

    return actions;
  }

  // == Folders ================================================================

  static Future<List<LauncherAction>> _buildFolderActions(String path) async {
    final List<LauncherAction> actions = <LauncherAction>[
      LauncherAction(
        label: 'Open in Explorer',
        icon: Icons.folder_open_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          WinUtils.open(path);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open Terminal Here',
        icon: Icons.terminal_rounded,
        subtitle: 'Windows Terminal / PowerShell',
        onExecute: (_) {
          // Try wt.exe (Windows Terminal), fall back to PowerShell
          try {
            WinUtils.open('wt.exe', arguments: '-d "$path"', parseParamaters: true);
          } catch (_) {
            WinUtils.runPowerShellDetachedVisible('', workingDirectory: path, keepOpen: true);
          }
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open CMD Here',
        icon: Icons.code_rounded,
        onExecute: (_) {
          WinUtils.open('cmd.exe', arguments: '/k cd /d "$path"', parseParamaters: true);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Open PowerShell Here',
        icon: Icons.terminal_rounded,
        onExecute: (_) {
          WinUtils.open(
            'powershell.exe',
            arguments: '-NoExit -Command "Set-Location \'$path\'"',
            parseParamaters: true,
          );
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy Path',
        icon: Icons.content_copy_rounded,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: path)),
      ),
      LauncherAction(
        label: 'Copy Folder',
        icon: Icons.content_paste_go_outlined,
        onExecute: (_) => ClipboardExtension.copyFolder(path),
      ),
      LauncherAction(
        label: 'Copy Folder Name',
        icon: Icons.title_rounded,
        subtitle: p.basename(path),
        onExecute: (_) => Clipboard.setData(ClipboardData(text: p.basename(path))),
      ),
      const LauncherAction.separator(label: 'Shell'),
    ];

    // == Shell context-menu items ==
    // final List<LauncherAction> shellActions = await Win32ContextMenuBridge.getActionsForPath(path);
    // actions.addAll(shellActions);

    final List<ShellMenuItem> shellActions = await ShellContextMenu.getMenuItems(path);
    final List<LauncherAction> newList = <LauncherAction>[];
    for (final ShellMenuItem action in shellActions) {
      if (<String>["Cut", "Copy"].contains(action.label)) continue;
      newList.add(LauncherAction(
        label: action.label,
        icon: action.iconBytes == null ? _iconForVerb(action.label) : null,
        iconImage: action.iconBytes,
        onExecute: (_) => Win32.invokeShellMenuItem(path, Win32.hWnd, verb: action.verb, id: action.id),
      ));
    }
    actions.addAll(newList);
    if (shellActions.isEmpty) {
      actions.addAll(<LauncherAction>[
        LauncherAction(
          label: 'Show Properties',
          icon: Icons.info_outline_rounded,
          onExecute: (_) {
            WinUtils.open('properties', arguments: path, parseParamaters: true);
          },
        ),
      ]);
    }

    return actions;
  }

  // == Apps ===================================================================

  static List<LauncherAction> _buildAppActions(LauncherAppResult app) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Launch',
        icon: Icons.launch_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          final String target = app.launchTarget;
          if (target.isNotEmpty) WinUtils.open(target, parseParamaters: false);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Launch as Administrator',
        icon: Icons.shield_outlined,
        subtitle: 'Elevated privileges',
        onExecute: (_) {
          final String target = app.launchTarget;
          if (target.isNotEmpty) WinUtils.runAsAdmin(target);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy App ID',
        icon: Icons.content_copy_rounded,
        subtitle: app.appUserModelId,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: app.appUserModelId)),
      ),
      if (app.subtitle.isNotEmpty)
        LauncherAction(
          label: 'Copy Executable Path',
          icon: Icons.content_copy_rounded,
          subtitle: app.subtitle,
          onExecute: (_) => Clipboard.setData(ClipboardData(text: app.subtitle)),
        ),
    ];
  }

  // == Windows ================================================================

  static List<LauncherAction> _buildWindowActions(Window window) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Focus Window',
        icon: Icons.open_in_full_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          Win32Window.activateWindow(window.hWnd);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Minimize',
        icon: Icons.minimize_rounded,
        onExecute: (_) {
          Win32Window.minimizeWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Maximize / Restore',
        icon: Icons.crop_square_rounded,
        onExecute: (_) {
          Win32Window.maximizeOrRestoreWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Close Window',
        icon: Icons.close_rounded,
        isDestructive: true,
        onExecute: (_) {
          Win32Window.closeWindow(window.hWnd);
        },
      ),
      LauncherAction(
        label: 'Copy Window Title',
        icon: Icons.content_copy_rounded,
        subtitle: window.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: window.title)),
      ),
      LauncherAction(
        label: 'Copy Process Name',
        icon: Icons.content_copy_rounded,
        subtitle: window.process.exe,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: window.process.exe)),
      ),
      if (window.process.exePath.isNotEmpty)
        LauncherAction(
          label: 'Open Executable Location',
          icon: Icons.folder_open_rounded,
          subtitle: window.process.exePath,
          onExecute: (_) {
            WinUtils.open(
              'explorer.exe',
              arguments: '/select,"${window.process.exePath}"',
              parseParamaters: true,
            );
          },
        ),
    ];
  }

  // == Bookmarks ==============================================================

  static Future<List<LauncherAction>> _buildBookmarkActions(
    BuildContext context,
    BookmarkSearchResult result,
  ) async {
    switch (result.kind) {
      case BookmarkResultKind.bookmark:
        return <LauncherAction>[
          LauncherAction(
            label: 'Open',
            icon: Icons.open_in_new_rounded,
            kbdHint: '↵',
            onExecute: (_) {
              WinUtils.open(result.bookmark!.stringToExecute, parseParamaters: true);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Copy URL / Path',
            icon: Icons.content_copy_rounded,
            subtitle: result.bookmark!.stringToExecute,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.bookmark!.stringToExecute)),
          ),
          LauncherAction(
            label: 'Copy Title',
            icon: Icons.title_rounded,
            subtitle: result.bookmark!.title,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.bookmark!.title)),
          ),
        ];

      case BookmarkResultKind.cliBook:
        return _buildCliActions(context, result.cli!);

      case BookmarkResultKind.appItem:
        return <LauncherAction>[
          LauncherAction(
            label: 'Launch',
            icon: Icons.launch_rounded,
            kbdHint: '↵',
            onExecute: (_) {
              WinUtils.open(result.app!.path, arguments: result.app!.arguments);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Launch as Administrator',
            icon: Icons.shield_outlined,
            onExecute: (_) {
              WinUtils.runAsAdmin(result.app!.path, arguments: result.app!.arguments);
              _closeLauncher();
            },
          ),
          LauncherAction(
            label: 'Copy Path',
            icon: Icons.content_copy_rounded,
            subtitle: result.app!.path,
            onExecute: (_) => Clipboard.setData(ClipboardData(text: result.app!.path)),
          ),
        ];
    }
  }

  // == CLI ====================================================================

  static List<LauncherAction> _buildCliActions(
    BuildContext context,
    CliBookItem cli,
  ) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Copy Command',
        icon: Icons.content_copy_rounded,
        kbdHint: '↵',
        subtitle: cli.value,
        onExecute: (_) {
          Clipboard.setData(ClipboardData(text: cli.value));
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run in PowerShell',
        icon: Icons.play_arrow_rounded,
        subtitle: 'Opens a visible PowerShell window',
        onExecute: (_) {
          WinUtils.runPowerShellDetachedVisible(cli.value, keepOpen: true);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Run with Parameters',
        icon: Icons.tune_rounded,
        subtitle: 'Fill variables & pick working directory',
        keepPanelOpen: true,
        onExecute: (BuildContext ctx) {
          showModalBottomSheet<void>(
            context: ctx,
            barrierColor: Colors.transparent,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CliRunSheet(cliItem: cli),
          );
        },
      ),
      LauncherAction(
        label: 'Run in Specific Folder',
        icon: Icons.folder_special_rounded,
        subtitle: 'Pick a working directory then run',
        onExecute: (_) async {
          _closeLauncher();

          // final DirectoryPicker picker = DirectoryPicker()..title = 'Select Working Directory';
          // final Directory? dir = picker.getDirectory();
          // if (dir == null || dir.path.isEmpty) return;
          // if (mounted) setState(() => _workingDirectory = dir.path);
          ///
          final DirectoryPicker picker = DirectoryPicker()..title = 'Select Working Directory';
          final Directory? dir = picker.getDirectory();
          if (dir == null || dir.path.isEmpty) return;
          WinUtils.runPowerShellDetachedVisible(
            cli.value,
            workingDirectory: dir.path,
            keepOpen: true,
          );
        },
      ),
    ];
  }

  // == Notion =================================================================

  static List<LauncherAction> _buildNotionActions(NotionResult result) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Open in Browser',
        icon: Icons.open_in_new_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          if (result.url.isNotEmpty) WinUtils.open(result.url);
          _closeLauncher();
        },
      ),
      LauncherAction(
        label: 'Copy URL',
        icon: Icons.content_copy_rounded,
        subtitle: result.url,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: result.url)),
      ),
      LauncherAction(
        label: 'Copy Title',
        icon: Icons.title_rounded,
        subtitle: result.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: result.title)),
      ),
    ];
  }

  // == Quick Actions ==========================================================

  static List<LauncherAction> _buildQuickActionActions(
    BuildContext context,
    QuickActionMenuEntry entry,
  ) {
    return <LauncherAction>[
      LauncherAction(
        label: 'Execute "${entry.title}"',
        icon: Icons.bolt_rounded,
        kbdHint: '↵',
        onExecute: (_) {
          if (entry.onExecute != null) entry.onExecute!();
        },
      ),
      LauncherAction(
        label: 'Copy Name',
        icon: Icons.content_copy_rounded,
        subtitle: entry.title,
        onExecute: (_) => Clipboard.setData(ClipboardData(text: entry.title)),
      ),
    ];
  }

  // == Helpers ================================================================

  static void _closeLauncher() {
    // Mirrors the pattern used throughout launcher.dart.
    QuickMenuFunctions.hideQuickMenu();
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    user.launcherSearchText = '';
  }
}

class Win32Window {
  static void activateWindow(int hWnd) => Win32.activateWindow(hWnd);

  static void minimizeWindow(int hWnd) {
    // ShowWindow(hWnd, SW_MINIMIZE) - Win32 exposes this via win32 package.
    // Use the same WinUtils helper pattern as the rest of the app.
    try {
      WinUtils.minimizeWindow(hWnd);
    } catch (_) {
      // Fallback: just activate so the user sees *something* happened.
      Win32.activateWindow(hWnd);
    }
  }

  static void maximizeOrRestoreWindow(int hWnd) {
    try {
      WinUtils.maximizeOrRestoreWindow(hWnd);
    } catch (_) {}
  }

  static void closeWindow(int hWnd) {
    try {
      Win32.closeWindow(hWnd);
    } catch (_) {}
  }
}

// =============================================================================
// _ParametersDialog - simple "run with args" input dialog
// =============================================================================
