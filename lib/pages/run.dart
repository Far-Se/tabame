import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../models/classes/boxes/boxes_base.dart';
import '../models/settings.dart';
import '../models/theme.dart';
import '../models/win32/win32.dart' show Win32;
import '../logic/app_startup.dart';

const Size _windowSize = Size(480, 360);

/// Entry point: decides whether to run a command or show a simple message.
Future<void> showRunStatus(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppStartup.initialize();
  await windowManager.ensureInitialized();
  // Load settings (needed for theme)
  await Boxes.registerBoxes(justLoad: true);

  // Parse arguments
  final ArgParser parser = ArgParser();
  parser.parseArgs(arguments);
  final String runType = parser.getArg('run') ?? '';

  // If a command should be executed, run it BEFORE showing the window
  CommandResult? result;
  if (runType == 'shellMenuItem') {
    result = await _runShellMenuItem(parser);
    windowManager.close();
  }

  // Now create and show the window (with or without command result)
  const WindowOptions windowOptions = WindowOptions(
    size: _windowSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
    title: 'Tabame Command Runner',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(CommandRunnerApp(arguments, result));
}

/// Result of executing a shell command.
class CommandResult {
  final bool success;
  final String path;
  final String verb;
  final int id;
  final String errorMessage;

  CommandResult({
    required this.success,
    required this.path,
    required this.verb,
    required this.id,
    this.errorMessage = '',
  });
}

/// Executes the shell context menu action.
Future<CommandResult> _runShellMenuItem(ArgParser parser) async {
  final String path = parser.getArg('path') ?? '';
  final String verb = parser.getArg('verb') ?? '';
  final int id = int.tryParse(parser.getArg('id') ?? '-1') ?? -1;

  if (path.isEmpty) {
    return CommandResult(
      success: false,
      path: '',
      verb: verb,
      id: id,
      errorMessage: 'Missing -path argument',
    );
  }

  final int hWnd = Win32.hWnd;
  bool success = false;
  String errorMsg = '';

  try {
    success = await ShellContextMenu.invoke(
      path,
      hWnd,
      verb: verb.isNotEmpty ? verb : '',
      id: id != -1 ? id : -1,
    );
    if (!success) {
      errorMsg = 'Shell command returned false';
    }
  } catch (e) {
    success = false;
    errorMsg = e.toString();
  }

  return CommandResult(
    success: success,
    path: path,
    verb: verb,
    id: id,
    errorMessage: errorMsg,
  );
}

/// Main app widget (similar to original MessageBoxApp but with command info).
class CommandRunnerApp extends StatelessWidget {
  const CommandRunnerApp(this.arguments, this.result, {super.key});

  final List<String> arguments;
  final CommandResult? result;

  @override
  Widget build(BuildContext context) {
    ThemeMode scheduled = ThemeMode.system;
    final ThemeType themeType = userSettings.themeType;
    if (themeType.index == 3) {
      scheduled = userSettings.themeTypeMode == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;
    }
    final ThemeMode themeMode =
        <ThemeMode>[ThemeMode.system, ThemeMode.light, ThemeMode.dark, scheduled][themeType.index];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getLightThemeData(context),
      darkTheme: AppTheme.getDarkThemeData(context),
      themeMode: themeMode,
      home: CommandRunnerWindow(arguments, result),
    );
  }
}

/// The actual window (draggable, themed, etc.)
class CommandRunnerWindow extends StatefulWidget {
  const CommandRunnerWindow(this.arguments, this.result, {super.key});

  final List<String> arguments;
  final CommandResult? result;

  @override
  State<CommandRunnerWindow> createState() => _CommandRunnerWindowState();
}

class _CommandRunnerWindowState extends State<CommandRunnerWindow> with WindowListener {
  late final _MessageArguments _message = _MessageArguments.fromArgs(widget.arguments);
  late final FocusNode _focusNode = FocusNode();
  final GlobalKey _contentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  void _exit() {
    windowManager.close();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = userSettings.themeColors.accent;
    final Color panelBase = scheme.surface;
    final Color panelOutline = accent.withValues(alpha: 0.16);
    final Color panelGlow = accent.withValues(alpha: 0.10);
    final Color headerTint = Color.alphaBlend(accent.withValues(alpha: 0.12), panelBase.withValues(alpha: 0.98));
    final Color contentTint = Color.alphaBlend(accent.withValues(alpha: 0.05), panelBase.withValues(alpha: 0.94));
    final Color bodyText = scheme.onSurface.withValues(alpha: 0.86);
    final Color secondaryText = scheme.onSurface.withValues(alpha: 0.58);

    // Determine what to show in the content area
    String displayTitle = _message.title;
    String displayMessage = _message.message;
    bool isCommandResult = widget.result != null;

    if (isCommandResult) {
      final CommandResult cmd = widget.result!;
      displayTitle = cmd.success ? 'Command executed' : 'Command failed';
      displayMessage = '''
Path: ${cmd.path}
${cmd.verb.isNotEmpty ? 'Verb: ${cmd.verb}' : 'ID: ${cmd.id}'}
Status: ${cmd.success ? 'Success' : 'Failed'}
${cmd.errorMessage.isNotEmpty ? 'Error: ${cmd.errorMessage}' : ''}
''';
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: KeyboardListener(
        focusNode: _focusNode,
        onKeyEvent: (KeyEvent e) {
          if (e is KeyDownEvent &&
              (e.logicalKey == LogicalKeyboardKey.escape ||
                  e.logicalKey == LogicalKeyboardKey.enter ||
                  e.logicalKey == LogicalKeyboardKey.space)) {
            _exit();
          }
        },
        child: Center(
          child: Semantics(
            label: isCommandResult ? 'Command Result Dialog' : 'Alert Dialog',
            namesRoute: true,
            scopesRoute: true,
            explicitChildNodes: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double screenWidth = MediaQuery.of(context).size.width;
                  final double boxWidth = screenWidth < 500 ? screenWidth * 0.94 : 480.0;

                  return Container(
                    key: _contentKey,
                    width: boxWidth,
                    constraints: const BoxConstraints(maxWidth: 480),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: scheme.shadow.withValues(alpha: 0.18),
                          blurRadius: 32,
                          offset: const Offset(0, 16),
                        ),
                        BoxShadow(
                          color: panelGlow.withValues(alpha: 0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          panelBase.withValues(alpha: 0.98),
                          Color.alphaBlend(accent.withValues(alpha: 0.08), panelBase.withValues(alpha: 0.96)),
                        ],
                      ),
                      border: Border.all(color: panelOutline),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
                        color: panelBase.withValues(alpha: 0.88),
                      ),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (DragStartDetails details) {
                          windowManager.startDragging();
                        },
                        child: Column(
                          children: <Widget>[
                            // Header (same as original)
                            Container(
                              padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: <Color>[
                                    headerTint,
                                    Color.alphaBlend(accent.withValues(alpha: 0.04), panelBase.withValues(alpha: 0.94)),
                                  ],
                                ),
                                border: Border(bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08))),
                              ),
                              child: Row(
                                children: <Widget>[
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.13),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: accent.withValues(alpha: 0.22)),
                                    ),
                                    child: Icon(
                                      isCommandResult ? Icons.code_rounded : Icons.info_rounded,
                                      color: accent,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          displayTitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isCommandResult ? 'Command execution details' : 'Tabame message',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: secondaryText,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 1,
                              color: scheme.onSurface.withValues(alpha: 0.08),
                            ),
                            // Content area
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                                decoration: BoxDecoration(
                                  color: contentTint,
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    // Scrollable text area (supports selection)
                                    Flexible(
                                      child: SingleChildScrollView(
                                        child: SelectableText(
                                          displayMessage,
                                          textAlign: TextAlign.left,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            height: 1.45,
                                            fontSize: 16,
                                            color: bodyText,
                                            fontFamily: isCommandResult ? 'monospace' : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                      onPressed: _exit,
                                      style: FilledButton.styleFrom(
                                        backgroundColor: accent,
                                        foregroundColor: theme.colorScheme.surface,
                                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                                        elevation: 0,
                                        textStyle: theme.textTheme.labelLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      child: const Text('OK'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Legacy argument parser and message arguments (kept for backward compatibility).
class _MessageArguments {
  const _MessageArguments({
    required this.title,
    required this.message,
    required this.speak,
  });

  final String title;
  final String message;
  final String speak;

  factory _MessageArguments.fromArgs(List<String> args) {
    return _MessageArguments(
      title: _readValue(args, '-title', fallback: 'Tabame'),
      message: _readValue(args, '-message', fallback: 'No message provided.'),
      speak: _readValue(args, '-speak', fallback: ''),
    );
  }

  static String _readValue(List<String> args, String key, {required String fallback}) {
    final int index = args.lastIndexOf(key);
    if (index == -1 || index + 1 >= args.length) return fallback;
    final String value = args[index + 1].trim();
    if (value.startsWith('-')) return fallback;
    return value.isEmpty ? fallback : value;
  }
}

/// Simple argument parser (supports -key value or -key).
class ArgParser {
  final Map<String, String> _parsedArgs = <String, String>{};

  String? getArg(String key) {
    final String normalizedKey = key.startsWith('-') ? key.toLowerCase() : '-${key.toLowerCase()}';
    return _parsedArgs[normalizedKey];
  }

  void parseArgs(List<String> args) {
    _parsedArgs.clear();
    for (int i = 0; i < args.length; i++) {
      String arg = args[i];
      if (arg.startsWith('-')) {
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          _parsedArgs[arg.toLowerCase()] = args[i + 1];
          i++;
        } else {
          _parsedArgs[arg.toLowerCase()] = 'true';
        }
      }
    }
  }
}
