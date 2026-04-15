import 'package:flutter/material.dart';
import '../itzy/interface/quickmenu_bottom_bar.dart';
import '../itzy/interface/quickmenu_taskbar.dart';
import '../itzy/interface/quickmenu_quickactions.dart';
import '../itzy/interface/quickmenu_search.dart';
import 'quickmenu/general_settings.dart';
import 'quickmenu/custom_quickactions_settings.dart';
import 'quickmenu/appaudio_settings.dart';
import 'quickmenu/apps_settings.dart';
import 'views_interface.dart';

// ---------------------------------------------------------------------------
// Data model for a settings sub-page entry
// ---------------------------------------------------------------------------
class _SettingsPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;

  const _SettingsPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });
}

// ---------------------------------------------------------------------------
// Main widget — shows a link list, navigates to sub-pages
// ---------------------------------------------------------------------------
class QuickmenuSettings extends StatefulWidget {
  const QuickmenuSettings({super.key});

  @override
  QuickmenuSettingsState createState() => QuickmenuSettingsState();
}

class QuickmenuSettingsState extends State<QuickmenuSettings> {
  int? _selectedPage;

  late final List<_SettingsPage> _pages = <_SettingsPage>[
    _SettingsPage(
      title: "General Settings",
      subtitle: "QuickMenu appearance and behavior",
      icon: Icons.tune,
      builder: () => const QuickmenuGeneralSettings(),
    ),
    _SettingsPage(
      title: "QuickActions Order",
      subtitle: "Reorder top bar actions",
      icon: Icons.reorder,
      builder: () => const QuickmenuTopbarSettings(),
    ),
    _SettingsPage(
      title: "Taskbar Settings",
      subtitle: "Taskbar style and order",
      icon: Icons.view_list_outlined,
      builder: () => const QuickmenuTaskbarSettings(),
    ),
    _SettingsPage(
      title: "Bottom Bar & System",
      subtitle: "Pinned files, system tray icons, weather and powershell",
      icon: Icons.widgets_outlined,
      builder: () => const QuickmenuBottomBarSettings(),
    ),
    _SettingsPage(
      title: "File Search",
      subtitle: "File search settings",
      icon: Icons.search,
      builder: () => const QuickmenuFileSearchSettings(),
    ),
    _SettingsPage(
      title: "Grid View",
      subtitle: "Resize windows based on a grid",
      icon: Icons.view_module,
      builder: () => const QuickmenuGridViewSettings(),
    ),
    _SettingsPage(
      title: "Custom QuickActions",
      subtitle: "Edit and manage custom actions",
      icon: Icons.settings_input_component,
      builder: () => const QuickmenuCustomQuickActionsSettings(),
    ),
    _SettingsPage(
      title: "App Audio Controls",
      subtitle: "Custom media controls in TopBar (max 5)",
      icon: Icons.audio_file,
      builder: () => const QuickmenuAppAudioSettings(),
    ),
    _SettingsPage(
      title: "Apps",
      subtitle: "Organize and launch your favorite applications",
      icon: Icons.apps,
      builder: () => const QuickmenuAppsSettingsSub(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_selectedPage != null) {
      return _buildSubPage(_pages[_selectedPage!]);
    }
    return _buildPageList();
  }

  // ---- Link list (main view) ----
  Widget _buildPageList() {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 10),
        Center(child: Text("QuickMenu", style: theme.textTheme.titleLarge)),
        const SizedBox(height: 6),
        Center(
          child: Text("Configure each section of the QuickMenu", style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
        ),
        const SizedBox(height: 16),
        ...List<Widget>.generate(_pages.length, (int i) {
          final _SettingsPage page = _pages[i];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: ListTile(
              leading: Icon(page.icon, color: theme.colorScheme.primary, size: 22),
              title: Text(page.title, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(page.subtitle, style: theme.textTheme.bodySmall),
              trailing: Icon(Icons.chevron_right, color: theme.hintColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () => setState(() => _selectedPage = i),
            ),
          );
        }),
        const SizedBox(height: 10),
      ],
    );
  }

  // ---- Sub-page wrapper with back button ----
  Widget _buildSubPage(_SettingsPage page) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: <Widget>[
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                tooltip: "Back to QuickMenu",
                onPressed: () => setState(() => _selectedPage = null),
              ),
              const SizedBox(width: 4),
              Icon(page.icon, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(page.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const Divider(height: 1),
        page.builder(),
      ],
    );
  }
}

// ===========================================================================
// Stateless wrappers for sub-pages
// ===========================================================================

class QuickmenuGeneralSettings extends StatelessWidget {
  const QuickmenuGeneralSettings({super.key});
  @override
  Widget build(BuildContext context) => const QuickmenuGeneralSettingsPage();
}

class QuickmenuTopbarSettings extends StatelessWidget {
  const QuickmenuTopbarSettings({super.key});
  @override
  Widget build(BuildContext context) => const QuickmenuTopbar();
}

class QuickmenuTaskbarSettings extends StatelessWidget {
  const QuickmenuTaskbarSettings({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: QuickmenuTaskbar(),
    );
  }
}

class QuickmenuTaskbarRewrites extends StatelessWidget {
  const QuickmenuTaskbarRewrites({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: QuickmenuTaskbar(),
    );
  }
}

class QuickmenuBottomBarSettings extends StatelessWidget {
  const QuickmenuBottomBarSettings({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: QuickmenuBottomBar(section: BottomBarSection.all),
    );
  }
}

class QuickmenuFileSearchSettings extends StatelessWidget {
  const QuickmenuFileSearchSettings({super.key});
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: QuickmenuSearchSettings(),
    );
  }
}

class QuickmenuGridViewSettings extends StatelessWidget {
  const QuickmenuGridViewSettings({super.key});
  @override
  Widget build(BuildContext context) => const ViewsInterface();
}

class QuickmenuCustomQuickActionsSettings extends StatelessWidget {
  const QuickmenuCustomQuickActionsSettings({super.key});
  @override
  Widget build(BuildContext context) => const QuickmenuCustomQuickActionsSettingsPage();
}

class QuickmenuAppAudioSettings extends StatelessWidget {
  const QuickmenuAppAudioSettings({super.key});
  @override
  Widget build(BuildContext context) => const QuickmenuAppAudioSettingsPage();
}

class QuickmenuAppsSettingsSub extends StatelessWidget {
  const QuickmenuAppsSettingsSub({super.key});
  @override
  Widget build(BuildContext context) => const QuickmenuAppsSettings();
}
