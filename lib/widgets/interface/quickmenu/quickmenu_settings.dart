import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/app_opacity.dart';

class QuickmenuGeneralSettingsPage extends StatefulWidget {
  const QuickmenuGeneralSettingsPage({super.key});

  @override
  State<QuickmenuGeneralSettingsPage> createState() => _QuickmenuGeneralSettingsPageState();
}

class _QuickmenuGeneralSettingsPageState extends State<QuickmenuGeneralSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final double horizontalPadding = isWide ? 16 : 8;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: <Widget>[
                    _buildBehaviorCard(constraints),
                    const SizedBox(height: 16),
                    _buildAppearanceCard(constraints),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBehaviorCard(BoxConstraints constraints) {
    return _buildSettingsCard(
      icon: Icons.tune_rounded,
      title: "Behavior",
      subtitle: "Panel focus and pop-up management",
      children: <Widget>[
        _buildSectionTitle(context, "QuickMenu Design"),
        const SizedBox(height: 12),
        _buildDesignSelector(context, constraints),
        const SizedBox(height: 16),
        _buildToggleSetting(
          title: "Hide when losing focus",
          subtitle: "Close Tabame when clicking external windows",
          value: globalSettings.hideTabameOnUnfocus,
          onChanged: (bool val) async {
            globalSettings.hideTabameOnUnfocus = val;
            await Boxes.updateSettings("hideTabameOnUnfocus", val);
            setState(() {});
          },
        ),
        _buildToggleSetting(
          title: "Keep popups persistent",
          subtitle: "Prevent detached popups from closing on unfocus",
          value: globalSettings.keepPopupsOpen,
          onChanged: (bool val) async {
            globalSettings.keepPopupsOpen = val;
            await Boxes.updateSettings("keepPopupsOpen", val);
            setState(() {});
          },
        ),
        _buildToggleSetting(
          title: "Drag popups by icon only",
          subtitle: "Drag around the QuickMenu by Popup header icon only rather than the header.",
          value: globalSettings.dragPopupsByIconOnly,
          onChanged: (bool val) async {
            globalSettings.dragPopupsByIconOnly = val;
            await Boxes.updateSettings("dragPopupsByIconOnly", val);
            setState(() {});
          },
        ),
        _buildToggleSetting(
          title: "Quick Actions at the bottom",
          subtitle: "Put Quick Action on the bottom, between pinned and tray.",
          value: globalSettings.quickActionsAtBottom,
          onChanged: (bool val) async {
            globalSettings.quickActionsAtBottom = val;
            globalSettings.bottomBarOnTop = false;
            await Boxes.updateSettings("quickActionsAtBottom", val);
            await Boxes.updateSettings("bottomBarOnTop", val);
            setState(() {});
          },
        ),
        if (globalSettings.quickActionsAtBottom)
          _buildToggleSetting(
            title: "Bottom Bar at top",
            subtitle: "Put Buttom bar at the top to not get crowded.",
            value: globalSettings.bottomBarOnTop,
            onChanged: (bool val) async {
              globalSettings.bottomBarOnTop = val;
              await Boxes.updateSettings("bottomBarOnTop", val);
              setState(() {});
            },
          ),
      ],
    );
  }

  Widget _buildAppearanceCard(BoxConstraints constraints) {
    return _buildSettingsCard(
      icon: Icons.palette_outlined,
      title: "Appearance",
      subtitle: "Visual style and branding assets",
      children: <Widget>[
        _buildToggleSetting(
          title: "Compact Tray Bar",
          subtitle: "Display system tray icons in the panel",
          value: globalSettings.showTrayBar,
          onChanged: (bool val) async {
            globalSettings.showTrayBar = val;
            await Boxes.updateSettings("showTrayBar", val);
            setState(() {});
          },
        ),
        _buildImageSetting(
          title: "Primary Logo",
          subtitle: "Replace the default QuickMenu icon",
          imagePath: globalSettings.customLogo,
          defaultAsset: globalSettings.logo,
          onChanged: _pickLogoImage,
        ),
        const SizedBox(height: 4),
        _buildImageSetting(
          title: "Splash Header",
          subtitle: "Floating image centered above the panel",
          imagePath: globalSettings.customSpash,
          onChanged: _pickSplashImage,
        ),
      ],
    );
  }

  Widget _buildDesignSelector(BuildContext context, BoxConstraints constraints) {
    final bool isWide = constraints.maxWidth > 550;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isWide
          ? Row(
              children:
                  QuickMenuDesigns.values.map((QuickMenuDesigns d) => Expanded(child: _buildDesignTile(d))).toList(),
            )
          : Column(
              children: QuickMenuDesigns.values.map((QuickMenuDesigns d) => _buildDesignTile(d)).toList(),
            ),
    );
  }

  Widget _buildDesignTile(QuickMenuDesigns design) {
    final bool isSelected = globalSettings.quickMenuDesign == design.index;
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: () async {
        await Boxes.switchQuickMenuDesign(design);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent,
          ),
        ),
        child: Column(
          children: <Widget>[
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 14,
              color: isSelected ? theme.colorScheme.primary : theme.hintColor.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              design.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? theme.colorScheme.primary : theme.textTheme.bodyMedium?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleSetting({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final ThemeData theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: theme.colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSetting({
    required String title,
    required String subtitle,
    required String imagePath,
    String? defaultAsset,
    required Function(bool) onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    final bool hasImage = imagePath.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: () => onChanged(!hasImage),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image.file(File(imagePath), fit: BoxFit.cover)
                    : defaultAsset != null
                        ? Padding(padding: const EdgeInsets.all(8), child: Image.asset(defaultAsset))
                        : Icon(Icons.add_photo_alternate_outlined, size: 20, color: theme.hintColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
                    ),
                  ],
                ),
              ),
              Icon(
                hasImage ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                color: hasImage ? theme.colorScheme.primary : theme.hintColor.withValues(alpha: 0.4),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(subtitle,
                          style:
                              TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogoImage(bool enabled) async {
    if (!enabled) {
      globalSettings.customLogo = "";
    } else {
      final File? result = _pickPngFile();
      if (result == null) return;
      globalSettings.customLogo = result.path;
    }
    await Boxes.updateSettings("customLogo", globalSettings.customLogo);
    setState(() {});
  }

  Future<void> _pickSplashImage(bool enabled) async {
    if (!enabled) {
      globalSettings.customSpash = "";
    } else {
      final File? result = _pickPngFile();
      if (result == null) return;
      globalSettings.customSpash = result.path;
    }
    await Boxes.updateSettings("customSpash", globalSettings.customSpash);
    setState(() {});
  }

  File? _pickPngFile() {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
      ..defaultFilterIndex = 0
      ..defaultExtension = 'png'
      ..title = 'Select an image';
    return file.getFile();
  }
}
