---
name: tm-instrument-panel
description: The official Tabame "Instrument Panel" design language. Characterized by high-density layouts, technical aesthetics, and precise interactive feedback. Use this to maintain consistency across all quick menu extensions, audio controls, and settings panels.
version: 1.0.0
---

# Tabame Instrument Panel Design Language

This skill codifies the high-fidelity, "pro-audio/aviation-grade" design system used in Tabame. It prioritizes information density and functional clarity through a minimal but rich visual hierarchy.

## 1. Design Philosophy

*   **High Performance**: Interfaces should feel like professional tools (DAWs, IDEs, Flight Panels).
*   **Information Density**: Maximize data visibility in small spaces without causing cognitive overload.
*   **Tactile Feedback**: Every interaction (hover, drag, tap) must have immediate, precise visual feedback.
*   **Distilled Aesthetics**: Ruthlessly remove generic "AI slop" or standard Material/Cupertino defaults. Avoid "glossy" high-glow effects or overly saturated solid blocks. Use custom shapes, subtle outlines, and alpha-blended color spaces to maintain a technical, matte tone.

## 2. Core Components

### Panel Header
Every modal or flyout MUST start with a `PanelHeader`. It provides the title, primary icon, and the "draggability" needed for the desktop environment.
*   **Usage**: Top of the main `Column`.
*   **Icon**: Typically `14px` or `16px`.
*   **Title**: `13px` bold font, letter-spaced `0.3`.

### Section Labels
Use these to divide content within a panel instead of standard headers.
*   **Pattern**: Icon + Label + Count Pill + Divider.
*   **Label Style**: `11px`, bold, `0.45` letter spacing.
*   **Pill**: Highly rounded (`999px`), `userSettings.themeColors.accentColor.withAlpha(28)` background.

### Cards & Rows
*   **Cards**: Background `onSurface.withAlpha(8)`, Border `onSurface.withAlpha(16)`, `12px` radius.
*   **Rows**: Interactive items should have `8-10px` internal padding and `9px` or `10px` border radius.
*   **Hover States**: Use `userSettings.themeColors.accentColor.withAlpha(60)` for active hover or `userSettings.themeColors.accentColor.withAlpha(10-18)` for passive selections.

### Primary Action Buttons (Sticky)
Major actions like "Save Changes" or "Add Item" should be anchored and visually prioritized but modern.
*   **Sticky**: Must be fixed at the bottom of the container, allowing other content to scroll independently.
*   **Style**: Avoid "screaming" solid backgrounds. Use a subtle `userSettings.themeColors.accentColor.withAlpha(20-30)` fill with a more defined `userSettings.themeColors.accentColor.withAlpha(80)` border.
*   **Typography**: Sentence Case, `w700` weight, `0.5` letter spacing.
*   **Visual Feed**: No heavy shadows or glossy gradients. Use precise single-pixel borders.

## 3. Visual Specifications

### Typography
*   **Body**: `11.5px` to `12px`.
*   **Metadata/Small Labels**: `9px` to `11px`.
*   **Letter Spacing**: Use `0.3` to `0.7` for technical labels.
*   **Weights**: `FontWeight.w400` for content, `w600` or `w700` for labels and counts.

### Spacing & Rhythm
*   **Outer Padding**: `10px` (Compact) to `14px` (Comfortable).
*   **Internal Gaps**: `6px` between related items, `10px` between sections.
*   **Heights**: Standard "Bar" items are `25px` or `30px`. Sliders are `20px` high.

### Colors (Tabame Palette)
*   **Neutrals**: Never use pure black/white. Use `withAlpha` to create layers on the theme surface.
*   **Accents**: All UI state should be derived from `userSettings.themeColors.accentColor`.
*   **Border Emphases**: Use `userSettings.themeColors.accentColor.withAlpha(70)` for selected items.

## 4. Interaction Patterns

### The "Volume Drag"
Standard pattern for linear values:
*   `onVerticalDragStart`: Reset accumulator.
*   `onVerticalDragUpdate`: Accumulate `delta.dy`. Trigger every `10-15px` of movement.
*   **Visuals**: Show feedback icon (volume_up, volume_down) temporarily.

### Multi-Tap
*   `Left Tap`: Primary action (Play/Toggle).
*   `Right Tap`: Secondary action (Next/Alternative).
*   `Middle Click (Tertiary)`: Destructive or "Previous" action.

## 5. Reference Implementation

```dart
// Standard Section Label
Widget _buildSectionLabel({
  required String label,
  required Color onSurface,
  required int count,
  required IconData icon,
}) {
  return Row(
    children: <Widget>[
      Icon(icon, size: 14, color: userSettings.themeColors.accentColor),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: onSurface,
        ),
      ),
      const SizedBox(width: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: userSettings.themeColors.accentColor.withAlpha(28),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text("$count", style: TextStyle(fontSize: 10, color: userSettings.themeColors.accentColor)),
      ),
      const SizedBox(width: 8),
      Expanded(child: Divider(height: 1, color: onSurface.withAlpha(20))),
    ],
  );
}

// Standard Custom Card
Decoration get instrumentCardDecoration => BoxDecoration(
  color: onSurface.withAlpha(8),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: onSurface.withAlpha(16)),
);

// Standard Fixed Bottom Bar (Sticky Action)
Widget _buildFixedBottomBar({
  required BuildContext context,
  required String label,
  required VoidCallback onTap,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withAlpha(100),
      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface.withAlpha(15))),
    ),
    child: Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 32),
          decoration: BoxDecoration(
            color: userSettings.themeColors.accentColor.withAlpha(28),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: userSettings.themeColors.accentColor.withAlpha(80), width: 1),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: userSettings.themeColors.accentColor,
            ),
          ),
        ),
      ),
    ),
  );
}
```
