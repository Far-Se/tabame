import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/classes/screen_draw_hotkeys.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';
import '../../widgets/windows_scroll.dart';

class SpotlightButton extends StatelessWidget {
  const SpotlightButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Spotlight Controls",
      icon: const Icon(Icons.no_flash),
      hoverColor: Design.accentHue(58, saturation: 0.92),
      onTap: () => showQuickMenuModal(
        context: context,
        maxWidth: 430,
        child: const SpotlightPanel(),
      ),
    );
  }
}

class SpotlightPanel extends StatefulWidget {
  const SpotlightPanel({super.key});

  @override
  State<SpotlightPanel> createState() => _SpotlightPanelState();
}

class _SpotlightPanelState extends State<SpotlightPanel> {
  static const List<ScreenDrawHotkeyAction> _spotlightActions = <ScreenDrawHotkeyAction>[
    ScreenDrawHotkeyAction.spotlightEnable,
    ScreenDrawHotkeyAction.spotlightSetActiveWindow,
    ScreenDrawHotkeyAction.spotlightRaiseBlurSigma,
    ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma,
    ScreenDrawHotkeyAction.spotlightRaiseDimOpacity,
    ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity,
    ScreenDrawHotkeyAction.spotlightClose,
  ];

  static const Map<ScreenDrawHotkeyAction, IconData> _hotkeyIcons = <ScreenDrawHotkeyAction, IconData>{
    ScreenDrawHotkeyAction.spotlightEnable: Icons.visibility_outlined,
    ScreenDrawHotkeyAction.spotlightSetActiveWindow: Icons.center_focus_strong,
    ScreenDrawHotkeyAction.spotlightRaiseBlurSigma: Icons.blur_on,
    ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma: Icons.blur_off,
    ScreenDrawHotkeyAction.spotlightRaiseDimOpacity: Icons.brightness_6_rounded,
    ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity: Icons.brightness_5_rounded,
    ScreenDrawHotkeyAction.spotlightClose: Icons.close_rounded,
  };

  static const Map<ScreenDrawHotkeyAction, String> _hotkeyDescriptions = <ScreenDrawHotkeyAction, String>{
    ScreenDrawHotkeyAction.spotlightEnable: "Toggle the spotlight overlay",
    ScreenDrawHotkeyAction.spotlightSetActiveWindow: "Spotlight the current foreground window",
    ScreenDrawHotkeyAction.spotlightRaiseBlurSigma: "Increase the outside blur",
    ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma: "Decrease the outside blur",
    ScreenDrawHotkeyAction.spotlightRaiseDimOpacity: "Increase the outside dimming",
    ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity: "Decrease the outside dimming",
    ScreenDrawHotkeyAction.spotlightClose: "Close the Spotlight overlay",
  };

  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _isRunning = Win32.findWindow("Tabame Spotlight") != 0;
  }

  void _toggleSpotlight() {
    final int spotlightHwnd = Win32.findWindow("Tabame Spotlight");
    if (spotlightHwnd != 0) {
      Win32.closeWindow(spotlightHwnd);
      if (mounted) setState(() => _isRunning = false);
      return;
    }

    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    QuickMenuFunctions.hideQuickMenu();
    WinUtils.startTabame(closeCurrent: false, arguments: "-spotlight");
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(
          title: "Spotlight",
          icon: Icons.no_flash,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildToggleCard(),
                    const SizedBox(height: 12),
                    _buildSectionLabel(),
                    const SizedBox(height: 6),
                    _buildInfoCard(),
                    const SizedBox(height: 8),
                    ..._spotlightActions.map(_buildHotkeyRow),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleCard() {
    final Color stateColor = _isRunning ? Design.accent : Design.text.withAlpha(140);

    return InkWell(
      onTap: _toggleSpotlight,
      borderRadius: BorderRadius.circular(10),
      hoverColor: Design.accent.withAlpha(10),
      splashColor: Design.accent.withAlpha(22),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: _isRunning ? Design.accent.withAlpha(14) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isRunning ? Design.accent.withAlpha(70) : Design.text.withAlpha(16),
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: stateColor.withAlpha(24),
                borderRadius: BorderRadius.circular(9),
              ),
              alignment: Alignment.center,
              child: Icon(
                _isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 17,
                color: stateColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Start / Stop Spotlight",
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 1.5,
                      fontWeight: FontWeight.w700,
                      color: Design.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isRunning ? "Overlay is active" : "Overlay is stopped",
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      color: Design.text.withAlpha(125),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _isRunning ? Design.accent.withAlpha(28) : Design.text.withAlpha(12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isRunning ? Design.accent.withAlpha(80) : Design.text.withAlpha(24),
                ),
              ),
              child: Text(
                _isRunning ? "STOP" : "START",
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: _isRunning ? Design.accent : Design.text.withAlpha(170),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel() {
    return Row(
      children: <Widget>[
        Icon(Icons.keyboard_alt_outlined, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          "SPOTLIGHT HOTKEYS",
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Design.accent.withAlpha(28),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            "${_spotlightActions.length}",
            style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.info_outline_rounded, size: 15, color: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Shortcuts can be changed in Settings > Hotkeys and work while Spotlight is running.",
              style: TextStyle(
                fontSize: Design.baseFontSize,
                height: 1.25,
                color: Design.text.withAlpha(165),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(ScreenDrawHotkeyAction action) {
    final ScreenDrawHotkeyBinding? binding = _bindingFor(action);
    final bool enabled = binding?.enabled ?? false;
    final String hotkey = enabled ? binding!.displayHotkey : "OFF";
    final Color hotkeyColor = enabled ? Design.accent : Design.text.withAlpha(105);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: hotkeyColor.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              _hotkeyIcons[action] ?? Icons.keyboard_alt_outlined,
              size: 14,
              color: hotkeyColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _hotkeyTitle(action),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w600,
                    color: Design.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _hotkeyDescriptions[action] ?? "Spotlight action",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    color: Design.text.withAlpha(115),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: hotkeyColor.withAlpha(enabled ? 24 : 10),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: hotkeyColor.withAlpha(enabled ? 55 : 18)),
            ),
            child: Text(
              hotkey,
              style: TextStyle(
                fontSize: Design.baseFontSize - 0.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: hotkeyColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ScreenDrawHotkeyBinding? _bindingFor(ScreenDrawHotkeyAction action) {
    for (final ScreenDrawHotkeyBinding binding in Boxes.screenDrawHotkeys) {
      if (binding.action == action) return binding;
    }
    return null;
  }

  String _hotkeyTitle(ScreenDrawHotkeyAction action) {
    if (action == ScreenDrawHotkeyAction.spotlightEnable) return "Start / stop Spotlight";
    return action.label.replaceFirst("Spotlight: ", "");
  }
}
