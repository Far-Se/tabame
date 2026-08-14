import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/system_power.dart';
import '../../../services/elevation_service.dart';
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
  final ElevationService _elevationService = ElevationService.forCurrentProfile();
  bool _elevationBusy = false;

  void _run(SystemPowerAction action) {
    if (action.isDestructive && _armedId != action.id) {
      setState(() => _armedId = action.id);
      return;
    }
    Navigator.of(context).maybePop();
    QuickMenuFunctions.hideQuickMenu();
    action.execute();
  }

  Future<void> _restartQuickMenuElevated() async {
    if (_elevationBusy) return;
    if (_elevationService.readPrivilegeStatus().isElevated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('QuickMenu is already running elevated.')),
      );
      return;
    }
    setState(() => _elevationBusy = true);
    final ElevationRequestResult result = await _elevationService.launchApplicationElevated(
      executable: Platform.resolvedExecutable,
      arguments: Globals.elevatedQuickMenuArgument,
    );
    if (!mounted) return;
    setState(() => _elevationBusy = false);
    if (result.didLaunch) {
      Navigator.of(context).maybePop();
      await QuickMenuFunctions.hideQuickMenu();
      Future<void>.delayed(const Duration(milliseconds: 300), () => exit(0));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    // final bool elevationAvailable = _elevationService.capability.isAvailable;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(title: "System Power", icon: Icons.power_settings_new_rounded),
        // if (elevationAvailable)
        //   Padding(
        //     padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        //     child: OutlinedButton.icon(
        //       onPressed: _elevationBusy ? null : _restartQuickMenuElevated,
        //       icon: const Icon(Icons.shield_outlined, size: 17),
        //       label: Text(_elevationBusy ? 'REQUESTING UAC…' : 'RUN QUICKMENU AS ADMINISTRATOR'),
        //     ),
        //   ),
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
