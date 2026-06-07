// ignore_for_file: public_member_api_docs, sort_constructors_first

import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/windows_scroll.dart';

class _AppOpacity {
  static const double subtle = 0.06;
  static const double border = 0.08;
  static const double borderEmphasis = 0.15;
  static const double accentFaint = 0.14;
  static const double textSecondary = 0.65;
}

// ---------------------------------------------------------------------------
// FAQ data
// ---------------------------------------------------------------------------

class _FaqItem {
  const _FaqItem({required this.question, required this.answer});
  final String question;
  final String answer;
}

const List<_FaqItem> _faqItems = <_FaqItem>[
  _FaqItem(
      question: "What is Tabame?",
      answer:
          "Tabame is a lightweight Windows utility that tries to replace the taskbar. It also includes extra features, such as Fancyshot, Screen Drawing and Recording, QuickGrid, QuickClick, Trktivity, Wizardly and more."),
  _FaqItem(
    question: "How do I open Tabame?",
    answer: "You set a hotkey to open QuickMenu preferably a mouse button and another hotkey to open Launcher.",
  ),
  _FaqItem(
    question: "Sometimes the app looks weird and I can not click on anything?",
    answer:
        "You can fix it by right clicking on the QuickMenu top left Logo (even if its not visible). This is caused by multiple async functions running at once when QuickMenu is shown and I can not duplicate it on Debug Mode, only on Release and it happens one time at few days, randomly.",
  ),
  _FaqItem(
    question: "Why does Tabame ask for administrator privileges?",
    answer:
        """Some features — such as closing protected system windows, forcing focus on elevated apps — require elevated permissions. You can enable "Run as Administrator" in Settings → Configuration. The app needs to be restarted.""",
  ),
  _FaqItem(
    question: "How do I make Tabame start with Windows?",
    answer: """
Go to Settings → Configuration and enable "Launch at Startup". Tabame will register a start-up shortcut in your shell startup folder automatically.""",
  ),
  _FaqItem(
    question: "Where are my settings stored?",
    answer:
        "All settings are saved in settings.json inside %LocalAppData%\\Tabame\\. You can open that folder directly from Settings → Data & Tools. To back up or migrate, simply copy that file.",
  ),
  _FaqItem(
    question: "How do I update Tabame?",
    answer:
        """Open Settings → System Status and press "Check for Updates". If a new version is available you can install it with one click via PowerShell, or download it manually from GitHub Releases.""",
  ),
  _FaqItem(
    question: "What is the Light Switch feature?",
    answer:
        "Light Switch automatically switches your Windows theme between light and dark mode. You can set fixed on/off times, or let Tabame calculate local sunrise and sunset based on your coordinates.",
  ),
  _FaqItem(
    question: "What is Wizardly?",
    answer:
        """Wizardly contains multiple tools, such as Text Search, Project Overview (count lines of code), Rename Files, Scan Folder Size, Context Menu Cleaner, Wallpaper Scheduler and Hosts Editor.""",
  ),
  _FaqItem(
    question: "How do I completely uninstall Tabame?",
    answer:
        """Go to Settings → Data & Tools and click "UNINSTALL TABAME". You will be asked to type a confirmation phrase. Tabame will then disable all integrations, remove its app-data folder, and delete its own executable.""",
  ),
  _FaqItem(
    question: "Tabame isn't responding to my hotkey. What should I try?",
    answer:
        """First make sure no other application has registered the same shortcut. If you enabled "Run as Administrator" at startup, Tabame must also be running as admin to intercept hotkeys from elevated windows. Finally, try restarting Tabame from the system tray.""",
  ),
  _FaqItem(
    question: "How can I report a bug or request a feature?",
    answer:
        """Use the "Send Feedback & Suggestions" button at the top of this page. It will open the GitHub Issues page where you can file a bug report or a feature request using the provided templates.""",
  ),
];

// ---------------------------------------------------------------------------
// Page widget
// ---------------------------------------------------------------------------

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  FaqPageState createState() => FaqPageState();
}

class FaqPageState extends State<FaqPage> {
  final Set<int> _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color background = userSettings.themeColors.background;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return WindowsScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // ── Header row ──────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _buildSectionTitle("Help"),
                      Text(
                        "Frequently Asked Questions",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Answers to the most common questions about Tabame.",
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 2,
                          color: onSurface.withValues(alpha: _AppOpacity.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ── Feedback button ─────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: () => WinUtils.open(
                    "https://github.com/Far-Se/tabame/issues/new/choose",
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: background,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.feedback_outlined, size: 16),
                  label: Text(
                    "Send Feedback & Suggestions",
                    style: entryStyle(null, fontSize: Design.baseFontSize + 2, color: User.theme.background),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── FAQ cards ───────────────────────────────────────────────────
            ...List<Widget>.generate(_faqItems.length, (int i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFaqCard(i, accent, onSurface),
              );
            }),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Section label (matches SettingsPage._buildSectionTitle) ──────────────

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: Design.baseFontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: _AppOpacity.textSecondary),
        ),
      ),
    );
  }

  // ── Individual FAQ card ───────────────────────────────────────────────────

  Widget _buildFaqCard(int index, Color accent, Color onSurface) {
    final bool isOpen = _expanded.contains(index);
    final _FaqItem item = _faqItems[index];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen
              ? accent.withValues(alpha: _AppOpacity.borderEmphasis)
              : onSurface.withValues(alpha: _AppOpacity.border),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: <Widget>[
            // ── Question row ───────────────────────────────────────────────
            InkWell(
              onTap: () {
                setState(() {
                  if (isOpen) {
                    _expanded.remove(index);
                  } else {
                    _expanded.add(index);
                  }
                });
              },
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(14),
                bottom: isOpen ? Radius.zero : const Radius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: <Widget>[
                    // Numbered badge
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: isOpen
                            ? accent.withValues(alpha: _AppOpacity.accentFaint)
                            : onSurface.withValues(alpha: _AppOpacity.subtle),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        "${index + 1}",
                        style: TextStyle(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w700,
                          color: isOpen ? accent : onSurface.withValues(alpha: _AppOpacity.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.question,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: isOpen ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: isOpen ? accent : onSurface.withValues(alpha: _AppOpacity.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Answer (animated) ──────────────────────────────────────────
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(54, 0, 16, 14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.03),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Divider(
                      color: onSurface.withValues(alpha: _AppOpacity.subtle),
                      height: 1,
                      thickness: 1,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.answer,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: isOpen ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }
}
