import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/system_power.dart';
import '../../widgets/panel_header.dart';

/// Modal listing Windows power/session commands (shutdown, restart, log off …).
///
/// Opened by right-clicking the QuickMenu settings button. Destructive actions
/// arm on the first tap and fire on the second; harmless ones run immediately.
class SystemPowerWidget extends StatefulWidget {
  const SystemPowerWidget({super.key});

  @override
  State<SystemPowerWidget> createState() => _SystemPowerWidgetState();
}

class _SystemPowerWidgetState extends State<SystemPowerWidget> {
  String? _armedId;

  void _run(SystemPowerAction action) {
    if (action.isDestructive && _armedId != action.id) {
      setState(() => _armedId = action.id);
      return;
    }
    Navigator.of(context).maybePop();
    QuickMenuFunctions.hideQuickMenu();
    action.execute();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(title: "System Power", icon: Icons.power_settings_new_rounded),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final SystemPowerAction action in SystemPowerAction.all)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _PowerRow(
                        action: action,
                        armed: _armedId == action.id,
                        onTap: () => _run(action),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PowerRow extends StatelessWidget {
  const _PowerRow({
    required this.action,
    required this.armed,
    required this.onTap,
  });

  final SystemPowerAction action;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final Color accent = armed ? scheme.error : Design.accent;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: accent.withAlpha(armed ? 28 : 14),
            border: Border.all(color: accent.withAlpha(armed ? 90 : 36)),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(armed ? Icons.warning_amber_rounded : action.icon, size: 18, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      armed ? "Tap again to ${action.label.toLowerCase()}" : action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: armed ? scheme.error : Design.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      armed ? "Confirm — this closes your session" : action.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: (armed ? scheme.error : Design.text).withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.keyboard_return_rounded, size: 14, color: Design.text.withAlpha(90)),
            ],
          ),
        ),
      ),
    );
  }
}
