import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../../models/win32/win_utils.dart';
import '../../../services/awake_guard_service.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/quick_actions_item.dart';
import '../../widgets/windows_scroll.dart';

/// Always Awake, extended: tap opens the Awake Guard panel with conditional
/// keep-awake rules and "when it finishes" automations; right-click keeps the
/// old instant manual toggle.
class AlwaysAwakeButton extends StatefulWidget {
  const AlwaysAwakeButton({
    super.key,
  });

  @override
  State<AlwaysAwakeButton> createState() => _AlwaysAwakeButtonState();
}

class _AlwaysAwakeButtonState extends State<AlwaysAwakeButton> {
  @override
  void initState() {
    super.initState();
    AwakeGuard.revision.addListener(_onGuardChanged);
  }

  @override
  void dispose() {
    AwakeGuard.revision.removeListener(_onGuardChanged);
    super.dispose();
  }

  void _onGuardChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool engaged = Globals.alwaysAwake || AwakeGuard.isForcing;
    return QuickActionItem(
      message: "Awake Guard",
      icon: Icon(Icons.running_with_errors, color: engaged ? Colors.red : Theme.of(context).iconTheme.color),
      onTap: () => showQuickMenuModal(
        context: context,
        child: const AwakeGuardPanel(),
      ),
      onSecondaryTap: () {
        Globals.alwaysAwake = !Globals.alwaysAwake;
        WinUtils.alwaysAwakeRun(Globals.alwaysAwake);
        setState(() {});
      },
    );
  }
}

class AwakeGuardPanel extends StatefulWidget {
  const AwakeGuardPanel({super.key});

  @override
  State<AwakeGuardPanel> createState() => _AwakeGuardPanelState();
}

enum _AddMode { none, awakeProcess, automationProcess }

class _AwakeGuardPanelState extends State<AwakeGuardPanel> {
  _AddMode _addMode = _AddMode.none;
  AwakeAutomationAction _pendingAction = AwakeAutomationAction.notify;
  List<String> _runningProcesses = <String>[];
  final TextEditingController _filterController = TextEditingController();

  static const List<int> _thresholds = <int>[50 * 1024, 200 * 1024, 1024 * 1024, 5 * 1024 * 1024];

  @override
  void initState() {
    super.initState();
    AwakeGuard.revision.addListener(_onGuardChanged);
  }

  @override
  void dispose() {
    AwakeGuard.revision.removeListener(_onGuardChanged);
    _filterController.dispose();
    super.dispose();
  }

  void _onGuardChanged() {
    if (mounted) setState(() {});
  }

  void _openPicker(_AddMode mode) {
    final List<String> processes = AwakeGuard.listRunningProcesses().toList()..sort();
    setState(() {
      _addMode = mode;
      _filterController.clear();
      _runningProcesses = processes;
    });
  }

  void _pickProcess(String exe) {
    if (_addMode == _AddMode.awakeProcess) {
      AwakeGuard.addProcessRule(exe);
    } else if (_addMode == _AddMode.automationProcess) {
      AwakeGuard.addProcessAutomation(exe, _pendingAction);
    }
    setState(() => _addMode = _AddMode.none);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: C.stretch,
      children: <Widget>[
        const PanelHeader(
          title: "Awake Guard",
          icon: Icons.running_with_errors,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                shrinkWrap: true,
                children: <Widget>[
                  _buildManualCard(),
                  const SizedBox(height: 10),
                  _buildSectionLabel("KEEP AWAKE WHILE", Icons.bolt_rounded,
                      AwakeGuard.processRules.length + (AwakeGuard.networkRule != null ? 1 : 0)),
                  const SizedBox(height: 6),
                  for (final ProcessAwakeRule rule in AwakeGuard.processRules) _buildProcessRuleRow(rule),
                  _buildNetworkRuleRow(),
                  if (_addMode == _AddMode.awakeProcess)
                    _buildProcessPicker()
                  else
                    _buildAddRow("Add process condition", () => _openPicker(_AddMode.awakeProcess)),
                  const SizedBox(height: 10),
                  _buildSectionLabel("WHEN IT FINISHES", Icons.flag_rounded,
                      AwakeGuard.processAutomations.length + (AwakeGuard.networkAutomation != null ? 1 : 0)),
                  const SizedBox(height: 6),
                  for (final ProcessAutomation automation in AwakeGuard.processAutomations)
                    _buildAutomationRow(automation),
                  _buildNetworkAutomationRow(),
                  if (_addMode == _AddMode.automationProcess)
                    _buildAutomationPicker()
                  else
                    _buildAddRow("Add finish automation", () => _openPicker(_AddMode.automationProcess)),
                  const SizedBox(height: 10),
                  _buildStatusStrip(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- manual toggle ---------------------------------------------------------

  Widget _buildManualCard() {
    final bool on = Globals.alwaysAwake;
    return InkWell(
      onTap: () {
        Globals.alwaysAwake = !Globals.alwaysAwake;
        WinUtils.alwaysAwakeRun(Globals.alwaysAwake);
        AwakeGuard.revision.value++;
        setState(() {});
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: on ? Design.accent.withAlpha(14) : Design.text.withAlpha(7),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.coffee_rounded, size: 16, color: on ? Design.accent : Design.text.withAlpha(150)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: C.start,
                children: <Widget>[
                  Text(
                    "Always awake",
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.w700, color: Design.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Manual override — ignores all conditions below",
                    style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(120)),
                  ),
                ],
              ),
            ),
            _buildMetaChip(on ? "ON" : "OFF", active: on),
          ],
        ),
      ),
    );
  }

  // --- shared bits -------------------------------------------------------------

  Widget _buildSectionLabel(String label, IconData icon, int count) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label,
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
          decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
          child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildMetaChip(String text, {bool active = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: (active ? Design.accent : Design.text).withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: Design.baseFontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: active ? Design.accent : Design.text.withAlpha(130),
        ),
      ),
    );
  }

  Widget _buildRuleShell({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: child,
    );
  }

  Widget _buildRemoveButton(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.close_rounded, size: 14, color: Design.text.withAlpha(120)),
      ),
    );
  }

  Widget _buildAddRow(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(Icons.add_rounded, size: 14, color: Design.accent),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                  fontSize: Design.baseFontSize + 0.5, fontWeight: FontWeight.w600, color: Design.accent),
            ),
          ],
        ),
      ),
    );
  }

  // --- keep-awake rules ---------------------------------------------------------

  Widget _buildProcessRuleRow(ProcessAwakeRule rule) {
    return _buildRuleShell(
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rule.isRunning ? Colors.greenAccent.shade400 : Design.text.withAlpha(60),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              rule.exe,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
            ),
          ),
          _buildMetaChip(rule.isRunning ? "RUNNING" : "NOT RUNNING", active: rule.isRunning),
          const SizedBox(width: 4),
          _buildRemoveButton(() => AwakeGuard.removeProcessRule(rule)),
        ],
      ),
    );
  }

  Widget _buildNetworkRuleRow() {
    final NetworkAwakeRule? rule = AwakeGuard.networkRule;
    return _buildRuleShell(
      child: Row(
        children: <Widget>[
          Icon(Icons.swap_vert_rounded, size: 14, color: rule != null ? Design.accent : Design.text.withAlpha(110)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "Network transfer active",
              style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
            ),
          ),
          for (final int threshold in _thresholds)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: InkWell(
                onTap: () => AwakeGuard.setNetworkRule(
                  rule?.thresholdBytesPerSec == threshold ? null : NetworkAwakeRule(threshold),
                ),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: rule?.thresholdBytesPerSec == threshold ? Design.accent.withAlpha(28) : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: rule?.thresholdBytesPerSec == threshold
                          ? Design.accent.withAlpha(80)
                          : Design.text.withAlpha(20),
                    ),
                  ),
                  child: Text(
                    AwakeGuard.formatRate(threshold.toDouble()).replaceAll('.0', ''),
                    style: TextStyle(
                      fontSize: Design.baseFontSize - 0.5,
                      fontWeight: FontWeight.w600,
                      color: rule?.thresholdBytesPerSec == threshold ? Design.accent : Design.text.withAlpha(140),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- automations ---------------------------------------------------------------

  Widget _buildAutomationRow(ProcessAutomation automation) {
    return _buildRuleShell(
      child: Row(
        children: <Widget>[
          Icon(Icons.outlined_flag_rounded, size: 14, color: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: automation.exe, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: " exits → ", style: TextStyle(color: Design.text.withAlpha(130))),
                  TextSpan(text: automation.action.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
            ),
          ),
          _buildMetaChip(automation.seenRunning ? "ARMED" : "WAITING", active: automation.seenRunning),
          const SizedBox(width: 4),
          _buildRemoveButton(() => AwakeGuard.removeProcessAutomation(automation)),
        ],
      ),
    );
  }

  Widget _buildNetworkAutomationRow() {
    final NetworkAutomation? automation = AwakeGuard.networkAutomation;
    if (automation == null) return const SizedBox.shrink();
    return _buildRuleShell(
      child: Row(
        children: <Widget>[
          Icon(Icons.download_done_rounded, size: 14, color: Design.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(text: "Network idles ", style: TextStyle(color: Design.text.withAlpha(130))),
                  TextSpan(
                      text: "(< ${AwakeGuard.formatRate(automation.thresholdBytesPerSec.toDouble())})",
                      style: TextStyle(color: Design.text.withAlpha(130))),
                  TextSpan(text: " → ", style: TextStyle(color: Design.text.withAlpha(130))),
                  TextSpan(text: automation.action.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
            ),
          ),
          _buildMetaChip(automation.armed ? "ARMED" : "WAITING", active: automation.armed),
          const SizedBox(width: 4),
          _buildRemoveButton(() => AwakeGuard.setNetworkAutomation(null)),
        ],
      ),
    );
  }

  // --- add pickers ------------------------------------------------------------------

  Widget _buildActionChips() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: <Widget>[
        for (final AwakeAutomationAction action in AwakeAutomationAction.values)
          InkWell(
            onTap: () => setState(() => _pendingAction = action),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _pendingAction == action ? Design.accent.withAlpha(28) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _pendingAction == action ? Design.accent.withAlpha(80) : Design.text.withAlpha(20),
                ),
              ),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w600,
                  color: _pendingAction == action ? Design.accent : Design.text.withAlpha(150),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildProcessPicker({bool withActions = false}) {
    final String filter = _filterController.text.toLowerCase();
    final List<String> filtered =
        _runningProcesses.where((String exe) => filter.isEmpty || exe.contains(filter)).take(8).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.accent.withAlpha(30)),
      ),
      child: Column(
        crossAxisAlignment: C.start,
        children: <Widget>[
          if (withActions) ...<Widget>[
            _buildActionChips(),
            const SizedBox(height: 8),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _filterController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (String value) {
                    if (filtered.isNotEmpty) {
                      _pickProcess(filtered.first);
                    } else if (value.trim().isNotEmpty) {
                      _pickProcess(value);
                    }
                  },
                  style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: "Filter running processes or type an exe name…",
                    hintStyle: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(100)),
                    border: InputBorder.none,
                  ),
                ),
              ),
              _buildRemoveButton(() => setState(() => _addMode = _AddMode.none)),
            ],
          ),
          Divider(height: 8, color: Design.text.withAlpha(20)),
          for (final String exe in filtered)
            InkWell(
              onTap: () => _pickProcess(exe),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.memory_rounded, size: 12, color: Design.text.withAlpha(110)),
                    const SizedBox(width: 6),
                    Text(exe, style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text)),
                  ],
                ),
              ),
            ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                "No running process matches — Enter adds it anyway (armed once it starts).",
                style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(110)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAutomationPicker() {
    return Column(
      crossAxisAlignment: C.start,
      children: <Widget>[
        _buildProcessPicker(withActions: true),
        _buildAddRow(
          "…or fire when network idles (${AwakeGuard.formatRate(200 * 1024.0)} threshold)",
          () {
            AwakeGuard.setNetworkAutomation(NetworkAutomation(200 * 1024, _pendingAction));
            setState(() => _addMode = _AddMode.none);
          },
        ),
      ],
    );
  }

  // --- status -----------------------------------------------------------------------

  Widget _buildStatusStrip() {
    final bool engaged = AwakeGuard.isForcing || Globals.alwaysAwake;
    final String network = AwakeGuard.lastNetworkBytesPerSec >= 0
        ? "  ·  net ${AwakeGuard.formatRate(AwakeGuard.lastNetworkBytesPerSec)}"
        : "";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: engaged ? Design.accent.withAlpha(14) : Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: engaged ? Design.accent.withAlpha(50) : Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            engaged ? Icons.bolt_rounded : Icons.bedtime_outlined,
            size: 14,
            color: engaged ? Design.accent : Design.text.withAlpha(120),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "${Globals.alwaysAwake ? "Keeping awake — manual override" : AwakeGuard.statusLine}$network",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w600,
                color: engaged ? Design.accent : Design.text.withAlpha(140),
              ),
            ),
          ),
          Text(
            "session only",
            style: TextStyle(fontSize: Design.baseFontSize - 1, color: Design.text.withAlpha(90)),
          ),
        ],
      ),
    );
  }
}
