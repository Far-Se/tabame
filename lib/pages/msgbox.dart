import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes/boxes_base.dart';
import '../models/settings.dart';
import '../models/theme.dart';

const Size _messageBoxSize = Size(420, 180);

Future<void> showMessage(List<String> arguments) async {
  const WindowOptions windowOptions = WindowOptions(
    size: _messageBoxSize,
    minimumSize: _messageBoxSize,
    maximumSize: _messageBoxSize,
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: 'Tabame Message',
  );

  await Boxes.registerBoxes(justLoad: true);
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(MessageBoxApp(arguments));
}

class MessageBoxApp extends StatelessWidget {
  const MessageBoxApp(this.arguments, {super.key});

  final List<String> arguments;

  @override
  Widget build(BuildContext context) {
    ThemeMode scheduled = ThemeMode.system;
    final ThemeType themeType = globalSettings.themeType;
    if (themeType.index == 3) {
      scheduled = globalSettings.themeTypeMode == ThemeType.dark ? ThemeMode.dark : ThemeMode.light;
    }
    final ThemeMode themeMode =
        <ThemeMode>[ThemeMode.system, ThemeMode.light, ThemeMode.dark, scheduled][themeType.index];

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.getLightThemeData(),
      darkTheme: AppTheme.getDarkThemeData(context),
      themeMode: themeMode,
      home: MessageBoxWindow(arguments),
    );
  }
}

class MessageBoxWindow extends StatefulWidget {
  const MessageBoxWindow(this.arguments, {super.key});

  final List<String> arguments;

  @override
  State<MessageBoxWindow> createState() => _MessageBoxWindowState();
}

class _MessageBoxWindowState extends State<MessageBoxWindow> with WindowListener {
  late final _MessageArguments _message = _MessageArguments.fromArgs(widget.arguments);
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
      if (_message.speak.isNotEmpty) {
        Process.run(
          'powershell',
          <String>[
            '-WindowStyle',
            'Hidden',
            '-Command',
            "(New-Object -ComObject SAPI.SpVoice).Speak('${_message.speak.replaceAll("'", "''")}')",
          ],
        );
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
    final Color accent = Color(globalSettings.theme.accentColor);
    final Color panelBase = scheme.surface;
    final Color panelOutline = accent.withValues(alpha: 0.16);
    final Color panelGlow = accent.withValues(alpha: 0.10);
    final Color headerTint = Color.alphaBlend(accent.withValues(alpha: 0.12), panelBase.withValues(alpha: 0.98));
    final Color contentTint = Color.alphaBlend(accent.withValues(alpha: 0.05), panelBase.withValues(alpha: 0.94));
    final Color bodyText = scheme.onSurface.withValues(alpha: 0.86);
    final Color secondaryText = scheme.onSurface.withValues(alpha: 0.58);

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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: _messageBoxSize.width,
              height: _messageBoxSize.height,
              // padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.26),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: panelGlow,
                    blurRadius: 18,
                    spreadRadius: 1,
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
                            border: Border(bottom: BorderSide(color: scheme.onSurface.withValues(alpha: 0.08)))),
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
                              child: Icon(Icons.info_rounded, color: accent, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    _message.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.1,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tabame message',
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
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                          decoration: BoxDecoration(
                            color: contentTint,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    SingleChildScrollView(
                                      child: SelectableText(
                                        _message.message,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          height: 1.45,
                                          fontSize: 18,
                                          color: bodyText,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton(
                                  onPressed: _exit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: theme.colorScheme.surface,
                                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                    textStyle: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: const Text('OK'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

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
