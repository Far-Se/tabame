import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../widgets/quick_actions_item.dart';

// ============================================================
// Button that lives in the quick-menu bar
// ============================================================

class TimersButton extends StatefulWidget {
  const TimersButton({super.key});
  @override
  TimersButtonState createState() => TimersButtonState();
}

class TimersButtonState extends State<TimersButton> {
  String remainingTimer = "";

  @override
  void initState() {
    Boxes().loadLatestQuickTimers();
    super.initState();
    _checkForTimers();
    Timer.periodic(const Duration(seconds: 1), (_) => _checkForTimers());
  }

  void _checkForTimers() {
    if (Boxes.quickTimers.isNotEmpty) {
      Duration diff = Boxes.quickTimers[0].endTime.difference(DateTime.now());
      for (final QuickTimer time in Boxes.quickTimers) {
        final Duration newDiff = time.endTime.difference(DateTime.now());
        if (newDiff < diff) diff = newDiff;
      }
      remainingTimer = diff.inMinutes != 0
          ? "${diff.inSeconds % 60 < 30 ? diff.inMinutes % 60 : (diff.inMinutes % 60) + 1}m"
          : "${(diff.inSeconds % 60)}s";
      if (mounted) setState(() {});
    } else if (remainingTimer != "") {
      remainingTimer = "";
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Timers",
      icon: Boxes.quickTimers.isNotEmpty
          ? Align(
              alignment: AlignmentGeometry.center,
              child: Text(
                remainingTimer,
                softWrap: false,
                style: const TextStyle(fontSize: 9, overflow: TextOverflow.fade),
              ),
            )
          : const Icon(Icons.timer_sharp),
      onTap: () => showQuickMenuModal(
        context: context,
        child: const TimersWidget(),
      ),
    );
  }
}

// ============================================================
// Main panel
// ============================================================

class TimersWidget extends StatefulWidget {
  const TimersWidget({super.key});
  @override
  TimersWidgetState createState() => TimersWidgetState();
}

class TimersWidgetState extends State<TimersWidget> {
  final TextEditingController _msgCtrl = TextEditingController();
  final TextEditingController _durCtrl = TextEditingController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    _durCtrl.dispose();
    super.dispose();
  }

  void _createTimer() {
    // Type is always "Message" (index 1)
    const int timerType = 1;
    Boxes().addQuickTimer(
      _msgCtrl.text.isEmpty ? "${_durCtrl.text} Minute Timer" : _msgCtrl.text,
      int.tryParse(_durCtrl.text) ?? 1,
      timerType,
    );

    if (_msgCtrl.text.isNotEmpty) {
      final SavedQuickTimers timer = SavedQuickTimers()
        ..name = _msgCtrl.text
        ..minutes = int.tryParse(_durCtrl.text) ?? 1
        ..type = 1; // Message
      Boxes.lastQuickTimers.add(timer);
      Boxes.lastQuickTimers.sort((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes);
      if (Boxes.lastQuickTimers.length > 20) {
        Boxes.lastQuickTimers.removeRange(0, Boxes.lastQuickTimers.length - 20);
      }
      Boxes().saveLatestQuickTimers();
    }

    context.findAncestorStateOfType<TimersButtonState>()?.setState(() {});
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(14, 15, 14, 0),
          child: _CreateTimerForm(
            accent: accent,
            durCtrl: _durCtrl,
            msgCtrl: _msgCtrl,
            onChanged: () => setState(() {}),
            onCreate: _createTimer,
          ),
        ),
        // ── Body ────────────────────────────────────────────────
        Flexible(
          child: SingleChildScrollView(
            controller: ScrollController(),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Create-timer form

                // Active timers
                if (Boxes.quickTimers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 5),
                  _SectionLabel(label: "Active", accent: accent, count: Boxes.quickTimers.length),
                  const SizedBox(height: 4),
                  ListTimersWidget(onChanged: () => setState(() {})),
                ],
                // History
                if (Boxes.lastQuickTimers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  _SectionLabel(label: "Recent", accent: accent, count: Boxes.lastQuickTimers.length),
                  const SizedBox(height: 4),
                  ListLatestQuickTimers(
                    onTriggered: () => setState(() {}),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Section label (Active / Recent)
// ============================================================

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.accent, required this.count});
  final String label;
  final Color accent;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: accent.withAlpha(210),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: accent.withAlpha(28),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            "$count",
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: accent.withAlpha(180)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Divider(height: 1, thickness: 1, color: accent.withAlpha(40))),
      ],
    );
  }
}

// ============================================================
// Create-timer form
// ============================================================

class _CreateTimerForm extends StatelessWidget {
  const _CreateTimerForm({
    required this.accent,
    required this.durCtrl,
    required this.msgCtrl,
    required this.onChanged,
    required this.onCreate,
  });

  final Color accent;
  final TextEditingController durCtrl;
  final TextEditingController msgCtrl;
  final VoidCallback onChanged;
  final VoidCallback onCreate;

  InputDecoration _inputDec(String hint, Color accent) => InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.withAlpha(140)),
        filled: true,
        fillColor: accent.withAlpha(12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent.withAlpha(50), width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent.withAlpha(40), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: accent.withAlpha(160), width: 1.5),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bool canCreate = durCtrl.text.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Minutes + Message row
        Row(
          children: <Widget>[
            SizedBox(
              width: 50,
              child: TextField(
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textInputAction: TextInputAction.done,
                decoration: _inputDec("Min", accent),
                style: const TextStyle(fontSize: 12),
                controller: durCtrl,
                autofocus: true,
                onChanged: (_) => onChanged(),
                onSubmitted: (_) {
                  if (durCtrl.text.isNotEmpty) {
                    onCreate();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                decoration: _inputDec("Message (optional)", accent),
                style: const TextStyle(fontSize: 12),
                controller: msgCtrl,
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: canCreate ? 1.0 : 0.45,
              child: SizedBox(
                height: 26,
                child: IconButton(
                  style: Theme.of(context).elevatedButtonTheme.style?.copyWith(
                        backgroundColor: WidgetStateProperty.all(accent),
                        foregroundColor: WidgetStateProperty.all(Colors.white),
                        elevation: WidgetStateProperty.all(0),
                        padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 12)),
                        shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                  onPressed: canCreate ? onCreate : null,
                  icon: const Icon(Icons.add_rounded, size: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// Active timers list  (live countdown)
// ============================================================

class ListTimersWidget extends StatefulWidget {
  const ListTimersWidget({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<ListTimersWidget> createState() => _ListTimersWidgetState();
}

class _ListTimersWidgetState extends State<ListTimersWidget> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: List<Widget>.generate(Boxes.quickTimers.length, (int i) {
        final QuickTimer qt = Boxes.quickTimers[i];
        final Duration diff = qt.endTime.difference(DateTime.now());
        final bool overdue = diff.isNegative;
        final String timeLabel = overdue
            ? "Done"
            : diff.inMinutes > 0
                ? "${diff.inMinutes}m ${diff.inSeconds % 60}s"
                : "${diff.inSeconds}s";

        return _ActiveTimerRow(
          name: qt.name,
          timeLabel: timeLabel,
          overdue: overdue,
          endTime: qt.endTime,
          accent: accent,
          onSurface: onSurface,
          onDelete: () {
            qt.timer?.cancel();
            Boxes.quickTimers.removeAt(i);
            Boxes().saveQuickTimers();
            widget.onChanged?.call();
            setState(() {});
          },
        );
      }),
    );
  }
}

class _ActiveTimerRow extends StatefulWidget {
  const _ActiveTimerRow({
    required this.name,
    required this.timeLabel,
    required this.overdue,
    required this.endTime,
    required this.accent,
    required this.onSurface,
    required this.onDelete,
  });
  final String name;
  final String timeLabel;
  final bool overdue;
  final DateTime endTime;
  final Color accent;
  final Color onSurface;
  final VoidCallback onDelete;

  @override
  State<_ActiveTimerRow> createState() => _ActiveTimerRowState();
}

class _ActiveTimerRowState extends State<_ActiveTimerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final Color rowAccent = widget.overdue ? Colors.orange : widget.accent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered ? rowAccent.withAlpha(60) : rowAccent.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: rowAccent.withAlpha(50), width: 1),
        ),
        child: Row(
          children: <Widget>[
            // Countdown chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: rowAccent.withAlpha(35),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.timeLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: rowAccent),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.name,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: widget.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    "ends ${widget.endTime.hour.formatZeros()}:${widget.endTime.minute.formatZeros()}",
                    style: TextStyle(fontSize: 10, color: widget.onSurface.withAlpha(120)),
                  ),
                ],
              ),
            ),
            // Delete button
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _hovered ? 1.0 : 0.35,
              child: InkWell(
                onTap: widget.onDelete,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 14, color: widget.onSurface.withAlpha(180)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Recent timers list
// ============================================================

class ListLatestQuickTimers extends StatefulWidget {
  const ListLatestQuickTimers({super.key, required this.onTriggered});
  final VoidCallback onTriggered;

  @override
  ListLatestQuickTimersState createState() => ListLatestQuickTimersState();
}

class ListLatestQuickTimersState extends State<ListLatestQuickTimers> {
  @override
  void initState() {
    super.initState();
    Boxes.lastQuickTimers.sort((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final bool boldFont = globalSettings.theme.quickMenuBoldFont;

    return Column(
      children: List<Widget>.generate(Boxes.lastQuickTimers.length, (int i) {
        final SavedQuickTimers t = Boxes.lastQuickTimers[i];
        return _RecentTimerRow(
          name: t.name,
          minutes: t.minutes,
          accent: accent,
          onSurface: onSurface,
          boldFont: boldFont,
          onTap: () {
            Boxes().addQuickTimer(t.name, t.minutes, t.type);
            setState(() {});
            Timer(
              const Duration(milliseconds: 200),
              () => context.findAncestorStateOfType<TimersButtonState>()?.setState(() {}),
            );
            widget.onTriggered();
          },
          onDelete: () {
            Boxes.lastQuickTimers.removeAt(i);
            Boxes.lastQuickTimers.sort((SavedQuickTimers a, SavedQuickTimers b) => a.minutes - b.minutes);
            Boxes().saveLatestQuickTimers();
            setState(() {});
          },
        );
      }),
    );
  }
}

class _RecentTimerRow extends StatefulWidget {
  const _RecentTimerRow({
    required this.name,
    required this.minutes,
    required this.accent,
    required this.onSurface,
    required this.boldFont,
    required this.onTap,
    required this.onDelete,
  });
  final String name;
  final int minutes;
  final Color accent;
  final Color onSurface;
  final bool boldFont;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_RecentTimerRow> createState() => _RecentTimerRowState();
}

class _RecentTimerRowState extends State<_RecentTimerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: _hovered ? widget.accent.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                // Left accent bar
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: _hovered ? 2.5 : 0,
                  height: 14,
                  margin: EdgeInsets.only(right: _hovered ? 7 : 0),
                  decoration: BoxDecoration(
                    color: widget.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Duration pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: widget.accent.withAlpha(28),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    "${widget.minutes}m",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: widget.accent.withAlpha(200),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Name
                Expanded(
                  child: Text(
                    widget.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: widget.boldFont ? FontWeight.w500 : FontWeight.w300,
                      color: _hovered ? widget.onSurface : widget.onSurface.withAlpha(200),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Play icon on hover
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 1.0 : 0.0,
                  child: Icon(Icons.play_arrow_rounded, size: 13, color: widget.accent.withAlpha(170)),
                ),
                const SizedBox(width: 2),
                // Delete
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _hovered ? 0.7 : 0.25,
                  child: InkWell(
                    onTap: widget.onDelete,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(Icons.close_rounded, size: 12, color: widget.onSurface.withAlpha(160)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
