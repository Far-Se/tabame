import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';

class QuickmenuGeneralSettingsPage extends StatefulWidget {
  const QuickmenuGeneralSettingsPage({super.key});

  @override
  State<QuickmenuGeneralSettingsPage> createState() => _QuickmenuGeneralSettingsPageState();
}

class _QuickmenuGeneralSettingsPageState extends State<QuickmenuGeneralSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme.copyWith(
              dense: true,
              style: ListTileStyle.drawer,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minVerticalPadding: 0,
              visualDensity: VisualDensity.compact,
              horizontalTitleGap: 14,
            ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildBehaviorCard(),
              const SizedBox(height: 16),
              _buildAppearanceCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBehaviorCard() {
    return _buildSettingsCard(
      icon: Icons.tune_rounded,
      title: "Behavior",
      subtitle: "Focus and popup handling while QuickMenu is open",
      child: Column(
        children: <Widget>[
          SwitchListTile(
            title: const Text("Hide QuickMenu when losing focus"),
            subtitle: const Text("Close the panel when another window becomes active"),
            secondary: const Icon(Icons.visibility_off_outlined, size: 20),
            value: globalSettings.hideTabameOnUnfocus,
            onChanged: (bool newValue) async {
              globalSettings.hideTabameOnUnfocus = newValue;
              await Boxes.updateSettings("hideTabameOnUnfocus", newValue);
              if (!mounted) return;
              setState(() {});
            },
          ),
          SwitchListTile(
            title: const Text("Keep popups open after losing focus"),
            subtitle: const Text("Useful if you work with detached QuickMenu popups"),
            secondary: const Icon(Icons.open_in_new_rounded, size: 20),
            value: globalSettings.keepPopupsOpen,
            onChanged: (bool newValue) async {
              globalSettings.keepPopupsOpen = newValue;
              await Boxes.updateSettings("keepPopupsOpen", newValue);
              if (!mounted) return;
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard() {
    final ThemeData theme = Theme.of(context);
    return _buildSettingsCard(
      icon: Icons.palette_outlined,
      title: "Appearance",
      subtitle: "Pick the menu style and optional branding assets",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(12),
              ),
              child: RadioGroup<int>(
                groupValue: globalSettings.quickMenuDesign,
                onChanged: (int? value) async {
                  final int selectedIndex = value ?? QuickMenuDesigns.modern.index;
                  await Boxes.switchQuickMenuDesign(QuickMenuDesigns.values[selectedIndex]);
                  if (!mounted) return;
                  setState(() {});
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text("QuickMenu Design", style: theme.textTheme.labelLarge),
                    ),
                    _designRadioTile(
                      title: "Modern",
                      subtitle: "Rounded card look with layered surface and accent glow",
                      value: QuickMenuDesigns.modern.index,
                    ),
                    _designRadioTile(
                      title: "Classic",
                      subtitle: "Original compact styling with the familiar panel look",
                      value: QuickMenuDesigns.classic.index,
                    ),
                    _designRadioTile(
                      title: "Interface",
                      subtitle: "Segmented cards and header styling inspired by the settings interface",
                      value: QuickMenuDesigns.interface.index,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(),
          _buildImageSettingTile(
            title: "Custom QuickMenu icon",
            subtitle: "Replace the current logo shown in QuickMenu",
            enabled: globalSettings.customLogo.isNotEmpty,
            preview: globalSettings.customLogo.isEmpty
                ? Image.asset(globalSettings.logo, fit: BoxFit.contain)
                : Image.file(File(globalSettings.customLogo), fit: BoxFit.contain),
            onChanged: (bool enabled) => _pickLogoImage(enabled),
          ),
          _buildImageSettingTile(
            title: "Splash image above QuickMenu",
            subtitle: "Show a small PNG above the menu panel",
            enabled: globalSettings.customSpash.isNotEmpty,
            preview: globalSettings.customSpash.isEmpty
                ? _buildEmptyPreview(Icons.image_not_supported_outlined, "No splash selected")
                : Image.file(File(globalSettings.customSpash), fit: BoxFit.cover),
            onChanged: (bool enabled) => _pickSplashImage(enabled),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              minLeadingWidth: 28,
              horizontalTitleGap: 14,
              leading: Icon(icon),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(subtitle),
            ),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _designRadioTile({
    required String title,
    required String subtitle,
    required int value,
  }) {
    return RadioListTile<int>(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: const VisualDensity(horizontal: 0, vertical: -1),
    );
  }

  Widget _buildImageSettingTile({
    required String title,
    required String subtitle,
    required bool enabled,
    required Widget preview,
    required ValueChanged<bool> onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      secondary: Container(
        width: 48,
        height: 48,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.18)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: preview,
        ),
      ),
      value: enabled,
      onChanged: onChanged,
    );
  }

  Widget _buildEmptyPreview(IconData icon, String label) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: Icon(icon, size: 18, color: theme.hintColor),
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
    if (!mounted) return;
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
    if (!mounted) return;
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
