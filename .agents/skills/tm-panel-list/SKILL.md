---
name: tm-panel-list
description: High-density, technical configuration list design language for Tabame. Standardizes configuration cards, meta chips, and selection rails for sidebars and modals.
---

# tm-panel-list

High-density, technical configuration list design language for Tabame.

## Overview

The `tm-panel-list` style is used for sidebars, modals, and narrow configuration panels (like the QuickMenu Design panel). It prioritizes information density while maintaining a professional, "instrument panel" aesthetic.

## Core Design Tokens

### Layout & Spacing

- **Panel Padding**: `EdgeInsets.fromLTRB(8, 8, 8, 10)` for the main list.
- **Card Spacing**: `SizedBox(height: 8)` between vertical cards.
- **Inner Padding**: `EdgeInsets.fromLTRB(10, 9, 10, 8)` for card contents.
- **Section Spacing**:
  - `SizedBox(height: 2)` between Header and Description.
  - `SizedBox(height: 8-10)` before interactive controls (Sliders, Chips).

### Card Decoration

- **Background**: `Theme.of(context).colorScheme.onSurface.withAlpha(7)`
- **Border**: `Border.all(color: onSurface.withAlpha(16))`
- **BorderRadius**: `BorderRadius.circular(10)`
- **Highlighted State**: Background `userSettings.themeColors.accentColor.withAlpha(10)`, border `userSettings.themeColors.accentColor.withAlpha(30)`.

### Typography

- **Card Title**: `fontSize: userSettings.themeColors.baseFontSize + 2.5`, `fontWeight: FontWeight.w700`.
- **Card Description**: `fontSize: userSettings.themeColors.baseFontSize + 0.5`, `color: onSurface.withAlpha(150)`, `height: 1.25`.
- **Meta Chips**: `fontSize: userSettings.themeColors.baseFontSize + 0.5`, `fontWeight: FontWeight.w700`.

## Key Components & Patterns

### 1. The Configuration Card

A vertical container grouping related settings.

```dart
Container(
  padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
  decoration: BoxDecoration(
    color: onSurface.withAlpha(7),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: onSurface.withAlpha(16)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Column(...)), // Title & Desc
          _buildMetaChip(...),         // Value Badge
        ],
      ),
      const SizedBox(height: 8),
      Slider(...), // Interactive Control
    ],
  ),
)
```

### 2. Meta Chips

Compact badges for showing values (hex codes, percentages, toggles).

- **Shape**: `StadiumBorder` / `BorderRadius.circular(999)`.
- **Padding**: `EdgeInsets.symmetric(horizontal: 7, vertical: 3)`.
- **Visuals**: Low-alpha colored background with high-alpha colored text.

### 3. Selection Rails (ChoiceChip)

Used for design types or mode switching within a card.

- `ChoiceChip` with `visualDensity: VisualDensity.compact`.
- `labelStyle`: `fontSize: userSettings.themeColors.baseFontSize + 1.5`.
- Selected color: `userSettings.themeColors.accentColor.withAlpha(18)`.

### 4. Color Swatches/Pickers

- Use `_buildSwatch` (20-22px circle) to show active colors.
- Use `InkWell` labels (e.g., "Pick") instead of heavy buttons for secondary actions.

## Implementation Guidelines

- **Density over whitespace**: Prefer tight spacing (`SizedBox(height: 2-4)`) between related labels.
- **Alignment**: Items in a card's header row usually use `crossAxisAlignment: CrossAxisAlignment.start`.
- **Interactivity**: Use `Slider` for range values and `ChoiceChip` for enum-like selections.
- **Visual Hierarchy**: Use the `userSettings.themeColors.accentColor` color sparingly (Meta Chips, active Sliders, selected Chips) to keep the focused look.
