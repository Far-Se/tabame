import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/settings.dart';
import '../../models/util/markdown_text.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Welcome Header
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Image.asset(userSettings.logo, width: 42),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Welcome to Tabame",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                  ),
                  Text(
                    "Master your workspace with this comprehensive guide.",
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Main Content Grid
          LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            final bool isSmall = constraints.maxWidth < 900;
            return Wrap(
              spacing: 24,
              runSpacing: 24,
              children: <Widget>[
                // Left Column - Core Logic
                SizedBox(
                  width: isSmall ? constraints.maxWidth : (constraints.maxWidth / 2 - 12),
                  child: _contentCard(
                    context,
                    title: "System Overview",
                    subtitle: "Core features and navigation logic.",
                    icon: Icons.auto_awesome_mosaic_rounded,
                    color: accent,
                    markdownContent: markdownHomeLeft,
                  ),
                ),
                // Right Column - Interaction & Tools
                SizedBox(
                  width: isSmall ? constraints.maxWidth : (constraints.maxWidth / 2 - 12),
                  child: _contentCard(
                    context,
                    title: "Interaction Guide",
                    subtitle: "Mouse shortcuts and productivity tips.",
                    icon: Icons.touch_app_rounded,
                    color: Colors.orange.shade400,
                    markdownContent: markdownHomeRight,
                  ),
                ),
              ],
            );
          }),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _contentCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String markdownContent,
  }) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(subtitle,
                        style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          MarkdownBody(
            data: markdownContent,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface, height: 2),
              h3: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.9), height: 1.8),
              h5: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.5),
              p: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.7), height: 1.5),
              strong: TextStyle(fontWeight: FontWeight.bold, color: onSurface),
              listBullet: TextStyle(color: color),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(top: BorderSide(color: onSurface.withValues(alpha: 0.08))),
              ),
            ),
            sizedImageBuilder: (MarkdownImageConfig config) {
              if (config.uri.path == "logo") return Image.asset(userSettings.logo, width: 20);

              const Map<String, IconData> icons = <String, IconData>{
                "quickMenu": Icons.apps,
                "runWindow": Icons.drag_handle,
                "remap": Icons.keyboard,
                "views": Icons.view_agenda,
                "wizardly": Icons.auto_fix_high,
                "tips": Icons.tips_and_updates,
                "bookmarks": Icons.folder_copy,
                "trktivty": Icons.scatter_plot,
                "tasks": Icons.task_alt,
              };

              if (icons.containsKey(config.alt)) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(icons[config.alt], size: 18, color: color),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
