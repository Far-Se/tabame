import 'package:flutter/material.dart';
import '../../models/classes/boxes/boxes_base.dart';
import '../../models/util/app_opacity.dart';
import '../../models/win32/mixed.dart';
import '../itzy/interface/quickmenu_bottom_bar.dart';
import '../itzy/interface/quickmenu_taskbar.dart';
import '../itzy/interface/quickmenu_quickactions.dart';
import '../itzy/interface/quickmenu_search.dart';
import 'quickmenu/quickmenu_settings.dart';
import 'quickmenu/custom_quickactions_settings.dart';
import 'quickmenu/appaudio_settings.dart';
import 'quickmenu/apps_settings.dart';
import 'quickmenu/quick_grid_settings.dart';
import 'grid_settings.dart';

// ---------------------------------------------------------------------------
// Data model for a settings sub-page entry
// ---------------------------------------------------------------------------
class _SettingsPage {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function() builder;
  final String Function()? stats;

  const _SettingsPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
    this.stats,
  });
}

// ---------------------------------------------------------------------------
// Main widget — shows a link list, navigates to sub-pages
// ---------------------------------------------------------------------------
class QuickmenuSettings extends StatefulWidget {
  const QuickmenuSettings({super.key});

  static int? pendingPage;

  @override
  QuickmenuSettingsState createState() => QuickmenuSettingsState();
}

class QuickmenuSettingsState extends State<QuickmenuSettings> {
  int? _selectedPage;

  @override
  void initState() {
    super.initState();
    if (QuickmenuSettings.pendingPage != null) {
      _selectedPage = QuickmenuSettings.pendingPage;
      QuickmenuSettings.pendingPage = null;
    }
  }

  String _searchQuery = "";

  late final List<_SettingsPage> _pages = <_SettingsPage>[
    _SettingsPage(
      title: "General",
      subtitle: "UI & Behavior",
      icon: Icons.tune_rounded,
      builder: () => const QuickmenuGeneralSettings(),
      stats: () => "${Monitor.list.length} Screens",
    ),
    _SettingsPage(
      title: "QuickActions",
      subtitle: "Top Bar Order",
      icon: Icons.reorder_rounded,
      builder: () => const QuickmenuTopbarSettings(),
    ),
    _SettingsPage(
      title: "Taskbar",
      subtitle: "Style & Logic",
      icon: Icons.view_list_outlined,
      builder: () => const QuickmenuTaskbarSettings(),
    ),
    _SettingsPage(
      title: "Bottom Bar",
      subtitle: "Files & Tray",
      icon: Icons.widgets_outlined,
      builder: () => const QuickmenuBottomBarSettings(),
    ),
    _SettingsPage(
      title: "File Search",
      subtitle: "Index & Logic",
      icon: Icons.search_rounded,
      builder: () => const QuickmenuFileSearchSettings(),
    ),
    _SettingsPage(
      title: "Grid View",
      subtitle: "Window Snapping",
      icon: Icons.view_module_rounded,
      builder: () => const QuickmenuGridViewSettings(),
    ),
    _SettingsPage(
      title: "Custom Actions",
      subtitle: "User Macros",
      icon: Icons.settings_input_component_rounded,
      builder: () => const QuickmenuCustomQuickActionsSettings(),
    ),
    _SettingsPage(
      title: "App Audio",
      subtitle: "Media Overlay",
      icon: Icons.audio_file_rounded,
      builder: () => const QuickmenuAppAudioSettings(),
    ),
    _SettingsPage(
      title: "Apps",
      subtitle: "Launcher Groups",
      icon: Icons.apps_rounded,
      builder: () => const QuickmenuAppsSettingsSub(),
      stats: () => "${Boxes.appCategories.length} Categories",
    ),
    _SettingsPage(
      title: "QuickSnap",
      subtitle: "Precision Layouts",
      icon: Icons.view_quilt_rounded,
      builder: () => const QuickmenuQuickGridsSettings(),
      stats: () => "${Boxes.quickGrids.length} Presets",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _selectedPage != null
          ? KeyedSubtree(key: ValueKey<int>(_selectedPage!), child: _buildSubPage(_pages[_selectedPage!]))
          : KeyedSubtree(key: const ValueKey<String>("dashboard"), child: _buildDashboard()),
    );
  }

  Widget _buildDashboard() {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    final List<_SettingsPage> filtered = _pages
        .where((_SettingsPage p) =>
            p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            p.subtitle.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // --- Header ---
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Dashboard", style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text("Configuration & Sub-systems",
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.hintColor)),
            ],
          ),
        ),

        // --- Search ---
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: onSurface.withValues(alpha: 0.08)),
            ),
            child: TextField(
              onChanged: (String v) => setState(() => _searchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: "Search Settings...",
                hintStyle: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.35)),
                prefixIcon: Icon(Icons.search_rounded, size: 18, color: onSurface.withValues(alpha: 0.35)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),

        // --- Compact Grid ---
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(Icons.search_off_rounded, size: 48, color: onSurface.withValues(alpha: 0.1)),
                      const SizedBox(height: 16),
                      Text(
                        "No settings match your hunt.",
                        style: TextStyle(color: onSurface.withValues(alpha: 0.3), fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Try a different keyword or browse the grid.",
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.2)),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final int crossAxisCount = constraints.maxWidth > 600 ? 3 : (constraints.maxWidth > 550 ? 2 : 1);
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.95,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (BuildContext context, int index) {
                          final _SettingsPage page = filtered[index];
                          return TweenAnimationBuilder<double>(
                            duration: Duration(milliseconds: 300 + (index * 40)),
                            curve: Curves.easeOutQuart,
                            tween: Tween<double>(begin: 0.0, end: 1.0),
                            builder: (BuildContext context, double value, Widget? child) {
                              return Opacity(
                                opacity: value,
                                child: Transform.translate(
                                  offset: Offset(0, 15 * (1 - value)),
                                  child: child,
                                ),
                              );
                            },
                            child: _NavigationTile(
                              page: page,
                              onTap: () {
                                final int realIndex = _pages.indexOf(page);
                                setState(() => _selectedPage = realIndex);
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSubPage(_SettingsPage page) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SubPageHeader(
          page: page,
          onBack: () => setState(() => _selectedPage = null),
        ),
        Expanded(child: page.builder()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium Header for Sub-pages
// ---------------------------------------------------------------------------
class _SubPageHeader extends StatefulWidget {
  const _SubPageHeader({required this.page, required this.onBack});
  final _SettingsPage page;
  final VoidCallback onBack;

  @override
  State<_SubPageHeader> createState() => _SubPageHeaderState();
}

class _SubPageHeaderState extends State<_SubPageHeader> {
  bool _isBackHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: <Widget>[
          // Custom Back Button
          MouseRegion(
            onEnter: (_) => setState(() => _isBackHovered = true),
            onExit: (_) => setState(() => _isBackHovered = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: widget.onBack,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color:
                      _isBackHovered ? primary.withValues(alpha: 0.1) : onSurface.withValues(alpha: AppOpacity.subtle),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _isBackHovered
                        ? primary.withValues(alpha: 0.3)
                        : onSurface.withValues(alpha: AppOpacity.border),
                  ),
                ),
                child: AnimatedScale(
                  scale: _isBackHovered ? 0.9 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 16,
                    color: _isBackHovered ? primary : onSurface.withValues(alpha: AppOpacity.textSecondary),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Divider
          Container(
            height: 24,
            width: 1.5,
            decoration: BoxDecoration(
              color: onSurface.withValues(alpha: AppOpacity.border),
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          const SizedBox(width: 16),

          // Page Icon in Accent Box
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: AppOpacity.accentFaint),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(widget.page.icon, size: 18, color: primary),
          ),

          const SizedBox(width: 14),

          // Title Cluster
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      "SETTINGS / ",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: onSurface.withValues(alpha: 0.3),
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      widget.page.title.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  widget.page.subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onSurface.withValues(alpha: AppOpacity.textSecondary),
                  ),
                ),
              ],
            ),
          ),

          // Stats if available
          if (widget.page.stats != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: AppOpacity.subtle),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: onSurface.withValues(alpha: AppOpacity.border)),
              ),
              child: Text(
                widget.page.stats!(),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavigationTile extends StatefulWidget {
  const _NavigationTile({required this.page, required this.onTap});
  final _SettingsPage page;
  final VoidCallback onTap;

  @override
  State<_NavigationTile> createState() => _NavigationTileState();
}

class _NavigationTileState extends State<_NavigationTile> with SingleTickerProviderStateMixin {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _isHovered
                    ? <Color>[
                        primary.withValues(alpha: 0.08),
                        primary.withValues(alpha: 0.15),
                        primary.withValues(alpha: 0.20),
                        primary.withValues(alpha: 0.20)
                      ]
                    : <Color>[onSurface.withValues(alpha: 0.03), onSurface.withValues(alpha: 0.08)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _isHovered ? primary.withValues(alpha: 0.4) : onSurface.withValues(alpha: 0.08),
                width: 1.5,
              ),
            ),
            child: Stack(
              children: <Widget>[
                // Stats in the corner
                if (widget.page.stats != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isHovered ? 1.0 : 0.4,
                      child: Text(
                        widget.page.stats!(),
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w700,
                          color: _isHovered ? primary : onSurface,
                        ),
                      ),
                    ),
                  ),
                // Main Content
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // Large Icon
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isHovered ? primary.withValues(alpha: 0.2) : onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: AnimatedScale(
                        scale: _isHovered ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.elasticOut,
                        child: Icon(widget.page.icon,
                            color: _isHovered ? primary : onSurface.withValues(alpha: 0.7), size: 25),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Labels
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.page.title,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, height: 1.1),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.page.subtitle,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: onSurface.withValues(alpha: 0.5),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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

class QuickmenuQuickGridsSettings extends StatelessWidget {
  const QuickmenuQuickGridsSettings({super.key});
  @override
  Widget build(BuildContext context) => const QuickGridsSettingsPage();
}
