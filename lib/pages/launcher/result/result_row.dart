import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';

abstract final class _SereneTokens {
  // Row geometry
  static const double rowHPad = 12;
  static const double rowVPad = 7;
  static const double rowRadius = 10.0;
  static const double rowVMargin = 1.5;

  // Icon well
  static const double iconWellSize = 30;
  static const double iconWellRadius = 7;

  // Typography
  static const double titleSize = 13;
  static const double subtitleSize = 11;

  // Badge
  static const double badgeFontSize = 9;
  static const double badgeRadius = 5;

  // Selection fill opacity (0-255)
  static const int selectionFillAlpha = 40;

  // Animation
  static const Duration fastAnim = Duration(milliseconds: 80);
  static const Duration normalAnim = Duration(milliseconds: 180);
  static const Curve animCurve = Curves.easeInOut;
}

// ---------------------------------------------------------------------------
// Serene private building blocks
// ---------------------------------------------------------------------------

class _SereneIconWell extends StatelessWidget {
  const _SereneIconWell({
    required this.child,
    required this.accent,
    this.isSelected = false,
  });

  final Widget child;
  final Color accent;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SereneTokens.iconWellSize,
      height: _SereneTokens.iconWellSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(isSelected ? 36 : 20),
        borderRadius: BorderRadius.circular(_SereneTokens.iconWellRadius),
      ),
      child: child,
    );
  }
}

class _SereneTitleSubtitle extends StatelessWidget {
  const _SereneTitleSubtitle({
    required this.title,
    required this.subtitle,
    required this.onSurface,
    required this.isSelected,
  });

  final String title;
  final String subtitle;
  final Color onSurface;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _SereneTokens.titleSize,
            fontWeight: FontWeight.w500,
            color: isSelected ? onSurface : onSurface.withAlpha(210),
            letterSpacing: -0.1,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _SereneTokens.subtitleSize,
            color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _SereneRowContainer extends StatelessWidget {
  const _SereneRowContainer({
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.child,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration dur = isRepeating ? _SereneTokens.fastAnim : _SereneTokens.normalAnim;
    return AnimatedContainer(
      duration: dur,
      curve: _SereneTokens.animCurve,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: _SereneTokens.rowVMargin),
      padding: const EdgeInsets.symmetric(
        horizontal: _SereneTokens.rowHPad,
        vertical: _SereneTokens.rowVPad,
      ),
      decoration: BoxDecoration(
        color: isSelected ? accent.withAlpha(_SereneTokens.selectionFillAlpha) : Colors.transparent,
        borderRadius: BorderRadius.circular(_SereneTokens.rowRadius),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherResultRow  (Classic + Serene)
// ---------------------------------------------------------------------------

class LauncherResultRow extends StatelessWidget {
  const LauncherResultRow({
    super.key,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
    required this.icon,
    this.content,
    this.title,
    this.subtitle,
    this.badge,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  final Widget icon;
  final String? title;
  final String? subtitle;

  final Widget? content;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return user.launcherDesign == LauncherDesign.serene ? _buildSerene(context) : _buildClassic(context);
  }

  // ── Classic ────────────────────────────────────────────────────────────────

  Widget _buildClassic(BuildContext context) {
    final int animMs = isRepeating ? 50 : 200;
    final Curve animCurve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: animCurve,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(55) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: animMs),
                    curve: animCurve,
                    width: isSelected ? 2.5 : 0,
                    height: 22,
                    margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: content == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: entryStyle(isSelected, fontSize: Design.baseFontSize + 2),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: Design.baseFontSize,
                                  color: isSelected ? onSurface.withAlpha(170) : onSurface.withAlpha(130),
                                ),
                              ),
                            ],
                          )
                        : content!,
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: badge,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Serene ─────────────────────────────────────────────────────────────────

  Widget _buildSerene(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: _SereneRowContainer(
            isSelected: isSelected,
            isRepeating: isRepeating,
            accent: accent,
            child: Row(
              children: <Widget>[
                _SereneIconWell(
                  accent: accent,
                  isSelected: isSelected,
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: content == null
                      ? _SereneTitleSubtitle(
                          title: title ?? '',
                          subtitle: subtitle ?? '',
                          onSurface: onSurface,
                          isSelected: isSelected,
                        )
                      : content!,
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherKindBadge  (Classic style)
// ---------------------------------------------------------------------------

class LauncherKindBadge extends StatelessWidget {
  const LauncherKindBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(60),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: accent.withAlpha(180)),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: accent.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherSereneBadge  (Serene style — no border, pure fill)
// ---------------------------------------------------------------------------

class LauncherSereneBadge extends StatelessWidget {
  const LauncherSereneBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(_SereneTokens.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: color.withAlpha(180)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: _SereneTokens.badgeFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: color.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}
